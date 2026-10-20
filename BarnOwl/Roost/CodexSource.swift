import Foundation

/// Reads Codex's session logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`),
/// read-only. Only event types, tool names, exit codes and timing are read,
/// never prompts, replies or output.
enum CodexSource {
    static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
    }

    static var sessionsFolder: URL { home.appending(path: "sessions") }

    /// A session log: `…/.codex/sessions/2026/10/20/rollout-<time>-<id>.jsonl`.
    static func isLog(_ path: String) -> Bool {
        path.hasPrefix(sessionsFolder.path + "/") && (path as NSString).lastPathComponent.hasPrefix("rollout-")
            && path.hasSuffix(".jsonl")
    }

    /// Logs written to in the last `within` seconds. A log lives in the folder
    /// of the day its session started, so the last week of folders is checked.
    static func recentLogs(now: Date, within: TimeInterval = 2 * 3600, days: Int = 7) -> [(url: URL, modified: Date)] {
        let fileManager = FileManager.default
        let calendar = Calendar.current
        var logs: [(URL, Date)] = []
        for back in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = sessionsFolder
                .appending(path: String(format: "%04d", parts.year ?? 0))
                .appending(path: String(format: "%02d", parts.month ?? 0))
                .appending(path: String(format: "%02d", parts.day ?? 0))
            for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".jsonl") {
                let url = folder.appending(path: name)
                if let modified = FileTimes.modified(url.path),
                   now.timeIntervalSince(modified) < within {
                    logs.append((url, modified))
                }
            }
        }
        return logs.sorted { $0.1 > $1.1 }.map { (url: $0.0, modified: $0.1) }
    }

    /// The folder a log's session works in, from its first line.
    static func folder(ofLog url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64_000),
              let line = data.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
              let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let payload = record["payload"] as? [String: Any] else { return nil }
        return payload["cwd"] as? String
    }

    /// One window of Codex's rate limits: `{"used_percent":38,"window_minutes":300,"resets_at":1792…}`.
    /// Older versions said `resets_in_seconds` instead.
    static func limit(_ value: Any?, at time: Date) -> PlanLimit? {
        guard let window = value as? [String: Any],
              let used = (window["used_percent"] as? NSNumber)?.doubleValue, used.isFinite, (0...1000).contains(used)
        else { return nil }
        let minutes = (window["window_minutes"] as? NSNumber)?.doubleValue ?? 300
        var resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        if resets == nil, let seconds = (window["resets_in_seconds"] as? NSNumber)?.doubleValue {
            resets = time.addingTimeInterval(seconds)
        }
        return PlanLimit(agent: .codex, window: minutes <= 6 * 60 ? .session : .week, used: used, resetsAt: resets,
                         updated: time)
    }

    /// The plan Codex names beside its limits: "plus" is "Plus".
    static func plan(_ value: Any?) -> String? {
        guard let type = value as? String, !type.isEmpty, type.count <= 24,
              type.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    struct LogState: Equatable, Sendable {
        var busy = false
        var lastTool: String?
        var failures = 0
        var turnStarted: Date?
        var turnEnded: Date?
        var lastTurn: TimeInterval?
        var rateLimited = false
        /// When the plan limit was last hit, to let it go once it has surely passed.
        var rateLimitedAt: Date?
        var aborted = false
        /// The plan's windows as Codex last reported them.
        var limits: [PlanLimit] = []
        /// The model of its latest turn: "gpt-6-astra".
        var model: String?

        mutating func consume(_ line: Substring) {
            guard line.utf8.count < 256_000, let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            consume(record)
        }

        mutating func consume(_ record: [String: Any]) {
            let time = (record["timestamp"] as? String).flatMap(ClaudeSource.LogState.date(from:))
            guard let payload = record["payload"] as? [String: Any] else { return }
            switch (record["type"] as? String, payload["type"] as? String) {
            case ("turn_context", _):
                if let model = payload["model"] as? String, !model.isEmpty, model.count < 80 { self.model = model }
            case ("event_msg", "task_started"):
                busy = true
                aborted = false
                turnStarted = time
                turnEnded = nil
                rateLimited = false
            case ("event_msg", "task_complete"):
                busy = false
                turnEnded = time
                lastTurn = (payload["duration_ms"] as? Double).map { $0 / 1000 }
            case ("event_msg", "turn_aborted"):
                busy = false
                aborted = true
                turnEnded = time
            case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
                lastTool = payload["name"] as? String
            case ("event_msg", "token_count"):
                let limits = payload["rate_limits"] as? [String: Any]
                rateLimited = !(limits?["rate_limit_reached_type"] is NSNull) && limits?["rate_limit_reached_type"] != nil
                if rateLimited { rateLimitedAt = time ?? Date() }
                if let limits, let time {
                    let plan = CodexSource.plan(limits["plan_type"])
                    let windows = ["primary", "secondary"].compactMap { CodexSource.limit(limits[$0], at: time) }
                        .map { limit in var limit = limit; limit.plan = plan; return limit }
                    if !windows.isEmpty { self.limits = windows }
                }
            case ("event_msg", "item_completed"):
                guard let item = payload["item"] as? [String: Any], item["type"] as? String == "CommandExecution"
                else { return }
                if let code = item["exit_code"] as? Int, code != 0 {
                    failures += 1
                } else if item["status"] as? String == "failed" {
                    failures += 1
                } else {
                    failures = 0
                }
            default:
                break
            }
        }

        func state(now: Date) -> (state: OwletState, detail: String?) {
            if rateLimited, let reset = limits.compactMap(\.resetsAt).filter({ $0 > now }).min() {
                return (.teaBreak, "Paused until \(PlanLimit.when(reset, now: now)) · plan limit")
            }
            // Without a reset time, a pause is let go after a quarter of an hour.
            if rateLimited, limits.allSatisfy({ $0.resetsAt == nil }), let at = rateLimitedAt,
               now.timeIntervalSince(at) < 15 * 60 {
                return (.teaBreak, "Paused for the plan limit")
            }
            if busy {
                if failures >= ClaudeSource.LogState.stuckAfter { return (.fixing, "Fixing after \(failures) failed commands") }
                switch lastTool {
                case "exec", "shell", "exec_command", "local_shell", "container.exec": return (.running, nil)
                case "apply_patch", "write_file": return (.typing, nil)
                case "web_search", "web.run": return (.browsing, nil)
                case "sleep", "wait": return (.waitingOnHelpers, nil)
                default: return (.thinking, nil)
                }
            }
            if failures >= ClaudeSource.LogState.stuckAfter { return (.stuck, "Stopped after \(failures) failed commands") }
            let since = turnEnded ?? .distantPast
            if !aborted, now.timeIntervalSince(since) < 60 * 60, let turn = lastTurn, turn >= 120 {
                return (.done, "Your turn · finished after \(ClaudeSource.duration(turn))")
            }
            return now.timeIntervalSince(since) > 10 * 60 ? (.napping, nil) : (.resting, nil)
        }
    }
}

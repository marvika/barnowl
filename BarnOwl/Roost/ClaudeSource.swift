import Foundation

/// Reads Claude Code's own bookkeeping, read-only: one small file per running
/// session in `~/.claude/sessions`, and each session's log in
/// `~/.claude/projects`. Covers the terminal, the Claude app's Code tab and the
/// Agent SDK alike. Only status, timing and tool names are read; never
/// prompts, replies or command output.
enum ClaudeSource {
    static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }

    static var sessionsFolder: URL { home.appending(path: "sessions") }
    static var projectsFolder: URL { home.appending(path: "projects") }

    /// A running session, as Claude Code describes it in `sessions/<pid>.json`.
    struct SessionFile: Decodable, Equatable, Sendable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        /// Milliseconds since 1970.
        var startedAt: Double?
        var kind: String?
        var entrypoint: String?
        var name: String?
        /// "busy", "idle", or "waiting" with `waitingFor` saying why.
        var status: String?
        var waitingFor: String?
        var statusUpdatedAt: Double?
        /// When its process started, as `ps` prints it in UTC: "Mon Oct 19 14:48:25 2026".
        var procStart: String?

        var started: Date { startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast }
        var statusSince: Date? { statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
        /// Run from a script, CI or the SDK rather than typed into by a person.
        var isScripted: Bool {
            guard let entrypoint else { return kind != nil && kind != "interactive" && kind != "bg" }
            return entrypoint.hasPrefix("sdk") || entrypoint == "print" || (kind != nil && kind != "interactive" && kind != "bg")
        }
    }

    /// The session files only; the `.key` files beside them are secrets and stay unopened.
    static func sessionFiles(in folder: URL = sessionsFolder) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { folder.appending(path: $0) }
    }

    static func parse(_ data: Data) -> SessionFile? {
        try? JSONDecoder().decode(SessionFile.self, from: data)
    }

    /// Whether the session's process is still the one that wrote the file. A
    /// crashed session leaves its file behind, and macOS reuses PIDs.
    static func isLive(_ file: SessionFile) -> Bool {
        guard kill(file.pid, 0) == 0, let started = ProcessScan.startTime(of: file.pid) else { return false }
        if let text = file.procStart, let recorded = procStartDate(text) {
            return abs(recorded.timeIntervalSince(started)) < 2
        }
        return file.startedAt == nil || started <= file.started.addingTimeInterval(5)
    }

    static func procStartDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        let single = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return formatter.date(from: single)
    }

    /// Claude Code names a project's log folder after its path, with every
    /// character other than a letter or digit turned into "-".
    static func projectFolderName(for cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    static func transcript(for session: SessionFile) -> URL? {
        let folder = projectsFolder.appending(path: projectFolderName(for: session.cwd))
        let file = folder.appending(path: "\(session.sessionId).jsonl")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        // Very long paths are shortened with a hash; look the session up instead.
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projectsFolder.path)) ?? []
        let prefix = String(projectFolderName(for: session.cwd).prefix(120))
        for name in folders where name.hasPrefix(prefix) {
            let candidate = projectsFolder.appending(path: name).appending(path: "\(session.sessionId).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: The log

    /// What the latest part of a session's log says, built up line by line.
    struct LogState: Equatable, Sendable {
        /// The tool the agent called last, such as "Bash" or "Edit".
        var lastTool: String?
        var lastToolAt: Date?
        /// Tools called but not answered yet, by call ID.
        var pending: [String: String] = [:]
        /// The command lines of pending Bash calls, sorted into kinds.
        var pendingKinds: [String: CommandKind] = [:]
        /// Failed commands in a row, with no success between.
        var failures = 0
        var lastFailureKind: CommandKind?
        /// When a streak of failures ended with a success.
        var fixedAt: Date?
        var turnStarted: Date?
        var turnEnded: Date?
        var shippedAt: Date?
        /// Pull requests already seen: Claude Code repeats them every turn.
        var pullRequests: Set<String> = []
        /// "rate_limit", "network"… from the latest API error, if the turn stopped on one.
        var apiError: String?
        var apiErrorAt: Date?
        var branch: String?
        var lastActivity: Date?
        /// The waiting calls' requests (command, question, file), by call ID. Memory only.
        var requests: [String: AgentRequest] = [:]
        /// This turn's edited files (memory only, to count them) and test runs.
        var editedFiles: Set<String> = []
        var testsRun = 0
        var testsFailed = 0

        var evidence: TurnEvidence? {
            let evidence = TurnEvidence(filesChanged: editedFiles.count, testsRun: testsRun, testsFailed: testsFailed)
            return evidence.summary == nil ? nil : evidence
        }

        /// What the newest waiting call asks of you.
        var currentRequest: AgentRequest? {
            requests.values.max { $0.since < $1.since }
        }

        /// The tool it's using now: the latest call still waiting for its result.
        var currentTool: String? {
            if let lastTool, pending.values.contains(lastTool) { return lastTool }
            return pending.values.first ?? lastTool
        }

        /// Reads one log line. Long lines (big tool results) are only scanned,
        /// never decoded.
        mutating func consume(_ line: Substring) {
            if line.utf8.count > 128_000 {
                consumeLarge(line)
                return
            }
            guard let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            consume(record)
        }

        mutating func consume(_ record: [String: Any]) {
            let time = (record["timestamp"] as? String).flatMap(LogState.date(from:))
            if let time { lastActivity = time }
            if let branch = record["gitBranch"] as? String, !branch.isEmpty { self.branch = branch }
            switch record["type"] as? String {
            case "assistant":
                if record["isSidechain"] as? Bool == true { return }
                if record["isApiErrorMessage"] as? Bool == true {
                    apiError = (record["error"] as? String) ?? "unknown"
                    apiErrorAt = time
                }
                guard let message = record["message"] as? [String: Any] else { return }
                for part in (message["content"] as? [[String: Any]]) ?? [] where part["type"] as? String == "tool_use" {
                    guard let id = part["id"] as? String, let name = part["name"] as? String else { continue }
                    pending[id] = name
                    lastTool = name
                    lastToolAt = time
                    let input = part["input"] as? [String: Any] ?? [:]
                    if name == "Bash", let command = input["command"] as? String {
                        pendingKinds[id] = CommandKind.of(command)
                    }
                    if let request = LogState.request(tool: name, input: input, at: time ?? lastActivity ?? Date()) {
                        requests[id] = request
                    }
                    if ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(name),
                       let path = (input["file_path"] ?? input["notebook_path"]) as? String {
                        editedFiles.insert(path)
                    }
                }
                if message["stop_reason"] as? String == "end_turn" {
                    turnEnded = time
                    pending.removeAll()
                    pendingKinds.removeAll()
                    requests.removeAll()
                }
            case "user":
                if record["isSidechain"] as? Bool == true { return }
                let message = record["message"] as? [String: Any]
                let parts = (message?["content"] as? [[String: Any]]) ?? []
                let results = parts.filter { $0["type"] as? String == "tool_result" }
                if results.isEmpty {
                    // A new prompt from you starts a turn (not a summary or a command's output).
                    if record["isMeta"] as? Bool != true, record["isCompactSummary"] as? Bool != true,
                       (message?["role"] as? String) == "user" {
                        startTurn(at: time)
                    }
                    return
                }
                for part in results {
                    guard let id = part["tool_use_id"] as? String else { continue }
                    result(id: id, failed: part["is_error"] as? Bool == true, at: time)
                }
            case "pr-link":
                // Only a pull request this session hasn't linked before is news.
                let pr = record["prUrl"] as? String ?? (record["prNumber"] as? Int).map(String.init) ?? ""
                if pullRequests.insert(pr).inserted { shippedAt = time ?? lastActivity }
            case "system":
                if record["subtype"] as? String == "api_error" {
                    let error = record["error"] as? [String: Any]
                    apiError = error?["isNetworkDown"] as? Bool == true ? "network" : (error?["type"] as? String ?? "api")
                    apiErrorAt = time
                }
            default:
                break
            }
        }

        private mutating func startTurn(at time: Date?) {
            turnStarted = time
            turnEnded = nil
            lastTool = nil
            requests.removeAll()
            editedFiles.removeAll()
            testsRun = 0
            testsFailed = 0
            apiError = nil
            fixedAt = nil
            shippedAt = nil
            // A new prompt starts fresh: no failure streak, nothing left pending.
            failures = 0
            lastFailureKind = nil
            pending.removeAll()
            pendingKinds.removeAll()
        }

        private mutating func result(id: String, failed: Bool, at time: Date?) {
            let tool = pending.removeValue(forKey: id)
            let kind = pendingKinds.removeValue(forKey: id)
            requests[id] = nil
            apiError = nil
            guard tool == "Bash" else { return }
            if kind == .test {
                testsRun += 1
                if failed { testsFailed += 1 }
            }
            if failed {
                failures += 1
                lastFailureKind = kind
            } else {
                if failures >= LogState.stuckAfter { fixedAt = time }
                failures = 0
                lastFailureKind = nil
            }
        }

        /// A huge line is almost always a tool result: find its call and
        /// whether it failed without decoding it. The flags can come before
        /// or after the content, so both ends are checked.
        private mutating func consumeLarge(_ line: Substring) {
            let head = line.prefix(4000), tail = line.suffix(4000)
            guard head.contains("\"tool_result\""), !head.contains("\"isSidechain\":true"),
                  !tail.contains("\"isSidechain\":true"),
                  let range = head.range(of: "\"tool_use_id\":\"") else { return }
            let id = head[range.upperBound...].prefix { $0 != "\"" }
            let failed = head.contains("\"is_error\":true") || tail.contains("\"is_error\":true")
            result(id: String(id), failed: failed, at: nil)
        }

        /// The request a tool call makes of you, if it has to wait for you:
        /// the command, the question with its answers, the file, the address.
        static func request(tool: String, input: [String: Any], at time: Date) -> AgentRequest? {
            func short(_ text: String, _ limit: Int = 240) -> String {
                let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
                return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
            }
            switch tool {
            case "Bash":
                guard let command = input["command"] as? String else { return nil }
                return AgentRequest(kind: .command, text: short(command), since: time)
            case "AskUserQuestion":
                guard let question = (input["questions"] as? [[String: Any]])?.first,
                      let text = question["question"] as? String else { return nil }
                let options = ((question["options"] as? [[String: Any]]) ?? []).compactMap { $0["label"] as? String }
                return AgentRequest(kind: .question, text: short(text, 400), options: Array(options.prefix(4)), since: time)
            case "Edit", "Write", "MultiEdit", "NotebookEdit":
                guard let path = (input["file_path"] ?? input["notebook_path"]) as? String else { return nil }
                return AgentRequest(kind: .edit, text: (path as NSString).lastPathComponent, since: time)
            case "WebFetch":
                guard let url = (input["url"] as? String).flatMap(URL.init(string:)) else { return nil }
                return AgentRequest(kind: .web, text: url.host() ?? url.absoluteString, since: time)
            case "ExitPlanMode":
                return AgentRequest(kind: .plan, text: "A plan to approve", since: time)
            default:
                return nil
            }
        }

        /// Three failed commands in a row, with no success between, is stuck;
        /// one or two are normal while testing a fix.
        static let stuckAfter = 3

        nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        static func date(from string: String) -> Date? {
            isoFormatter.date(from: string)
        }
    }

    // MARK: Putting it together

    /// The owlet's state from the session file and its log.
    static func state(file: SessionFile, log: LogState, helpers: [AgentHelper], now: Date)
        -> (state: OwletState, detail: String?) {
        let status = file.status ?? "idle"
        if status == "waiting" || file.waitingFor != nil {
            if log.pending.values.contains("AskUserQuestion") { return (.asking, "Has a question for you") }
            if log.pending.values.contains("ExitPlanMode") { return (.needsYou, "Has a plan for you to approve") }
            return (.needsYou, waitingDetail(file.waitingFor, tool: log.currentTool))
        }
        if let error = log.apiError, let at = log.apiErrorAt, now.timeIntervalSince(at) < 15 * 60 {
            if error.contains("rate_limit") { return (.teaBreak, "Paused for the plan limit") }
            if error == "network" { return (.offline, "Can't reach the internet") }
        }
        // A session marked busy for hours with nothing in its log since was
        // most likely left behind; don't keep the Mac awake for it.
        let lastSign = [log.lastActivity, file.statusSince].compactMap { $0 }.max()
        // A long silent command (a two-hour build) still counts as work.
        if status == "busy", log.pending.isEmpty, let lastSign, now.timeIntervalSince(lastSign) > 2 * 3600 {
            return (.napping, nil)
        }
        if status == "busy" {
            if let newest = helpers.map(\.started).max(), now.timeIntervalSince(newest) < 4 {
                return (.hatching, "Starting a helper")
            }
            if log.failures >= LogState.stuckAfter {
                return (.fixing, "Fixing after \(log.failures) failed \(noun(log.lastFailureKind))")
            }
            if let tool = log.currentTool {
                if tool == "Agent" || tool == "Task", helpers.contains(where: \.isWorking) {
                    return (.waitingOnHelpers, helpers.count == 1 ? "1 helper working" : "\(helpers.count) helpers working")
                }
                return (flavour(of: tool), nil)
            }
            return (.thinking, nil)
        }
        // Idle: waiting for your next prompt.
        if log.failures >= LogState.stuckAfter {
            return (.stuck, "Stopped after \(log.failures) failed \(noun(log.lastFailureKind))")
        }
        let since = file.statusSince ?? log.turnEnded ?? file.started
        if let shipped = log.shippedAt, now.timeIntervalSince(shipped) < 120 { return (.shipped, "Opened a pull request") }
        if now.timeIntervalSince(since) < 60 * 60, let turn = turnLength(log), turn >= 120 {
            let evidence = log.evidence?.summary.map { " · \($0)" } ?? ""
            return (.done, "Your turn · finished after \(duration(turn))\(evidence)")
        }
        return now.timeIntervalSince(since) > 10 * 60 ? (.napping, nil) : (.resting, nil)
    }

    static func turnLength(_ log: LogState) -> TimeInterval? {
        guard let start = log.turnStarted, let end = log.turnEnded, end > start else { return nil }
        return end.timeIntervalSince(start)
    }

    static func flavour(of tool: String) -> OwletState {
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit": .typing
        case "Read", "Grep", "Glob", "LS", "ToolSearch": .searching
        case "Bash", "BashOutput", "KillShell", "Monitor": .running
        case "WebFetch", "WebSearch": .browsing
        case "Agent", "Task": .hatching
        case "AskUserQuestion": .asking
        default: tool.hasPrefix("mcp__") ? .running : .thinking
        }
    }

    static func waitingDetail(_ waitingFor: String?, tool: String?) -> String {
        if waitingFor == "input needed" { return "Needs your input" }
        if waitingFor == "sandbox request" { return "Wants network access for a command" }
        switch tool {
        case "Bash": return "Wants to run a command"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "Wants to edit a file"
        case "WebFetch", "WebSearch": return "Wants to look something up"
        default: return "Wants your permission"
        }
    }

    static func noun(_ kind: CommandKind?) -> String {
        switch kind {
        case .test: "test runs"
        case .build: "builds"
        case .git: "git commands"
        default: "commands"
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    // MARK: Helpers (subagents)

    /// A session's subagents, from `<session>/subagents/agent-<id>.meta.json`.
    /// One still writing to its log in the last 20 seconds counts as working.
    static func helpers(transcript: URL, now: Date) -> [AgentHelper] {
        let folder = transcript.deletingPathExtension().appending(path: "subagents")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var helpers: [AgentHelper] = []
        for name in names where name.hasSuffix(".meta.json") {
            let id = String(name.dropLast(".meta.json".count))
            let log = folder.appending(path: "\(id).jsonl")
            guard let times = FileTimes.of(log.path), now.timeIntervalSince(times.modified) < 10 * 60 else { continue }
            let modified = times.modified, created = times.created
            guard let data = try? Data(contentsOf: folder.appending(path: name)),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            helpers.append(AgentHelper(id: id, type: meta["agentType"] as? String ?? "helper",
                                       task: meta["description"] as? String ?? "",
                                       isWorking: now.timeIntervalSince(modified) < 20, started: created))
        }
        return helpers.sorted { $0.started < $1.started }
    }
}

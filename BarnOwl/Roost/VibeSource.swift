import Foundation

/// Reads Mistral Vibe's session store (`~/.vibe/logs/session`), read-only.
///
/// Vibe 3 keeps each session in `unified/<id>/`: a `meta.json` with its folder
/// and title, and a journal of what happened (`journal/<sequence>.jsonl`) that
/// it appends to as the turn goes and starts afresh after each turn. A running
/// Vibe holds a lease on its session in `active/<id>.lock.json`, which names
/// its process. Only states, tool names, the request waiting on you and
/// timing are read, never prompts, replies or output.
enum VibeSource {
    static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["VIBE_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".vibe")
    }

    static var sessionsFolder: URL { home.appending(path: "logs/session") }
    static var leasesFolder: URL { sessionsFolder.appending(path: "active") }

    // MARK: Which session a process runs

    /// The process each open session belongs to, from the leases:
    /// `{"process_id":38711,"session_id":"a8700966-…",…}`.
    static func leases(in folder: URL = sessionsFolder) -> [Int32: String] {
        let active = folder.appending(path: "active")
        var leases: [Int32: String] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: active.path)) ?? []
        where name.hasSuffix(".lock.json") {
            guard let data = FileManager.default.contents(atPath: active.appending(path: name).path),
                  let lease = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (lease["process_id"] as? NSNumber)?.int32Value,
                  let session = lease["session_id"] as? String, isSessionID(session) else { continue }
            leases[pid] = session
        }
        return leases
    }

    /// The session a Vibe process runs. The lease names the app server Vibe
    /// starts as its child, or the process itself when an editor hosts Vibe.
    static func session(of pid: Int32, leases: [Int32: String], parentOf: (Int32) -> Int32?) -> String? {
        if let own = leases[pid] { return own }
        return leases.first { parentOf($0.key) == pid }?.value
    }

    /// Session IDs become folder names, so only plain ones are used.
    static func isSessionID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    static func folder(of session: String, in folder: URL = sessionsFolder) -> URL {
        folder.appending(path: "unified").appending(path: session)
    }

    /// The session's title and model, from `meta.json`.
    struct Meta: Equatable, Sendable {
        var title: String?
        var model: String?
    }

    static func meta(of session: URL) -> Meta? {
        guard let data = FileManager.default.contents(atPath: session.appending(path: "meta.json").path),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let title = (meta["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = meta["config"] as? [String: Any]
        return Meta(title: title?.isEmpty == false ? title : nil,
                    model: (config?["active_model"] ?? config?["model_name"]) as? String)
    }

    /// The display names of the models in Vibe's config, by alias:
    /// `{ alias = "glm-5.3", …, display_name = "GLM 5.3", … }`.
    static func modelNames(config: URL = home.appending(path: "config.toml")) -> [String: String] {
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return [:] }
        func value(_ key: String, in line: Substring) -> String? {
            guard let range = line.range(of: #"\b"# + key + #"\s*=\s*"([^"]{1,80})""#, options: .regularExpression)
            else { return nil }
            let match = line[range]
            guard let open = match.firstIndex(of: "\"") else { return nil }
            return String(match[match.index(after: open)...].dropLast())
        }
        // Vibe writes models either as inline tables, one per line, or as `[[models]]`
        // blocks with a key per line (after it saves the config itself).
        var names: [String: String] = [:]
        var alias: String?, display: String?
        func keep() {
            if let alias, let display { names[alias] = display }
            alias = nil
            display = nil
        }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[\"") { keep() }
            if let found = value("alias", in: line) {
                if value("display_name", in: line) == nil, trimmed.hasPrefix("{") { keep() }
                alias = found
            }
            if let found = value("display_name", in: line) { display = found }
            if trimmed.hasPrefix("{") || trimmed.hasSuffix("},") || trimmed.hasSuffix("}") { keep() }
        }
        keep()
        return names
    }

    /// The journal's segments, oldest first: `journal/0000000000000043.jsonl`.
    static func segments(of session: URL) -> [URL] {
        let journal = session.appending(path: "journal")
        return ((try? FileManager.default.contentsOfDirectory(atPath: journal.path)) ?? [])
            .filter { $0.hasSuffix(".jsonl") && $0.dropLast(6).allSatisfy(\.isNumber) }
            .sorted()
            .map { journal.appending(path: $0) }
    }

    // MARK: What it's doing

    struct LogState: Equatable, Sendable {
        /// "running", "idle", "failed" or "archived".
        var status: String?
        /// The latest turn's "in_progress", "completed", "failed" or "interrupted".
        var turnStatus: String?
        var turnStarted: Date?
        var turnEnded: Date?
        /// The tool running now, if one is.
        var runningTool: String?
        var lastTool: String?
        var failures = 0
        var rateLimited = false
        /// Approvals and questions waiting on you, by callback ID.
        var open: [String: AgentRequest] = [:]
        /// The order they were asked in.
        var openOrder: [String] = []
        /// The model call it's waiting on, if any: Vibe asked the model and has no answer yet.
        var pendingCompletion: String?

        mutating func consume(_ line: Substring) {
            guard line.utf8.count < 2_000_000, let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            consume(record)
        }

        mutating func consume(_ record: [String: Any]) {
            guard let payload = record["payload"] as? [String: Any] else { return }
            switch record["type"] as? String {
            case "projection_delta":
                for change in (payload["delta"] as? [[String: Any]]) ?? [] {
                    switch change["op"] as? String {
                    case "set_envelope":
                        if let state = change["state"] as? [String: Any] { envelope(state) }
                    case "append_entry", "replace_entry":
                        if let entry = change["entry"] as? [String: Any] { self.entry(entry) }
                    default:
                        break
                    }
                }
            case "callback_registered":
                guard let id = payload["callback_id"] as? String,
                      let routing = payload["routing"] as? [String: Any] else { return }
                let request = Self.request(kind: payload["kind"] as? String, callback: routing)
                    ?? AgentRequest(kind: .other, text: "Waiting for you", since: Self.date(routing["createdAt"]) ?? Date())
                if open[id] == nil { openOrder.append(id) }
                open[id] = request
            case "action_intent":
                if payload["kind"] as? String == "completion" { pendingCompletion = payload["action_id"] as? String }
            case "action_result":
                if let id = payload["action_id"] as? String, id == pendingCompletion { pendingCompletion = nil }
            case "callback_resolved":
                guard let id = payload["callback_id"] as? String else { return }
                open[id] = nil
                openOrder.removeAll { $0 == id }
            default:
                break
            }
        }

        /// The session's public state: `{"session":{"status":{"type":"running"}},"latestTurn":{…}}`.
        private mutating func envelope(_ state: [String: Any]) {
            let session = state["session"] as? [String: Any]
            if let status = (session?["status"] as? [String: Any])?["type"] as? String {
                if status != "running", self.status == "running" {
                    // A turn that ended can't still be running a tool or waiting.
                    runningTool = nil
                    pendingCompletion = nil
                    open = [:]
                    openOrder = []
                }
                self.status = status
            }
            if let turn = state["latestTurn"] as? [String: Any] {
                let started = Self.date(turn["startedAt"])
                if let started, started != turnStarted {
                    failures = 0
                    rateLimited = false
                }
                turnStarted = started ?? turnStarted
                turnEnded = Self.date(turn["completedAt"])
                turnStatus = turn["status"] as? String
            }
            let retrying = state["retrying"] as? [String: Any]
            rateLimited = (retrying?["category"] as? String) == "rate_limited"
        }

        /// A history entry. Tool runs are effects:
        /// `{"type":"effect","detail":{"toolName":"file_system.bash"},"state":{"status":"running"}}`.
        private mutating func entry(_ entry: [String: Any]) {
            guard entry["type"] as? String == "effect",
                  let detail = entry["detail"] as? [String: Any], detail["kind"] as? String == "tool",
                  let tool = detail["toolName"] as? String else { return }
            let status = (entry["state"] as? [String: Any])?["status"] as? String
            lastTool = tool
            switch status {
            case "running":
                runningTool = tool
            case "failed":
                if runningTool == tool { runningTool = nil }
                if Self.isCommand(tool) { failures += 1 }
            case "completed":
                if runningTool == tool { runningTool = nil }
                if Self.isCommand(tool) { failures = 0 }
            default:
                if runningTool == tool { runningTool = nil }
            }
        }

        /// What an open callback asks of you: the command, the file, the question.
        static func request(kind: String?, callback: [String: Any]) -> AgentRequest? {
            let since = date(callback["createdAt"]) ?? Date()
            guard let detail = callback["detail"] as? [String: Any] else { return nil }
            func short(_ text: String, _ limit: Int = 240) -> String {
                let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
                return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
            }
            if kind == "user_input" || detail["kind"] as? String == "user_input" {
                let input = detail["request"] as? [String: Any] ?? [:]
                let question = (input["questions"] as? [[String: Any]])?.first ?? input
                let text = (question["question"] as? String) ?? "Has a question for you"
                let options = ((question["options"] as? [Any]) ?? []).compactMap { option in
                    (option as? String) ?? ((option as? [String: Any])?["label"] as? String)
                }
                return AgentRequest(kind: .question, text: short(text, 400), options: Array(options.prefix(4)),
                                    since: since, timesOut: false)
            }
            guard let effect = detail["effect"] as? [String: Any], let tool = effect["toolName"] as? String
            else { return nil }
            let input = effect["input"] as? [String: Any] ?? [:]
            if isCommand(tool), let command = input["command"] as? String {
                return AgentRequest(kind: .command, text: short(command), since: since, timesOut: false)
            }
            if isEdit(tool), let path = (input["path"] ?? input["file_path"]) as? String {
                return AgentRequest(kind: .edit, text: (path as NSString).lastPathComponent, since: since, timesOut: false)
            }
            if isWeb(tool) {
                let address = (input["url"] as? String).flatMap(URL.init(string:))
                return AgentRequest(kind: .web, text: address?.host() ?? (input["query"] as? String).map { short($0) } ?? tool,
                                    since: since, timesOut: false)
            }
            return AgentRequest(kind: .other, text: tool, since: since, timesOut: false)
        }

        /// The request it's waiting on you for, the oldest first.
        var request: AgentRequest? { openOrder.first.flatMap { open[$0] } }

        /// `thinkingSince`: when the model call it's waiting on was first seen, for "Thinking · 3 min".
        func state(now: Date, thinkingSince: Date? = nil) -> (state: OwletState, detail: String?) {
            if let request {
                return request.kind == .question ? (.asking, "Has a question for you") : (.needsYou, "Wants your OK")
            }
            if status == "running" {
                if rateLimited { return (.teaBreak, "Paused for the rate limit") }
                if failures >= ClaudeSource.LogState.stuckAfter {
                    return (.fixing, "Fixing after \(failures) failed commands")
                }
                guard let tool = runningTool else {
                    // A long answer looks like a hang; say how long the model has been at it.
                    if pendingCompletion != nil, let since = thinkingSince, now.timeIntervalSince(since) >= 90 {
                        return (.thinking, "Thinking · \(ClaudeSource.duration(now.timeIntervalSince(since)))")
                    }
                    return (.thinking, nil)
                }
                if Self.isCommand(tool) { return (.running, nil) }
                if Self.isEdit(tool) { return (.typing, nil) }
                if Self.isWeb(tool) { return (.browsing, nil) }
                if Self.isHelpers(tool) { return (.waitingOnHelpers, nil) }
                if tool.hasSuffix("read_file") || tool.hasSuffix("grep") || tool == "skill.read" { return (.searching, nil) }
                return (.thinking, nil)
            }
            if status == "failed" || turnStatus == "failed" {
                if let ended = turnEnded, now.timeIntervalSince(ended) < 60 * 60 { return (.stuck, "Its last turn failed") }
            }
            if failures >= ClaudeSource.LogState.stuckAfter { return (.stuck, "Stopped after \(failures) failed commands") }
            let since = turnEnded ?? .distantPast
            if turnStatus == "completed", now.timeIntervalSince(since) < 60 * 60, let turn = lastTurn, turn >= 120 {
                return (.done, "Your turn · finished after \(ClaudeSource.duration(turn))")
            }
            return now.timeIntervalSince(since) > 10 * 60 ? (.napping, nil) : (.resting, nil)
        }

        /// How long the last finished turn ran.
        var lastTurn: TimeInterval? {
            guard let started = turnStarted, let ended = turnEnded, ended >= started else { return nil }
            return ended.timeIntervalSince(started)
        }

        // Vibe 3 names tools by group ("file_system.bash"); Vibe 2 didn't ("bash").
        static func isCommand(_ tool: String) -> Bool {
            tool == "file_system.bash" || tool == "bash" || tool == "process.start"
        }

        static func isEdit(_ tool: String) -> Bool {
            ["file_system.write_file", "file_system.search_replace", "write_file", "search_replace", "edit"].contains(tool)
        }

        static func isWeb(_ tool: String) -> Bool {
            tool.hasSuffix("web_search") || tool.hasSuffix("web_fetch")
        }

        static func isHelpers(_ tool: String) -> Bool {
            tool.hasPrefix("agents.") || tool.hasPrefix("subagent.") || tool == "task"
                || tool == "self.wait" || tool == "self.sleep"
        }

        /// Vibe writes times as milliseconds since 1970.
        static func date(_ value: Any?) -> Date? {
            (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
    }

    // MARK: Following a session

    /// Reads a session's journal as it grows, across its segments.
    struct Follower: Sendable {
        let session: String
        var segment: URL?
        var offset: UInt64 = 0
        var partial = Data()
        var log = LogState()
        /// When the model call it's waiting on was first seen. The journal has no times of its own.
        var thinkingSince: Date?

        init(session: String) { self.session = session }

        /// Reads what was added since last time. The first time, the last two
        /// segments are read (the newest is empty between turns), at most the
        /// last 256 KB of each.
        mutating func read(folder: URL, now: Date = Date()) {
            let before = log.pendingCompletion
            defer {
                if log.pendingCompletion == nil {
                    thinkingSince = nil
                } else if log.pendingCompletion != before || thinkingSince == nil {
                    thinkingSince = now
                }
            }
            let segments = VibeSource.segments(of: folder)
            guard !segments.isEmpty else { return }
            let known = segment.flatMap { segments.firstIndex(of: $0) }
            for url in segments[(known ?? max(0, segments.count - 2))...] {
                guard segment != url else {
                    readSegment(url, skippingFirst: false)
                    continue
                }
                segment = url
                partial = Data()
                // A segment begun since the last read is read whole.
                let size = known == nil ? FileTimes.size(url.path) ?? 0 : 0
                offset = size > 256 * 1024 ? size - 256 * 1024 : 0
                readSegment(url, skippingFirst: offset > 0)
            }
        }

        private mutating func readSegment(_ url: URL, skippingFirst: Bool) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { return }
            if size < offset { offset = 0; partial = Data() }
            guard size > offset else { return }
            let length = min(size - offset, 8 * 1024 * 1024)
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.read(upToCount: Int(length)), !data.isEmpty else { return }
            offset += UInt64(data.count)
            var bytes = partial + data
            partial = Data()
            if bytes.last != UInt8(ascii: "\n") {
                let cut = bytes.lastIndex(of: UInt8(ascii: "\n"))
                partial = cut.map { Data(bytes[bytes.index(after: $0)...]) } ?? bytes
                bytes = cut.map { Data(bytes[...$0]) } ?? Data()
            }
            var lines = bytes.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            if skippingFirst, !lines.isEmpty { lines.removeFirst() }
            for line in lines { log.consume(Substring(String(decoding: line, as: UTF8.self))) }
            if partial.count > 4 * 1024 * 1024 { partial = Data() }
        }
    }
}

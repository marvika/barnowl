import AppKit
import Foundation

/// Answering Claude Code from the island, through its own hooks.
///
/// Turned on, two hooks in ~/.claude/settings.json run Barn Owl's binary
/// (`Barn Owl --answer`) as Claude Code is about to ask for permission or
/// put a question to you. That small process leaves the request in a folder
/// Barn Owl watches and waits for your answer from the island: Allow Once,
/// Deny, or the "don't ask again" rule Claude Code itself suggests (shown
/// with exactly what it covers); or one of the question's options.
///
/// It always steps aside, so the usual prompt appears, when Barn Owl isn't
/// running, when you're already in that session's app or switch to it, when
/// you choose "Answer in Terminal", when the session moves on by itself (you
/// answered in the Claude app), or after ten minutes. Nothing is ever allowed
/// without a click, and a standing rule only ever as Claude Code proposed it.
enum IslandAnswers {
    static let flag = "--answer"

    /// A request waiting in the folder.
    struct Ask: Codable, Hashable, Sendable, Identifiable {
        enum Kind: String, Codable, Hashable, Sendable { case permission, question }
        let id: String
        let kind: Kind
        /// Claude Code's session ID.
        let session: String
        /// The hook process waiting for the answer.
        let pid: Int32
        let tool: String
        let asked: Date
        /// The command, file or address; or the question.
        let text: String
        /// The question's options, in order.
        var options: [String] = []
        /// What Claude Code's own "don't ask again" would cover, when it
        /// offers one: "www.vg.no", "npm test commands".
        var always: String?
    }

    enum Reply: Codable, Equatable, Sendable {
        case allow, deny
        /// Allow, and add the rule Claude Code suggested, so it doesn't ask again.
        case always
        /// Picked option label.
        case answer(String)
        /// Let the usual prompt take it.
        case pass
    }

    static var folder: URL { PlanLimits.relayFile.deletingLastPathComponent().appending(path: "answers") }
    private static var listening: URL { folder.appending(path: "listening") }
    /// Longest a request is held before the usual prompt takes over.
    static let holdFor: TimeInterval = 10 * 60

    // MARK: The app's side

    /// Says Barn Owl is listening (its PID), or stops.
    /// Barn Owl holds a lock on the `listening` file while it listens; the
    /// system lets go of it the moment Barn Owl quits or crashes, so a hook
    /// never waits on an app that isn't there.
    nonisolated(unsafe) private static var lock: Int32 = -1

    static func listen(_ on: Bool) {
        if on {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            guard lock < 0 else { return }
            let descriptor = open(listening.path, O_RDWR | O_CREAT, 0o600)
            guard descriptor >= 0 else { return }
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                lock = descriptor
            } else {
                close(descriptor)
            }
        } else {
            if lock >= 0 {
                flock(lock, LOCK_UN)
                close(lock)
                lock = -1
            }
            try? FileManager.default.removeItem(at: listening)
            // Anyone still waiting gets the usual prompt.
            for ask in pending() { reply(.pass, to: ask) }
        }
    }

    /// Requests whose hook is still waiting; leftovers are cleared away.
    static func pending(now: Date = Date()) -> [Ask] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var asks: [Ask] = []
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "ask" {
            guard let data = try? Data(contentsOf: file), let ask = try? decoder.decode(Ask.self, from: data) else { continue }
            if kill(ask.pid, 0) != 0 || now.timeIntervalSince(ask.asked) > holdFor + 30 {
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.removeItem(at: replyFile(ask.id))
                continue
            }
            if FileManager.default.fileExists(atPath: replyFile(ask.id).path) { continue }
            asks.append(ask)
        }
        return asks.sorted { $0.asked < $1.asked }
    }

    static func reply(_ reply: Reply, to ask: Ask) {
        guard let data = try? JSONEncoder().encode(reply) else { return }
        FileManager.default.createFile(atPath: replyFile(ask.id).path, contents: data,
                                       attributes: [.posixPermissions: 0o600])
    }

    private static func askFile(_ id: String) -> URL { folder.appending(path: "\(id).ask") }
    private static func replyFile(_ id: String) -> URL { folder.appending(path: "\(id).reply") }

    // MARK: The hook's side

    /// `Barn Owl --answer`, run by Claude Code with the hook's input on
    /// standard input. Prints a decision, or nothing to let the usual
    /// prompt take it. Never starts the app.
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2, arguments[1] == flag else { return }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        if let output = answer(input) { FileHandle.standardOutput.write(output) }
        exit(0)
    }

    /// Leaves the request, waits for the answer, and turns it into the hook's output.
    static func answer(_ input: Data, folder: URL = folder, wait: TimeInterval = holdFor,
                       listener: () -> Bool = { isListening() }) -> Data? {
        guard listener(), let hook = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let ask = ask(from: hook) else { return nil }
        let askURL = folder.appending(path: "\(ask.id).ask"), replyURL = folder.appending(path: "\(ask.id).reply")
        guard let data = try? JSONEncoder().encode(ask),
              FileManager.default.createFile(atPath: askURL.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { return nil }
        defer {
            try? FileManager.default.removeItem(at: askURL)
            try? FileManager.default.removeItem(at: replyURL)
        }
        let deadline = Date().addingTimeInterval(wait)
        var looks = 0
        while Date() < deadline {
            if let data = try? Data(contentsOf: replyURL), let reply = try? JSONDecoder().decode(Reply.self, from: data) {
                return output(for: reply, ask: ask, hook: hook)
            }
            looks += 1
            // Barn Owl quit meanwhile: the usual prompt.
            if looks % 20 == 0, !listener() { return nil }
            usleep(100_000)
        }
        return nil
    }

    /// Whether Barn Owl holds its lock: if this hook can take the lock, nobody does.
    static func isListening(at url: URL = listening) -> Bool {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_SH | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return false
        }
        return true
    }

    /// The request as the island shows it. Questions with several parts or
    /// several choices are left to the usual prompt.
    static func ask(from hook: [String: Any], now: Date = Date()) -> Ask? {
        guard let session = hook["session_id"] as? String, let tool = hook["tool_name"] as? String else { return nil }
        let input = hook["tool_input"] as? [String: Any] ?? [:]
        let id = UUID().uuidString
        switch hook["hook_event_name"] as? String {
        case "PermissionRequest":
            guard tool != "AskUserQuestion" else { return nil }
            // The command, file or address; for any other tool, its name and
            // every argument, so nothing is allowed unseen.
            let text = ["command", "file_path", "url", "pattern", "path", "query"].lazy
                .compactMap { input[$0] as? String }.first ?? summary(tool: tool, input: input)
            return Ask(id: id, kind: .permission, session: session, pid: getpid(), tool: tool, asked: now, text: text,
                       always: alwaysScope(allowing(hook["permission_suggestions"])))
        case "PreToolUse":
            guard tool == "AskUserQuestion", let questions = input["questions"] as? [[String: Any]], questions.count == 1,
                  let question = questions[0]["question"] as? String,
                  (questions[0]["multiSelect"] as? Bool) != true,
                  let options = questions[0]["options"] as? [[String: Any]] else { return nil }
            let labels = options.compactMap { $0["label"] as? String }
            guard !labels.isEmpty else { return nil }
            return Ask(id: id, kind: .question, session: session, pid: getpid(), tool: tool, asked: now, text: question,
                       options: labels)
        default:
            return nil
        }
    }

    /// The hook's output for an answer, as Claude Code's hooks reference describes it.
    static func output(for reply: Reply, ask: Ask, hook: [String: Any]) -> Data? {
        let decision: [String: Any]
        switch (reply, ask.kind) {
        case (.pass, _):
            return nil
        case (.allow, .permission):
            decision = ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]
        case (.always, .permission):
            let rules = allowing(hook["permission_suggestions"])
            guard !rules.isEmpty else { return nil }
            decision = ["hookEventName": "PermissionRequest",
                        "decision": ["behavior": "allow", "updatedPermissions": rules]]
        case (.deny, .permission):
            decision = ["hookEventName": "PermissionRequest",
                        "decision": ["behavior": "deny", "message": "Denied from Barn Owl's island."]]
        case (.answer(let label), .question):
            guard ask.options.contains(label) else { return nil }
            var input = hook["tool_input"] as? [String: Any] ?? [:]
            input["answers"] = [ask.text: label]
            decision = ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": input]
        default:
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": decision])
    }

    /// Claude Code's suggestions that allow something; others are left out.
    static func allowing(_ suggestions: Any?) -> [[String: Any]] {
        ((suggestions as? [[String: Any]]) ?? []).filter { suggestion in
            switch suggestion["type"] as? String {
            case "addRules", "replaceRules": suggestion["behavior"] as? String == "allow"
            case "addDirectories", "setMode": true
            default: false
            }
        }
    }

    /// What those suggestions cover, in a few words: "www.vg.no",
    /// "npm test commands", "files in ~/code/site", "edits, this session".
    static func alwaysScope(_ suggestions: [[String: Any]]) -> String? {
        var parts: [String] = []
        for suggestion in suggestions {
            switch suggestion["type"] as? String {
            case "addDirectories":
                let folders = (suggestion["directories"] as? [String] ?? []).map { ($0 as NSString).abbreviatingWithTildeInPath }
                parts += folders.map { "files in \($0)" }
            case "setMode":
                parts.append(suggestion["mode"] as? String == "acceptEdits" ? "all edits" : "\(suggestion["mode"] as? String ?? "this mode")")
            default:
                for rule in suggestion["rules"] as? [[String: Any]] ?? [] {
                    parts.append(scope(tool: rule["toolName"] as? String ?? "", content: rule["ruleContent"] as? String))
                }
            }
        }
        // Offered only when everything it would allow fits on the button.
        guard !parts.isEmpty, parts.count <= 2 else { return nil }
        let session = suggestions.allSatisfy { $0["destination"] as? String == "session" }
        return parts.joined(separator: ", ") + (session ? ", this session" : "")
    }

    private static func scope(tool: String, content: String?) -> String {
        guard let content, !content.isEmpty else { return "all \(tool)" }
        if content.hasPrefix("domain:") { return String(content.dropFirst(7)) }
        if tool == "Bash" {
            return content.hasSuffix(":*") ? "\(content.dropLast(2)) commands" : content
        }
        return "\(tool) \(content)"
    }

    /// "send_email · to: ana@… · subject: Hi" for a tool without an obvious target.
    static func summary(tool: String, input: [String: Any]) -> String {
        let name = tool.split(separator: "__").last.map(String.init) ?? tool
        let arguments = input.keys.sorted().map { key -> String in
            let value = input[key].map { value in
                (value as? String) ?? (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
                    .map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
            } ?? ""
            return "\(key): \(value)"
        }
        return ([name] + arguments).joined(separator: "\n")
    }

    // MARK: Turning it on and off

    /// `b='…/Barn Owl'; [ -x "$b" ] && exec "$b" --answer; :` (nothing, if Barn Owl is gone)
    static func command(binary: String) -> String {
        "b=\(StatusLineRelay.shellQuoted(binary)); [ -x \"$b\" ] && exec \"$b\" \(flag); :"
    }

    /// Exactly the command `command(binary:)` writes, so a hook of the user's own that
    /// merely mentions Barn Owl is never taken for ours (and removed).
    static func isOurs(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.hasPrefix("b='") && command.hasSuffix("[ -x \"$b\" ] && exec \"$b\" \(flag); :")
    }

    /// Our two hook entries.
    static func entries(binary: String) -> [String: [String: Any]] {
        let hook: [String: Any] = ["type": "command", "command": command(binary: binary), "timeout": Int(holdFor) + 15]
        return ["PermissionRequest": ["matcher": "*", "hooks": [hook]],
                "PreToolUse": ["matcher": "AskUserQuestion", "hooks": [hook]]]
    }

    static func isOn(files: StatusLineRelay.Files = .standard) -> Bool {
        guard let settings = try? StatusLineRelay.readSettings(files), let hooks = settings["hooks"] as? [String: Any]
        else { return false }
        return hooks.values.contains { event in
            ((event as? [[String: Any]]) ?? []).contains { (($0["hooks"] as? [[String: Any]]) ?? []).contains(where: isOurs) }
        }
    }

    /// What the hooks setting would become, for showing before anything changes.
    static func preview(files: StatusLineRelay.Files = .standard) throws -> (before: String, after: String) {
        guard let binary = StatusLineRelay.installedBinary else { throw StatusLineRelay.Failure.notInstalled }
        let settings = try StatusLineRelay.readSettings(files)
        let after = adding(binary: binary, to: settings["hooks"] as? [String: Any] ?? [:])
        return (settings["hooks"].map(StatusLineRelay.pretty) ?? "(none)", StatusLineRelay.pretty(after))
    }

    static func turnOn(files: StatusLineRelay.Files = .standard,
                       binary: String? = StatusLineRelay.installedBinary) throws {
        guard let binary else { throw StatusLineRelay.Failure.notInstalled }
        try StatusLineRelay.changing {
            var (settings, bytes) = try StatusLineRelay.snapshot(files)
            try StatusLineRelay.backUp(files)
            settings["hooks"] = adding(binary: binary, to: removing(from: settings["hooks"] as? [String: Any] ?? [:]))
            try StatusLineRelay.write(settings, files, over: bytes)
        }
    }

    static func turnOff(files: StatusLineRelay.Files = .standard) throws {
        try StatusLineRelay.changing {
            var (settings, bytes) = try StatusLineRelay.snapshot(files)
            guard let hooks = settings["hooks"] as? [String: Any] else { return }
            let left = removing(from: hooks)
            // None of them ours: leave the file exactly as it is.
            guard !NSDictionary(dictionary: left).isEqual(to: hooks) else { return }
            if left.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = left }
            try StatusLineRelay.write(settings, files, over: bytes)
        }
    }

    /// After an update or a move, point the hooks at this copy.
    static func repointIfNeeded(files: StatusLineRelay.Files = .standard) {
        guard let binary = StatusLineRelay.installedBinary, isOn(files: files) else { return }
        try? StatusLineRelay.changing {
            guard var (settings, bytes) = try? StatusLineRelay.snapshot(files),
                  let hooks = settings["hooks"] as? [String: Any],
                  !StatusLineRelay.pretty(hooks).contains(StatusLineRelay.shellQuoted(binary)) else { return }
            settings["hooks"] = adding(binary: binary, to: removing(from: hooks))
            try StatusLineRelay.write(settings, files, over: bytes)
        }
    }

    static func adding(binary: String, to hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for (event, entry) in entries(binary: binary) {
            hooks[event] = ((hooks[event] as? [[String: Any]]) ?? []) + [entry]
        }
        return hooks
    }

    /// The hooks without ours; events left empty are dropped.
    static func removing(from hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var group = group
                let inner = ((group["hooks"] as? [[String: Any]]) ?? []).filter { !isOurs($0) }
                guard !inner.isEmpty else { return nil }
                group["hooks"] = inner
                return group
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        return hooks
    }
}

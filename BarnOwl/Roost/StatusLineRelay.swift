import Foundation

/// Claude Code hands its status line command your plan limits, with reset
/// times. With the relay on, that command first runs Barn Owl
/// (`Barn Owl --statusline`), which saves only the limits and then becomes
/// your own status line command, so your status line looks exactly as before.
///
/// The command carries your original with it: if Barn Owl is moved or
/// deleted, it simply runs your original, so the status line never breaks.
/// Turning it on edits `statusLine` in ~/.claude/settings.json after a
/// backup; turning it off puts back what was there.
enum StatusLineRelay {
    static let flag = "--statusline"

    enum Failure: Error, Equatable {
        case unreadableSettings
        case couldNotWrite
        /// The file changed between reading and writing: read it again.
        case changedMeanwhile
        /// Barn Owl runs from a temporary or downloaded copy; move it to Applications first.
        case notInstalled
    }

    /// Where things live; tests use their own.
    struct Files {
        var settings: URL
        var support: URL

        static var standard: Files {
            Files(settings: ClaudeSource.home.appending(path: "settings.json"),
                  support: PlanLimits.relayFile.deletingLastPathComponent())
        }

        /// The status line setting from before, to put it back.
        var original: URL { support.appending(path: "statusline-original.json") }
        var backup: URL { settings.appendingPathExtension("barnowl-backup") }
    }

    /// This copy of Barn Owl's binary, if it's installed somewhere it stays.
    static var installedBinary: String? {
        guard let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
              !path.contains("/AppTranslocation/"), !path.contains("/DerivedData/"),
              path.contains("/Applications/") else { return nil }
        return path
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `b='…/Barn Owl'; [ -x "$b" ] && exec "$b" --statusline -- 'original'; original`
    static func command(binary: String, original: String?) -> String {
        let original = original?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var command = "b=\(shellQuoted(binary)); [ -x \"$b\" ] && exec \"$b\" \(flag)"
        if !original.isEmpty { command += " -- \(shellQuoted(original))" }
        return command + "; " + (original.isEmpty ? ":" : original)
    }

    static func isRelay(_ command: String) -> Bool {
        command.contains(" \(flag)") && command.contains("Barn Owl")
    }

    static func isOn(files: Files = .standard) -> Bool {
        guard let settings = try? readSettings(files), let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String else { return false }
        return isRelay(command)
    }

    // MARK: Turning it on and off

    /// What the setting would become, for showing before anything changes.
    static func preview(files: Files = .standard) throws -> (before: String, after: String) {
        guard let binary = installedBinary else { throw Failure.notInstalled }
        let settings = try readSettings(files)
        let existing = settings["statusLine"] as? [String: Any]
        return (settings["statusLine"].map(pretty) ?? "(none)", pretty(relayLine(replacing: existing, binary: binary)))
    }

    static func turnOn(files: Files = .standard, binary: String? = installedBinary) throws {
        guard let binary else { throw Failure.notInstalled }
        try changing {
            var (settings, bytes) = try snapshot(files)
            let existing = settings["statusLine"] as? [String: Any]
            if let command = existing?["command"] as? String, isRelay(command) { return }
            try FileManager.default.createDirectory(at: files.support, withIntermediateDirectories: true)
            let saved: [String: Any] = ["statusLine": existing.map { $0 as Any } ?? NSNull()]
            try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted, .sortedKeys])
                .write(to: files.original, options: .atomic)
            // It holds the user's own command, which can carry secrets.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: files.original.path)
            try backUp(files)
            settings["statusLine"] = relayLine(replacing: existing, binary: binary)
            try write(settings, files, over: bytes)
        }
    }

    static func turnOff(files: Files = .standard) throws {
        var removed = false
        try changing {
            var (settings, bytes) = try snapshot(files)
            guard let line = settings["statusLine"] as? [String: Any], let command = line["command"] as? String,
                  isRelay(command) else { return }
            settings["statusLine"] = restoredLine(line, command: command, files: files)
            if settings["statusLine"] is NSNull { settings.removeValue(forKey: "statusLine") }
            try write(settings, files, over: bytes)
            removed = true
        }
        guard removed else { return }
        try? FileManager.default.removeItem(at: files.original)
        try? FileManager.default.removeItem(at: PlanLimits.relayFile)
    }

    /// What the status line was before the relay: from the saved copy, the
    /// backup, or the user's command carried inside the relay; NSNull for none.
    private static func restoredLine(_ line: [String: Any], command: String, files: Files) -> Any {
        // What was there before: from the saved copy, or from the backup.
        let saved = (try? Data(contentsOf: files.original))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["statusLine"]
            ?? (try? Data(contentsOf: files.backup))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["statusLine"]
        if let saved = saved as? [String: Any], !((saved["command"] as? String).map(isRelay) ?? false) {
            return saved
        } else if let original = Self.original(inRelay: command) {
            // Nothing saved, but the relay carries the user's own command.
            var restored = line
            restored["command"] = original
            return restored
        }
        return NSNull()
    }

    /// After an update or a move to another Applications folder, point the
    /// relay at this copy.
    static func repointIfNeeded(files: Files = .standard) {
        guard let binary = installedBinary else { return }
        try? changing {
            guard var (settings, bytes) = try? snapshot(files),
                  var line = settings["statusLine"] as? [String: Any], let command = line["command"] as? String,
                  isRelay(command), !command.contains(shellQuoted(binary)) else { return }
            let original = ((try? Data(contentsOf: files.original))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["statusLine"] as? [String: Any])?["command"] as? String
                ?? Self.original(inRelay: command)
            line["command"] = Self.command(binary: binary, original: original)
            settings["statusLine"] = line
            try write(settings, files, over: bytes)
        }
    }

    static func relayLine(replacing existing: [String: Any]?, binary: String) -> [String: Any] {
        var line: [String: Any] = ["type": "command",
                                   "command": command(binary: binary, original: existing?["command"] as? String)]
        if let padding = existing?["padding"] { line["padding"] = padding }
        if let interval = existing?["refreshInterval"] { line["refreshInterval"] = interval }
        return line
    }

    // MARK: The settings file

    /// The real file behind a symlink (dotfiles repositories often link it).
    private static func target(_ files: Files) -> URL { files.settings.resolvingSymlinksInPath() }

    static func readSettings(_ files: Files) throws -> [String: Any] {
        try snapshot(files).settings
    }

    /// The settings and the exact bytes they came from, so a write can tell
    /// whether Claude Code changed the file in the meantime.
    static func snapshot(_ files: Files) throws -> (settings: [String: Any], bytes: Data?) {
        let url = target(files)
        guard FileManager.default.fileExists(atPath: url.path) else { return ([:], nil) }
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableSettings
        }
        return (settings, data)
    }

    /// Runs one read-change-write of the settings, again from a fresh read if
    /// the file changed between reading and writing (Claude Code writes it too).
    static func changing(_ body: () throws -> Void) throws {
        for _ in 0..<3 {
            do {
                try body()
                return
            } catch Failure.changedMeanwhile {
                continue
            }
        }
        throw Failure.couldNotWrite
    }

    /// The file as it was before Barn Owl first touched it, by content (not
    /// a link). Made once, so turning on a second feature keeps the original;
    /// readable only by you, as settings can hold secrets.
    static func backUp(_ files: Files) throws {
        guard !FileManager.default.fileExists(atPath: files.backup.path),
              let data = try? Data(contentsOf: target(files)) else { return }
        try data.write(to: files.backup, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: files.backup.path)
    }

    /// The user's own command, carried inside the relay's (`-- 'original'`).
    static func original(inRelay command: String) -> String? {
        guard let range = command.range(of: " \(flag) -- '") else { return nil }
        var rest = command[range.upperBound...]
        var original = ""
        while let quote = rest.firstIndex(of: "'") {
            original += rest[..<quote]
            rest = rest[rest.index(after: quote)...]
            // '\'' is an escaped quote inside the original.
            guard rest.hasPrefix("\\''") else { return original }
            original += "'"
            rest = rest.dropFirst(3)
        }
        return nil
    }

    /// Writes the settings back to the real file, keeping its permissions
    /// and ending with a newline, as editors do.
    static func write(_ settings: [String: Any], _ files: Files, over bytes: Data?? = .none) throws {
        let url = target(files)
        // Only over what was read: if it changed since, start again from the new file.
        if case .some(let expected) = bytes, (try? Data(contentsOf: url)) != expected { throw Failure.changedMeanwhile }
        guard var data = try? JSONSerialization.data(withJSONObject: settings,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            throw Failure.couldNotWrite
        }
        data.append(UInt8(ascii: "\n"))
        let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
        do {
            // Into a file that already has the right permissions, then renamed over the
            // settings: never a moment when they're readable by others.
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).barnowl-\(getpid())")
            guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                                 attributes: [.posixPermissions: permissions ?? 0o600]) else {
                throw Failure.couldNotWrite
            }
            guard rename(temporary.path, url.path) == 0 else {
                try? FileManager.default.removeItem(at: temporary)
                throw Failure.couldNotWrite
            }
        } catch {
            throw Failure.couldNotWrite
        }
    }

    static func pretty(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys,
                                                                                    .withoutEscapingSlashes])
        else { return String(describing: value) }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Running as the status line

    /// `Barn Owl --statusline [-- original]`, run by Claude Code with the
    /// status as JSON on standard input. Saves the plan limits, then becomes
    /// your original command (same process, same input), so cancelling it
    /// cancels everything. Never starts the app.
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2, arguments[1] == flag else { return }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        saveLimits(from: input, now: Date())
        let original = arguments.count >= 4 && arguments[2] == "--" ? arguments[3] : ""
        guard !original.isEmpty else { exit(0) }
        hand(input, to: original)
        exit(1) // only if exec failed
    }

    /// Puts the input back on standard input through a temporary file and
    /// replaces this process with `/bin/sh -c original`.
    private static func hand(_ input: Data, to original: String) {
        let path = NSTemporaryDirectory() + "barnowl-status-\(getpid())"
        guard FileManager.default.createFile(atPath: path, contents: input, attributes: [.posixPermissions: 0o600]) else {
            return
        }
        let descriptor = open(path, O_RDONLY)
        unlink(path)
        guard descriptor >= 0 else { return }
        dup2(descriptor, STDIN_FILENO)
        close(descriptor)
        let words: [String] = ["/bin/sh", "-c", original]
        var args: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) }
        args.append(nil)
        execv("/bin/sh", args)
    }

    /// Keeps only `rate_limits` from the status JSON; nothing else is saved.
    static func saveLimits(from input: Data, now: Date, to file: URL = PlanLimits.relayFile) {
        guard let status = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let limits = status["rate_limits"] as? [String: Any] else { return }
        var saved: [String: Any] = ["saved": now.timeIntervalSince1970]
        for key in ["five_hour", "seven_day"] {
            guard let window = limits[key] as? [String: Any] else { continue }
            saved[key] = window.filter { ["used_percentage", "resets_at"].contains($0.key) }
        }
        guard saved.count > 1, let data = try? JSONSerialization.data(withJSONObject: saved) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

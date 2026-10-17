import Foundation

/// Lets the Mac keep running with the lid closed and no external display,
/// like Amphetamine's closed-display mode. macOS sleeps on lid close whatever
/// power assertions say, so this uses `pmset disablesleep`, which needs an
/// administrator password each time it's switched.
///
/// Risky by nature: a running Mac in a bag gets hot and drains its battery.
/// Off by default, explained in Settings, and switched off again when Barkeep
/// quits.
enum ClosedLidMode {
    /// Reads the current setting; needs no password.
    static var isEnabled: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parse(output)
    }

    /// `pmset -g` lists "SleepDisabled 1" while sleep is disabled.
    static func parse(_ pmsetOutput: String) -> Bool {
        pmsetOutput.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
        }
    }

    /// Asks for an administrator password with the standard macOS prompt.
    /// Returns false if the user cancelled or it failed.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        let source = "do shell script \"/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.keepAwake.error("Closed-lid mode change failed: \(error)")
            return false
        }
        Log.keepAwake.info("Closed-lid mode \(enabled ? "on" : "off")")
        return true
    }
}

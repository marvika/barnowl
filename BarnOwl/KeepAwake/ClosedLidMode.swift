import Foundation
import IOKit

/// Lets the Mac keep running with the lid closed and no external display,
/// like Amphetamine's closed-display mode, but only while Barn Owl keeps it
/// awake: close the lid with nothing keeping it awake and it sleeps as usual.
///
/// macOS sleeps on lid close whatever power assertions say, so this uses
/// `pmset disablesleep`, which needs root. To switch it as keep awake starts
/// and stops without asking each time, turning the setting on installs one
/// narrow rule, asking for your password once: your account may run exactly
/// `pmset -a disablesleep 1` and `pmset -a disablesleep 0` as root without a
/// password, nothing else. Turning the setting off removes the rule again.
///
/// Risky by nature: a running Mac in a bag gets hot and drains its battery.
/// Off by default, explained in Settings, and switched off whenever keep awake
/// stops, the battery runs low or Barn Owl quits.
enum ClosedLidMode {
    /// The rule's file. sudo skips files in sudoers.d with a dot in the name.
    static let rulePath = "/private/etc/sudoers.d/barnowl"
    private static let pmset = "/usr/bin/pmset"

    /// Whether sleep is disabled right now; needs no password.
    static var isEnabled: Bool {
        let (status, output) = run("/usr/bin/pmset", ["-g"])
        return status == 0 && parse(output)
    }

    /// `pmset -g` lists "SleepDisabled 1" while sleep is disabled.
    static func parse(_ pmsetOutput: String) -> Bool {
        pmsetOutput.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
        }
    }

    /// Whether the rule is installed, so it can be switched without a password.
    static var canSwitchWithoutPassword: Bool {
        run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"]).status == 0
    }

    /// The rule for one account: these two exact commands, nothing more. Nil
    /// for a name sudoers could read as more than a name.
    static func rule(for user: String) -> String? {
        guard let first = user.first, first.isLetter || first == "_", user != "ALL",
              user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
        return "# Barn Owl's closed-lid mode: lets \(user) switch sleep with the lid closed, nothing else.\n"
            + "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1\n"
    }

    /// Installs the rule, asking for an administrator password with the
    /// standard macOS prompt. visudo checks it before it goes in, and it's
    /// taken out again if sudo doesn't then accept it. False if cancelled or
    /// it failed.
    @discardableResult
    static func install() -> Bool {
        guard let rule = rule(for: NSUserName()) else { return false }
        // The per-user temporary folder only this account can write to.
        let draft = FileManager.default.temporaryDirectory.appending(path: "barnowl-rule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: draft) }
        guard (try? rule.write(to: draft, atomically: true, encoding: .utf8)) != nil else { return false }
        let script = "/usr/sbin/visudo -cf '\(draft.path)' && /bin/mkdir -p /private/etc/sudoers.d"
            + " && /usr/bin/install -m 0440 -o root -g wheel '\(draft.path)' \(rulePath)"
        guard runAsAdministrator(script) else { return false }
        guard canSwitchWithoutPassword else {
            Log.keepAwake.error("Closed-lid rule installed but sudo doesn't use it; taking it out")
            runAsAdministrator("/bin/rm -f \(rulePath)")
            return false
        }
        Log.keepAwake.info("Closed-lid mode set up")
        return true
    }

    /// Lets the Mac sleep again and removes the rule, asking for a password.
    @discardableResult
    static func uninstall() -> Bool {
        let done = runAsAdministrator("\(pmset) -a disablesleep 0; /bin/rm -f \(rulePath)")
        if done { Log.keepAwake.info("Closed-lid mode removed") }
        return done
    }

    /// Switches whether the Mac keeps running with the lid closed, without
    /// asking. Needs the rule; does nothing if it's already that way.
    @discardableResult
    static func apply(_ enabled: Bool) -> Bool {
        guard enabled != isEnabled else { return true }
        let status = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", enabled ? "1" : "0"]).status
        Log.keepAwake.info("Lid closed: \(enabled ? "keeps running" : "sleeps as usual")\(status == 0 ? "" : " (failed)")")
        return status == 0
    }

    /// Lets the Mac sleep again with a password prompt, for when there's no
    /// rule: closed-lid mode left on by a version from before the rule.
    @discardableResult
    static func turnOffWithPassword() -> Bool {
        runAsAdministrator("\(pmset) -a disablesleep 0")
    }

    @discardableResult
    private static func runAsAdministrator(_ command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            Log.keepAwake.error("Closed-lid change failed: \(error)")
            return false
        }
        return true
    }

    private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}

/// Keeps closed-lid mode in step with keep awake: the Mac runs with the lid
/// closed only while Barn Owl keeps it awake, and the screen locks when the
/// lid closes during that time.
@MainActor
final class ClosedLidController {
    private let keepAwake: KeepAwakeController
    private var lidTask: Task<Void, Never>?
    /// What was last asked of pmset, so unchanged states cost nothing.
    private var applied: Bool?

    init(keepAwake: KeepAwakeController) {
        self.keepAwake = keepAwake
    }

    /// On while the setting is on and keep awake is active; off otherwise.
    func sync() {
        let wanted = Preferences.closedLidMode && keepAwake.isActive
        if wanted != applied {
            applied = wanted
            Task.detached { ClosedLidMode.apply(wanted) }
        }
        wanted ? watchLid() : stopWatchingLid()
    }

    /// Sleep comes back on, without asking, when Barn Owl quits.
    func quit() {
        stopWatchingLid()
        if Preferences.closedLidMode || applied == true { ClosedLidMode.apply(false) }
    }

    /// Closing the lid while the Mac keeps running, with no other display,
    /// locks the screen, so a running Mac in a bag isn't open to whoever
    /// opens it.
    private func watchLid() {
        guard lidTask == nil else { return }
        lidTask = Task { [weak self] in
            var wasClosed = Lid.isClosed
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let closed = Lid.isClosed
                // With an external display, a closed lid is ordinary clamshell use.
                if closed, !wasClosed, self != nil, !SystemConditions.hasExternalDisplay {
                    Log.keepAwake.info("Lid closed while keeping awake: locking the screen")
                    Lid.lockScreen()
                }
                wasClosed = closed
            }
        }
    }

    private func stopWatchingLid() {
        lidTask?.cancel()
        lidTask = nil
    }
}

/// The MacBook's lid, and locking the screen.
enum Lid {
    /// Whether the lid is closed (false on a Mac without one).
    static var isClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    /// Locks the screen the way the Lock Screen menu item does.
    static func lockScreen() {
        typealias Lock = @convention(c) () -> Void
        if let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(login, "SACLockScreenImmediate") {
            unsafeBitCast(symbol, to: Lock.self)()
            return
        }
        // Fallback: sleep the display, which locks when a password is required after sleep.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}

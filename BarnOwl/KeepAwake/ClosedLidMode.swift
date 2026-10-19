import AppKit
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

    /// Whether it really switches without a password: tried by setting it to
    /// what it already is, which changes nothing. (`sudo -l` only says a
    /// command is allowed, not that it needs no password: on a managed Mac a
    /// later "PASSWD: ALL" line wins over the rule.)
    static var canSwitchWithoutPassword: Bool {
        if DemoMode.isOn { return true }
        let current = isEnabled ? "1" : "0"
        return run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", current]).status == 0
    }

    enum InstallResult {
        case done, cancelled
        /// The Mac's own sudo settings ask for a password for every command
        /// (company device management does this), so a rule can't help.
        case passwordAlwaysRequired
    }

    /// What to tell the user when the Mac won't allow it.
    static let managedMacExplanation = "This Mac's administrator settings (often your company's device management) ask for a password for every change of this kind, so Barn Owl can't switch closed-lid mode by itself. It stays off, and your Mac sleeps as usual when you close the lid."


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
    static func install() -> InstallResult {
        // The demo copy (Scripts/demo.sh) pretends; it never touches the system.
        if DemoMode.isOn { return .done }
        guard let rule = rule(for: NSUserName()) else { return .cancelled }
        // The per-user temporary folder only this account can write to.
        let draft = FileManager.default.temporaryDirectory.appending(path: "barnowl-rule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: draft) }
        guard (try? rule.write(to: draft, atomically: true, encoding: .utf8)) != nil else { return .cancelled }
        // One password prompt for all of it: check the rule, install it, then
        // try it as the user, changing nothing. If the Mac still wants a
        // password (a later rule wins), take it out again and say so.
        let current = isEnabled ? "1" : "0"
        let user = NSUserName()
        let script = "/usr/sbin/visudo -cf '\(draft.path)' && /bin/mkdir -p /private/etc/sudoers.d"
            + " && /usr/bin/install -m 0440 -o root -g wheel '\(draft.path)' \(rulePath)"
            + " && { /usr/bin/sudo -u '\(user)' /usr/bin/sudo -n \(pmset) -a disablesleep \(current)"
            + " || { /bin/rm -f \(rulePath); exit 3; }; }"
        switch runAsAdministrator(script) {
        case .ok:
            Log.keepAwake.info("Closed-lid mode set up")
            return .done
        case .failed(let code) where code == 3:
            Log.keepAwake.error("Closed-lid rule doesn't take effect on this Mac (sudo asks for a password anyway)")
            return .passwordAlwaysRequired
        case .failed, .cancelled:
            return .cancelled
        }
    }

    /// Lets the Mac sleep again and removes the rule, asking for a password.
    @discardableResult
    static func uninstall() -> Bool {
        if DemoMode.isOn { return true }
        let done = runAsAdministrator("\(pmset) -a disablesleep 0; /bin/rm -f \(rulePath)") == .ok
        if done { Log.keepAwake.info("Closed-lid mode removed") }
        return done
    }

    /// Switches whether the Mac keeps running with the lid closed, without
    /// asking. Needs the rule; does nothing if it's already that way.
    @discardableResult
    static func apply(_ enabled: Bool) -> Bool {
        guard !DemoMode.isOn, enabled != isEnabled else { return true }
        let status = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", enabled ? "1" : "0"]).status
        Log.keepAwake.info("Lid closed: \(enabled ? "keeps running" : "sleeps as usual")\(status == 0 ? "" : " (failed)")")
        return status == 0
    }

    /// Lets the Mac sleep again with a password prompt, for when there's no
    /// rule: closed-lid mode left on by a version from before the rule.
    @discardableResult
    static func turnOffWithPassword() -> Bool {
        runAsAdministrator("\(pmset) -a disablesleep 0") == .ok
    }

    enum AdminResult: Equatable { case ok, cancelled, failed(Int) }

    @discardableResult
    private static func runAsAdministrator(_ command: String) -> AdminResult {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        guard let error else { return .ok }
        Log.keepAwake.error("Closed-lid change failed: \(error)")
        // -128: the user cancelled the password prompt.
        let number = error[NSAppleScript.errorNumber] as? Int ?? 0
        return number == -128 ? .cancelled : .failed(number)
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

extension ClosedLidMode {
    /// Turning the setting on: sets up the rule (one password) and checks it
    /// works. On a Mac whose settings always ask for a password, explains why
    /// it can't be on. True if it's on now.
    @MainActor static func enableFromSettings() -> Bool {
        if canSwitchWithoutPassword { return true }
        switch install() {
        case .done: return true
        case .cancelled: return false
        case .passwordAlwaysRequired:
            let alert = NSAlert()
            alert.messageText = "Closed-lid mode isn't available on this Mac"
            alert.informativeText = managedMacExplanation
            alert.runModal()
            return false
        }
    }
}

/// Keeps closed-lid mode in step with keep awake: the Mac runs with the lid
/// closed only while Barn Owl keeps it awake, and the screen locks when the
/// lid closes during that time.
@MainActor
final class ClosedLidController {
    private let keepAwake: KeepAwakeController
    private var lidTask: Task<Void, Never>?
    /// What closed-lid mode should be now.
    private var wanted = false
    /// The change running now, if any; it loops until pmset matches `wanted`.
    private var applying: Task<Void, Never>?
    /// A switch that failed, so it isn't retried every time a setting changes.
    private var failedTarget: Bool?

    init(keepAwake: KeepAwakeController) {
        self.keepAwake = keepAwake
    }

    /// On while the setting is on and keep awake is active; off otherwise.
    func sync() {
        wanted = Preferences.closedLidMode && keepAwake.isActive
        wanted ? watchLid() : stopWatchingLid()
        // Already tried this and it failed: try again only when it changes.
        if failedTarget == wanted { return }
        failedTarget = nil
        guard applying == nil else { return }
        // One change at a time, off the main thread. Quick on-off-on can't
        // finish out of order and leave it on: each pass re-reads what's
        // wanted, and pmset is only told when it differs.
        applying = Task { [weak self] in
            while let self {
                let target = self.wanted
                let done = await Task.detached { ClosedLidMode.apply(target) }.value
                if !done {
                    Log.keepAwake.error("Couldn't switch closed-lid mode \(target ? "on" : "off")")
                    self.failedTarget = target
                    // Stuck on with nothing keeping the Mac awake: it wouldn't
                    // sleep with the lid closed. Say so; never stay quiet.
                    if !target { self.warnStuckOn() }
                }
                if self.wanted == target {
                    self.applying = nil
                    return
                }
            }
        }
    }

    /// Tells the user once, and offers to fix it with their password.
    private var warned = false

    private func warnStuckOn() {
        guard !warned else { return }
        warned = true
        let notStillOn = Task.detached { !ClosedLidMode.isEnabled }
        Task { @MainActor in
            guard !(await notStillOn.value) else { return }
            NSApp.activate()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Your Mac won't sleep with the lid closed"
            alert.informativeText = "Barn Owl couldn't switch closed-lid mode off. "
                + ClosedLidMode.managedMacExplanation.replacingOccurrences(of: " It stays off, and your Mac sleeps as usual when you close the lid.", with: "")
                + " Turn it off now with your password?"
            alert.addButton(withTitle: "Turn Off")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if ClosedLidMode.uninstall() {
                Preferences.closedLidMode = false
                self.failedTarget = nil
            }
        }
    }

    /// Sleep comes back on, without asking, when Barn Owl quits.
    func quit() {
        stopWatchingLid()
        applying?.cancel()
        wanted = false
        ClosedLidMode.apply(false)
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
    /// Whether this Mac has a lid at all (a MacBook, not an iMac or Mac mini).
    static var exists: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() != nil
    }

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

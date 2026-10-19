import AppKit
import Foundation
import IOKit

/// Lets a MacBook keep running with the lid closed, even on battery and
/// without an external display, but only while Barn Owl keeps it awake:
/// close the lid with nothing keeping it awake and it sleeps as usual.
///
/// It asks macOS's power manager (IOPMrootDomain) not to sleep when the lid
/// closes, the way Amphetamine's closed-display mode does on Apple silicon.
/// That needs no administrator rights, no password and no helper, so it also
/// works on company-managed Macs.
///
/// Risky by nature: a running Mac in a bag gets hot and drains its battery.
/// Off by default, explained in Settings, switched off whenever keep awake
/// stops, the battery runs low or Barn Owl quits, and the screen locks when
/// the lid closes.
enum ClosedLidMode {
    /// IOPMrootDomain's user-client method that sets whether closing the lid
    /// sleeps the Mac (kPMSetClamshellSleepState).
    private static let setClamshellSleepState: UInt32 = 12

    /// Tells macOS whether closing the lid should keep the Mac running
    /// (`enabled`) or sleep it, as usual. True if macOS accepted it.
    @discardableResult
    static func apply(_ enabled: Bool) -> Bool {
        guard !DemoMode.isOn else { return true }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(root, mach_task_self_, 0, &connect) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connect) }
        var input: UInt64 = enabled ? 1 : 0
        var outputCount: UInt32 = 0
        let result = IOConnectCallScalarMethod(connect, setClamshellSleepState, &input, 1, nil, &outputCount)
        Log.keepAwake.info("Lid closed: \(enabled ? "keeps running" : "sleeps as usual")\(result == KERN_SUCCESS ? "" : " (failed \(result))")")
        return result == KERN_SUCCESS
    }

    // MARK: The old way (0.10.x–0.11.x)

    /// Versions up to 0.11.2 used `pmset disablesleep` and a sudoers rule.
    static let legacyRulePath = "/private/etc/sudoers.d/barnowl"

    /// Whether `pmset disablesleep` is still on, maybe left by an old version.
    static var legacySleepDisabled: Bool {
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

    /// Undoes what an old version may have left: sleep disabled for good.
    /// Silent where the old rule still works; returns whether sleep is
    /// still disabled afterwards. The rule file itself is harmless and stays.
    static func cleanUpLegacySilently() -> Bool {
        guard !DemoMode.isOn, legacySleepDisabled else { return false }
        if FileManager.default.fileExists(atPath: legacyRulePath) {
            _ = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
        }
        return legacySleepDisabled
    }

    /// Turns sleep back on and removes the old rule, with the password.
    @discardableResult
    static func cleanUpLegacyWithPassword() -> Bool {
        let script = "/usr/bin/pmset -a disablesleep 0; /bin/rm -f \(legacyRulePath)"
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(script)\" with administrator privileges")?.executeAndReturnError(&error)
        if error == nil { Log.keepAwake.info("Turned off the old closed-lid mode") }
        return error == nil
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
    /// What was last told to macOS, so unchanged states cost nothing.
    private var applied: Bool?

    init(keepAwake: KeepAwakeController) {
        self.keepAwake = keepAwake
    }

    /// On while the setting is on and keep awake is active; off otherwise.
    /// A quick call to the power manager, so it's done right here, in order.
    func sync() {
        let wanted = Preferences.closedLidMode && keepAwake.isActive
        if wanted != applied, ClosedLidMode.apply(wanted) { applied = wanted }
        wanted ? watchLid() : stopWatchingLid()
    }

    /// The lid sleeps the Mac again when Barn Owl quits.
    func quit() {
        stopWatchingLid()
        ClosedLidMode.apply(false)
        applied = false
    }

    /// If the user wants it: closing the lid while the Mac keeps running,
    /// with no other display, locks the screen.
    private func watchLid() {
        guard lidTask == nil, Preferences.closedLidLocks else {
            if !Preferences.closedLidLocks { stopWatchingLid() }
            return
        }
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

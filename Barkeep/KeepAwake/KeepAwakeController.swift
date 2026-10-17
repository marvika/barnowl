import AppKit
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac awake with a power assertion, the same mechanism Amphetamine
/// and `caffeinate` use. The assertion goes away by itself if Barkeep quits.
@MainActor
@Observable
final class KeepAwakeController {
    enum Session: Equatable {
        case indefinite
        case until(Date)
        case whileAppRunning(bundleIdentifier: String, name: String)
    }

    private(set) var session: Session?
    var isActive: Bool { session != nil }
    var onChange: (() -> Void)?

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    func start(_ session: Session) {
        stop(notify: false)
        if case .whileAppRunning(let bundleIdentifier, _) = session {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
                Log.keepAwake.error("Not starting: \(bundleIdentifier) isn't running")
                return
            }
            watchTermination(of: bundleIdentifier)
        }
        guard createAssertion() else { return }
        self.session = session
        if case .until(let date) = session {
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }
        Log.keepAwake.info("Keep awake started: \(String(describing: session))")
        onChange?()
    }

    func start(minutes: Int) {
        start(minutes > 0 ? .until(Date().addingTimeInterval(TimeInterval(minutes * 60))) : .indefinite)
    }

    func stop() {
        stop(notify: true)
    }

    /// Re-creates the assertion so a change to "allow display sleep" applies now.
    func refreshAssertion() {
        guard isActive else { return }
        releaseAssertion()
        _ = createAssertion()
    }

    private func stop(notify: Bool) {
        expiryTask?.cancel()
        expiryTask = nil
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        releaseAssertion()
        let wasActive = session != nil
        session = nil
        if wasActive {
            Log.keepAwake.info("Keep awake stopped")
            if notify { onChange?() }
        }
    }

    private func createAssertion() -> Bool {
        // Display sleep prevention implies system sleep prevention.
        let type = Preferences.keepAwakeAllowDisplaySleep ? "PreventUserIdleSystemSleep" : "PreventUserIdleDisplaySleep"
        let result = IOPMAssertionCreateWithName(type as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Barkeep keep-awake session" as CFString,
                                                 &assertionID)
        guard result == kIOReturnSuccess else {
            Log.keepAwake.error("IOPMAssertionCreateWithName failed: \(result)")
            assertionID = 0
            return false
        }
        return true
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func watchTermination(of bundleIdentifier: String) {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.stop() }
        }
    }
}

enum KeepAwakeFormatter {
    /// Short status for the menu, e.g. "Awake for 1 h 20 min more".
    static func status(for session: KeepAwakeController.Session, now: Date = Date()) -> String {
        switch session {
        case .indefinite:
            return "Awake until you stop it"
        case .whileAppRunning(_, let name):
            return "Awake while \(name) is running"
        case .until(let date):
            return "Awake for \(remaining(date.timeIntervalSince(now))) more"
        }
    }

    static func remaining(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func durationLabel(minutes: Int) -> String {
        minutes == 0 ? "Indefinitely" : remaining(TimeInterval(minutes * 60))
    }
}

import AppKit
import IOKit.pwr_mgt
import Observation
import UserNotifications

/// Keeps the Mac awake with a power assertion, the mechanism Amphetamine and
/// `caffeinate` use. The assertion goes away by itself if Barkeep quits.
///
/// Two things can ask for it: a session the user starts, and rules that
/// switch it on automatically (on power with an external display, during
/// calls…). Either is enough.
@MainActor
@Observable
final class KeepAwakeController {
    enum Session: Equatable {
        case indefinite
        case until(Date)
        case whileAppRunning(bundleIdentifier: String, name: String)
        case whileDownloading
    }

    private(set) var session: Session?
    /// The rule keeping the Mac awake right now, if any.
    private(set) var activeRule: KeepAwakeRule?
    /// Set when a session or the rules stopped because the battery got low.
    private(set) var stoppedForBattery = false
    /// Presenter mode keeps the Mac (and display) awake while presenting.
    private(set) var presenting = false

    var isActive: Bool { session != nil || activeRule != nil || presenting }
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored let rules: RuleStore
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var assertionType: String?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var appsObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastNudge = Date.distantPast

    init(rules: RuleStore) {
        self.rules = rules
    }

    /// Starts watching for rule changes. Rules are checked every 15 seconds
    /// and whenever apps, displays or power change.
    func start() {
        rules.onChange = { [weak self] in self?.evaluate() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        appsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.evaluate() }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluate()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    // MARK: Sessions

    func start(_ session: Session) {
        if case .whileAppRunning(let bundle, _) = session, !SystemConditions.isRunning(bundle) {
            Log.keepAwake.error("Not starting: \(bundle) isn't running")
            return
        }
        stoppedForBattery = false
        self.session = session
        Log.keepAwake.info("Keep awake started: \(String(describing: session))")
        evaluate()
        onChange?()
    }

    func start(minutes: Int) {
        start(minutes > 0 ? .until(Date().addingTimeInterval(TimeInterval(minutes * 60))) : .indefinite)
    }

    /// Ends the user's session. Rules keep working.
    func stop() {
        guard session != nil else { return }
        endSession(reason: nil)
    }

    func setPresenting(_ presenting: Bool) {
        self.presenting = presenting
        evaluate()
        onChange?()
    }

    /// Re-applies after "allow display sleep" changes.
    func refreshAssertion() {
        releaseAssertion()
        evaluate()
    }

    private func endSession(reason: String?) {
        session = nil
        Log.keepAwake.info("Keep awake stopped\(reason.map { ": \($0)" } ?? "")")
        if let reason, Preferences.keepAwakeNotify { Self.notify(reason) }
        evaluate()
        onChange?()
    }

    // MARK: Evaluation

    /// Checks the session's end conditions and the rules, then holds or
    /// releases the assertion to match.
    func evaluate() {
        let snapshot = snapshot()

        // Low battery ends everything, so a forgotten session can't drain it.
        let threshold = Preferences.keepAwakeStopBelowBattery
        if threshold > 0, !snapshot.onAC, let percent = snapshot.batteryPercent, percent < threshold {
            if session != nil || activeRule != nil {
                stoppedForBattery = true
                if session != nil { endSession(reason: "Battery is below \(threshold)%, so your Mac can sleep again.") }
                activeRule = nil
                applyAssertion()
                onChange?()
            }
            return
        }

        if let session {
            switch session {
            case .until(let date) where date <= Date():
                return endSession(reason: "Your keep-awake session has ended.")
            case .whileAppRunning(let bundle, let name) where !snapshot.runningBundles.contains(bundle):
                return endSession(reason: "\(name) quit, so your Mac can sleep again.")
            case .whileDownloading where !snapshot.downloading:
                return endSession(reason: "Downloads finished, so your Mac can sleep again.")
            default:
                break
            }
        }

        let rule = rules.rules.first { $0.holds(in: snapshot) }
        if rule != activeRule {
            activeRule = rule
            Log.keepAwake.info("Active rule: \(rule?.title ?? "none")")
            onChange?()
        }
        applyAssertion()
        nudgeIfNeeded()
    }

    /// Reads only what the session and enabled rules need. Reading the
    /// Downloads folder asks for permission the first time, so it's checked
    /// only when something actually depends on downloads.
    private func snapshot() -> ConditionSnapshot {
        let power = SystemConditions.power()
        let needsDownloads = session == .whileDownloading
            || rules.rules.contains { $0.isEnabled && $0.conditions.contains(.downloading) }
        let needsMicrophone = rules.rules.contains { $0.isEnabled && $0.conditions.contains(.microphoneInUse) }
        let now = Calendar.current.dateComponents([.weekday, .hour, .minute], from: Date())
        return ConditionSnapshot(
            runningBundles: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            hasExternalDisplay: SystemConditions.hasExternalDisplay,
            onAC: power.onAC,
            batteryPercent: power.batteryPercent,
            microphoneInUse: needsMicrophone && SystemConditions.isMicrophoneInUse,
            downloading: needsDownloads && SystemConditions.isDownloading,
            weekday: now.weekday ?? 2,
            minuteOfDay: (now.hour ?? 0) * 60 + (now.minute ?? 0))
    }

    // MARK: Assertion

    private func applyAssertion() {
        guard isActive else { return releaseAssertion() }
        // Display sleep is allowed only if every active source allows it.
        let sessionAllows = session == nil || Preferences.keepAwakeAllowDisplaySleep
        let ruleAllows = activeRule?.allowDisplaySleep ?? true
        let type = sessionAllows && ruleAllows && !presenting ? "PreventUserIdleSystemSleep" : "PreventUserIdleDisplaySleep"
        guard type != assertionType || assertionID == 0 else { return }
        releaseAssertion()
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Barkeep keep awake" as CFString, &assertionID)
        if result == kIOReturnSuccess {
            assertionType = type
        } else {
            Log.keepAwake.error("IOPMAssertionCreateWithName failed: \(result)")
            assertionID = 0
        }
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        assertionType = nil
    }

    // MARK: Keep me available

    /// Chat apps (Teams, Slack) mark you Away after a few idle minutes, even
    /// while the Mac stays awake. With "keep me available" on, an idle Mac
    /// gets a one-pixel pointer nudge every four minutes, which they count as
    /// activity. Only while keeping awake.
    private func nudgeIfNeeded() {
        guard isActive, Preferences.keepAwakeKeepAvailable,
              SystemConditions.secondsSinceInput > 4 * 60, Date().timeIntervalSince(lastNudge) > 4 * 60,
              let location = CGEvent(source: nil)?.location else { return }
        lastNudge = Date()
        let source = CGEventSource(stateID: .hidSystemState)
        for point in [CGPoint(x: location.x + 1, y: location.y), location] {
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Notifications

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private static func notify(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Keep Awake"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension KeepAwakeController {
    /// The durations offered in menus and Settings; 0 means indefinitely.
    static let durations = [0, 15, 30, 60, 120, 240, 480]
}

enum KeepAwakeFormatter {
    /// Short status for menus and panels, e.g. "Awake for 1 h 20 min more".
    static func status(for session: KeepAwakeController.Session, now: Date = Date()) -> String {
        switch session {
        case .indefinite:
            return "Awake until you stop it"
        case .whileAppRunning(_, let name):
            return "Awake while \(name) is running"
        case .whileDownloading:
            return "Awake until downloads finish"
        case .until(let date):
            let remaining = date.timeIntervalSince(now)
            if remaining > 3 * 3600 { return "Awake until \(date.formatted(date: .omitted, time: .shortened))" }
            return "Awake for \(Self.remaining(remaining)) more"
        }
    }

    /// The whole state in one line, including rules.
    @MainActor
    static func status(of controller: KeepAwakeController) -> String {
        if let session = controller.session { return status(for: session) }
        if let rule = controller.activeRule { return "Awake because \(rule.phrase)" }
        if controller.presenting { return "Awake while you present" }
        if controller.stoppedForBattery { return "Stopped: battery low" }
        return "Off. Your Mac sleeps as usual."
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

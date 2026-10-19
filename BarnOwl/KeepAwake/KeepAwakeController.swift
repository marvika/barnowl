import AppKit
import IOKit.pwr_mgt
import Observation
import UserNotifications

/// Keeps the Mac awake with a power assertion, the mechanism Amphetamine and
/// `caffeinate` use. The assertion goes away by itself if Barn Owl quits.
///
/// Two things can ask for it: a session the user starts, and rules that
/// switch it on automatically (on power with an external display, during
/// calls…). Either is enough.
@MainActor
@Observable
final class KeepAwakeController {
    enum Session: Equatable, Codable {
        case indefinite
        case until(Date)
        case whileAppRunning(bundleIdentifier: String, name: String)
        case whileDownloading
    }

    private(set) var session: Session?
    /// Set when Barn Owl quits only to come straight back (an update), so the
    /// session carries on in the new version.
    static var saveSessionOnQuit = false
    private static let savedSessionKey = "savedKeepAwakeSession"
    /// When the current timed session started (or was last extended), for
    /// the countdown ring.
    private(set) var sessionStart: Date?
    /// The rule keeping the Mac awake right now, if any.
    private(set) var activeRule: KeepAwakeRule?
    /// Set when a session or the rules stopped because the battery got low.
    private(set) var stoppedForBattery = false
    /// Presenter mode keeps the Mac (and display) awake while presenting.
    private(set) var presenting = false

    /// Whether the Mac is being kept awake. Not below the battery cutoff,
    /// presenting included.
    var isActive: Bool { (session != nil || activeRule != nil || presenting) && !stoppedForBattery }
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
        sessionStart = Date()
        Log.keepAwake.info("Keep awake started: \(String(describing: session))")
        evaluate()
        onChange?()
    }

    /// Saves the running session for the next launch, a minute or two from now.
    func saveSession() {
        guard let session, let data = try? JSONEncoder().encode(SavedSession(session: session, saved: Date())) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedSessionKey)
    }

    /// Picks up a session saved just before an update relaunch. Anything
    /// older than ten minutes, already over, or for an app that's gone is dropped.
    func restoreSavedSession() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedSessionKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.savedSessionKey)
        guard let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
              let session = Self.resumable(saved, now: Date()) else { return }
        Log.keepAwake.info("Carrying on the keep-awake session from before the update")
        start(session)
    }

    struct SavedSession: Codable {
        let session: Session
        let saved: Date
    }

    nonisolated static func resumable(_ saved: SavedSession, now: Date) -> Session? {
        guard now.timeIntervalSince(saved.saved) < 600 else { return nil }
        if case .until(let end) = saved.session, end <= now { return nil }
        return saved.session
    }

    /// The longest session or extension: a year. Anything longer would only
    /// come from a typo, and very large numbers overflow.
    nonisolated static let longestMinutes = 525_600

    func start(minutes: Int) {
        let minutes = min(minutes, Self.longestMinutes)
        start(minutes > 0 ? .until(Date().addingTimeInterval(TimeInterval(minutes * 60))) : .indefinite)
    }

    /// Adds time to a timed session (from now if it has already run out).
    /// Other sessions have no end time, so there's nothing to add to.
    func extend(minutes: Int) {
        guard let current = session, let extended = Self.extended(current, by: minutes) else { return }
        session = extended
        Log.keepAwake.info("Keep awake extended by \(minutes) min")
        evaluate()
        onChange?()
    }

    nonisolated static func extended(_ session: Session, by minutes: Int, now: Date = Date()) -> Session? {
        guard case .until(let end) = session, minutes > 0 else { return nil }
        return .until(max(end, now).addingTimeInterval(TimeInterval(min(minutes, longestMinutes)) * 60))
    }

    /// How much of a timed session is left, 1 at the start to 0 at the end.
    var remainingFraction: Double? {
        guard let end = endDate, let start = sessionStart else { return nil }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return max(0, min(1, end.timeIntervalSinceNow / total))
    }

    /// When the current session ends, if it has an end time.
    var endDate: Date? {
        if case .until(let date) = session { return date }
        return nil
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
        if Self.batteryTooLow(threshold: threshold, onAC: snapshot.onAC, percent: snapshot.batteryPercent) {
            if session != nil || activeRule != nil || (presenting && !stoppedForBattery) {
                stoppedForBattery = true
                if session != nil { endSession(reason: "Battery is below \(threshold)%, so your Mac can sleep again.") }
                activeRule = nil
                applyAssertion()
                onChange?()
            }
            return
        }
        // Plugged in (or the limit lowered): the low-battery note no longer applies.
        if stoppedForBattery {
            stoppedForBattery = false
            onChange?()
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

    nonisolated static func batteryTooLow(threshold: Int, onAC: Bool, percent: Int?) -> Bool {
        guard threshold > 0, !onAC, let percent else { return false }
        return percent < threshold
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
        let type = displayMaySleep ? "PreventUserIdleSystemSleep" : "PreventUserIdleDisplaySleep"
        guard type != assertionType || assertionID == 0 else { return }
        releaseAssertion()
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Barn Owl keep awake" as CFString, &assertionID)
        if result == kIOReturnSuccess {
            assertionType = type
        } else {
            Log.keepAwake.error("IOPMAssertionCreateWithName failed: \(result)")
            assertionID = 0
        }
    }

    /// Display sleep is allowed only if every active source allows it.
    private var displayMaySleep: Bool {
        Self.displayMaySleep(session: session, sessionAllows: Preferences.keepAwakeAllowDisplaySleep,
                             rule: activeRule, presenting: presenting)
    }

    nonisolated static func displayMaySleep(session: Session?, sessionAllows: Bool, rule: KeepAwakeRule?,
                                            presenting: Bool) -> Bool {
        (session == nil || sessionAllows) && (rule?.allowDisplaySleep ?? true) && !presenting
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
    /// activity. Only while keeping awake, and not while the display may
    /// sleep: a nudge counts as you, so the display would never sleep or lock.
    private func nudgeIfNeeded() {
        guard isActive, Preferences.keepAwakeKeepAvailable, !displayMaySleep,
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
    /// What the add-time buttons offer.
    static let extensions = [15, 30, 60, 120]
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

    /// Time left for the menu bar, kept short: "42m", "1:05", "<1m".
    static func countdown(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.up))
        if interval <= 0 || minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func remaining(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func durationLabel(minutes: Int) -> String {
        minutes == 0 ? "Indefinitely" : remaining(TimeInterval(minutes) * 60)
    }
}

import AppKit
import Observation
import UserNotifications

/// Watches the coding agents on this Mac and turns them into owlets.
///
/// Light by design: Claude Code's session folder is watched for changes and
/// each session's process for its exit. Logs are only ever read from where
/// they were last read, off the main thread. While an agent works, a look
/// every 2 seconds; while sessions sit idle, every 5; with none at all,
/// every 30; other agents' processes are scanned every 15 seconds, or every
/// minute while none turn up. With
/// the feature off, none of this runs.
@MainActor
@Observable
final class AgentWatcher {
    /// Every session found, hidden ones included.
    private(set) var all: [AgentSession] = []
    /// Claude's and Codex's plan limits, where they're known.
    private(set) var limits: [PlanLimit] = []
    /// Today's work, for the Roost's flight log.
    private(set) var flightLog = FlightLog()
    /// The desktop widget's snapshot.
    @ObservationIgnored let widget = WidgetFeed()
    /// Sessions that ended today, newest last: they sleep in the Roost's nest.
    private(set) var cameHome: [AgentSession] = []
    @ObservationIgnored var onChange: (() -> Void)?
    let choices = AgentChoices()

    @ObservationIgnored private let reader = AgentReader()
    @ObservationIgnored private var folderSource: DispatchSourceFileSystemObject?
    /// Answering from the island: on while its hooks are in Claude Code's settings.
    private(set) var answering = false
    @ObservationIgnored private var answersSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// Requests already looked at once, when they arrived.
    @ObservationIgnored private var seenAsks: Set<String> = []
    @ObservationIgnored private var exitSources: [Int32: DispatchSourceProcess] = [:]
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var readAgain = false
    /// Each session's last state, for notifications; nil until the first read.
    @ObservationIgnored private var previous: [String: OwletState]?
    /// A new state must be seen for 1.5 seconds before the owlet changes pose.
    @ObservationIgnored private var candidates: [String: (state: OwletState, since: Date)] = [:]
    @ObservationIgnored private var hosts: [Int32: (name: String?, pid: Int32?)] = [:]
    /// When an agent that counts for keep awake last worked, in seconds since startup.
    @ObservationIgnored private var lastWorked: TimeInterval?

    /// Keep awake carries on this long after the last agent stops, and this
    /// long into one waiting for you.
    static let grace: TimeInterval = 5 * 60

    var isRunning: Bool { tickTask != nil || (DemoMode.isOn && !all.isEmpty) }

    // MARK: What the views show

    /// The owlets to show: not hidden, needs-you first.
    var visible: [AgentSession] {
        all.filter { !choices.isHidden($0) }.sorted(by: Self.order)
    }

    var hiddenCount: Int { all.count - visible.count }

    /// Whether keep awake should hold: an agent you haven't left out is
    /// working, or one stopped or started waiting for you less than five
    /// minutes ago. Clocked by uptime, so a clock change can't stretch it.
    var keepsAwake: Bool {
        guard let lastWorked else { return false }
        return ProcessInfo.processInfo.systemUptime - lastWorked < Self.grace
    }

    nonisolated static func order(_ a: AgentSession, _ b: AgentSession) -> Bool {
        if a.state.rank != b.state.rank { return a.state.rank < b.state.rank }
        // Among those waiting on you: the one about to time out, then the one waiting longest.
        if a.state.needsYou {
            let aDeadline = a.request?.deadline ?? .distantFuture, bDeadline = b.request?.deadline ?? .distantFuture
            if aDeadline != bDeadline { return aDeadline < bDeadline }
            let aSince = a.request?.since ?? a.stateSince, bSince = b.request?.since ?? b.stateSince
            if aSince != bSince { return aSince < bSince }
        }
        return a.started < b.started
    }

    // MARK: Starting and stopping

    func start() {
        guard tickTask == nil else { return }
        if DemoMode.isOn {
            all = AgentDemo.sessions(now: Date())
            limits = AgentDemo.limits(now: Date())
            widget.update(sessions: all, limits: limits, worked: FlightLog.demo(now: Date()).total(.working), now: Date())
            onChange?()
            return
        }
        previous = nil
        watchSessionsFolder()
        Task { [weak self] in
            let on = await Task.detached { IslandAnswers.isOn() }.value
            self?.setAnswering(on)
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.nextLook))
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        if answering { IslandAnswers.listen(false) }
        answersSource?.cancel()
        answersSource = nil
        activationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activationObserver = nil
        pending?.cancel()
        pending = nil
        folderSource?.cancel()
        folderSource = nil
        exitSources.values.forEach { $0.cancel() }
        exitSources.removeAll()
        candidates.removeAll()
        hosts.removeAll()
        previous = nil
        lastWorked = nil
        all = []
        limits = []
        alerted.removeAll()
        widget.stop()
        onChange?()
    }

    func applySettings() {
        Preferences.agentsEnabled ? start() : stop()
    }

    /// Turns answering from the island on or off (its hooks were just added or removed).
    func setAnswering(_ on: Bool) {
        answering = on
        let live = on && tickTask != nil
        IslandAnswers.listen(live)
        answersSource?.cancel()
        answersSource = nil
        activationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activationObserver = nil
        guard live else { return scheduleRefresh() }
        watchAnswers()
        // Switching to a session's app to answer there: the usual prompt takes it.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                for session in self.all where session.hostPID == pid {
                    if let ask = session.pendingAsk { IslandAnswers.reply(.pass, to: ask) }
                }
            }
        }
        scheduleRefresh()
    }

    /// Hears a request arrive for the island, or go.
    private func watchAnswers() {
        let descriptor = open(IslandAnswers.folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleRefresh() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        answersSource = source
    }

    /// Read again soon, after an answer.
    func refreshSoon() { scheduleRefresh() }

    private var nextLook: Double {
        if all.contains(where: { $0.state.isWorking || $0.state.needsYou }) { return 2 }
        return all.isEmpty ? 30 : 5
    }

    /// Something changed: read again shortly.
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Hears when sessions start and end. The folder may not exist yet, or
    /// be replaced; then it's watched again on a later read.
    private func watchSessionsFolder() {
        guard folderSource == nil else { return }
        let descriptor = open(ClaudeSource.sessionsFolder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                if !source.data.isDisjoint(with: [.rename, .delete]) {
                    source.cancel()
                    self.folderSource = nil
                }
                self.scheduleRefresh()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        folderSource = source
    }

    /// Hears straight away when a session's process ends.
    private func watchExits(of pids: Set<Int32>) {
        for (pid, source) in exitSources where !pids.contains(pid) {
            source.cancel()
            exitSources[pid] = nil
        }
        for pid in pids where exitSources[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid_t(pid), eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            source.resume()
            exitSources[pid] = source
        }
    }

    // MARK: Reading

    func refresh() async {
        guard !DemoMode.isOn else { return }
        guard !reading else {
            readAgain = true
            return
        }
        reading = true
        defer {
            reading = false
            if readAgain, tickTask != nil {
                readAgain = false
                scheduleRefresh()
            }
        }
        let now = Date()
        let result = await reader.read(now: now, answers: answering)
        guard tickTask != nil else { return } // turned off meanwhile
        if result.sessionsFolderExists { watchSessionsFolder() }
        let known = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sessions: [AgentSession] = []

        for read in result.claude {
            let id = "claude:\(read.file.sessionId)"
            var (state, detail) = ClaudeSource.state(file: read.file, log: read.log, helpers: read.helpers, now: now)
            var session = known[id] ?? AgentSession(
                id: id, agent: .claude, pid: read.file.pid, name: "", folder: URL(fileURLWithPath: read.file.cwd),
                place: read.place, started: read.file.started, state: state, stateSince: now, detail: detail)
            session.pid = read.file.pid
            session.name = read.file.name.flatMap { $0.isEmpty ? nil : $0 } ?? read.chat?.title
                ?? read.place.worktree ?? read.place.repository
            session.appChat = read.chat?.id
            session.isScripted = read.file.isScripted
            session.helpers = read.helpers
            session.lastTurn = ClaudeSource.turnLength(read.log)
            session.branch = read.log.branch
            session.evidence = read.log.evidence
            session.request = state.needsYou ? read.log.currentRequest : nil
            let host = read.file.entrypoint == "claude-desktop" ? claudeApp() : host(of: read.file.pid)
            session.host = host.name
            session.hostPID = host.pid
            session.pendingAsk = nil
            if let ask = result.asks.first(where: { $0.session == read.file.sessionId }),
               holds(ask, for: session, hostPID: host.pid, log: read.log) {
                session.pendingAsk = ask
                session.request = Self.request(for: ask)
                state = ask.kind == .question ? .asking : .needsYou
                detail = ask.kind == .question ? "Has a question" : "Wants your OK"
            }
            update(&session, to: state, detail: detail, now: now)
            sessions.append(session)
        }

        // A request no session claims (its session file may lag a moment)
        // goes back to the usual prompt rather than waiting unseen.
        for ask in result.asks where !sessions.contains(where: { $0.pendingAsk?.id == ask.id })
            && now.timeIntervalSince(ask.asked) > 3 {
            IslandAnswers.reply(.pass, to: ask)
        }
        seenAsks.formIntersection(result.asks.map(\.id))

        for read in result.agents {
            let id = "\(read.found.agent.rawValue):\(read.found.pid)"
            // Without a log to read, an agent using the CPU counts as working.
            let (state, detail) = read.codex?.state(now: now) ?? (read.busy ? .thinking : .resting, nil)
            var session = known[id] ?? AgentSession(
                id: id, agent: read.found.agent, pid: read.found.pid, name: "", folder: URL(fileURLWithPath: read.found.folder),
                place: read.place, started: read.found.started, state: state, stateSince: now, detail: detail)
            session.name = read.place.worktree ?? read.place.repository
            session.lastTurn = read.codex?.lastTurn
            let host = host(of: read.found.pid)
            session.host = host.name
            session.hostPID = host.pid
            update(&session, to: state, detail: detail, now: now)
            sessions.append(session)
        }

        let live = Set(sessions.map(\.id))
        candidates = candidates.filter { live.contains($0.key) }
        hosts = hosts.filter { pid, _ in sessions.contains { $0.pid == pid } }
        for session in sessions where session.state.needsYou { choices.cameBack(session) }
        choices.forget(except: live)
        noteWork(in: sessions, now: now)
        notifyChanges(in: sessions)
        watchExits(of: Set(sessions.compactMap { $0.agent == .claude ? $0.pid : nil }))
        noteLimits(result.limits)
        noteDepartures(from: known, live: live, now: now)
        var log = flightLog
        log.record(sessions.filter { !choices.isHidden($0) }, now: now)
        DailyLog.shared.record(sessions.filter { !choices.isHidden($0) }, now: now)
        widget.update(sessions: sessions.filter { !choices.isHidden($0) }, limits: result.limits,
                      worked: log.total(.working), now: now)
        if log != flightLog { flightLog = log }
        if sessions != all || result.limits != limits {
            all = sessions
            limits = result.limits
            onChange?()
        }
    }

    /// Sessions gone since the last read go to the nest, for today.
    private func noteDepartures(from known: [String: AgentSession], live: Set<String>, now: Date) {
        var home = cameHome.filter { Calendar.current.isDate($0.stateSince, inSameDayAs: now) && !live.contains($0.id) }
        for (id, session) in known where !live.contains(id) && !choices.isHidden(session)
            && !home.contains(where: { $0.id == id }) {
            var resting = session
            resting.state = .napping
            resting.stateSince = now
            home.append(resting)
        }
        if home.count > 50 { home.removeFirst(home.count - 50) }
        if home != cameHome { cameHome = home }
    }

    // MARK: Plan limit alerts

    /// Windows already told about: crossed 80% (per reset), or seen high.
    @ObservationIgnored private var alerted: [String: Date] = [:]
    @ObservationIgnored private var lastUsed: [String: Double] = [:]

    /// One note when a window passes 80%, and one when a window that was
    /// high resets ("a fresh window"). Never on the first reading.
    private func noteLimits(_ fresh: [PlanLimit]) {
        defer { lastUsed = Dictionary(fresh.map { ($0.id, $0.used) }, uniquingKeysWith: { a, _ in a }) }
        guard Preferences.agentsLimitAlerts else { return }
        for limit in fresh {
            guard let before = lastUsed[limit.id] else { continue }
            let owner = limit.agent == .claude ? "Claude" : limit.agent.name
            let name = "\(owner)'s \(limit.window == .session ? "5-hour" : "weekly") limit"
            if before < 80, limit.used >= 80, alerted[limit.id] == nil {
                alerted[limit.id] = Date()
                let reset = limit.resetsAt.map { " It resets \(PlanLimit.when($0))." } ?? ""
                notifyPlan(id: limit.id, title: "\(Int(limit.used))% of \(name) used", body: "Pace yourself a little.\(reset)")
            } else if before >= 80, limit.used < 20 {
                alerted[limit.id] = nil
                notifyPlan(id: limit.id, title: "A fresh window", body: "\(name) has reset.")
            }
        }
    }

    private func notifyPlan(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.notificationCategory
        let request = UNNotificationRequest(identifier: "plan-\(id)", content: content, trigger: nil)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }

    /// Keep awake follows agents that are working, and ones that started
    /// waiting for you less than the grace period ago (not all night).
    private func noteWork(in sessions: [AgentSession], now: Date) {
        let working = sessions.filter { choices.countsForKeepAwake($0) }.contains { session in
            session.state.isWorking
                || (session.state.needsYou && now.timeIntervalSince(session.stateSince) < Self.grace)
        }
        if working { lastWorked = ProcessInfo.processInfo.systemUptime }
    }

    /// A new state must hold for 1.5 seconds before the owlet changes pose,
    /// so quick tool calls don't make it flicker. "Needs you" shows at once.
    private func update(_ session: inout AgentSession, to state: OwletState, detail: String?, now: Date) {
        guard session.state != state else {
            candidates[session.id] = nil
            session.detail = detail
            return
        }
        let candidate = candidates[session.id]
        let seenSince = candidate.flatMap { $0.state == state ? $0.since : nil } ?? now
        if state.needsYou || !session.state.isWorking || now.timeIntervalSince(seenSince) >= 1.5 {
            session.state = state
            session.stateSince = now
            session.detail = detail
            candidates[session.id] = nil
        } else {
            candidates[session.id] = (state, seenSince)
        }
    }

    /// Whether the island should hold a request: not when you're already in
    /// that session's app, and not once the session has moved on (you
    /// answered in the Claude app); then the usual prompt takes it.
    private func holds(_ ask: IslandAnswers.Ask, for session: AgentSession, hostPID: Int32?,
                       log: ClaudeSource.LogState) -> Bool {
        // Only while the island will show it: never hold what nothing shows.
        if !islandCanShow() || choices.isHidden(session) || choices.isMuted(session) {
            IslandAnswers.reply(.pass, to: ask)
            return false
        }
        if let last = log.lastActivity, last > ask.asked.addingTimeInterval(1) {
            IslandAnswers.reply(.pass, to: ask)
            return false
        }
        if seenAsks.insert(ask.id).inserted, let hostPID,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == hostPID {
            IslandAnswers.reply(.pass, to: ask)
            return false
        }
        return true
    }

    nonisolated static func request(for ask: IslandAnswers.Ask) -> AgentRequest {
        let kind: AgentRequest.Kind = switch (ask.kind, ask.tool) {
        case (.question, _): .question
        case (_, "Bash"): .command
        case (_, "Edit"), (_, "Write"), (_, "MultiEdit"), (_, "NotebookEdit"): .edit
        case (_, "WebFetch"), (_, "WebSearch"): .web
        default: .other
        }
        return AgentRequest(kind: kind, text: ask.text, options: ask.options, since: ask.asked, timesOut: false)
    }

    private func host(of pid: Int32) -> (name: String?, pid: Int32?) {
        if let known = hosts[pid] { return known }
        let app = ProcessScan.hostApp(of: pid)
        let host = (name: app?.localizedName, pid: app?.processIdentifier)
        hosts[pid] = host
        return host
    }

    private func claudeApp() -> (name: String?, pid: Int32?) {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: AgentActions.claudeApp).first?.processIdentifier
        return ("the Claude app", pid)
    }

    // MARK: Notifications

    nonisolated static let notificationCategory = "agent"
    /// Whether the island can show it; notifications only step in when it can't.
    @ObservationIgnored var islandCanShow: () -> Bool = { false }

    /// Away from the Mac: a notification waits in Notification Center for you.
    private var userAway: Bool { SystemConditions.secondsSinceInput > 120 }
    /// Clicking an agent notification shows that session.
    static var openFromNotification: ((String) -> Void)?

    /// One notification per change into "needs you", "stuck" or a long
    /// task's "done". Nothing for what was already so when watching began.
    private func notifyChanges(in sessions: [AgentSession]) {
        defer { previous = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first }) }
        guard let previous else { return }
        // Resolved: take back what was said about it.
        let resolved = previous.compactMap { id, state -> String? in
            let now = sessions.first { $0.id == id }?.state
            return (state.needsYou || state == .stuck) && now != state ? "agent-\(id)" : nil
        }
        if !resolved.isEmpty { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: resolved) }
        // The island tells you when it can; a notification only when it can't, or you're away.
        guard !islandCanShow() || userAway else { return }
        for session in sessions where previous[session.id] != session.state && choices.mayNotify(session) {
            let before = previous[session.id]
            if session.state.needsYou, Preferences.agentsNotifyNeedsYou, before?.needsYou != true {
                let body = session.request.map { $0.kind == .question ? "“\($0.text)”" : $0.text } ?? session.detail ?? "It's waiting for you."
                notify(session, title: session.state == .asking ? "\(session.placeName) is asking" : "\(session.placeName) needs you",
                       body: body)
            } else if session.state == .stuck, Preferences.agentsNotifyNeedsYou, before?.isWorking == true {
                notify(session, title: "\(session.placeName) is stuck", body: session.detail ?? "It stopped after failures.")
            } else if session.state == .done || session.state == .shipped, Preferences.agentsNotifyDone,
                      before?.isWorking == true,
                      (session.lastTurn ?? 0) >= TimeInterval(Preferences.agentsNotifyAfterMinutes * 60) {
                notify(session, title: "\(session.placeName) is done", body: session.detail ?? "Your turn.")
            }
        }
    }

    private func notify(_ session: AgentSession, title: String, body: String) {
        // No need when its window is already in front of you.
        if let host = session.hostPID, NSWorkspace.shared.frontmostApplication?.processIdentifier == host { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(session.agent.name) · \(body)"
        content.categoryIdentifier = Self.notificationCategory
        content.userInfo = ["session": session.id]
        let request = UNNotificationRequest(identifier: "agent-\(session.id)", content: content, trigger: nil)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }

    func session(withID id: String) -> AgentSession? {
        all.first { $0.id == id }
    }
}

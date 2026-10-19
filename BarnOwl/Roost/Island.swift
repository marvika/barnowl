import AppKit
import SwiftUI

/// The agents' island at the notch: it grows out of the notch (or hangs
/// from the top of the screen on a Mac without one) when an agent needs you
/// or finishes, says so in a line, and opens on hover to show what's waiting.
///
/// Calm by design: it stays away while you present, share your screen or
/// use an app full screen, and it only animates as it changes. Its window
/// keeps one size and the island grows inside it, so opening never jumps;
/// the window lets clicks through everywhere but the island itself, so it
/// never catches clicks meant for the menu bar or the app beneath.
@MainActor
final class IslandController {
    private let model: AppModel
    private var panel: NSPanel?
    private var hosting: NSHostingView<IslandView>?
    private let state = IslandState()
    private var hideTask: Task<Void, Never>?
    private var placing = false
    private var mouseMonitors: [Any] = []
    private var hoverIntent: Task<Void, Never>?
    /// Where the pointer was at the last look: over the island or not.
    private var pointerInside = false
    /// Room for the island at its largest; the window never changes size.
    static let canvas = NSSize(width: 520, height: 400)
    /// The Nest's height under the notch, when it's showing, so the island makes room.
    var nestHeight: () -> CGFloat = { 0 }

    /// How long a finished task stays in the island.
    static let doneFor: TimeInterval = 6

    init(model: AppModel) {
        self.model = model
        state.onHover = { [weak self] in self?.update() }
        state.onAction = { [weak self] action in self?.perform(action) }
        // A full-screen app or a new Space can hide the menu bar: check again then.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        // Displays added, removed or rearranged: find the notch again.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Recomputes what the island shows, and shows or hides it.
    func update() {
        // Not for muted folders, and not while you're already in that session's app.
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let sessions = model.agents.visible.filter { session in
            !model.agents.choices.isMuted(session) && !(session.state.needsYou && front != nil && session.hostPID == front)
        }
        let items = Self.items(from: sessions, mode: Preferences.agentsIsland, now: Date())
        let shouldShow = Preferences.agentsEnabled && !items.isEmpty && quietTimeAllows
        state.items = items
        state.mode = Preferences.agentsIsland
        guard shouldShow else { return hide() }
        show()
        scheduleDoneExpiry(items)
    }

    /// Whether the island can be seen right now, so notifications know when to step in.
    var canShow: Bool { Preferences.agentsEnabled && Preferences.agentsIsland != .off && quietTimeAllows }

    /// Not while presenting, sharing the screen, or with the menu bar hidden by a full-screen app.
    private var quietTimeAllows: Bool {
        if model.presenter.isPresenting { return false }
        let options = NSApp.currentSystemPresentationOptions
        return !options.contains(.hideMenuBar) && !options.contains(.autoHideMenuBar) && !options.contains(.fullScreen)
    }

    // MARK: What it shows

    struct Item: Identifiable, Equatable {
        enum Kind: Equatable {
            case needsYou, stuck, done, working
            /// A one-off line: the dawn report, a parliament.
            case note(String)
        }
        let session: AgentSession
        let kind: Kind
        var id: String { session.id }
    }

    /// Needs you and stuck first, then tasks that finished in the last few
    /// seconds; in "while agents work" mode, the working ones too.
    static func items(from sessions: [AgentSession], mode: IslandMode, now: Date) -> [Item] {
        guard mode != .off else { return [] }
        var items: [Item] = []
        for session in sessions {
            if session.state.needsYou {
                items.append(Item(session: session, kind: .needsYou))
            } else if session.state == .stuck {
                items.append(Item(session: session, kind: .stuck))
            } else if session.state == .done || session.state == .shipped,
                      now.timeIntervalSince(session.stateSince) < doneFor {
                items.append(Item(session: session, kind: .done))
            } else if mode == .always, session.state.isWorking {
                items.append(Item(session: session, kind: .working))
            }
        }
        return items
    }

    private func scheduleDoneExpiry(_ items: [Item]) {
        hideTask?.cancel()
        let done = items.filter { $0.kind == .done }.map { $0.session.stateSince.addingTimeInterval(Self.doneFor) }
        guard let next = done.min() else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.5, next.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            // Hovering keeps it open: you're reading it.
            if self.state.hovering { return self.scheduleDoneExpiry(items) }
            self.update()
        }
    }

    private func perform(_ action: IslandState.Action) {
        switch action {
        case .show(let session): AgentActions.show(session)
        case .open(let session): AgentActions.openInEditor(session)
        case .roost(let id): model.showRoost(id)
        case .answer(let session, let reply):
            if reply == .pass {
                AgentActions.show(session)
            } else if let ask = session.pendingAsk {
                IslandAnswers.reply(reply, to: ask)
            }
            model.agents.refreshSoon()
        }
        state.hovering = false
        update()
    }

    // MARK: The window

    private func show() {
        guard !placing, let screen = Self.screen else { return }
        placing = true
        defer { placing = false }
        let notch = NotchGeometry.of(screen)
        // The Nest lives on the first screen; it only makes room there.
        let nest = screen == NSScreen.screens.first ? nestHeight() : 0
        state.notchWidth = nest > 0 ? nil : notch.map { $0.maxX - $0.minX }
        // The notch's height, even when the menu bar hides itself.
        state.menuBarHeight = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        state.moves = Preferences.owlMoves && !ProcessInfo.processInfo.isLowPowerModeEnabled
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = NSSize(width: Self.canvas.width, height: Self.canvas.height + (state.notchWidth == nil ? 0 : state.menuBarHeight))
        var centre = notch.map { ($0.minX + $0.maxX) / 2 } ?? screen.frame.midX
        // The notch's areas may be in the screen's own coordinates.
        if !(screen.frame.minX...screen.frame.maxX).contains(centre) { centre += screen.frame.minX }
        // Flush with the top of the screen at the notch; below the Nest or the
        // menu bar otherwise.
        let top = state.notchWidth != nil ? screen.frame.maxY : screen.visibleFrame.maxY - nest - 6
        let frame = NSRect(x: (centre - size.width / 2).rounded(), y: (top - size.height.rounded(.up)),
                           width: size.width.rounded(.up), height: size.height.rounded(.up))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible {
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
        }
        followPointer()
    }

    /// Opens or closes it as hovering would, for links and the demo.
    func setOpen(_ open: Bool) {
        guard panel?.isVisible == true else { return }
        withAnimation(.spring(duration: 0.42, bounce: 0.16)) { state.hovering = open }
    }

    func hide() {
        hideTask?.cancel()
        hoverIntent?.cancel()
        state.hovering = false
        pointerInside = false
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        panel?.orderOut(nil)
    }

    // MARK: The pointer

    /// Watches the pointer while the island is up: over the island, the
    /// window takes clicks and the island opens; anywhere else, clicks pass
    /// through to whatever is beneath.
    private func followPointer() {
        guard mouseMonitors.isEmpty else { return pointerMoved() }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { mouseMonitors.append(local) }
        pointerMoved()
    }

    private func pointerMoved() {
        guard let panel, panel.isVisible else { return }
        let island = state.islandFrame
        // The island's frame is measured from the window's top-left corner.
        let rect = NSRect(x: panel.frame.minX + island.minX, y: panel.frame.maxY - island.maxY,
                          width: island.width, height: island.height).insetBy(dx: -4, dy: -4)
        let inside = !island.isEmpty && rect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside
        // Open on a short dwell, close on a slightly longer one, so passing
        // the pointer over it or a shrinking edge never makes it flicker.
        hoverIntent?.cancel()
        hoverIntent = Task { [weak self] in
            // A pointer passing by on its way to a tab shouldn't open it.
            try? await Task.sleep(for: .milliseconds(inside ? 250 : 320))
            guard !Task.isCancelled, let self, self.state.hovering != inside else { return }
            let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(still ? .easeInOut(duration: 0.15) : .spring(duration: 0.42, bounce: 0.16)) {
                self.state.hovering = inside
            }
        }
    }

    private static var screen: NSScreen? {
        NSScreen.screens.first { NotchGeometry.of($0) != nil } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        let hosting = NSHostingView(rootView: IslandView(state: state))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.hosting = hosting
        return panel
    }
}

/// What the island's view reads; the controller writes it.
@MainActor
@Observable
final class IslandState {
    enum Action {
        case show(AgentSession)
        case open(AgentSession)
        case roost(String?)
        /// An answer to a request held for the island.
        case answer(AgentSession, IslandAnswers.Reply)
    }

    var items: [IslandController.Item] = []
    var mode = IslandMode.attention
    /// The notch's width, when the island grows out of it.
    var notchWidth: CGFloat?
    var menuBarHeight: CGFloat = 24
    /// Whether the owlet may animate (not with Reduce Motion, Still, or Low Power Mode).
    var moves = true
    var hovering = false {
        didSet { if hovering != oldValue { onHover?() } }
    }
    @ObservationIgnored var onHover: (() -> Void)?
    /// The island's shape in the window, from its top-left corner, for the pointer.
    @ObservationIgnored var islandFrame = CGRect.zero
    @ObservationIgnored var onAction: ((Action) -> Void)?
}

struct IslandView: View {
    @Bindable var state: IslandState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { state.hovering }
    private var lead: IslandController.Item? { state.items.first }

    var body: some View {
        VStack(spacing: 0) {
            if let notch = state.notchWidth {
                // The part that hides in the notch, so the island grows out of it.
                Color.clear.frame(width: notch, height: state.menuBarHeight)
            }
            Group {
                if expanded, let lead {
                    expandedContent(lead).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    compactContent.transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, state.notchWidth == nil ? 8 : 5)
            .padding(.bottom, expanded ? 16 : 8)
            .frame(minWidth: max((state.notchWidth ?? 0) + 48, 210))
        }
        .background {
            IslandShape(notchWidth: state.notchWidth, notchHeight: state.notchWidth == nil ? 0 : state.menuBarHeight,
                        radius: expanded ? 26 : 18)
                .fill(.black)
        }
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.islandFrame = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.owletsMove, state.moves)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: state.items.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lead.map(accessibleSummary) ?? "Agents")
        .accessibilityAction(named: expanded ? "Hide Details" : "Show Details") { state.hovering.toggle() }
        .accessibilityAction(named: "Show") { if let lead { state.onAction?(.show(lead.session)) } }
    }

    // MARK: Compact: one line

    private var compactContent: some View {
        HStack(spacing: 8) {
            if let lead {
                ZStack {
                    if let deadline = lead.session.request?.deadline, lead.kind == .needsYou {
                        CountdownRing(since: lead.session.request?.since ?? Date(), deadline: deadline, width: 2)
                            .frame(width: 22, height: 22)
                    }
                    // Moves while it's news, then rests: the island shouldn't fidget for long.
                    OwletIcon(icon: lead.session.state.icon, palette: lead.session.agent.palette, scale: 1,
                              seed: lead.id.hashValue,
                              animated: lead.kind != .working && Date().timeIntervalSince(lead.session.stateSince) < 12)
                }
                .frame(width: 22, height: 22)
                // A long name shortens; what's happening never does.
                HStack(spacing: 4) {
                    if let subject = subject(lead) {
                        Text(subject).lineLimit(1).truncationMode(.tail).frame(maxWidth: 190, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verb(lead)).lineLimit(1).fixedSize()
                }
                .font(.callout.weight(.semibold)).foregroundStyle(.white)
                Spacer(minLength: 4)
                if lead.kind == .needsYou { Waited(request: lead.session.request, since: lead.session.stateSince) }
                if let trailing = trailing(lead) {
                    Text(trailing).font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                let queued = state.items.filter { $0.kind == .needsYou || $0.kind == .stuck }.count - 1
                if queued > 0 {
                    Text("+\(queued)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.14), in: .capsule)
                }
            }
        }
        .frame(height: 22)
        .contentShape(.rect)
        .onTapGesture { withAnimation(.spring(duration: 0.42, bounce: 0.16)) { state.hovering = true } }
    }

    /// Who: the session's name, or nothing for a count or a note.
    private func subject(_ item: IslandController.Item) -> String? {
        switch item.kind {
        case .working, .note: nil
        default: item.session.name
        }
    }

    /// What's happening: "is asking", "shipped", "3 agents working".
    private func verb(_ item: IslandController.Item) -> String {
        switch item.kind {
        case .needsYou: item.session.state == .asking ? "is asking" : "needs you"
        case .stuck: "is stuck"
        case .done: item.session.state == .shipped ? "shipped" : "is done"
        case .working, .note: headline(item)
        }
    }

    private func headline(_ item: IslandController.Item) -> String {
        switch item.kind {
        case .needsYou: return item.session.state == .asking ? "\(item.session.name) is asking" : "\(item.session.name) needs you"
        case .stuck: return "\(item.session.name) is stuck"
        case .done: return item.session.state == .shipped ? "\(item.session.name) shipped" : "\(item.session.name) is done"
        case .working:
            let count = state.items.count
            return count == 1 ? "1 agent working" : "\(count) agents working"
        case .note(let text): return text
        }
    }

    private func trailing(_ item: IslandController.Item) -> String? {
        switch item.kind {
        case .done: return item.session.lastTurn.map { ClaudeSource.duration($0) }
        case .working:
            return state.items.map(\.session.started).min().map { ClaudeSource.duration(Date().timeIntervalSince($0)) }
        default: return nil
        }
    }

    private func accessibleSummary(_ item: IslandController.Item) -> String {
        var text = headline(item)
        if let request = item.session.request { text += ": \(request.text)" }
        return text
    }

    // MARK: Expanded: the one request, and one action

    private func expandedContent(_ lead: IslandController.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    if let deadline = lead.session.request?.deadline, lead.kind == .needsYou {
                        CountdownRing(since: lead.session.request?.since ?? Date(), deadline: deadline, width: 3)
                            .frame(width: 44, height: 44)
                    }
                    OwletIcon(icon: lead.session.state.icon, palette: lead.session.agent.palette, scale: 2,
                              seed: lead.id.hashValue, animated: lead.kind != .working)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.session.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle(lead)).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            if let request = lead.session.request {
                RequestBody(request: request, showsOptions: lead.session.pendingAsk == nil)
            } else if let detail = lead.session.detail {
                Text(detail).font(.callout).foregroundStyle(lead.kind == .stuck ? Brand.amber : .white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ask = lead.session.pendingAsk {
                AnswerControls(ask: ask, host: host(lead)) { reply in state.onAction?(.answer(lead.session, reply)) }
            } else {
                Button {
                    state.onAction?(.show(lead.session))
                } label: {
                    HStack(spacing: 6) {
                        Text(actionTitle(lead))
                        Image(systemName: "return").font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(IslandButtonStyle(prominent: lead.kind == .needsYou))
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("\(actionTitle(lead)), \(lead.session.name)")
            }
            if let next = state.items.dropFirst().first(where: { $0.kind == .needsYou || $0.kind == .stuck }) {
                Button {
                    state.onAction?(.show(next.session))
                } label: {
                    HStack(spacing: 8) {
                        OwletIcon(icon: next.session.state.icon, palette: next.session.agent.palette, scale: 1, animated: false)
                        Text("Also waiting · \(next.session.name)").lineLimit(1)
                        if let request = next.session.request { Text(request.text).lineLimit(1).foregroundStyle(.white.opacity(0.45)) }
                        Spacer(minLength: 4)
                        Text(ClaudeSource.duration(Date().timeIntervalSince(next.session.request?.since ?? next.session.stateSince)))
                            .monospacedDigit().foregroundStyle(.white.opacity(0.45))
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            let waiting = state.items.filter { $0.kind == .needsYou || $0.kind == .stuck }.count
            if waiting > 2 {
                Button {
                    state.onAction?(.roost(nil))
                } label: {
                    HStack(spacing: 4) {
                        Text("and \(waiting - 2) more in the Roost")
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 420)
    }

    private func subtitle(_ item: IslandController.Item) -> String {
        var parts = [item.session.placeName, item.session.agent.name]
        if item.kind == .needsYou, let since = item.session.request?.since ?? Optional(item.session.stateSince) {
            parts.append("asked \(Self.ago(since))")
        }
        return parts.joined(separator: " · ")
    }

    private func host(_ item: IslandController.Item) -> String {
        (item.session.host ?? "Terminal").replacingOccurrences(of: "the ", with: "")
    }

    private func actionTitle(_ item: IslandController.Item) -> String {
        item.kind == .needsYou ? "Answer in \(host(item))" : "Show in \(host(item))"
    }

    static func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(max(1, seconds)) s ago" }
        return "\(ClaudeSource.duration(TimeInterval(seconds))) ago"
    }
}

/// The question, or the command, exactly as the agent asked it.
private struct RequestBody: View {
    let request: AgentRequest
    var showsOptions = true

    var body: some View {
        switch request.kind {
        case .question:
            VStack(alignment: .leading, spacing: 8) {
                Text("“\(request.text)”").font(.callout).foregroundStyle(.white).lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                if showsOptions && !request.options.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(request.options.enumerated()), id: \.offset) { index, option in
                            HStack(spacing: 4) {
                                Text("\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.5))
                                Text(option).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.1), in: .capsule)
                        }
                    }
                }
            }
        case .command, .other:
            // The whole command (or a tool and its arguments), always: a long
            // one scrolls rather than hiding its end.
            let long = request.text.count > 140 || request.text.contains("\n")
            Group {
                if long {
                    ScrollView {
                        Text(request.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 92)
                } else {
                    Text(request.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout.monospaced()).foregroundStyle(Brand.amber).textSelection(.enabled)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: .rect(cornerRadius: 10))
        case .edit:
            Label("Wants to edit \(request.text)", systemImage: "pencil").font(.callout).foregroundStyle(.white.opacity(0.85))
        case .web:
            Label("Wants to fetch \(request.text)", systemImage: "globe").font(.callout).foregroundStyle(.white.opacity(0.85))
        case .plan:
            Text(request.text).font(.callout).foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Answering in the island: the question's options, or Allow Once and Deny.
/// Nothing is the default button, so a stray Return never allows anything.
private struct AnswerControls: View {
    let ask: IslandAnswers.Ask
    let host: String
    let reply: (IslandAnswers.Reply) -> Void
    /// Answers take clicks only after a moment, and again after the request
    /// changes, so a click meant for something else never lands on Allow.
    @State private var armed = false

    var body: some View {
        VStack(spacing: 8) {
            answers
                .allowsHitTesting(armed)
                .opacity(armed ? 1 : 0.6)
                .animation(.easeOut(duration: 0.15), value: armed)
            Button {
                reply(.pass)
            } label: {
                HStack(spacing: 4) {
                    Text("Answer in \(host)")
                    Image(systemName: "arrow.up.forward").font(.caption2.weight(.bold))
                }
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .task(id: ask.id) {
            armed = false
            try? await Task.sleep(for: .milliseconds(450))
            armed = !Task.isCancelled
        }
    }

    @ViewBuilder private var answers: some View {
        VStack(spacing: 8) {
            switch ask.kind {
            case .question:
                ForEach(Array(ask.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        reply(.answer(option))
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                            Text(option).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(IslandButtonStyle(prominent: false))
                    .accessibilityLabel("Answer: \(option)")
                }
            case .permission:
                HStack(spacing: 8) {
                    Button("Deny") { reply(.deny) }
                        .buttonStyle(IslandButtonStyle(prominent: false))
                    Button("Allow Once") { reply(.allow) }
                        .buttonStyle(IslandButtonStyle(prominent: true))
                }
                // Claude Code's own "don't ask again", saying exactly what it covers.
                if let always = ask.always {
                    Button {
                        reply(.always)
                    } label: {
                        Text("Always allow \(always)").lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(IslandQuietButtonStyle())
                    .help("Allows this now, and adds Claude Code's suggested rule so it won't ask again for \(always).")
                }
            }
        }
    }
}

/// A ring that drains over a question's minute, then a quiet "carried on".
struct CountdownRing: View {
    let since: Date
    let deadline: Date
    var width: CGFloat = 2

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(1, deadline.timeIntervalSince(since))
            let left = max(0, deadline.timeIntervalSince(context.date))
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: width)
                Circle().trim(from: 0, to: left / total)
                    .stroke(Brand.amber, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
            }
        }
        .accessibilityHidden(true)
    }
}

/// How long it has waited ("4:10"), or for a question, the time left ("0:42").
private struct Waited: View {
    let request: AgentRequest?
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let deadline = request?.deadline, deadline > context.date {
                Text(Self.clock(deadline.timeIntervalSince(context.date)))
                    .font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(Brand.amber)
            } else {
                Text(Self.clock(context.date.timeIntervalSince(request?.since ?? since)))
                    .font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A rounded capsule button, quiet unless it's the thing to do.
/// The least of the island's buttons: a standing rule is never the obvious click.
private struct IslandQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay { Capsule().strokeBorder(.white.opacity(configuration.isPressed ? 0.35 : 0.18)) }
            .contentShape(.capsule)
    }
}

private struct IslandButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .font(.callout.weight(.semibold))
            .foregroundStyle(prominent ? Color.black : .white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(prominent ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.white.opacity(0.14)), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The island's outline: under the notch it's the notch's own width at the
/// top, curving out into a wider body like the notch's shoulders; without a
/// notch, a rounded pill.
struct IslandShape: Shape {
    var notchWidth: CGFloat?
    var notchHeight: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard let notchWidth, notchHeight > 0 else {
            return Path(roundedRect: rect, cornerRadius: min(radius, rect.height / 2), style: .continuous)
        }
        let shoulder: CGFloat = 10
        let top = (rect.width - notchWidth) / 2
        var path = Path()
        // Exactly the notch's width up top, hidden in it; the body flares out below.
        path.move(to: CGPoint(x: top, y: 0))
        path.addLine(to: CGPoint(x: rect.width - top, y: 0))
        path.addLine(to: CGPoint(x: rect.width - top, y: notchHeight - shoulder))
        path.addQuadCurve(to: CGPoint(x: min(rect.width, rect.width - top + shoulder), y: notchHeight),
                          control: CGPoint(x: rect.width - top, y: notchHeight))
        path.addLine(to: CGPoint(x: rect.width - radius, y: notchHeight))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: notchHeight + radius), control: CGPoint(x: rect.width, y: notchHeight))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: notchHeight + radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: notchHeight), control: CGPoint(x: 0, y: notchHeight))
        path.addLine(to: CGPoint(x: max(0, top - shoulder), y: notchHeight))
        path.addQuadCurve(to: CGPoint(x: top, y: notchHeight - shoulder), control: CGPoint(x: top, y: notchHeight))
        path.closeSubpath()
        return path
    }
}

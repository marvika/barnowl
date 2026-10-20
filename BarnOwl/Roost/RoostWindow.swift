import AppKit
import SwiftUI

/// The Roost's window: every agent on one tree, the one you pick in the
/// inspector, and today's flight log. Its views are let go when it closes,
/// so nothing draws or animates while it's away.
@MainActor
final class RoostWindowController {
    private let model: AppModel
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    /// Whether any of the window can be seen: owlets hold still when it can't.
    private let visibility = RoostVisibility()

    init(model: AppModel) {
        self.model = model
    }

    func show(selecting id: String? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if window.contentViewController == nil || id != nil {
            let host = NSHostingController(rootView: RoostView(model: model, visibility: visibility,
                                                               selected: id).tint(Brand.accent))
            // The window keeps the size you gave it; SwiftUI would shrink it to the content's minimum.
            host.sizingOptions = []
            let frame = window.frame
            window.contentViewController = host
            window.setFrame(frame, display: false)
        }
        OpenPanel.shared.closeAll()
        // The demo's stage floats above other windows; recordings need the Roost above it.
        if DemoMode.isOn { window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.performClose(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.title = "Roost"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // The Roost keeps its night colours in light and dark alike.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x1B / 255, green: 0x1A / 255, blue: 0x36 / 255, alpha: 1)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 520)
        if !window.setFrameUsingName("BarnOwlRoost") { window.center() }
        window.setFrameAutosaveName("BarnOwlRoost")
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                               queue: .main) { [weak window] _ in
            MainActor.assumeIsolated { window?.contentViewController = nil }
        }
        // Hidden behind other windows or minimised: nothing moves.
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                   object: window, queue: .main) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                self?.visibility.isVisible = window?.occlusionState.contains(.visible) ?? false
            }
        }
        return window
    }
}

@MainActor
@Observable
final class RoostVisibility {
    var isVisible = true
}

struct RoostView: View {
    let model: AppModel
    var visibility = RoostVisibility()
    @State var selected: String?
    /// Opens on what needs doing; the tree is a tab away.
    @AppStorage("roostShowsTree") private var showsTree = false
    @AppStorage(PrefKey.roostSky) private var sky = RoostSky.follow

    private var agents: AgentWatcher { model.agents }

    /// Only these repositories, or all.
    @State private var repository: String?

    /// Today so far; the demo copy shows a made-up day, never the real log.
    private var log: FlightLog { DemoMode.isOn ? .demo(now: Date()) : agents.flightLog }
    private var day: DaySummary? { DemoMode.isOn ? nil : DailyLog.shared.today }
    /// The last eight weeks; made up in demo mode, so screenshots never show a real log.
    private var history: History { DemoMode.isOn ? History.demo(now: Date()) : DailyLog.shared.history(endingOn: Date()) }

    var body: some View {
        let all = agents.visible
        // A filter whose repository has gone shows everyone again.
        let filtered = repository.map { name in all.filter { $0.place.repository == name } } ?? []
        let sessions = filtered.isEmpty ? all : filtered
        VStack(spacing: 0) {
            header(all: all, shown: sessions)
            if showsTree {
                HStack(spacing: 0) {
                    RoostTreeView(model: model, sessions: sessions, cameHome: agents.cameHome, sky: sky, selected: $selected)
                        .frame(minWidth: 420)
                    RoostInspector(session: sessions.first { $0.id == selected }, sessions: sessions, limits: agents.limits,
                                   log: log, cameHome: agents.cameHome.count, returned: agents.cameHome.filter(\.isHelper),
                                   day: day)
                        .frame(width: 290)
                        .background(RoostInk.bottom)
                }
            } else {
                RoostNowView(model: model, sessions: sessions, cameHome: agents.cameHome, limits: agents.limits,
                             log: log, day: day, history: history, selected: $selected)
            }
        }
        .background(RoostInk.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.owletsMove, visibility.isVisible && Preferences.owlMoves
                         && !ProcessInfo.processInfo.isLowPowerModeEnabled)
        .frame(minHeight: 480)
        .onChange(of: Set(all.map(\.place.repository))) { _, repositories in
            if let repository, !repositories.contains(repository) { self.repository = nil }
        }
    }

    /// Beside the window buttons: the title, how many need you, and the controls.
    private func header(all: [AgentSession], shown: [AgentSession]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Roost").font(.system(size: 14, weight: .bold)).foregroundStyle(RoostInk.primary)
                Self.subtitleText(shown, waiting: all.filter(\.state.needsYou).count)
                    .font(.system(size: 11.5, weight: .medium))
            }
            Spacer()
            let repositories = Array(Set(all.map(\.place.repository))).sorted()
            if repositories.count > 1 || repository != nil {
                Menu {
                    Picker("Repositories", selection: $repository) {
                        Text("All Repos").tag(String?.none)
                        Divider()
                        ForEach(repositories, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(repository ?? "All Repos")
                }
                .menuStyle(.button).buttonStyle(.bordered).controlSize(.small).fixedSize()
                .help("Show one repository's owlets")
            }
            Picker("View", selection: $showsTree) {
                Text("Now").tag(false)
                Text("Tree").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("What needs you now, or every owlet on the tree")
            Button { model.showTree() } label: { Image(systemName: "pip.exit") }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Pop the tree out into its own window, which can stay on top")
        }
        .padding(.leading, 88).padding(.trailing, 20)
        .frame(height: 56)
    }

    /// "12 owlets in 5 repos · 2 need you", the last part in amber.
    /// `waiting` counts every repository, so a filter never hides what needs you.
    static func subtitleText(_ sessions: [AgentSession], waiting: Int? = nil) -> Text {
        let waiting = waiting ?? sessions.filter(\.state.needsYou).count
        let base = Text(subtitle(sessions)).foregroundStyle(RoostInk.secondary)
        guard waiting > 0 else { return base }
        return base + Text(" · ").foregroundStyle(RoostInk.secondary)
            + Text("\(waiting) need\(waiting == 1 ? "s" : "") you").foregroundStyle(RoostInk.amber)
    }

    /// "12 owlets in 5 repos"
    static func subtitle(_ sessions: [AgentSession]) -> String {
        guard !sessions.isEmpty else { return "No owlets out" }
        let repositories = Set(sessions.map(\.place.repository)).count
        var text = sessions.count == 1 ? "1 owlet" : "\(sessions.count) owlets"
        if repositories > 1 { text += " in \(repositories) repos" }
        return text
    }
}

// MARK: The inspector

struct RoostInspector: View {
    /// The owlet picked on the tree, if any.
    let session: AgentSession?
    /// Everyone on the tree, for the summary when none is picked.
    var sessions: [AgentSession] = []
    let limits: [PlanLimit]
    let log: FlightLog
    let cameHome: Int
    /// Helpers that finished, to list with the session that asked them.
    var returned: [AgentSession] = []
    var day: DaySummary?
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content }.scrollIndicators(.never) } else { content }
        }
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .leading) { Rectangle().fill(RoostInk.cardEdge).frame(width: 1) }
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let session { details(session) } else { summary }
            if !limits.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Plan limits").font(.system(size: 13, weight: .bold)).foregroundStyle(RoostInk.primary)
                    ForEach(limits) { limit in MoonRow(limit: limit) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: One owlet

    @ViewBuilder
    private func details(_ session: AgentSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            OwletSprite(sprite: session.state.sprite, palette: session.agent.palette, scale: 1.5, seed: session.id.hashValue)
                .frame(width: 48, height: 45)
                .padding(8)
                .background(RoostInk.card, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(RoostInk.cardEdge) }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.state.label).font(.callout.weight(.semibold)).foregroundStyle(tone(session))
                Text(session.agent.name).font(.caption).foregroundStyle(RoostInk.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(session.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(RoostInk.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.placeName).font(.callout).foregroundStyle(RoostInk.secondary)
        }
        if let request = session.request, session.state.needsYou {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.kind == .command ? "Wants to run" : request.kind == .question ? "Asks" : "Wants")
                    .font(.caption).foregroundStyle(RoostInk.secondary)
                Text(request.kind == .question ? "“\(request.text)”" : request.text)
                    .font(request.kind == .command ? .system(size: 12, design: .monospaced) : .callout)
                    .foregroundStyle(request.kind == .command ? RoostInk.command : RoostInk.primary)
                    .lineLimit(5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.25), in: .rect(cornerRadius: 10))
            }
        } else if let detail = session.detail, session.state == .stuck {
            Text(detail).font(.callout).foregroundStyle(RoostInk.coral)
        }
        // Side by side when they fit, stacked when they don't.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actions(session) }
            VStack(alignment: .leading, spacing: 8) { actions(session) }
        }
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
            if let host = session.host { fact("Where", host) }
            if let caller = session.calledBy {
                fact("Asked by", sessions.first { $0.id == caller }.map { "\($0.name) (\($0.agent.name))" } ?? "Another agent")
            }
            if let model = session.model { fact("Model", model) }
            fact("Folder", (session.folder.path as NSString).abbreviatingWithTildeInPath)
            if let branch = session.branch { fact("Branch", branch) }
            fact("Started", "\(session.started.formatted(date: .omitted, time: .shortened)) · \(RoostNumbers.duration(Date().timeIntervalSince(session.started), long: true))")
            if let detail = session.detail, !(session.state.needsYou || session.state == .stuck) { fact("Now", detail) }
            if let summary = session.evidence?.summary { fact("Last turn", summary) }
        }
        .font(.callout)
        let asked = sessions.filter { $0.calledBy == session.id }
        let back = returned.filter { $0.calledBy == session.id }
        if !asked.isEmpty || !back.isEmpty { AskedAgents(working: asked, back: back) }
        if !session.helpers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(asked.isEmpty && back.isEmpty ? "Helpers" : "Its own subagents")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(RoostInk.primary)
                ForEach(session.helpersByActivity.prefix(12)) { helper in
                    HStack(alignment: .top, spacing: 8) {
                        OwletIcon(icon: helper.state.icon, palette: session.agent.palette, scale: 1, animated: false)
                            .opacity(helper.isWorking ? 1 : 0.55)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(helper.task.isEmpty ? helper.type : helper.task).font(.callout).foregroundStyle(RoostInk.primary)
                                .lineLimit(2)
                            Text("\(helper.type) · \(helper.isWorking ? "working" : "done")").font(.caption)
                                .foregroundStyle(RoostInk.secondary)
                        }
                    }
                }
                if session.helpers.count > 12 {
                    Text("and \(session.helpers.count - 12) more").font(.caption).foregroundStyle(RoostInk.secondary)
                }
            }
        }
    }

    @ViewBuilder private func actions(_ session: AgentSession) -> some View {
        // Amber means "needs you": only then is the action amber.
        if session.state.needsYou {
            Button("Answer in \(host(session))") { AgentActions.show(session) }.buttonStyle(RoostPillStyle()).fixedSize()
        } else {
            Button("Show") { AgentActions.show(session) }.buttonStyle(RoostQuietButtonStyle()).fixedSize()
        }
        if let editor = AgentActions.editor {
            Button("Open in \(editor.name)") { AgentActions.openInEditor(session) }
                .buttonStyle(RoostQuietButtonStyle()).fixedSize()
        }
    }

    private func tone(_ session: AgentSession) -> Color {
        if session.state.needsYou { return RoostInk.amber }
        if session.state == .stuck { return RoostInk.coral }
        if session.state == .done || session.state == .shipped { return RoostInk.green }
        return RoostInk.secondary
    }

    private func host(_ session: AgentSession) -> String {
        (session.host ?? "Terminal").replacingOccurrences(of: "the ", with: "")
    }

    private func fact(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(RoostInk.secondary)
            Text(value).foregroundStyle(RoostInk.primary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                .help(value)
        }
    }

    // MARK: Nobody picked: the tree in a few lines

    private var summary: some View {
        let needing = sessions.filter(\.state.needsYou).count
        let working = sessions.filter(\.state.isWorking).count
        let stuck = sessions.filter { $0.state == .stuck }.count
        let napping = sessions.filter { $0.state == .napping || $0.state == .resting }.count
        let done = sessions.filter { $0.state == .done || $0.state == .shipped }.count + cameHome
        let worked = max(day?.working ?? 0, log.total(.working))
        return VStack(alignment: .leading, spacing: 12) {
            Text(needing > 0 ? "\(needing) need\(needing == 1 ? "s" : "") you" : working > 0 ? "\(working) at work" : "All quiet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(needing > 0 ? RoostInk.amber : RoostInk.primary)
            VStack(alignment: .leading, spacing: 6) {
                if working > 0 && needing > 0 { line("\(working) working", RoostInk.lavender) }
                if stuck > 0 { line("\(stuck) stuck", RoostInk.coral) }
                if napping > 0 { line("\(napping) napping", RoostInk.quiet) }
                if done > 0 { line("\(done) done today", RoostInk.green) }
            }
            if worked >= 60 {
                Text("\(RoostNumbers.duration(worked, long: true)) of owl work today").font(.callout).foregroundStyle(RoostInk.secondary)
            }
            Text("Click an owlet to see it here; double-click to go to it.")
                .font(.caption).foregroundStyle(RoostInk.quiet).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func line(_ text: String, _ colour: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(text).font(.callout).foregroundStyle(RoostInk.primary)
        }
    }
}

/// A quiet capsule beside the amber one.
struct RoostQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RoostInk.primary)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.09), in: .capsule)
            .contentShape(.capsule)
    }
}

// MARK: The flight log

/// Today at a glance: one line per repository showing when its agents
/// worked (lavender), waited for you (amber stripes) or paused for a plan
/// limit (dashes), with hour marks below and each one's total on the right.
struct FlightLogView: View {
    let log: FlightLog

    var body: some View {
        let repositories = Array(log.repositories.prefix(5))
        if let first = log.firstActivity, !repositories.isEmpty {
            let start = Self.axisStart(first)
            VStack(alignment: .leading, spacing: 8) {
                header
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(repositories, id: \.self) { repository in
                        HStack(spacing: 10) {
                            Text(repository).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: Self.labelWidth, alignment: .leading)
                            Lane(segments: log.segments.filter { $0.repository == repository }, start: start)
                                .frame(height: 10)
                            Text(total(repository)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: Self.totalWidth, alignment: .trailing)
                        }
                    }
                    HourMarks(start: start)
                        .frame(height: 12)
                        .padding(.leading, Self.labelWidth + 10)
                        .padding(.trailing, Self.totalWidth + 10)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.background.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(log.summary ?? "Today's agent work")
        }
    }

    static let labelWidth: CGFloat = 96
    static let totalWidth: CGFloat = 56

    /// "Today · 1 h 10 min of agent work · up to 3 at once", and what the marks mean.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Today").font(.callout.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Key(title: "Working") { Capsule().fill(Brand.lavender).frame(width: 14, height: 6) }
            Key(title: "Waiting for you") { Stripes().frame(width: 14, height: 6) }
            Key(title: "Paused") { Dashes().frame(width: 14, height: 6) }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        let work = log.total(.working)
        parts.append(work >= 60 ? "\(ClaudeSource.duration(work)) of agent work" : "Under a minute of agent work")
        if log.peak > 1 { parts.append("up to \(log.peak) at once") }
        let waiting = log.total(.waiting)
        if waiting >= 60 { parts.append("\(ClaudeSource.duration(waiting)) waiting for you") }
        if !Calendar.current.isDate(log.watchingSince, equalTo: Calendar.current.startOfDay(for: Date()), toGranularity: .minute) {
            parts.append("since \(log.watchingSince.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private func total(_ repository: String) -> String {
        let work = log.total(.working, in: repository)
        return work < 60 ? "<1 min" : ClaudeSource.duration(work)
    }

    /// The hour before the first activity, so the marks fall on whole hours.
    static func axisStart(_ first: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: first)?.start ?? first
    }

    private struct Key<Swatch: View>: View {
        let title: String
        @ViewBuilder let swatch: Swatch

        var body: some View {
            HStack(spacing: 5) {
                swatch
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }

    private struct Stripes: View {
        var body: some View {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.clip(to: Path(roundedRect: rect, cornerRadius: size.height / 2))
                context.fill(Path(rect), with: .color(Brand.amber.opacity(0.35)))
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(Brand.amber))
                    x += 5
                }
            }
        }
    }

    private struct Dashes: View {
        var body: some View {
            Canvas { context, size in
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: size.height / 2 - 1, width: 4, height: 2)), with: .color(.secondary))
                    x += 7
                }
            }
        }
    }

    /// Hour marks under the lanes: "21:00", "22:00"… thinned out to fit.
    private struct HourMarks: View {
        let start: Date

        var body: some View {
            Canvas { context, size in
                let span = max(3600, Date().timeIntervalSince(start))
                let hours = Int(span / 3600)
                let every = max(1, Int((Double(hours) / Double(max(1, Int(size.width / 56)))).rounded(.up)))
                for hour in stride(from: 0, through: hours, by: every) {
                    let date = start.addingTimeInterval(TimeInterval(hour) * 3600)
                    let x = size.width * date.timeIntervalSince(start) / span
                    let label = Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                    context.draw(label, at: CGPoint(x: min(max(x, 14), size.width - 14), y: size.height / 2))
                }
            }
        }
    }

    private struct Lane: View {
        let segments: [FlightLog.Segment]
        let start: Date

        var body: some View {
            Canvas { context, size in
                let span = max(3600, Date().timeIntervalSince(start))
                context.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)),
                             with: .color(.primary.opacity(0.12)))
                for segment in segments {
                    let x = size.width * segment.start.timeIntervalSince(start) / span
                    let width = max(3, size.width * segment.end.timeIntervalSince(segment.start) / span)
                    let rect = CGRect(x: x, y: 1, width: width, height: size.height - 2)
                    switch segment.kind {
                    case .working:
                        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(Brand.lavender))
                    case .waiting:
                        var striped = context
                        striped.clip(to: Path(roundedRect: rect, cornerRadius: rect.height / 2))
                        striped.fill(Path(rect), with: .color(Brand.amber.opacity(0.35)))
                        var stripe = rect.minX
                        while stripe < rect.maxX {
                            striped.fill(Path(CGRect(x: stripe, y: rect.minY, width: 2, height: rect.height)),
                                         with: .color(Brand.amber))
                            stripe += 5
                        }
                    case .paused:
                        var dash = rect.minX
                        while dash < rect.maxX {
                            context.fill(Path(CGRect(x: dash, y: rect.midY - 1, width: 4, height: 2)), with: .color(.secondary))
                            dash += 7
                        }
                    }
                }
            }
        }
    }
}

/// The agents a session asked to help: how many are working and back, and
/// a row for each, working ones first.
private struct AskedAgents: View {
    let working: [AgentSession]
    let back: [AgentSession]

    var body: some View {
        let total = working.count + back.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(total == 1 ? "1 helper" : "\(total) helpers").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RoostInk.primary)
                Spacer()
                let busy = working.filter { $0.state.isWorking || $0.state.needsYou }.count
                if busy > 0 { pill("\(busy) working", RoostInk.lavender) }
                if working.count > busy { pill("\(working.count - busy) idle", RoostInk.secondary) }
                if !back.isEmpty { pill("\(back.count) back", RoostInk.green) }
            }
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(RoostInk.green)
                            .frame(width: max(back.isEmpty ? 0 : 4, proxy.size.width * Double(back.count) / Double(max(total, 1))))
                    }
            }
            .frame(height: 4)
            .accessibilityLabel("\(back.count) of \(total) back")
            ForEach(working.sorted(by: AgentWatcher.order)) { helper in row(helper, back: false) }
            ForEach(back.sorted { $0.stateSince > $1.stateSince }) { helper in row(helper, back: true) }
        }
    }

    private func pill(_ text: String, _ colour: Color) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(colour)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(colour.opacity(0.16), in: .capsule)
    }

    private func row(_ helper: AgentSession, back: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            OwletIcon(icon: back ? "done" : helper.state.icon, palette: helper.agent.palette, scale: 1, animated: false)
                .opacity(back ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(helper.model ?? helper.agent.name).font(.callout.weight(.medium)).foregroundStyle(RoostInk.primary)
                    .lineLimit(1)
                Text(back ? "\(helper.agent.name) · back" : "\(helper.agent.name) · \(helper.detail ?? helper.state.label)")
                    .font(.caption).foregroundStyle(helper.state.needsYou && !back ? RoostInk.amber : RoostInk.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(RoostNumbers.duration((back ? helper.stateSince : Date()).timeIntervalSince(helper.started)))
                .font(.caption.monospacedDigit()).foregroundStyle(RoostInk.secondary)
        }
        .opacity(back ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }
}

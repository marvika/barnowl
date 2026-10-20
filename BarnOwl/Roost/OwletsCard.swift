import SwiftUI

/// The quick panel's agents, the Pocket Roost: every owlet on one branch in
/// a small night scene, the one that most needs you, one line for the rest,
/// and the plan as moons.
struct OwletsCard: View {
    let model: AppModel
    let close: () -> Void

    private var agents: AgentWatcher { model.agents }

    var body: some View {
        PocketRoost(sessions: agents.visible, hiddenCount: agents.hiddenCount, limits: agents.limits,
                    cameHome: agents.cameHome, recap: recapWeek, revealHidden: agents.choices.revealHidden,
                    model: model, close: close,
                    toggleHidden: { agents.choices.revealHidden.toggle() },
                    openRoost: {
                        close()
                        model.showRoost(nil)
                    },
                    openRecap: { week in
                        close()
                        model.showRecap(week)
                    })
            .environment(\.owletsMove, Preferences.owlMoves && !ProcessInfo.processInfo.isLowPowerModeEnabled)
            .onDisappear { agents.choices.revealHidden = false }
    }

    /// From Friday afternoon to Sunday, a week worth looking back on.
    private var recapWeek: WeekSummary? {
        guard RecapWindowController.isRecapTime(.now) else { return nil }
        let week = DemoMode.isOn ? WeekSummary.demo(now: .now) : DailyLog.shared.week(endingOn: .now)
        return week.isWorthARecap ? week : nil
    }
}

/// The card itself, from plain values, so it can be drawn without the app around it.
struct PocketRoost: View {
    let sessions: [AgentSession]
    var hiddenCount = 0
    let limits: [PlanLimit]
    var cameHome: [AgentSession] = []
    var recap: WeekSummary?
    var revealHidden = false
    var model: AppModel?
    var close: () -> Void = {}
    var toggleHidden: () -> Void = {}
    var openRoost: () -> Void = {}
    var openRecap: (WeekSummary) -> Void = { _ in }
    /// The owlet under the pointer: the card and line below the strip describe it.
    var hoveredForPreview: String?
    @State private var hovered: String?

    var body: some View {
        if !sessions.isEmpty || hiddenCount > 0 || !limits.isEmpty || recap != nil {
            VStack(alignment: .leading, spacing: 12) {
                if !sessions.isEmpty || hiddenCount > 0 { header }
                if !sessions.isEmpty {
                    PocketStrip(sessions: sessions, model: model, close: close, openRoost: openRoost, hovered: $hovered)
                    news
                }
                if !limits.isEmpty { PlanMoons(limits: limits) }
                if let recap { RecapEntryRow(week: recap) { openRecap(recap) } }
                if hiddenCount > 0 || revealHidden {
                    Button(revealHidden ? "Hide Them Again" : "Hidden (\(hiddenCount))", action: toggleHidden)
                        .buttonStyle(.plain).font(.caption).foregroundStyle(Brand.lavender)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Owlets").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Button(action: openRoost) {
                Text("Roost ") + Text(Image(systemName: "chevron.right")).font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12.5, weight: .semibold))
            .buttonStyle(.plain).foregroundStyle(Brand.lavender)
            .help("Open the Roost: every agent on one tree, and today's flight log")
        }
        .padding(.horizontal, 2)
    }

    // MARK: What's new: one card and one line, or the owlet under the pointer

    private var attention: AgentSession? {
        sessions.first { $0.state.rank <= 2 && $0.state != .shipped }
    }

    private var news: some View {
        let lead = attention
        let line = summary(excluding: lead?.id)
        let pointed = (hoveredForPreview ?? hovered).flatMap(describe)
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 13) {
                if let lead { AttentionCard(session: lead, model: model, close: close) }
                if let line {
                    Text(line).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
            }
            .opacity(pointed == nil ? 1 : 0)
            if let pointed { pointed }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    /// "3 busy (12 helpers) · 1 stuck · docs shipped 2 min ago", leaving out the one in the card.
    private func summary(excluding lead: String?) -> String? {
        let others = sessions.filter { $0.id != lead }
        var parts: [String] = []
        let needing = others.filter(\.state.needsYou).count
        if needing > 0 { parts.append(lead == nil ? "\(needing) \(needing == 1 ? "needs" : "need") you" : "\(needing) more \(needing == 1 ? "needs" : "need") you") }
        let busy = others.filter(\.state.isWorking)
        if !busy.isEmpty {
            let helpers = busy.reduce(0) { $0 + $1.helpers.filter(\.isWorking).count }
            parts.append(helpers > 0 ? "\(busy.count) busy (\(helpers) \(helpers == 1 ? "helper" : "helpers"))" : "\(busy.count) busy")
        }
        let stuck = others.filter { $0.state == .stuck }.count
        if stuck > 0 { parts.append("\(stuck) stuck") }
        let done = others.filter { $0.state == .done }.count
        if done > 0 { parts.append("\(done) done") }
        if parts.isEmpty {
            let resting = others.filter { $0.state == .resting || $0.state == .napping }.count
            if resting > 0 { parts.append("\(resting) napping") }
        }
        if let home = lastHome { parts.append(home) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The last owlet to ship or fly home today: "docs shipped 2 min ago".
    private var lastHome: String? {
        let now = Date()
        let candidates = sessions.filter { $0.state == .shipped } + cameHome
        guard let last = candidates.filter({ Calendar.current.isDate($0.stateSince, inSameDayAs: now) })
            .max(by: { $0.stateSince < $1.stateSince }) else { return nil }
        let ago = now.timeIntervalSince(last.stateSince)
        let when = ago < 60 ? "just now" : "\(ClaudeSource.duration(ago)) ago"
        return "\(last.place.repository) \(last.state == .shipped ? "shipped" : "finished") \(when)"
    }

    /// What the pointer is on, in the card's place.
    private func describe(_ id: String) -> AnyView? {
        if id == PocketStrip.nappersID {
            let nappers = sessions.filter { $0.state == .napping || $0.state == .resting }
            guard !nappers.isEmpty else { return nil }
            return AnyView(PointedCard(title: "\(nappers.count) napping",
                                       lines: [nappers.map(\.placeName).joined(separator: ", ")]))
        }
        guard let session = sessions.first(where: { $0.id == id }) else { return nil }
        var facts = [session.placeName, session.agent.name, session.detail ?? session.state.label]
        if session.state.isWorking { facts.append(ClaudeSource.duration(Date().timeIntervalSince(session.started))) }
        var lines = [facts.joined(separator: " · ")]
        let helpers = session.helpers.filter(\.isWorking)
        if !helpers.isEmpty {
            let names = helpers.map { $0.task.isEmpty ? $0.type : $0.task }
            lines.append("\(helpers.count) \(helpers.count == 1 ? "helper" : "helpers"): " + names.joined(separator: " · "))
        }
        return AnyView(PointedCard(title: session.name, lines: lines))
    }
}

/// The owlet under the pointer, said in two or three quiet lines.
private struct PointedCard: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}

// MARK: - The strip

/// One row of owlets on a branch, in a small night scene: the fastest way
/// to read several states at once. Owlets that have napped a while curl up
/// together at the end; a "+N" says how many more there are.
struct PocketStrip: View {
    let sessions: [AgentSession]
    var model: AppModel?
    var close: () -> Void = {}
    var openRoost: () -> Void = {}
    @Binding var hovered: String?
    @Environment(\.displayScale) private var displayScale

    static let size = CGSize(width: 312, height: 96)
    static let nappersID = "nappers"

    /// Points per scene cell and sprite pixel: three device pixels on a
    /// Retina display, as in the design; one point where pixels are bigger.
    private var unit: CGFloat { displayScale >= 2 ? 1.5 : 1 }

    enum Slot {
        case owlet(AgentSession, helpers: Int)
        case nappers(count: Int, palette: String)
        case more(Int)
    }

    /// Owlets in the order given, as many as fit, each at its centre, in cells.
    static func layout(_ sessions: [AgentSession], width: Int) -> [(slot: Slot, x: Int)] {
        let nappers = sessions.filter { $0.state == .napping || $0.state == .resting }
        let grouped = nappers.count >= 2
        let awake = grouped ? sessions.filter { $0.state != .napping && $0.state != .resting } : sessions
        let margin = 5.0, inner = Double(width) - margin * 2
        let room = max(2, Int(inner / 33) - (grouped ? 1 : 0))
        var slots: [Slot] = []
        let fits = awake.count <= room
        for session in awake.prefix(fits ? room : room - 1) {
            slots.append(.owlet(session, helpers: session.helpers.filter(\.isWorking).count))
        }
        if !fits { slots.append(.more(awake.count - (room - 1))) }
        if grouped { slots.append(.nappers(count: nappers.count, palette: nappers[0].agent.palette)) }
        let step = inner / Double(max(slots.count, 1))
        return slots.enumerated().map { index, slot in (slot, Int((margin + step * (Double(index) + 0.5)).rounded())) }
    }

    var body: some View {
        let unit = self.unit
        let cols = Int(Self.size.width / unit), rows = Int(Self.size.height / unit)
        let slots = Self.layout(sessions, width: cols)
        let image = PocketScene.strip(width: cols, height: rows, marks: marks(slots))
        ZStack(alignment: .topLeading) {
            PocketImage(image: image, pixelsPerPoint: 1 / unit)
            if let lantern = slots.first(where: { if case .owlet(let session, _) = $0.slot { session.state.needsYou } else { false } }) {
                let glass = PocketScene.lanternGlass(x: lantern.x, height: rows)
                LanternGlow(radius: 50)
                    .offset(x: CGFloat(glass.x) * unit + unit / 2 - 50, y: CGFloat(glass.y - 3) * unit - 50)
            }
            ForEach(Array(slots.enumerated()), id: \.offset) { index, item in
                let top = CGFloat(PocketScene.branchTop(x: item.x, height: rows) - PocketScene.owletHeight) * unit
                let left = CGFloat(item.x - OwletArt.width / 2) * unit
                switch item.slot {
                case .owlet(let session, let helpers):
                    PerchedOwlet(session: session, helpers: helpers, unit: unit, animated: index < 4, model: model,
                                 close: close, hovered: $hovered)
                        .offset(x: left, y: top)
                case .nappers(let count, let palette):
                    Nappers(count: count, palette: palette, unit: unit, hovered: $hovered, open: openRoost)
                        .offset(x: left, y: top)
                case .more(let count):
                    Button(action: openRoost) {
                        Text("+\(count)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: CGFloat(OwletArt.width) * unit, height: 22).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("\(count) more in the Roost")
                    .offset(x: left, y: top + CGFloat(OwletArt.height) * unit - 26)
                }
            }
        }
        .frame(width: Self.size.width, height: CGFloat(rows) * unit, alignment: .topLeading)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.06)))
    }

    private func marks(_ slots: [(slot: Slot, x: Int)]) -> [PocketScene.Mark] {
        var marks: [PocketScene.Mark] = []
        var lit = false
        for item in slots {
            switch item.slot {
            case .owlet(let session, let helpers):
                if session.state.needsYou && !lit {
                    marks.append(.lantern(x: item.x))
                    lit = true
                }
                if session.state == .stuck { marks.append(.rain(x: item.x)) }
                if helpers > 0 { marks.append(.fireflies(x: item.x)) }
                if session.state == .napping { marks.append(.sleep(x: item.x)) }
            case .nappers:
                marks.append(.sleep(x: item.x))
            case .more:
                break
            }
        }
        return marks
    }
}

/// Owlets napping a while, curled up together at the end of the branch.
private struct Nappers: View {
    let count: Int
    let palette: String
    let unit: CGFloat
    @Binding var hovered: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            OwletSprite(sprite: "nap", palette: palette, scale: unit, animated: false)
                .overlay(alignment: .topLeading) {
                    Text("\(count)").font(.system(size: 9.5, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(height: 14)
                        .background(Color(red: 0.36, green: 0.33, blue: 0.6), in: .capsule)
                        .fixedSize()
                        .offset(x: 1 * unit, y: 6 * unit)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? PocketStrip.nappersID : (hovered == PocketStrip.nappersID ? nil : hovered) }
        .accessibilityLabel("\(count) agents napping")
        .accessibilityHint("Opens the Roost")
    }
}

/// One session on the branch; its helpers at work are a brood count at its shoulder.
private struct PerchedOwlet: View {
    let session: AgentSession
    let helpers: Int
    let unit: CGFloat
    let animated: Bool
    let model: AppModel?
    let close: () -> Void
    @Binding var hovered: String?
    @State private var hovering = false

    var body: some View {
        Button {
            close()
            AgentActions.show(session)
        } label: {
            OwletSprite(sprite: session.state.sprite, palette: session.agent.palette, scale: unit,
                        seed: session.id.hashValue, animated: animated)
                .overlay(alignment: .topTrailing) {
                    if helpers > 0 { BroodBadge(count: helpers).fixedSize().offset(x: 5 * unit, y: 0) }
                }
                .offset(y: hovering ? -1 : 0)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { hovered = session.id } else if hovered == session.id { hovered = nil }
        }
        .animation(.snappy(duration: 0.15), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.placeName), \(session.name), \(session.agent.name), \(session.state.label)"
            + (helpers > 0 ? ", \(helpers) helpers at work" : ""))
        .contextMenu { if let model { AgentMenu(session: session, model: model, close: close) } }
    }
}

// MARK: - The one that most needs you

/// "Perch tint is asking · 0:42", what it asks, and a way to answer.
private struct AttentionCard: View {
    let session: AgentSession
    let model: AppModel?
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var urgent: Bool { session.state.needsYou || session.state == .stuck }
    private var ink: Color { scheme == .dark ? Brand.amber : Color(hex: 0xB0650A) }

    private var verb: String {
        switch session.state {
        case .asking: "is asking"
        case .needsYou: "needs you"
        case .stuck: "is stuck"
        default: "is done"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                headline
                detail
            }
            Spacer(minLength: 4)
            Button {
                close()
                AgentActions.show(session)
            } label: {
                Text(session.state.needsYou ? "Answer" : "Show")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(urgent ? Color(hex: 0x2A1604) : .primary)
                    .padding(.horizontal, 13).frame(height: 26)
                    .background(urgent ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(Color.primary.opacity(0.1)),
                                in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help("Go to \(session.placeName)")
        }
        .padding(.leading, 13).padding(.trailing, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(urgent ? Brand.amber.opacity(0.12) : Color.primary.opacity(0.05), in: .rect(cornerRadius: 13))
        .contextMenu { if let model { AgentMenu(session: session, model: model, close: close) } }
        .accessibilityElement(children: .combine)
    }

    private var headline: some View {
        // Ticks by the second only while someone waits; otherwise by the minute.
        TimelineView(session.state.needsYou ? .periodic(from: .now, by: 1) : .periodic(from: .now, by: 60)) { context in
            let since = session.request?.since ?? session.stateSince
            // A question that times out says how long is left, as everywhere else.
            let clock: String = if let deadline = session.request?.deadline, deadline > context.date {
                "\(RoostNumbers.clock(deadline.timeIntervalSince(context.date))) left"
            } else if session.state.needsYou {
                RoostNumbers.clock(context.date.timeIntervalSince(since))
            } else {
                ClaudeSource.duration(context.date.timeIntervalSince(since))
            }
            // A long name shortens; what's happening and the clock never do.
            HStack(spacing: 4) {
                Text(session.name).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
                Text("\(verb) · \(clock)").foregroundStyle(urgent ? ink : .secondary).lineLimit(1).fixedSize()
            }
            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let request = session.request {
            Text(request.text)
                .font(request.kind == .command ? .system(size: 11, design: .monospaced) : .system(size: 11.5))
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                .help(request.text)
        } else {
            Text(session.detail ?? session.state.label).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// What a right-click on an owlet offers.
struct AgentMenu: View {
    let session: AgentSession
    let model: AppModel
    let close: () -> Void

    private var choices: AgentChoices { model.agents.choices }

    var body: some View {
        Button("Show") {
            close()
            AgentActions.show(session)
        }
        if let editor = AgentActions.editor {
            Button("Open in \(editor.name)") {
                close()
                AgentActions.openInEditor(session)
            }
        }
        Button("Open in Terminal") {
            close()
            AgentActions.openInTerminal(session)
        }
        Button("Reveal in Finder") {
            close()
            AgentActions.revealInFinder(session)
        }
        Divider()
        Menu("Hide") {
            Button("Until It Needs Me") { choices.hide(session, for: .untilNeeded) }
            Button("For Today") { choices.hide(session, for: .today) }
            Button("Always for “\(session.place.repository)”") { choices.hideFolder(of: session) }
        }
        Toggle("Mute “\(session.place.repository)”", isOn: Binding(
            get: { choices.isMuted(session) },
            set: { choices.setMuted($0, folder: session.place.root.path) }))
        Toggle("Keep the Mac Awake While It Works", isOn: Binding(
            get: { choices.countsForKeepAwake(session) },
            set: {
                choices.setCountsForKeepAwake($0, session)
                model.keepAwake.evaluate()
            }))
    }
}

// MARK: - The plan

/// The plan as moon tiles, two to a row: a moon that waxes as the window is
/// used, its name, and when it resets. An old reading is faded and dashed,
/// and says when it's from instead.
struct PlanMoons: View {
    let limits: [PlanLimit]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(limits.prefix(4)) { limit in MoonTile(limit: limit) }
        }
    }
}

private struct MoonTile: View {
    let limit: PlanLimit
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let stale = limit.isStale()
        let percent = "\(Int(limit.used.rounded()))%"
        HStack(spacing: 8) {
            PocketMoon(fraction: limit.used / 100, stale: stale, lit: moonColour(stale: stale),
                       dark: .primary.opacity(scheme == .dark ? 0.12 : 0.1))
                .frame(width: stale ? 30 : 26, height: stale ? 30 : 26)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Group {
                    if stale {
                        Text("\(percent) · as of \(PlanLimit.when(limit.updated))").italic()
                    } else if let reset = limit.resetsAt {
                        Text("\(Text(percent).foregroundStyle(limit.isHigh ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.secondary))) · resets \(PlanLimit.when(reset))")
                    } else {
                        Text("\(percent) used")
                    }
                }
                .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 13)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 13))
        .help(help(stale: stale))
        .accessibilityElement(children: .combine)
    }

    private func moonColour(stale: Bool) -> Color {
        if stale { return scheme == .dark ? Color(hex: 0xB9B5CF) : Color(hex: 0x8E8AA6) }
        if limit.isHigh { return Brand.amber }
        return scheme == .dark ? Color(hex: 0xF7EBD4) : Color(hex: 0xC9A66B)
    }

    private var title: String {
        "\(limit.owner) · " + (limit.window == .session ? "5 hours" : "week")
    }

    private func help(stale: Bool) -> String {
        var parts = ["\(limit.owner) plan, \(limit.window.title.lowercased()) limit: \(Int(limit.used.rounded()))% used"]
        if stale { parts.append("as of \(PlanLimit.when(limit.updated))") }
        if let reset = limit.resetsAt { parts.append("resets \(PlanLimit.moment(reset))") }
        if let full = limit.fullAt, !stale { parts.append("at this pace it runs out \(PlanLimit.moment(full))") }
        return parts.joined(separator: ", ")
    }
}

import SwiftUI

/// The Roost's own colours: a calm night indigo, the same in light and dark,
/// so the owlets and the amber of "needs you" are the brightest things in it.
enum RoostInk {
    static let top = Color(hex: 0x1B1A36)
    static let bottom = Color(hex: 0x121124)
    static let card = Color.white.opacity(0.04)
    static let cardEdge = Color.white.opacity(0.07)
    static let primary = Color(hex: 0xF6F4FF)
    static let secondary = Color(hex: 0xA9A6C6)
    static let quiet = Color(hex: 0x8F8BB3)
    static let amber = Color(hex: 0xF5A633)
    static let amberInk = Color(hex: 0x2A1604)
    static let command = Color(hex: 0xFFD79A)
    static let lavender = Color(hex: 0x8C87FF)
    static let lilac = Color(hex: 0xB5B1FF)
    static let link = Color(hex: 0xA6A1FF)
    static let green = Color(hex: 0x7CE0A0)
    static let coral = Color(hex: 0xFF9A8A)
    static let moon = Color(hex: 0xF6EAD6)
    static let moonDark = Color(hex: 0x3A3858)

    static var background: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The Roost's workbench: what's waiting on you first, as cards holding the
/// actual question; then who's working, each on its own twig; what got done;
/// and on the right, how today went and how fresh each plan number is.
struct RoostNowView: View {
    let model: AppModel?
    let sessions: [AgentSession]
    let cameHome: [AgentSession]
    let limits: [PlanLimit]
    let log: FlightLog
    /// Today so far, kept across restarts.
    var day: DaySummary?
    @Binding var selected: String?
    var scrolls = true
    @State private var showsAllWorking = false
    @State private var showsResting = false
    @State private var showsDone = false
    @State private var showsFlightLog = false

    private var waiting: [AgentSession] { sessions.filter(\.state.needsYou) }
    private var done: [AgentSession] { sessions.filter { $0.state == .done || $0.state == .shipped } }
    /// At it, busiest first: working, then stuck, on a break or offline.
    /// Helpers shown on their caller's working row rather than their own: only while the
    /// caller has such a row, and isn't itself a helper (a helper's helpers keep their rows).
    private var withCaller: Set<String> {
        let rows = Set(sessions.filter { !$0.isHelper && !$0.state.needsYou && !Self.done($0) && !Self.resting($0) }.map(\.id))
        return Set(sessions.filter { $0.calledBy.map(rows.contains) ?? false }.map(\.id))
    }

    private var working: [AgentSession] {
        let hidden = withCaller
        let busy = sessions.filter { !$0.state.needsYou && !Self.done($0) && !Self.resting($0) && !hidden.contains($0.id) }
        return busy.filter(\.state.isWorking) + busy.filter { !$0.state.isWorking }
    }
    private var resting: [AgentSession] { sessions.filter { Self.resting($0) && !withCaller.contains($0.id) } }
    private static func done(_ session: AgentSession) -> Bool { session.state == .done || session.state == .shipped }
    private static func resting(_ session: AgentSession) -> Bool { session.state == .resting || session.state == .napping }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            column { main }
                .frame(minWidth: 440, maxWidth: .infinity)
            column {
                TodayCard(limits: limits, log: log, day: day) { showsFlightLog = true }
                    .padding(.vertical, 16)
            }
            .frame(width: 330)
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showsFlightLog) {
            VStack(alignment: .trailing, spacing: 0) {
                FlightLogView(log: log)
                Button("Done") { showsFlightLog = false }.keyboardShortcut(.defaultAction).padding(12)
            }
            .frame(width: 640)
        }
    }

    @ViewBuilder private func column(@ViewBuilder _ content: () -> some View) -> some View {
        if scrolls {
            ScrollView { content() }.scrollIndicators(.never)
        } else {
            content()
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 26) {
            if sessions.isEmpty && cameHome.isEmpty {
                VStack(spacing: 10) {
                    OwletSprite(sprite: "nap", scale: 3, animated: false)
                    Text("No owlets out").font(.title3.weight(.semibold)).foregroundStyle(RoostInk.primary)
                    Text("Start Claude Code, Codex or another agent in any folder, and it shows up here.")
                        .font(.callout).foregroundStyle(RoostInk.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            }
            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Needs you")
                    ForEach(Array(waiting.enumerated()), id: \.element.id) { index, session in
                        Group {
                            if index == 0 { AskingCard(session: session, model: model) }
                            else { WaitingCard(session: session, model: model) }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18).strokeBorder(RoostInk.lilac, lineWidth: 1.5)
                                .opacity(selected == session.id ? 1 : 0)
                        }
                        .onTapGesture { selected = session.id }
                        .accessibilityAddTraits(selected == session.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selected = session.id }
                    }
                }
            }
            if !working.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Working", detail: workingSummary)
                    let shown = showsAllWorking ? working : Array(working.prefix(4))
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, session in
                            let roomy = session.helpers.count > 1
                            let previousRoomy = index > 0 && shown[index - 1].helpers.count > 1
                            if index > 0 && !roomy && !previousRoomy {
                                Rectangle().fill(RoostInk.cardEdge).frame(height: 1).padding(.leading, 88)
                            }
                            WorkingRow(session: session, selected: selected == session.id, model: model,
                                       twin: twins.contains(session.name),
                                       asked: sessions.filter { $0.calledBy == session.id },
                                       back: HelperBatch.back(of: session.id, live: sessions, returned: cameHome,
                                                              now: Date()).count)
                                .onTapGesture { selected = session.id }
                        .accessibilityAddTraits(selected == session.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selected = session.id }
                        }
                    }
                    if working.count > 4 {
                        Button {
                            withAnimation(.snappy) { showsAllWorking.toggle() }
                        } label: {
                            Text(showsAllWorking ? "Show fewer" : "\(working.count - 4) more working")
                                + Text(" \(Image(systemName: showsAllWorking ? "chevron.up" : "chevron.right"))").font(.caption)
                        }
                        .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(RoostInk.link)
                        .padding(.leading, 88)
                    }
                }
            }
            if done.contains(where: { !$0.isHelper }) || cameHome.contains(where: { !$0.isHelper }) {
                // Helpers went back to their caller, not home: they're counted on its row.
                DoneCard(done: done.filter { !$0.isHelper }, cameHome: cameHome.filter { !$0.isHelper },
                         expanded: $showsDone, model: model)
            }
            if !resting.isEmpty {
                RestingCard(sessions: resting, twins: twins, expanded: $showsResting, selected: $selected, model: model)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Names that more than one owlet has.
    private var twins: Set<String> {
        Set(Dictionary(grouping: sessions, by: \.name).filter { $0.value.count > 1 }.keys)
    }

    /// "8 owlets · 23 helpers"
    private var workingSummary: String {
        let helpers = working.reduce(0) { $0 + $1.helpers.count }
        let owlets = working.count == 1 ? "1 owlet" : "\(working.count) owlets"
        return helpers == 0 ? owlets : "\(owlets) · \(helpers) helper\(helpers == 1 ? "" : "s")"
    }
}

private struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(RoostInk.primary)
            if let detail { Text(detail).font(.callout).foregroundStyle(RoostInk.secondary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The amber pill: the one thing to do.
struct RoostPillStyle: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: .semibold))
            .foregroundStyle(RoostInk.amberInk)
            .padding(.horizontal, large ? 14 : 13).padding(.vertical, large ? 8 : 6)
            .background(RoostInk.amber.opacity(configuration.isPressed ? 0.8 : 1), in: .capsule)
            .contentShape(.capsule)
    }
}

// MARK: Needs you

/// The first request waiting on you: the question itself, its options and
/// its countdown, and one action that takes you there.
private struct AskingCard: View {
    let session: AgentSession
    let model: AppModel?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(RoostInk.amber.opacity(0.08))
                    if let deadline = session.request?.deadline {
                        CountdownRing(since: session.request?.since ?? session.stateSince, deadline: deadline, width: 3)
                    } else {
                        Circle().strokeBorder(RoostInk.amber.opacity(0.55), lineWidth: 3)
                    }
                    OwletSprite(sprite: session.state.sprite, palette: session.agent.palette, scale: 1.5, seed: session.id.hashValue)
                        .frame(width: 48, height: 45)
                }
                .frame(width: 74, height: 74)
                WaitClock(request: session.request, since: session.stateSince)
            }
            .frame(width: 88)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(RoostInk.primary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(meta).font(.callout).foregroundStyle(RoostInk.secondary).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        AgentActions.show(session)
                    } label: {
                        Text("\(host.count <= 12 ? "Answer in \(host)" : "Answer") \(Image(systemName: "return"))")
                    }
                    .buttonStyle(RoostPillStyle(large: true))
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                    .help("Go to \(host) to answer")
                }
                RequestText(session: session)
            }
        }
        .padding(16)
        .background(RoostInk.amber.opacity(0.09), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(RoostInk.amber.opacity(0.38), lineWidth: 1) }
        .contentShape(.rect)
        .contextMenu { if let model { AgentMenu(session: session, model: model, close: {}) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.name), \(session.state.label)")
    }

    private var host: String { (session.host ?? "Terminal").replacingOccurrences(of: "the ", with: "") }

    private var meta: String {
        var parts = [session.callerName.map { "for \($0)" } ?? session.placeName]
        parts.append("asked \(IslandView.ago(session.request?.since ?? session.stateSince))")
        return parts.joined(separator: " · ")
    }
}

/// The question with its numbered options, or the command, as the agent put it.
private struct RequestText: View {
    let session: AgentSession

    var body: some View {
        if let request = session.request {
            switch request.kind {
            case .question:
                VStack(alignment: .leading, spacing: 10) {
                    Text("“\(request.text)”").font(.system(size: 15)).foregroundStyle(RoostInk.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !request.options.isEmpty {
                        FlowRow(spacing: 22) {
                            ForEach(Array(request.options.enumerated()), id: \.offset) { index, option in
                                HStack(spacing: 8) {
                                    Text("\(index + 1)").font(.caption.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(RoostInk.primary)
                                        .frame(width: 20, height: 20)
                                        .background(.white.opacity(0.07), in: .rect(cornerRadius: 6))
                                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.14)) }
                                    Text(option).font(.system(size: 14)).foregroundStyle(Color(hex: 0xDCD9EE)).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            case .command:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wants to run").font(.caption).foregroundStyle(RoostInk.secondary)
                    Text(request.text).font(.system(size: 13, design: .monospaced)).foregroundStyle(RoostInk.command)
                        .lineLimit(4).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.25), in: .rect(cornerRadius: 10))
                }
            case .edit: Label("Wants to edit \(request.text)", systemImage: "pencil").foregroundStyle(RoostInk.primary)
            case .web: Label("Wants to fetch \(request.text)", systemImage: "globe").foregroundStyle(RoostInk.primary)
            case .plan, .other: Text(request.text).foregroundStyle(RoostInk.primary)
            }
        } else {
            Text(session.detail ?? session.state.label).font(.system(size: 15)).foregroundStyle(RoostInk.primary)
        }
    }
}

/// Every other request waiting: one line, how long it's waited, and Show.
private struct WaitingCard: View {
    let session: AgentSession
    let model: AppModel?

    var body: some View {
        HStack(spacing: 14) {
            OwletSprite(sprite: session.state.sprite, palette: session.agent.palette, scale: 1.5, animated: false)
                .frame(width: 48, height: 45)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(RoostInk.amber).frame(width: 9, height: 9).offset(x: 2, y: -2)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(RoostInk.primary).lineLimit(1)
                line.lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(WaitClock.clock(context.date.timeIntervalSince(session.request?.since ?? session.stateSince)))
                    .font(.callout.monospacedDigit()).foregroundStyle(RoostInk.secondary)
            }
            Button("Answer") { AgentActions.show(session) }.buttonStyle(RoostPillStyle()).fixedSize()
                .help("Go to \(session.host ?? "the session") to answer")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoostInk.card, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(RoostInk.cardEdge, lineWidth: 1) }
        .contentShape(.rect)
        .contextMenu { if let model { AgentMenu(session: session, model: model, close: {}) } }
        .accessibilityElement(children: .combine)
    }

    /// "tk-app-2026 · wants to run git push origin main"
    private var line: Text {
        let place = Text("\(session.placeName) · ").foregroundStyle(RoostInk.secondary)
        guard let request = session.request else {
            return place + Text(session.detail ?? session.state.label).foregroundStyle(RoostInk.secondary)
        }
        switch request.kind {
        case .command:
            return place + Text("wants to run ").foregroundStyle(RoostInk.secondary)
                + Text(request.text).font(.system(size: 13, design: .monospaced)).foregroundStyle(RoostInk.command)
        case .question:
            return place + Text("“\(request.text)”").foregroundStyle(RoostInk.primary)
        default:
            return place + Text(request.text).foregroundStyle(RoostInk.secondary)
        }
    }
}

/// "0:42 left to answer" for a question that times out, or how long it's waited.
private struct WaitClock: View {
    let request: AgentRequest?
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                if let deadline = request?.deadline, deadline > context.date {
                    Text(Self.clock(deadline.timeIntervalSince(context.date)))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(RoostInk.amber)
                    Text("left to answer").font(.caption2).foregroundStyle(RoostInk.secondary)
                } else {
                    Text(Self.clock(context.date.timeIntervalSince(request?.since ?? since)))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(RoostInk.amber)
                    Text("waiting").font(.caption2).foregroundStyle(RoostInk.secondary)
                }
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String { RoostNumbers.clock(seconds) }
}

// MARK: Working

/// An owlet on its own twig: what it's doing, for how long, and its helpers,
/// a team on a sub-twig with their roles, or a brood as a matrix.
private struct WorkingRow: View {
    let session: AgentSession
    let selected: Bool
    let model: AppModel?
    /// Another owlet has the same name: say when this one started.
    var twin = false

    /// Agents it asked to help, still out, and how many are back.
    var asked: [AgentSession] = []
    var back = 0

    private var stuck: Bool { session.state == .stuck }
    private var team: Bool { session.helpers.count > 1 && session.helpers.count <= 6 }
    private var brood: Bool { session.helpers.count > 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Perched(session: session)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(RoostInk.primary)
                        .lineLimit(1)
                    Text(meta).font(.callout).foregroundStyle(stuck ? RoostInk.coral : RoostInk.secondary).lineLimit(1)
                }
                .padding(.top, 4)
                Spacer(minLength: 12)
                if brood { Brood(helpers: session.helpers).padding(.top, 4) }
                TimelineView(.everyMinute) { context in
                    Text(RoostNumbers.duration(context.date.timeIntervalSince(session.started)))
                        .font(.callout.monospacedDigit()).foregroundStyle(RoostInk.secondary)
                        .frame(minWidth: 52, alignment: .trailing)
                }
                    .padding(.top, 4)
            }
            if team { Team(session: session).padding(.leading, 74) }
            if !asked.isEmpty || back > 0 { AskedProgress(asked: asked, back: back).padding(.leading, 74) }
        }
        .padding(.horizontal, 14).padding(.vertical, team || brood ? 14 : 10)
        .background(team || brood ? RoostInk.card : .clear, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(RoostInk.lilac.opacity(selected ? 0.8 : 0), lineWidth: 1.5)
        }
        .padding(.vertical, team || brood ? 4 : 0)
        .contentShape(.rect)
        .onTapGesture(count: 2) { AgentActions.show(session) }
        .contextMenu { if let model { AgentMenu(session: session, model: model, close: {}) } }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Show") { AgentActions.show(session) }
    }

    /// "barnowl · typing · team of 5", "site · stuck, trying a third fix"
    private var meta: String {
        var parts: [String] = []
        if session.placeName != session.name { parts.append(session.placeName) }
        if session.state == .napping || session.state == .resting {
            parts.append("\(session.state.label.lowercased()) since \(session.stateSince.formatted(date: .omitted, time: .shortened))")
        } else if let detail = session.detail, detail != session.state.label {
            parts.append(detail)
        } else {
            parts.append(session.state.label.lowercased())
        }
        if team { parts.append("team of \(session.helpers.count + 1)") }
        if session.agent != .claude { parts.append(session.agent.name) }
        if twin { parts.append("started \(session.started.formatted(date: .omitted, time: .shortened))") }
        return parts.joined(separator: " · ")
    }
}

/// The owlet on its twig.
private struct Perched: View {
    let session: AgentSession

    var body: some View {
        VStack(spacing: -2) {
            OwletSprite(sprite: session.state.sprite, palette: session.agent.palette, scale: 1.5, seed: session.id.hashValue)
                .frame(width: 48, height: 45)
            OwletBranch(scale: 2).frame(width: 60)
        }
        .frame(width: 60)
        .accessibilityHidden(true)
    }
}

/// A small team: each helper on a shared sub-twig, its role under it.
private struct Team: View {
    let session: AgentSession

    var body: some View {
        let helpers = Array(session.helpersByActivity.prefix(6))
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(helpers) { helper in
                    OwletSprite(sprite: helper.state.sprite, palette: session.agent.palette, scale: 1, seed: helper.id.hashValue,
                                animated: helper.isWorking)
                        .opacity(helper.isWorking ? 1 : 0.55)
                        .frame(width: 56)
                        .help(helper.task.isEmpty ? helper.type : "\(helper.type): \(helper.task)")
                }
            }
            Capsule().fill(Color(hex: 0x4D3A57)).frame(width: CGFloat(helpers.count) * 66 - 10, height: 3)
            HStack(spacing: 10) {
                ForEach(helpers) { helper in
                    Text(Self.role(helper)).font(.caption).foregroundStyle(RoostInk.secondary).lineLimit(1)
                        .truncationMode(.tail).frame(width: 56)
                        .help(Self.role(helper))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Team: " + helpers.map { Self.role($0) }.joined(separator: ", "))
    }

    /// "Explore" → "explore", "general-purpose" → "helper", custom names as given.
    static func role(_ helper: AgentHelper) -> String {
        switch helper.type.lowercased() {
        case "general-purpose", "": "helper"
        default: helper.type.lowercased()
        }
    }
}

/// A brood of helpers, one square each: lilac working, green done. Past
/// thirty, each square stands for a share, in proportion.
struct Brood: View {
    let helpers: [AgentHelper]

    var body: some View {
        let all = helpers.filter(\.isWorking).count
        let total = min(helpers.count, 30)
        let working = helpers.count > 30 ? Int((Double(all) / Double(helpers.count) * 30).rounded()) : all
        let columns = min(10, max(total, 1))
        let rows = Int((Double(total) / Double(columns)).rounded(.up))
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, _ in
                for index in 0..<total {
                    let rect = CGRect(x: CGFloat(index % columns) * 12.5, y: CGFloat(index / columns) * 12.5, width: 9, height: 9)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(index < working ? RoostInk.lilac : RoostInk.green))
                }
            }
            .frame(width: CGFloat(columns) * 12.5, height: CGFloat(rows) * 12.5)
            Text("\(all) working · \(helpers.count - all) done").font(.callout).foregroundStyle(RoostInk.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(helpers.count) helpers, \(all) working")
    }
}

// MARK: Resting

/// Owlets with nothing to do: one quiet row, opening to the list.
private struct RestingCard: View {
    let sessions: [AgentSession]
    let twins: Set<String>
    @Binding var expanded: Bool
    @Binding var selected: String?
    let model: AppModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                OwletSprite(sprite: OwletState.napping.sprite, palette: sessions.first?.agent.palette ?? "golden", scale: 1.5,
                            animated: false)
                    .frame(width: 48, height: 45)
                    .opacity(0.8).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Napping · \(sessions.count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(RoostInk.primary)
                    Text(sessions.map(\.name).joined(separator: ", ")).font(.callout).foregroundStyle(RoostInk.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Fewer" : "See All") + Text(" \(Image(systemName: expanded ? "chevron.up" : "chevron.down"))")
                        .font(.caption)
                }
                .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(RoostInk.link)
            }
            if expanded {
                ForEach(sessions) { session in
                    WorkingRow(session: session, selected: selected == session.id, model: model, twin: twins.contains(session.name))
                        .onTapGesture { selected = session.id }
                        .accessibilityAddTraits(selected == session.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selected = session.id }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoostInk.card, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(RoostInk.cardEdge, lineWidth: 1) }
    }
}

// MARK: Done

/// "Done today · 4 / Docs pass shipped 2 min ago · 3 earlier", opening to the list.
private struct DoneCard: View {
    let done: [AgentSession]
    let cameHome: [AgentSession]
    @Binding var expanded: Bool
    let model: AppModel?

    var body: some View {
        let latest = done.max { $0.stateSince < $1.stateSince }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                OwletSprite(sprite: (latest?.state ?? .done).sprite, palette: latest?.agent.palette ?? "ghost", scale: 1.5,
                            animated: false)
                    .frame(width: 48, height: 45)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Done today · \(done.count + cameHome.count)")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(RoostInk.primary)
                    summary.font(.callout).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Fewer" : "See All") + Text(" \(Image(systemName: expanded ? "chevron.up" : "chevron.down"))")
                        .font(.caption)
                }
                .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(RoostInk.link)
            }
            if expanded {
                ForEach(done) { session in
                    HStack(spacing: 10) {
                        Text(session.name).foregroundStyle(RoostInk.primary)
                        Text([session.placeName == session.name ? nil : session.placeName, session.evidence?.summary,
                              IslandView.ago(session.stateSince)].compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(RoostInk.secondary)
                        Spacer()
                        Button("Show") { AgentActions.show(session) }.buttonStyle(.plain).foregroundStyle(RoostInk.link)
                    }
                    .font(.callout).lineLimit(1)
                    .contextMenu { if let model { AgentMenu(session: session, model: model, close: {}) } }
                }
                .padding(.leading, 62)
                if !cameHome.isEmpty {
                    Text("Went home: " + cameHome.map(\.name).joined(separator: ", "))
                        .font(.callout).foregroundStyle(RoostInk.secondary).lineLimit(2).padding(.leading, 62)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoostInk.green.opacity(0.07), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(RoostInk.cardEdge, lineWidth: 1) }
    }

    private var summary: Text {
        guard let latest = done.max(by: { $0.stateSince < $1.stateSince }) else {
            return Text("\(cameHome.count) finished and went home").foregroundStyle(RoostInk.secondary)
        }
        let verb = latest.state == .shipped ? "shipped" : "finished"
        var text = Text("\(latest.name) \(verb) \(IslandView.ago(latest.stateSince))").foregroundStyle(RoostInk.green)
        let earlier = done.count + cameHome.count - 1
        if earlier > 0 { text = text + Text(" · \(earlier) earlier").foregroundStyle(RoostInk.secondary) }
        return text
    }
}

// MARK: Today

/// How today went, and how far to trust each plan number.
struct TodayCard: View {
    let limits: [PlanLimit]
    let log: FlightLog
    /// Today so far from the saved log, so a restart doesn't start the day over.
    var day: DaySummary?
    var openLog: () -> Void = {}

    private var worked: TimeInterval { max(day?.working ?? 0, log.total(.working)) }
    private var waited: TimeInterval { max(day?.waiting ?? 0, log.total(.waiting)) }
    private var peak: Int { max(day?.peak ?? 0, log.peak) }
    /// Time per repository, the larger of the saved day and this run.
    private var byRepository: [(name: String, time: TimeInterval)] {
        var times = day?.repositories ?? [:]
        for repository in log.repositories { times[repository] = max(times[repository] ?? 0, log.total(.working, in: repository)) }
        return times.filter { $0.value >= 30 }.map { ($0.key, $0.value) }.sorted { $0.time > $1.time }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.system(size: 15, weight: .bold)).foregroundStyle(RoostInk.primary)
                Text(worked >= 60 ? RoostNumbers.duration(worked, long: true) : "Quiet so far")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(RoostInk.primary)
                    .padding(.top, 4)
                Text(subtitle).font(.callout).foregroundStyle(RoostInk.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                HourChart(log: log, day: day).frame(height: 96)
                HStack(spacing: 18) {
                    Legend(colour: RoostInk.lavender, text: "Working")
                    Legend(colour: RoostInk.amber,
                           text: waited >= 60 ? "Waited on you \(RoostNumbers.duration(waited, long: true))" : "Waited on you")
                }
            }
            if !limits.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Plan limits").font(.system(size: 15, weight: .bold)).foregroundStyle(RoostInk.primary)
                    ForEach(limits) { limit in MoonRow(limit: limit) }
                    if let projection {
                        Text(projection.text).font(.callout).foregroundStyle(projection.warns ? RoostInk.amber : RoostInk.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            let repositories = byRepository
            if !repositories.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                VStack(alignment: .leading, spacing: 9) {
                    Text("By repo").font(.system(size: 15, weight: .bold)).foregroundStyle(RoostInk.primary)
                    let most = repositories.map(\.time).max() ?? 1
                    ForEach(Array(repositories.prefix(6).enumerated()), id: \.element.name) { index, entry in
                        let time = entry.time
                        HStack(spacing: 12) {
                            Text(entry.name).font(.callout).foregroundStyle(RoostInk.secondary).lineLimit(1)
                                .frame(width: 92, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(RoostInk.lavender.opacity(1 - Double(index) * 0.12))
                                    .frame(width: max(6, proxy.size.width * time / max(1, most)), height: 7)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: 14)
                            Text(RoostNumbers.duration(time)).font(.callout.monospacedDigit()).foregroundStyle(RoostInk.secondary)
                                .frame(width: 46, alignment: .trailing)
                        }
                    }
                }
            }
            if worked >= 60 {
                Button(action: openLog) {
                    Text("Open the full flight log") + Text(" \(Image(systemName: "chevron.right"))").font(.caption)
                }
                .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(RoostInk.link)
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(RoostInk.cardEdge, lineWidth: 1) }
    }

    /// "of owl work · up to 9 at once"
    private var subtitle: String {
        var parts = ["of owl work"]
        if peak > 1 { parts.append("up to \(peak) at once") }
        return parts.joined(separator: " · ")
    }

    /// Where the 5-hour window is heading, only while its number is fresh.
    private var projection: (text: String, warns: Bool)? {
        guard let limit = limits.first(where: { $0.window == .session && $0.agent == .claude }) ?? limits.first,
              !limit.isStale() else { return nil }
        let name = "\(limit.owner)'s " + (limit.window == .session ? "5-hour window" : "week")
        // Only a forecast can say how the pace ends; without one, say nothing.
        guard let full = limit.fullAt, full < (limit.resetsAt ?? .distantFuture) else { return nil }
        return ("At this pace \(name) runs out \(PlanLimit.moment(full)).", true)
    }
}

private struct Legend: View {
    let colour: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(colour).frame(width: 9, height: 9)
            Text(text).font(.callout).foregroundStyle(RoostInk.secondary)
        }
    }
}

/// Today hour by hour, Screen Time style: a lavender bar for work, and an
/// amber cap above it for the time it waited on you.
private struct HourChart: View {
    let log: FlightLog
    var day: DaySummary?

    var body: some View {
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        let firstSaved = day?.hours.firstIndex { $0 > 0 }.map { midnight.addingTimeInterval(Double($0) * 3600) }
        let first = calendar.dateInterval(of: .hour, for: [log.firstActivity, firstSaved].compactMap { $0 }.min() ?? now)?.start ?? now
        let sixHoursAgo = calendar.dateInterval(of: .hour, for: now.addingTimeInterval(-5 * 3600))?.start ?? now
        let start = min(first, sixHoursAgo)
        let hours = max(6, Int(now.timeIntervalSince(start) / 3600) + 1)
        let buckets = (0..<hours).map { hour -> (work: Double, wait: Double) in
            let from = start.addingTimeInterval(Double(hour) * 3600), to = from.addingTimeInterval(3600)
            func overlap(_ kind: FlightLog.Kind) -> Double {
                log.segments.filter { $0.kind == kind }.reduce(0) { total, segment in
                    total + max(0, min(segment.end, to).timeIntervalSince(max(segment.start, from)))
                }
            }
            let saved = calendar.isDate(from, inSameDayAs: now) ? day?.hours[calendar.component(.hour, from: from)] ?? 0 : 0
            return (max(saved, overlap(.working)), overlap(.waiting))
        }
        let most = max(1800, buckets.map(\.work).max() ?? 1)
        VStack(spacing: 6) {
            Canvas { context, size in
                let slot = size.width / CGFloat(buckets.count)
                let width = max(3, slot * 0.72)
                let room = size.height - 10
                for (index, bucket) in buckets.enumerated() {
                    let x = CGFloat(index) * slot + (slot - width) / 2
                    context.fill(Path(roundedRect: CGRect(x: x, y: 10, width: width, height: room), cornerRadius: 4),
                                 with: .color(.white.opacity(0.05)))
                    let workHeight = bucket.work > 0 ? max(6, room * bucket.work / most) : 0
                    if workHeight > 0 {
                        context.fill(Path(roundedRect: CGRect(x: x, y: size.height - workHeight, width: width, height: workHeight),
                                          cornerRadius: 4), with: .color(RoostInk.lavender))
                    }
                    if bucket.wait >= 30 {
                        let cap = min(8, 3 + bucket.wait / 300)
                        context.fill(Path(roundedRect: CGRect(x: x, y: size.height - workHeight - cap - 3, width: width,
                                                              height: cap), cornerRadius: 2), with: .color(RoostInk.amber))
                    }
                }
            }
            GeometryReader { proxy in
                let slot = proxy.size.width / CGFloat(hours)
                ForEach(0..<hours, id: \.self) { hour in
                    let date = start.addingTimeInterval(Double(hour) * 3600)
                    let label: String? = hour == hours - 1 ? "now"
                        : hour == 0 || (calendar.component(.hour, from: date) % 6 == 0 && hour > 1 && hour < hours - 2)
                            ? String(format: "%02d", calendar.component(.hour, from: date)) : nil
                    if let label {
                        Text(label).font(.caption2.monospacedDigit()).foregroundStyle(RoostInk.quiet).fixedSize()
                            .position(x: CGFloat(hour) * slot + slot / 2, y: 6)
                    }
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent work by hour today")
    }
}

/// A plan window as a moon that waxes as you use it. A reading that's gone
/// old is dashed and faded, in italics, with its age.
struct MoonRow: View {
    let limit: PlanLimit

    var body: some View {
        let stale = limit.isStale()
        HStack(alignment: .top, spacing: 12) {
            PlanMoon(fraction: limit.used / 100, stale: stale, high: limit.isHigh).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) · \(Int(limit.used.rounded()))%").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(stale ? RoostInk.secondary : limit.isHigh ? RoostInk.amber : RoostInk.primary)
                // Ages as it sits there: "updated just now" becomes "As of …".
                TimelineView(.everyMinute) { _ in
                    detail(stale: limit.isStale()).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        "\(limit.owner) · " + (limit.window == .session ? "5-hour window" : "week")
    }

    private func detail(stale: Bool) -> Text {
        let resets = limit.resetsAt.map { "resets \(PlanLimit.moment($0))" }
        if stale {
            let age = "As of \(PlanLimit.when(limit.updated)), \(RoostNumbers.duration(Date().timeIntervalSince(limit.updated), long: true)) ago"
            return Text(age).italic().foregroundStyle(RoostInk.secondary)
                + Text(resets.map { " · \($0)" } ?? "").foregroundStyle(RoostInk.secondary)
        }
        let fresh = Date().timeIntervalSince(limit.updated) < 120 ? "updated just now" : "updated \(IslandView.ago(limit.updated))"
        let lead = resets.map { $0.prefix(1).uppercased() + $0.dropFirst() + " · " } ?? ""
        return Text(lead).foregroundStyle(RoostInk.secondary) + Text(fresh).foregroundStyle(RoostInk.green)
    }
}

/// The moon's lit part grows from the right as the plan fills; new again at
/// the reset. Stale: faded, with a dashed ring around it.
struct PlanMoon: View {
    let fraction: Double
    var stale = false
    var high = false

    var body: some View {
        Canvas { context, size in
            let ring: CGFloat = stale ? size.width * 0.12 : 0
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: ring + 0.5, dy: ring + 0.5)
            let disc = Path(ellipseIn: rect)
            context.fill(disc, with: .color(RoostInk.moonDark))
            let lit = min(1, max(0, fraction))
            var light = Path()
            let r = rect.width / 2, centre = CGPoint(x: rect.midX, y: rect.midY)
            let steps = 48
            for i in 0...steps {
                let angle = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
                let point = CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
                if i == 0 { light.move(to: point) } else { light.addLine(to: point) }
            }
            let bulge = r * (1 - 2 * lit)
            for i in stride(from: steps, through: 0, by: -1) {
                let angle = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
                light.addLine(to: CGPoint(x: centre.x + bulge * cos(angle), y: centre.y + r * sin(angle)))
            }
            light.closeSubpath()
            let colour: Color = stale ? Color(hex: 0x8F8BAE) : high ? RoostInk.amber : RoostInk.moon
            context.fill(light, with: .color(colour))
            if stale {
                let outer = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
                context.stroke(Path(ellipseIn: outer), with: .color(RoostInk.secondary.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
            }
        }
        .opacity(stale ? 0.8 : 1)
        .accessibilityHidden(true)
    }
}

/// The Roost's way with numbers: "14 h 25 min" big, "5 h 40" in a table.
enum RoostNumbers {
    /// A ticking clock: "0:42", "4:10", "1:05:09".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func duration(_ seconds: TimeInterval, long: Bool = false) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(max(1, minutes)) min" }
        if long { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }
}

/// Lays its children out in rows, wrapping when the next one doesn't fit.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    /// Its natural size, but never wider than the row: a long one truncates.
    private func fitted(_ subview: LayoutSubview, to width: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        guard width.isFinite, natural.width > width else { return natural }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = fitted(subview, to: width)
            if x > 0 && x + size.width > width { y += line + lineSpacing; x = 0; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = fitted(subview, to: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX { y += line + lineSpacing; x = bounds.minX; line = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// A caller's helpers on its row: a segment each, green once back, and what
/// the busiest is doing: "3 of 10 back · Devstral is running a command".
private struct AskedProgress: View {
    let asked: [AgentSession]
    let back: Int

    var body: some View {
        let total = asked.count + back
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(0..<min(total, 16), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < back ? RoostInk.green : asked[index - back].state.needsYou ? RoostInk.amber : RoostInk.lavender)
                            .frame(width: total > 10 ? 9 : 14, height: 7)
                    }
                }
                Text("\(back) of \(total) back").font(.callout.monospacedDigit()).foregroundStyle(RoostInk.secondary)
            }
            if let lead = asked.sorted(by: AgentWatcher.order).first {
                let doing = lead.state == .asking ? "has a question for you" : lead.state.needsYou ? "wants your OK"
                    : "is \(lead.state.label.lowercased())"
                Text("\(lead.model ?? lead.agent.name) \(doing)")
                    .font(.caption).foregroundStyle(lead.state.needsYou ? RoostInk.amber : RoostInk.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(back) of \(total) helpers back")
    }
}

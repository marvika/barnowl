import Foundation
import WidgetKit

/// Keeps the desktop widget's snapshot current. WidgetKit allows a widget
/// only so many reloads a day, so it reloads when what the widget shows has
/// changed, a minute apart at most when something needs you and five
/// otherwise. Between those it only rewrites the file now and then, so the
/// widget can tell a quiet hour from Barn Owl having stopped.
@MainActor
final class WidgetFeed {
    private var shown: RoostSnapshot?
    private var lastReload = Date.distantPast
    private var lastWrite = Date.distantPast
    private var trailing: Task<Void, Never>?
    /// Not for the demo copy: the real widget would show its made-up owlets.
    private let enabled = RoostSnapshot.groupID != nil && !DemoMode.isOn
    /// One writer, in order, so an older snapshot never lands after a newer one.
    private let writer = DispatchQueue(label: "io.github.marvika.BarnOwl.widget", qos: .utility)
    /// The sessions seen last time, to notice one leaving.
    private var seen: [String: AgentSession] = [:]
    private var departed: RoostSnapshot.Homecoming?
    /// Sessions that left today, by id, with their colour: home in the nest.
    private var gone: [String: (palette: String, at: Date)] = [:]

    func update(sessions: [AgentSession], limits: [PlanLimit], worked: TimeInterval, now: Date) {
        guard enabled else { return }
        let live = Set(sessions.map(\.id))
        let left = seen.values.filter { !live.contains($0.id) }
        if let last = left.max(by: { $0.stateSince < $1.stateSince }) {
            departed = .init(name: last.place.repository, shipped: last.state == .shipped, at: now)
        }
        for session in left { gone[session.id] = (session.agent.palette, now) }
        gone = gone.filter { Calendar.current.isDate($0.value.at, inSameDayAs: now) && !live.contains($0.key) }
        seen = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let departed, !Calendar.current.isDate(departed.at, inSameDayAs: now) { self.departed = nil }
        var snapshot = Self.snapshot(sessions: sessions, limits: limits, worked: worked, now: now, departed: departed)
        let homeward = gone.values.sorted { $0.at < $1.at }.map(\.palette)
        snapshot.homeToday = (snapshot.homeToday ?? 0) + homeward.count
        snapshot.homePalettes = Array(((snapshot.homePalettes ?? []) + homeward).suffix(3))
        if let shown, snapshot.looksLike(shown) {
            if now.timeIntervalSince(lastWrite) >= 10 * 60 { write(snapshot, now: now) }
            return
        }
        let urgent = Set(snapshot.needing.map(\.id)) != Set(shown?.needing.map(\.id) ?? [])
        write(snapshot, now: now)
        shown = snapshot
        let wait = (urgent ? 60.0 : 300.0) - now.timeIntervalSince(lastReload)
        trailing?.cancel()
        if wait <= 0 {
            reload(now: now)
        } else {
            trailing = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.reload(now: Date())
            }
        }
    }

    /// Barn Owl is quitting, or the agents feature turned off.
    func stop() {
        guard enabled, shown?.running != false else { return }
        trailing?.cancel()
        let stopped = RoostSnapshot(updated: Date(), running: false)
        writer.sync { stopped.save() }
        shown = stopped
        WidgetCenter.shared.reloadTimelines(ofKind: RoostSnapshot.widgetKind)
    }

    private func write(_ snapshot: RoostSnapshot, now: Date) {
        lastWrite = now
        writer.async { snapshot.save() }
    }

    private func reload(now: Date) {
        lastReload = now
        WidgetCenter.shared.reloadTimelines(ofKind: RoostSnapshot.widgetKind)
    }

    static func snapshot(sessions: [AgentSession], limits: [PlanLimit], worked: TimeInterval, now: Date,
                         departed: RoostSnapshot.Homecoming? = nil) -> RoostSnapshot {
        let owlets = sessions.sorted(by: AgentWatcher.order).prefix(12).map { session in
            RoostSnapshot.Owlet(
                id: session.id, name: session.name, place: session.placeName, palette: session.agent.palette,
                sprite: session.state.sprite, icon: session.state.icon, label: session.detail ?? session.state.label,
                needsYou: session.state.needsYou, working: session.state.isWorking,
                request: session.state.needsYou ? session.request?.text : nil,
                isCommand: session.request?.kind == .command,
                since: session.state.needsYou ? (session.request?.since ?? session.stateSince)
                    : session.state.isWorking ? session.started : session.stateSince,
                helpers: session.helpers.filter(\.isWorking).count, stuck: session.state == .stuck,
                active: !isAway(session.state))
        }
        let plan = limits.prefix(4).map { limit in
            RoostSnapshot.Limit(id: limit.id, title: "\(limit.owner) " + (limit.window == .session ? "5-hour" : "week"),
                                used: limit.used, updated: limit.updated, resetsAt: limit.resetsAt, high: limit.isHigh)
        }
        let ordered = sessions.sorted(by: AgentWatcher.order)
        let nappers = ordered.filter { $0.state == .napping || $0.state == .resting }
        let finished = ordered.filter { $0.state == .done || $0.state == .shipped }
        return RoostSnapshot(updated: now, owlets: Array(owlets), limits: plan, workedToday: worked,
                             lastHome: lastHome(sessions: sessions, departed: departed),
                             nappers: nappers.count, napperPalettes: nappers.prefix(3).map(\.agent.palette),
                             homeToday: finished.count, homePalettes: finished.suffix(3).map(\.agent.palette),
                             sky: UserDefaults.standard.string(forKey: PrefKey.roostSky))
    }

    /// Napping, resting or finished: in the hollow or the nest rather than on a branch, as on the tree.
    static func isAway(_ state: OwletState) -> Bool {
        switch state {
        case .napping, .resting, .done, .shipped: true
        default: false
        }
    }

    /// The most recent owlet to finish or ship: one still out in that state, or one that left.
    static func lastHome(sessions: [AgentSession], departed: RoostSnapshot.Homecoming?) -> RoostSnapshot.Homecoming? {
        let finished = sessions.filter { $0.state == .shipped || $0.state == .done }
            .map { RoostSnapshot.Homecoming(name: $0.place.repository, shipped: $0.state == .shipped, at: $0.stateSince) }
        return (finished + [departed].compactMap { $0 }).max { $0.at < $1.at }
    }
}

import Foundation

/// Today's agent work, for the Roost's flight log: when each session worked,
/// waited for you or paused for a limit. Kept in memory, from midnight.
struct FlightLog: Equatable, Sendable {
    enum Kind: Sendable { case working, waiting, paused }

    struct Segment: Equatable, Sendable {
        var session: String
        var repository: String
        var kind: Kind
        var start: Date
        var end: Date
    }

    private(set) var segments: [Segment] = []
    private(set) var day = Date.distantPast
    /// When Barn Owl started keeping this log: midnight, or later if it started later.
    private(set) var watchingSince = Date.distantPast
    /// The most agents working at once today.
    private(set) var peak = 0

    /// A made-up day, for demo mode and previews.
    static func demo(now: Date) -> FlightLog {
        var log = FlightLog()
        log.day = now
        log.watchingSince = Calendar.current.startOfDay(for: now)
        log.peak = 4
        func add(_ repository: String, _ kind: Kind, _ from: Double, _ to: Double) {
            log.segments.append(Segment(session: repository, repository: repository, kind: kind,
                                        start: now.addingTimeInterval(-from * 3600), end: now.addingTimeInterval(-to * 3600)))
        }
        add("barnowl", .working, 2.4, 0.3)
        add("barnowl", .waiting, 0.3, 0)
        add("tk-app-2026", .working, 1.5, 0.6)
        add("tk-app-2026", .paused, 0.6, 0.2)
        add("tk-app-2026", .working, 0.2, 0)
        add("dotfiles", .working, 2.2, 1.4)
        return log
    }

    static func kind(of state: OwletState) -> Kind? {
        if state.isWorking { return .working }
        if state.needsYou { return .waiting }
        if state == .teaBreak { return .paused }
        return nil
    }

    /// Adds what each session is doing now. A segment carries on while the
    /// same thing goes on, with reads at most a minute apart.
    mutating func record(_ sessions: [AgentSession], now: Date) {
        if !Calendar.current.isDate(day, inSameDayAs: now) {
            // A day already under way when Barn Owl started counts from then; the next from midnight.
            watchingSince = day == .distantPast ? now : Calendar.current.startOfDay(for: now)
            segments.removeAll()
            peak = 0
            day = now
        }
        peak = max(peak, sessions.filter { $0.state.isWorking }.count)
        for session in sessions {
            guard let kind = Self.kind(of: session.state) else { continue }
            if let index = segments.lastIndex(where: { $0.session == session.id }), segments[index].kind == kind,
               now.timeIntervalSince(segments[index].end) < 60 {
                segments[index].end = now
            } else {
                segments.append(Segment(session: session.id, repository: session.place.repository, kind: kind,
                                        start: now, end: now))
            }
        }
        if segments.count > 4000 { segments.removeFirst(segments.count - 4000) }
    }

    /// Total time agents spent on each kind of thing today, added up across
    /// agents, in one repository or all of them.
    func total(_ kind: Kind, in repository: String? = nil) -> TimeInterval {
        segments.filter { $0.kind == kind && (repository == nil || $0.repository == repository) }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    var repositories: [String] {
        var seen: [String] = []
        for segment in segments where !seen.contains(segment.repository) { seen.append(segment.repository) }
        return seen
    }

    var firstActivity: Date? { segments.map(\.start).min() }

    /// "3 h 5 min of agent work today · up to 5 at once · you kept them waiting 9 min".
    var summary: String? {
        let work = total(.working)
        guard work >= 60 else { return nil }
        var parts = ["\(ClaudeSource.duration(work)) of agent work today"]
        if peak > 1 { parts.append("up to \(peak) at once") }
        let waiting = total(.waiting)
        if waiting >= 60 { parts.append("you kept them waiting \(ClaudeSource.duration(waiting))") }
        return parts.joined(separator: " · ")
    }
}

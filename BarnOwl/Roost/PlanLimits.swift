import Foundation

/// How much of a subscription's usage limit is used: Claude's 5-hour and
/// weekly windows, Codex's the same. Read from what the agents themselves
/// write down; Barn Owl never asks a server and never touches a login.
struct PlanLimit: Identifiable, Hashable, Sendable {
    enum Window: String, Sendable, Comparable {
        case session, week

        var title: String { self == .session ? "5-hour" : "Weekly" }

        static func < (a: Window, b: Window) -> Bool { a == .session && b == .week }
    }

    var agent: AgentKind
    var window: Window
    /// 0–100.
    var used: Double
    var resetsAt: Date?
    /// When this reading was taken.
    var updated: Date
    /// When, at the recent pace, it would reach 100%, if before it resets.
    var fullAt: Date?

    var id: String { "\(agent.rawValue).\(window.rawValue)" }
    var isHigh: Bool { used >= 80 }

    /// Older than half an hour: shown greyed, with its time, never as current.
    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(updated) > 30 * 60 }
}

enum PlanLimits {
    // MARK: The Claude app's history

    /// The Claude app writes your plan usage here every few minutes while its
    /// menu bar icon is on: `{"samples":[{"t":ms,"org":"…","u":{"fh":38,"sd":71}}]}`,
    /// fh being the 5-hour window and sd the week, in percent.
    static var claudeHistory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/plan-usage-history.json")
    }

    struct Sample: Sendable, Equatable {
        let time: Date
        let session: Double?
        let week: Double?
    }

    /// The samples of the organisation used most recently, oldest first.
    static func claudeSamples(from data: Data) -> [Sample] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]] else { return [] }
        let usable = samples.compactMap { sample -> (org: String, sample: Sample)? in
            guard let t = sample["t"] as? Double, let usage = sample["u"] as? [String: Any] else { return nil }
            let session = (usage["fh"] as? NSNumber)?.doubleValue
            let week = (usage["sd"] as? NSNumber)?.doubleValue
            guard session != nil || week != nil else { return nil }
            return (sample["org"] as? String ?? "", Sample(time: Date(timeIntervalSince1970: t / 1000), session: session, week: week))
        }.sorted { $0.sample.time < $1.sample.time }
        guard let org = usable.last?.org else { return [] }
        return usable.filter { $0.org == org }.map(\.sample)
    }

    /// Limits from the history, if its newest reading is recent enough to trust.
    /// The Claude app saves a reading only now and then. A week's number from
    /// earlier in the week still tells you something, shown as old ("as of");
    /// past a week it would belong to another window.
    static func claudeLimits(from samples: [Sample], now: Date, maxAge: TimeInterval = 7 * 24 * 3600) -> [PlanLimit] {
        guard let last = samples.last, now.timeIntervalSince(last.time) < maxAge else { return [] }
        var limits: [PlanLimit] = []
        if let week = last.week {
            limits.append(PlanLimit(agent: .claude, window: .week, used: week, updated: last.time,
                                    fullAt: forecast(samples.compactMap { s in s.week.map { (s.time, $0) } }, now: now)))
        }
        // Without a reset time, a 5-hour reading can't be trusted past five hours.
        if let session = last.session, session > 0, now.timeIntervalSince(last.time) < 5 * 3600 {
            limits.append(PlanLimit(agent: .claude, window: .session, used: session, updated: last.time))
        }
        return limits
    }

    /// When the week's usage would reach 100% at the pace of the last day,
    /// if it keeps rising. Nil when it isn't rising or the samples are few.
    static func forecast(_ points: [(Date, Double)], now: Date, horizon: TimeInterval = 24 * 3600) -> Date? {
        let recent = points.filter { now.timeIntervalSince($0.0) <= horizon }
        // A drop on the way means the window reset: measure from after it.
        let afterReset = Array(recent.drop { point in recent.contains { $0.0 > point.0 && $0.1 < point.1 - 5 } })
        guard let start = afterReset.first, let last = afterReset.last, afterReset.count >= 3,
              last.0.timeIntervalSince(start.0) >= 3600, last.1 > start.1, last.1 < 100 else { return nil }
        let rate = (last.1 - start.1) / last.0.timeIntervalSince(start.0)
        let eta = last.0.addingTimeInterval((100 - last.1) / rate)
        return eta.timeIntervalSince(now) < 7 * 24 * 3600 ? eta : nil
    }

    // MARK: The status line relay

    /// What `Barn Owl --statusline` saves from Claude Code's status line:
    /// the same percentages, with reset times.
    static var relayFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Barn Owl/claude-limits.json")
    }

    static func relayLimits(from data: Data, now: Date, maxAge: TimeInterval = 6 * 3600) -> [PlanLimit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let saved = root["saved"] as? Double else { return [] }
        let updated = Date(timeIntervalSince1970: saved)
        guard now.timeIntervalSince(updated) < maxAge else { return [] }
        var limits: [PlanLimit] = []
        for (key, window) in [("five_hour", PlanLimit.Window.session), ("seven_day", .week)] {
            guard let entry = root[key] as? [String: Any],
                  let used = (entry["used_percentage"] as? NSNumber)?.doubleValue else { continue }
            let resets = (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            // Past its reset, the reading no longer holds.
            if let resets, resets < now { continue }
            limits.append(PlanLimit(agent: .claude, window: window, used: used, resetsAt: resets, updated: updated))
        }
        return limits
    }

    /// The relay's readings win where they're newer; the history adds the forecast.
    static func merge(history: [PlanLimit], relay: [PlanLimit]) -> [PlanLimit] {
        var byID = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for limit in relay {
            if let old = byID[limit.id], old.updated > limit.updated {
                byID[limit.id]?.resetsAt = limit.resetsAt
            } else {
                var merged = limit
                merged.fullAt = byID[limit.id]?.fullAt
                byID[limit.id] = merged
            }
            // A forecast past the reset means nothing.
            if let full = byID[limit.id]?.fullAt, let reset = byID[limit.id]?.resetsAt, full >= reset {
                byID[limit.id]?.fullAt = nil
            }
        }
        return byID.values.sorted { ($0.agent.rawValue, $0.window) < ($1.agent.rawValue, $1.window) }
    }
}

extension PlanLimit {
    /// "38% · resets 19:30", "71% · resets Thu", or for an old reading "43% · as of 16:44".
    func summary(now: Date = Date()) -> String {
        var text = "\(Int(used.rounded()))%"
        if isStale(now: now) {
            text += " · as of \(PlanLimit.when(updated, now: now))"
        } else if let resetsAt {
            text += " · resets \(PlanLimit.when(resetsAt, now: now))"
        }
        return text
    }

    /// "today at 19:30", "Thu at 15:00".
    static func moment(_ date: Date, now: Date = Date()) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) at \(time)"
    }

    /// "19:30" today, "Thu" this week.
    static func when(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if date.timeIntervalSince(now) < 6 * 24 * 3600 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

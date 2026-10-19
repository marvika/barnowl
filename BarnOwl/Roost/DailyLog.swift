import Foundation

/// One day of agent work, for the weekly Roost recap. Only times, counts and
/// repository names, which never leave the Mac; nothing from prompts or code.
struct DaySummary: Codable, Sendable, Equatable {
    /// The local day, "2026-10-19".
    var day: String
    /// Time agents spent working, added up across agents.
    var working: TimeInterval = 0
    /// Time agents spent waiting for you, added up across agents.
    var waiting: TimeInterval = 0
    /// Time at least one agent was waiting for you, by the clock.
    var needed: TimeInterval = 0
    /// The most agents working at once, and when that was first reached.
    var peak = 0
    var peakAt: Date?
    /// Sessions seen that day.
    var sessions = 0
    /// The most one session worked that day, and when it started.
    var longest: TimeInterval = 0
    var longestStart: Date?
    /// Pull requests opened: each move into `.shipped`.
    var shipped = 0
    /// Working time between 22:00 and 06:00.
    var night: TimeInterval = 0
    /// Working time in each local hour, 0–23.
    var hours: [TimeInterval] = Array(repeating: 0, count: 24)
    /// Working time per repository name.
    var repositories: [String: TimeInterval] = [:]
    /// How long each wait for you lasted, in the order they ended.
    var waits: [TimeInterval] = []

    static let maxWaits = 400
}

extension DaySummary {
    /// Reads older or newer files too: anything missing starts empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        working = try c.decodeIfPresent(TimeInterval.self, forKey: .working) ?? 0
        waiting = try c.decodeIfPresent(TimeInterval.self, forKey: .waiting) ?? 0
        needed = try c.decodeIfPresent(TimeInterval.self, forKey: .needed) ?? 0
        peak = try c.decodeIfPresent(Int.self, forKey: .peak) ?? 0
        peakAt = try c.decodeIfPresent(Date.self, forKey: .peakAt)
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        longest = try c.decodeIfPresent(TimeInterval.self, forKey: .longest) ?? 0
        longestStart = try c.decodeIfPresent(Date.self, forKey: .longestStart)
        shipped = try c.decodeIfPresent(Int.self, forKey: .shipped) ?? 0
        night = try c.decodeIfPresent(TimeInterval.self, forKey: .night) ?? 0
        let hours = try c.decodeIfPresent([TimeInterval].self, forKey: .hours) ?? []
        self.hours = hours.count == 24 ? hours : Array(repeating: 0, count: 24)
        repositories = try c.decodeIfPresent([String: TimeInterval].self, forKey: .repositories) ?? [:]
        waits = try c.decodeIfPresent([TimeInterval].self, forKey: .waits) ?? []
    }
}

/// Owl species for the field guide, each earned by one real thing that happened.
enum FieldGuideSpecies: String, Codable, Sendable, CaseIterable {
    case eagleOwl, greatGrey, longEared, snowy

    var name: String {
        switch self {
        case .eagleOwl: "Eagle-Owl"
        case .greatGrey: "Great Grey Owl"
        case .longEared: "Long-eared Owl"
        case .snowy: "Snowy Owl"
        }
    }

    /// Why it's in the guide, in one plain sentence.
    var reason: String {
        switch self {
        case .eagleOwl: "100 hours of agent flight"
        case .greatGrey: "three hours in one session"
        case .longEared: "your first parliament, five at once"
        case .snowy: "worked through the night"
        }
    }

    /// Whether a day earns it. `lifetime` is all working time ever recorded.
    func isEarned(by day: DaySummary, lifetime: TimeInterval) -> Bool {
        switch self {
        case .eagleOwl: lifetime >= 100 * 3600
        case .greatGrey: day.longest >= 3 * 3600
        case .longEared: day.peak >= 5
        case .snowy: day.night >= 3600
        }
    }
}

/// A Monday-to-Sunday week of `DaySummary`s, with what the recap shows.
struct WeekSummary: Codable, Sendable, Equatable {
    /// Monday, 00:00 local.
    var start: Date
    /// The ISO week number.
    var week: Int
    /// Monday to Sunday, always seven.
    var days: [DaySummary]
    /// Species first found this week.
    var newSpecies: [FieldGuideSpecies] = []

    /// Sunday, around midday.
    var end: Date { start.addingTimeInterval(6 * 86_400 + 12 * 3600) }

    var working: TimeInterval { days.reduce(0) { $0 + $1.working } }
    var waiting: TimeInterval { days.reduce(0) { $0 + $1.waiting } }
    var needed: TimeInterval { days.reduce(0) { $0 + $1.needed } }
    var night: TimeInterval { days.reduce(0) { $0 + $1.night } }
    var shipped: Int { days.reduce(0) { $0 + $1.shipped } }
    var sessions: Int { days.reduce(0) { $0 + $1.sessions } }

    /// The most at once, and when (the first time it was reached).
    var peak: (count: Int, at: Date?) {
        var best = (count: 0, at: Date?.none)
        for day in days where day.peak > best.count { best = (day.peak, day.peakAt) }
        return best
    }

    /// The longest one session worked in a day, and when it started.
    var longest: (seconds: TimeInterval, start: Date?) {
        var best = (seconds: TimeInterval(0), start: Date?.none)
        for day in days where day.longest > best.seconds { best = (day.longest, day.longestStart) }
        return best
    }

    /// The median wait for you, if you were waited for at all.
    var typicalWait: TimeInterval? {
        let waits = days.flatMap(\.waits).sorted()
        guard !waits.isEmpty else { return nil }
        let middle = waits.count / 2
        return waits.count.isMultiple(of: 2) ? (waits[middle - 1] + waits[middle]) / 2 : waits[middle]
    }

    /// Repositories by working time, busiest first.
    var repositories: [(name: String, seconds: TimeInterval)] {
        var totals: [String: TimeInterval] = [:]
        for day in days { totals.merge(day.repositories, uniquingKeysWith: +) }
        return totals.map { (name: $0.key, seconds: $0.value) }
            .sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
    }

    /// Repositories worked in for at least a minute.
    var trees: Int { repositories.filter { $0.seconds >= 60 }.count }

    /// Working seconds per day (Mon first) and hour.
    var heatmap: [[TimeInterval]] { days.map(\.hours) }

    /// Enough happened for a recap to be worth showing.
    var isWorthARecap: Bool { working >= 3600 }
}

/// What agents did each day, kept for 60 days so the Roost can show a weekly
/// recap. Fed by `AgentWatcher` on every refresh; saved now and then, and on quit.
@MainActor
final class DailyLog {
    static let shared = DailyLog()

    /// ~/Library/Application Support/Barn Owl/daily-log.json
    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Barn Owl/daily-log.json")
    }

    static let keptDays = 60
    /// Reads further apart than this (sleep, a stalled refresh) count as this much.
    static let maxStep: TimeInterval = 60

    private struct Tally: Codable, Equatable {
        var work: TimeInterval = 0
        var firstWork: Date?
    }

    private struct Snapshot {
        var state: OwletState
        var repository: String
    }

    private struct Stored: Codable {
        var version = 1
        var days: [DaySummary]
        var tallyDay: String?
        /// Today's sessions by a hash of their id, never the id itself.
        var tallies: [String: Tally]?
        var species: [String: String]?
        var lifetime: TimeInterval?
    }

    let fileURL: URL?
    private let calendar: Calendar
    private let saveDelay: Duration
    private var days: [String: DaySummary] = [:]
    private var tallyDay = ""
    private var tallies: [String: Tally] = [:]
    /// Species, by raw value, to the day they were found.
    private var species: [String: String] = [:]
    private var lifetime: TimeInterval = 0
    private var lastCall: Date?
    private var previous: [String: Snapshot] = [:]
    private var waitRuns: [String: TimeInterval] = [:]
    private var saveTask: Task<Void, Never>?
    private static let writer = DispatchQueue(label: "io.github.marvika.BarnOwl.daily-log", qos: .utility)

    /// `fileURL` nil keeps the log in memory only.
    init(fileURL: URL? = DailyLog.defaultURL, calendar: Calendar = .current, saveDelay: Duration = .seconds(60)) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.saveDelay = saveDelay
        load()
    }

    // MARK: Recording

    /// Adds the time since the last call to what each session was doing then.
    /// Call on every refresh.
    func record(_ sessions: [AgentSession], now: Date) {
        let step = lastCall.map { min(max(now.timeIntervalSince($0), 0), Self.maxStep) } ?? 0
        let key = dayKey(now)
        if tallyDay != key {
            tallyDay = key
            tallies.removeAll()
            prune(now: now)
        }
        let before = days[key]
        var day = before ?? DaySummary(day: key)
        let hour = calendar.component(.hour, from: now)

        if step > 0 {
            var anyNeedsYou = false
            for (id, snapshot) in previous {
                if snapshot.state.isWorking {
                    day.working += step
                    day.hours[hour] += step
                    day.repositories[snapshot.repository, default: 0] += step
                    if hour >= 22 || hour < 6 { day.night += step }
                    lifetime += step
                    var tally = tallies[Self.hash(id), default: Tally()]
                    if tally.firstWork == nil { tally.firstWork = now.addingTimeInterval(-step) }
                    tally.work += step
                    tallies[Self.hash(id)] = tally
                    if tally.work > day.longest {
                        day.longest = tally.work
                        day.longestStart = tally.firstWork
                    }
                }
                if snapshot.state.needsYou {
                    day.waiting += step
                    waitRuns[id, default: 0] += step
                    anyNeedsYou = true
                }
            }
            if anyNeedsYou { day.needed += step }
        }

        var current: [String: AgentSession] = [:]
        for session in sessions where current[session.id] == nil { current[session.id] = session }

        // Waits that just ended: you answered, or the session went away.
        for (id, run) in waitRuns where current[id]?.state.needsYou != true {
            if run >= 1, day.waits.count < DaySummary.maxWaits { day.waits.append(run) }
            waitRuns[id] = nil
        }

        // A ship counts once, on the move into it. One seen already shipped
        // counts only if it shipped since the last look (not after a relaunch).
        for session in current.values where session.state == .shipped {
            if let was = previous[session.id]?.state {
                if was != .shipped { day.shipped += 1 }
            } else if let lastCall, session.stateSince > lastCall {
                day.shipped += 1
            }
        }

        for id in current.keys where tallies[Self.hash(id)] == nil { tallies[Self.hash(id)] = Tally() }
        day.sessions = max(day.sessions, tallies.count)

        let working = current.values.filter { $0.state.isWorking }.count
        if working > day.peak {
            day.peak = working
            day.peakAt = now
        }

        for kind in FieldGuideSpecies.allCases where species[kind.rawValue] == nil {
            if kind.isEarned(by: day, lifetime: lifetime) { species[kind.rawValue] = key }
        }

        if day != before { days[key] = day; scheduleSave() }
        previous = current.mapValues { Snapshot(state: $0.state, repository: $0.place.repository) }
        lastCall = now
    }

    // MARK: Reading

    /// Today so far.
    var today: DaySummary { summary(for: Date()) }

    func summary(for date: Date) -> DaySummary {
        let key = dayKey(date)
        return days[key] ?? DaySummary(day: key)
    }

    /// The Monday-to-Sunday week that holds `date`.
    func week(endingOn date: Date) -> WeekSummary {
        let monday = Self.monday(of: date, calendar: calendar)
        let keys = (0..<7).map { dayKey(calendar.date(byAdding: .day, value: $0, to: monday) ?? monday) }
        let found = FieldGuideSpecies.allCases.filter { kind in species[kind.rawValue].map(keys.contains) ?? false }
        return WeekSummary(start: monday, week: Self.isoWeek(of: monday, calendar: calendar),
                           days: keys.map { days[$0] ?? DaySummary(day: $0) }, newSpecies: found)
    }

    /// Every species found so far, with the day.
    var fieldGuide: [FieldGuideSpecies: String] {
        Dictionary(uniqueKeysWithValues: species.compactMap { key, day in FieldGuideSpecies(rawValue: key).map { ($0, day) } })
    }

    /// Forgets everything, on disk too.
    func forgetAll() {
        days.removeAll()
        tallies.removeAll()
        species.removeAll()
        lifetime = 0
        waitRuns.removeAll()
        saveNow()
    }

    // MARK: Saving

    /// Writes the log now and waits for it. Call on quit.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL, let data = encoded() else { return }
        Self.writer.sync { Self.write(data, to: fileURL) }
    }

    private func scheduleSave() {
        guard fileURL != nil, saveTask == nil else { return }
        saveTask = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveSoon()
        }
    }

    private func saveSoon() {
        saveTask = nil
        guard let fileURL, let data = encoded() else { return }
        Self.writer.async { Self.write(data, to: fileURL) }
    }

    private func encoded() -> Data? {
        let stored = Stored(days: days.values.sorted { $0.day < $1.day }, tallyDay: tallyDay, tallies: tallies,
                            species: species, lifetime: lifetime)
        return try? JSONEncoder().encode(stored)
    }

    private nonisolated static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        for day in stored.days { days[day.day] = day }
        tallyDay = stored.tallyDay ?? ""
        tallies = stored.tallies ?? [:]
        species = stored.species ?? [:]
        lifetime = stored.lifetime ?? stored.days.reduce(0) { $0 + $1.working }
        prune(now: Date())
    }

    private func prune(now: Date) {
        guard let oldest = calendar.date(byAdding: .day, value: -Self.keptDays, to: now) else { return }
        let cut = dayKey(oldest)
        days = days.filter { $0.key > cut }
    }

    // MARK: Calendar

    private func dayKey(_ date: Date) -> String { Self.dayKey(date, calendar: calendar) }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 00:00 on the Monday of `date`'s week.
    nonisolated static func monday(of date: Date, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: midnight) + 5) % 7 // Sunday is 1
        return calendar.date(byAdding: .day, value: -back, to: midnight) ?? midnight
    }

    nonisolated static func isoWeek(of date: Date, calendar: Calendar) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        return iso.component(.weekOfYear, from: date)
    }

    /// A stable, one-way stand-in for a session id (FNV-1a), so the file
    /// holds no ids.
    nonisolated static func hash(_ id: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01B3
        }
        return String(value, radix: 16)
    }
}

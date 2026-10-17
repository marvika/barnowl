import AppKit
import Observation

/// One thing a rule checks.
enum RuleCondition: Codable, Hashable, Sendable {
    case appRunning(bundleIdentifier: String, name: String)
    case externalDisplay
    case onPower
    case microphoneInUse
    case downloading
    /// Weekdays are 1 = Sunday … 7 = Saturday (Calendar's numbering);
    /// minutes are from midnight.
    case schedule(weekdays: Set<Int>, startMinute: Int, endMinute: Int)

    /// Lower-case, to join into a sentence: "on power adapter and an
    /// external display is connected".
    var phrase: String {
        switch self {
        case .appRunning(_, let name): "\(name) is running"
        case .externalDisplay: "an external display is connected"
        case .onPower: "on power adapter"
        case .microphoneInUse: "the microphone is in use (calls)"
        case .downloading: "files are downloading"
        case .schedule(let days, let start, let end):
            "\(Self.dayList(days).lowercased()) \(Self.time(start))–\(Self.time(end))"
        }
    }

    /// The phrase as a label on its own.
    var title: String { phrase.prefix(1).uppercased() + phrase.dropFirst() }

    var symbol: String {
        switch self {
        case .appRunning: "app.badge.checkmark"
        case .externalDisplay: "display"
        case .onPower: "bolt.fill"
        case .microphoneInUse: "mic.fill"
        case .downloading: "arrow.down.circle.fill"
        case .schedule: "calendar"
        }
    }

    static func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func dayList(_ days: Set<Int>) -> String {
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days.count == 7 { return "Every day" }
        if days == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    /// Whether this condition holds, given a snapshot of the system.
    func holds(in snapshot: ConditionSnapshot) -> Bool {
        switch self {
        case .appRunning(let bundle, _): snapshot.runningBundles.contains(bundle)
        case .externalDisplay: snapshot.hasExternalDisplay
        case .onPower: snapshot.onAC
        case .microphoneInUse: snapshot.microphoneInUse
        case .downloading: snapshot.downloading
        case .schedule(let days, let start, let end):
            days.contains(snapshot.weekday) && Self.minute(snapshot.minuteOfDay, isWithin: start, end)
        }
    }

    /// Handles ranges past midnight, such as 22:00–02:00.
    static func minute(_ minute: Int, isWithin start: Int, _ end: Int) -> Bool {
        start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }
}

/// Everything rules look at, read once per evaluation.
struct ConditionSnapshot: Equatable, Sendable {
    var runningBundles: Set<String> = []
    var hasExternalDisplay = false
    var onAC = true
    var batteryPercent: Int?
    var microphoneInUse = false
    var downloading = false
    var weekday = 2
    var minuteOfDay = 0
}

/// Keeps the Mac awake while all of its conditions hold.
struct KeepAwakeRule: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var conditions: [RuleCondition]
    var isEnabled = true
    var allowDisplaySleep = false

    var phrase: String {
        conditions.map(\.phrase).joined(separator: " and ")
    }

    var title: String { phrase.prefix(1).uppercased() + phrase.dropFirst() }

    func holds(in snapshot: ConditionSnapshot) -> Bool {
        isEnabled && !conditions.isEmpty && conditions.allSatisfy { $0.holds(in: snapshot) }
    }

    /// Ready-made rules offered in Settings.
    static let presets: [KeepAwakeRule] = [
        KeepAwakeRule(conditions: [.onPower, .externalDisplay]),
        KeepAwakeRule(conditions: [.microphoneInUse]),
        KeepAwakeRule(conditions: [.downloading], allowDisplaySleep: true),
        KeepAwakeRule(conditions: [.schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 8 * 60, endMinute: 17 * 60)]),
    ]
}

/// The rules, saved as JSON in UserDefaults.
@MainActor
@Observable
final class RuleStore {
    private(set) var rules: [KeepAwakeRule] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "keepAwakeRules"
    @ObservationIgnored var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([KeepAwakeRule].self, from: data) {
            rules = saved
        }
    }

    func add(_ rule: KeepAwakeRule) {
        rules.append(rule)
        save()
    }

    func update(_ rule: KeepAwakeRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func delete(_ id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: key) }
        onChange?()
    }
}

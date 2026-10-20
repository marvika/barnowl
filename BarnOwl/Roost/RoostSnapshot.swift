import Foundation

/// What the desktop widget shows, written by Barn Owl to the folder it
/// shares with the widget. Small, and only what's on screen: names, states,
/// the request's text and the plan, never transcripts.
struct RoostSnapshot: Codable, Equatable, Sendable {
    struct Owlet: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var place: String
        var palette: String
        var sprite: String
        var icon: String
        var label: String
        var needsYou: Bool
        var working: Bool
        /// The question or command it waits on.
        var request: String?
        var isCommand = false
        /// When it started waiting, or working.
        var since: Date
        /// Its helpers at work. Optional so an older file still reads.
        var helpers: Int?
        /// Stopped on an error it can't get past.
        var stuck: Bool?
        /// Doing something, so it sits on a branch rather than in the hollow or the nest.
        var active: Bool?

        var isActive: Bool { active ?? !["nap", "idle", "done", "ship"].contains(sprite) }
    }

    /// The last owlet to finish today: "docs shipped", "dotfiles finished".
    struct Homecoming: Codable, Equatable, Sendable {
        var name: String
        var shipped: Bool
        var at: Date
    }

    struct Limit: Codable, Equatable, Sendable, Identifiable {
        var id: String
        /// "Claude 5-hour", "Codex Plus week"
        var title: String
        var used: Double
        var updated: Date
        var resetsAt: Date?
        var high: Bool
    }

    var updated: Date
    /// False once Barn Owl has quit, or the agents feature is off.
    var running = true
    var owlets: [Owlet] = []
    var limits: [Limit] = []
    /// Agent time worked today.
    var workedToday: TimeInterval = 0
    /// The last owlet to finish today, if one has.
    var lastHome: Homecoming?
    /// Owlets napping or resting, curled up in the hollow, and up to three of their colours.
    var nappers: Int?
    var napperPalettes: [String]?
    /// Owlets home today, finished or gone, asleep in the nest, and up to three of their colours.
    var homeToday: Int?
    var homePalettes: [String]?
    /// The Roost's sky setting: "follow", "dusk", "night" or "plain".
    var sky: String?

    static let widgetKind = "BarnOwlRoost"
    /// A reading this old with no word from Barn Owl is shown as "as of".
    static let freshFor: TimeInterval = 20 * 60

    var needing: [Owlet] { owlets.filter(\.needsYou) }
    var working: [Owlet] { owlets.filter { $0.working && !$0.needsYou } }
    /// Owlets doing something: on a branch.
    var active: [Owlet] { owlets.filter(\.isActive) }
    /// Helpers at work across all owlets.
    var helpersAtWork: Int { owlets.reduce(0) { $0 + ($1.helpers ?? 0) } }

    func isStale(at now: Date) -> Bool { !running || now.timeIntervalSince(updated) > Self.freshFor }

    /// The app group the app and widget share, from Info.plist.
    static var groupID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "BarnOwlAppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var fileURL: URL? {
        groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appendingPathComponent("roost.json")
    }

    static func load(from url: URL? = fileURL) -> RoostSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(RoostSnapshot.self, from: data)
    }

    func save(to url: URL? = fileURL) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Two snapshots that look the same on the widget, ignoring the clock.
    func looksLike(_ other: RoostSnapshot) -> Bool {
        var a = self, b = other
        a.updated = .distantPast
        b.updated = .distantPast
        a.workedToday = (a.workedToday / 900).rounded(.down)
        b.workedToday = (b.workedToday / 900).rounded(.down)
        a.limits = a.limits.map { var l = $0; l.updated = .distantPast; l.used = l.used.rounded(); return l }
        b.limits = b.limits.map { var l = $0; l.updated = .distantPast; l.used = l.used.rounded(); return l }
        return a == b
    }
}

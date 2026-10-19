import AppKit
import Observation

/// What you've chosen to hide, mute or keep out of keep awake, saved in
/// UserDefaults.
@MainActor
@Observable
final class AgentChoices {
    enum HideLength: String, Codable, Sendable {
        /// Until the owlet needs you again.
        case untilNeeded
        case today
    }

    private(set) var hiddenSessions: [String: Hidden] = [:]
    private(set) var hiddenFolders: Set<String> = []
    private(set) var mutedFolders: Set<String> = []
    private(set) var notKeepingAwake: Set<String> = []
    /// Show hidden owlets anyway, until the panel closes.
    var revealHidden = false

    struct Hidden: Codable, Hashable, Sendable {
        var length: HideLength
        var since: Date
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "agentChoices"

    private struct Saved: Codable {
        var hiddenSessions: [String: Hidden] = [:]
        var hiddenFolders: Set<String> = []
        var mutedFolders: Set<String> = []
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            hiddenSessions = saved.hiddenSessions
            hiddenFolders = saved.hiddenFolders
            mutedFolders = saved.mutedFolders
        }
    }

    func isHidden(_ session: AgentSession, now: Date = Date()) -> Bool {
        if revealHidden { return false }
        if hiddenFolders.contains(session.place.root.path) { return !session.state.needsYou }
        if session.isScripted, Preferences.agentsHideScripted { return true }
        if Preferences.agentsHideScratch, Self.isScratch(session.folder) { return true }
        guard let hidden = hiddenSessions[session.id] else { return false }
        switch hidden.length {
        case .untilNeeded: return !session.state.needsYou && session.state != .stuck
        case .today: return Calendar.current.isDate(hidden.since, inSameDayAs: now)
        }
    }

    func isMuted(_ session: AgentSession) -> Bool {
        mutedFolders.contains(session.place.root.path)
    }

    /// Notifications respect muting and the automatic hiding of scripts and
    /// scratch folders. Hidden "until it needs me", or a hidden folder, still
    /// tells you when it needs you.
    func mayNotify(_ session: AgentSession, now: Date = Date()) -> Bool {
        if isMuted(session) { return false }
        if session.isScripted, Preferences.agentsHideScripted { return false }
        if Preferences.agentsHideScratch, Self.isScratch(session.folder) { return false }
        if let hidden = hiddenSessions[session.id], hidden.length == .today,
           Calendar.current.isDate(hidden.since, inSameDayAs: now) { return false }
        return true
    }

    /// Hidden "until it needs me": once it has, it stays in view.
    func cameBack(_ session: AgentSession) {
        guard hiddenSessions[session.id]?.length == .untilNeeded else { return }
        hiddenSessions[session.id] = nil
        save()
    }

    func countsForKeepAwake(_ session: AgentSession) -> Bool {
        !notKeepingAwake.contains(session.id)
    }

    /// Temporary folders and the Claude app's scratch workspaces.
    static func isScratch(_ folder: URL) -> Bool {
        let path = folder.path
        for temporary in ["/private/var/folders", "/var/folders", "/private/tmp", "/tmp"]
        where path == temporary || path.hasPrefix(temporary + "/") {
            return true
        }
        return path.contains("/Application Support/Claude/scratch-workspaces/")
    }

    func hide(_ session: AgentSession, for length: HideLength) {
        hiddenSessions[session.id] = Hidden(length: length, since: Date())
        save()
    }

    func hideFolder(of session: AgentSession) {
        hiddenFolders.insert(session.place.root.path)
        save()
    }

    func showFolder(_ path: String) {
        hiddenFolders.remove(path)
        save()
    }

    func setMuted(_ muted: Bool, folder path: String) {
        if muted { mutedFolders.insert(path) } else { mutedFolders.remove(path) }
        save()
    }

    func setCountsForKeepAwake(_ counts: Bool, _ session: AgentSession) {
        if counts { notKeepingAwake.remove(session.id) } else { notKeepingAwake.insert(session.id) }
    }

    /// Forgets hidden sessions that are gone.
    func forget(except live: Set<String>) {
        let kept = hiddenSessions.filter { live.contains($0.key) }
        if kept.count != hiddenSessions.count {
            hiddenSessions = kept
            save()
        }
        notKeepingAwake.formIntersection(live)
    }

    private func save() {
        let saved = Saved(hiddenSessions: hiddenSessions, hiddenFolders: hiddenFolders, mutedFolders: mutedFolders)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
    }
}

import Foundation
import Observation

/// A user-made group: one icon in the menu bar that opens a strip of its
/// member icons, which otherwise stay out of sight.
struct MenuBarGroup: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var symbol: String
    /// `MenuBarItem.key`s, in display order.
    var memberKeys: [String] = []

    static let symbolChoices = [
        "briefcase.fill", "hammer.fill", "shield.lefthalf.filled", "network", "cloud.fill", "folder.fill",
        "star.fill", "bolt.fill", "gearshape.2.fill", "square.grid.2x2.fill", "music.note", "bubble.left.fill",
    ]
}

/// The groups, saved in UserDefaults as JSON.
@MainActor
@Observable
final class GroupStore {
    private(set) var groups: [MenuBarGroup] = []
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaultsKey = "groups"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([MenuBarGroup].self, from: data) {
            groups = saved
        }
    }

    func group(containing key: String) -> MenuBarGroup? {
        groups.first { $0.memberKeys.contains(key) }
    }

    var allMemberKeys: Set<String> { Set(groups.flatMap(\.memberKeys)) }

    @discardableResult
    func create(name: String, symbol: String) -> MenuBarGroup {
        let group = MenuBarGroup(name: name, symbol: symbol)
        groups.append(group)
        save()
        return group
    }

    func update(_ group: MenuBarGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group
        save()
    }

    func delete(_ id: UUID) {
        groups.removeAll { $0.id == id }
        save()
    }

    /// Puts an item in a group (taking it out of any other), before `beforeKey` if given.
    func add(_ key: String, to id: UUID, before beforeKey: String? = nil) {
        removeFromGroups(key, notify: false)
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        var members = groups[index].memberKeys
        if let beforeKey, let position = members.firstIndex(of: beforeKey) {
            members.insert(key, at: position)
        } else {
            members.append(key)
        }
        groups[index].memberKeys = members
        save()
    }

    func removeFromGroups(_ key: String, notify: Bool = true) {
        for index in groups.indices { groups[index].memberKeys.removeAll { $0 == key } }
        if notify { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(groups) {
            defaults.set(data, forKey: defaultsKey)
        }
        onChange?()
    }
}

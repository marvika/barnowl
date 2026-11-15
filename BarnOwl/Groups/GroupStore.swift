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
    /// Text or an emoji to show instead of the symbol.
    var label: String?
    /// A custom icon for one app: clicking opens that icon's menu directly
    /// instead of a strip.
    var opensDirectly = false

    init(id: UUID = UUID(), name: String, symbol: String, memberKeys: [String] = [], label: String? = nil,
         opensDirectly: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.memberKeys = memberKeys
        self.label = label
        self.opensDirectly = opensDirectly
    }

    /// Groups saved by older versions lack the newer fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        memberKeys = try container.decodeIfPresent([String].self, forKey: .memberKeys) ?? []
        label = try container.decodeIfPresent(String.self, forKey: .label)
        opensDirectly = try container.decodeIfPresent(Bool.self, forKey: .opensDirectly) ?? false
    }

    /// The apps with an icon in the group. macOS 27 hides an app's icons
    /// together, so there the whole app belongs to the group.
    var memberApps: Set<String> { Set(memberKeys.map(AppRows.app(ofKey:))) }

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

    /// The group an icon is in. On macOS 27 that's the group its app has any
    /// icon in, whichever icon was put there.
    func group(containing item: MenuBarItem) -> MenuBarGroup? {
        guard MenuBarPlatform.hidesByApp, let app = item.bundleIdentifier else { return group(containing: item.key) }
        return groups.first { $0.memberApps.contains(app) }
    }

    var allMemberApps: Set<String> { Set(groups.flatMap(\.memberApps)) }

    /// The group's icons among `items`, in the group's order.
    func members(of group: MenuBarGroup, among items: [MenuBarItem]) -> [MenuBarItem] {
        guard MenuBarPlatform.hidesByApp else {
            let byKey = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            return group.memberKeys.compactMap { byKey[$0] }
        }
        let apps = group.memberKeys.map(AppRows.app(ofKey:))
        return items.filter { $0.bundleIdentifier.map(apps.contains) ?? false }
            .sorted { (apps.firstIndex(of: $0.bundleIdentifier ?? "") ?? 0) < (apps.firstIndex(of: $1.bundleIdentifier ?? "") ?? 0) }
    }

    /// Takes every icon of an app out of its group.
    func removeApp(_ app: String, notify: Bool = true) {
        guard allMemberApps.contains(app) else { return }
        for index in groups.indices { groups[index].memberKeys.removeAll { AppRows.app(ofKey: $0) == app } }
        if notify { save() }
    }

    @discardableResult
    func create(name: String, symbol: String, label: String? = nil, opensDirectly: Bool = false) -> MenuBarGroup {
        let group = MenuBarGroup(name: name, symbol: symbol, label: label, opensDirectly: opensDirectly)
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

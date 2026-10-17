import AppKit
import Observation

enum LayoutRow: Hashable, Sendable {
    case visible
    case hidden
    case alwaysHidden
    case group(UUID)
}

/// Turns "put this icon there" into ⌘-drags, for the layout editor, the
/// Barkeep Bar's context menu and first-run defaults.
@MainActor
@Observable
final class LayoutController {
    private(set) var isBusy = false
    private(set) var lastError: String?

    @ObservationIgnored private let scanner: ItemScanner
    @ObservationIgnored private let mover: ItemMover
    @ObservationIgnored private let statusItems: StatusItems
    @ObservationIgnored private let sections: SectionController
    @ObservationIgnored private let groups: GroupStore

    init(scanner: ItemScanner, mover: ItemMover, statusItems: StatusItems, sections: SectionController,
         groups: GroupStore) {
        self.scanner = scanner
        self.mover = mover
        self.statusItems = statusItems
        self.sections = sections
        self.groups = groups
    }

    /// The items in each row, in menu bar order (groups in their own order).
    func items(in row: LayoutRow) -> [MenuBarItem] {
        let members = groups.allMemberKeys
        switch row {
        case .visible:
            return scanner.items.filter { $0.section == .visible && !members.contains($0.key) }
        case .hidden:
            return scanner.items.filter { $0.section == .hidden && !members.contains($0.key) }
        case .alwaysHidden:
            return scanner.items.filter { $0.section == .alwaysHidden && !members.contains($0.key) }
        case .group(let id):
            guard let group = groups.groups.first(where: { $0.id == id }) else { return [] }
            let byKey = Dictionary(scanner.items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            return group.memberKeys.compactMap { byKey[$0] }
        }
    }

    func row(of item: MenuBarItem) -> LayoutRow {
        if let group = groups.group(containing: item.key) { return .group(group.id) }
        switch item.section {
        case .visible: return .visible
        case .hidden: return .hidden
        case .alwaysHidden: return .alwaysHidden
        }
    }

    /// Moves an icon into a row, before another icon if given (else at the
    /// row's end, nearest the arrow).
    func place(_ key: String, in row: LayoutRow, before beforeKey: String? = nil) async {
        guard let item = scanner.items.first(where: { $0.key == key }) else { return }
        guard item.isMovable else {
            lastError = "\(item.name) can't be moved; macOS keeps it in place."
            return
        }
        isBusy = true
        lastError = nil
        defer {
            isBusy = false
            scanner.updateFrames()
        }

        if case .group(let id) = row {
            groups.add(key, to: id, before: beforeKey)
        } else {
            groups.removeFromGroups(key)
        }
        guard let destination = await destination(for: row, before: beforeKey, moving: item) else {
            lastError = "Couldn't find where to put \(item.name)."
            return
        }
        if !(await mover.move(item.windowID, to: destination)) {
            lastError = "Couldn't move \(item.name). Try again, or ⌘-drag it in the menu bar."
        }
    }

    private func destination(for row: LayoutRow, before beforeKey: String?,
                             moving item: MenuBarItem) async -> MoveDestination? {
        // Grouped icons live in the always-hidden section, so it has to exist.
        if case .group = row { await ensureAlwaysHiddenSection() }
        if case .alwaysHidden = row { await ensureAlwaysHiddenSection() }

        if let beforeKey, beforeKey != item.key,
           let target = scanner.items.first(where: { $0.key == beforeKey }) {
            return .leftOf(target.windowID)
        }
        // The ⌘-drag's mouse-down lands on the arrow, so "left of the arrow"
        // is unreliable (macOS reserves the lifted item's slot right there).
        // The visible section starts right of the | divider instead.
        switch row {
        case .visible: return StatusItems.windowID(of: statusItems.separator).map { .rightOf($0) }
        case .hidden: return StatusItems.windowID(of: statusItems.separator).map { .leftOf($0) }
        case .alwaysHidden, .group: return StatusItems.windowID(of: statusItems.alwaysHidden).map { .leftOf($0) }
        }
    }

    private func ensureAlwaysHiddenSection() async {
        guard !Preferences.alwaysHiddenEnabled else { return }
        UserDefaults.standard.set(true, forKey: PrefKey.alwaysHiddenEnabled)
        _ = statusItems.ensureAlwaysHiddenItem()
        sections.refresh()
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// First run: keep Battery and Wi‑Fi in the menu bar, since most people
    /// want to see them. Everything else starts hidden.
    func applyFirstRunDefaults() async {
        let flag = "appliedDefaultLayout"
        guard !UserDefaults.standard.bool(forKey: flag), AccessibilityInventory.isTrusted,
              !scanner.items.isEmpty else { return }
        // macOS spells Wi‑Fi with a non-breaking hyphen.
        let wanted = ["battery", "wi-fi"]
        func normalized(_ name: String) -> String { name.replacingOccurrences(of: "\u{2011}", with: "-").lowercased() }
        for item in scanner.items where item.isSystem && item.section != .visible
            && wanted.contains(normalized(item.name)) {
            await place(item.key, in: .visible)
        }
        UserDefaults.standard.set(true, forKey: flag)
    }
}

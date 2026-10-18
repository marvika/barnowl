import AppKit
import Observation

enum LayoutRow: Hashable, Sendable {
    case visible
    case hidden
    case alwaysHidden
    case group(UUID)

    /// For saving: "visible", "hidden", "alwaysHidden" or "group:<id>".
    var storageValue: String {
        switch self {
        case .visible: "visible"
        case .hidden: "hidden"
        case .alwaysHidden: "alwaysHidden"
        case .group(let id): "group:\(id.uuidString)"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "visible": self = .visible
        case "hidden": self = .hidden
        case "alwaysHidden": self = .alwaysHidden
        default:
            guard storageValue.hasPrefix("group:"), let id = UUID(uuidString: String(storageValue.dropFirst(6)))
            else { return nil }
            self = .group(id)
        }
    }

    init(_ section: MenuBarSection) {
        switch section {
        case .visible: self = .visible
        case .hidden: self = .hidden
        case .alwaysHidden: self = .alwaysHidden
        }
    }
}

enum DisplayProfile: String, Sendable {
    case single
    case laptop
    case desk

    var storageKey: String {
        self == .single ? "itemRows" : "itemRows.\(rawValue)"
    }

    var title: String {
        switch self {
        case .single: "Your layout"
        case .laptop: "Laptop layout"
        case .desk: "Desk layout"
        }
    }

    static func current(enabled: Bool, hasExternalDisplay: Bool) -> DisplayProfile {
        guard enabled else { return .single }
        return hasExternalDisplay ? .desk : .laptop
    }
}

/// Stops the keeper from correcting the same icon over and over. Each
/// correction is a ⌘-drag that briefly takes the pointer, so a disagreement
/// between what Barn Owl reads and what it does must never become a loop.
struct CorrectionLimiter: Sendable {
    var limit = 2
    var window: TimeInterval = 120
    private var history: [String: [Date]] = [:]

    init(limit: Int = 2, window: TimeInterval = 120) {
        self.limit = limit
        self.window = window
    }

    /// Whether another correction of `key` is allowed now; records it if so.
    mutating func allow(_ key: String, now: Date = Date()) -> Bool {
        let recent = (history[key] ?? []).filter { now.timeIntervalSince($0) < window }
        guard recent.count < limit else {
            history[key] = recent
            return false
        }
        history[key] = recent + [now]
        return true
    }

    /// The user moved it on purpose: start counting afresh.
    mutating func reset(_ key: String) {
        history[key] = nil
    }
}

/// Where new icons go when an app adds one Barn Owl hasn't seen before.
enum NewIconPlacement: String, CaseIterable, Identifiable, Sendable {
    case hidden
    case visible
    var id: Self { self }
}

/// Decides what to do with each icon after a scan, so icons stay where the
/// user put them. Pure, so it can be tested.
enum LayoutKeeper {
    struct Decision: Equatable {
        let key: String
        let row: LayoutRow
    }

    /// - `remembered`: each key's saved row.
    /// - `lastWindowIDs`: each key's window at the previous scan; a different
    ///   window means the app re-added the icon (often after a relaunch), and
    ///   macOS put it wherever it liked.
    /// - `hasBaseline`: false on the very first scan, which only records.
    ///
    /// Returns the moves to make and the updated memory.
    static func reconcile(items: [(key: String, windowID: CGWindowID, row: LayoutRow, movable: Bool)],
                          groupOf: (String) -> UUID?,
                          remembered: [String: LayoutRow], lastWindowIDs: [String: CGWindowID],
                          hasBaseline: Bool, newIcons: NewIconPlacement)
        -> (moves: [Decision], remembered: [String: LayoutRow]) {
        var memory = remembered
        var moves: [Decision] = []
        for item in items where item.movable {
            if let group = groupOf(item.key) {
                // Grouped icons wait in the always-hidden section.
                if item.row != .alwaysHidden { moves.append(Decision(key: item.key, row: .group(group))) }
                memory[item.key] = .group(group)
                continue
            }
            let isNewWindow = lastWindowIDs[item.key] != item.windowID
            if let saved = memory[item.key], saved != item.row {
                if case .group = saved {
                    // Its group is gone: it stays where it is.
                    memory[item.key] = item.row
                } else if isNewWindow {
                    moves.append(Decision(key: item.key, row: saved))
                } else {
                    // Same window, new place: the user ⌘-dragged it. Keep that.
                    memory[item.key] = item.row
                }
            } else if memory[item.key] == nil {
                if hasBaseline, isNewWindow, newIcons == .hidden, item.row == .visible {
                    moves.append(Decision(key: item.key, row: .hidden))
                    memory[item.key] = .hidden
                } else {
                    memory[item.key] = item.row
                }
            }
        }
        return (moves, memory)
    }
}

/// Turns "put this icon there" into ⌘-drags, for the layout editor, the
/// Perch's context menu and first-run defaults.
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
    @ObservationIgnored var images: ItemImageCache?
    @ObservationIgnored private var lastWindowIDs: [String: CGWindowID] = [:]
    @ObservationIgnored private var hasBaseline = false
    @ObservationIgnored private var isReconciling = false
    @ObservationIgnored private var limiter = CorrectionLimiter()
    /// Which layout is in use: one for everything, or with display profiles
    /// on, one for the laptop screen alone and one for a desk with an
    /// external display.
    private(set) var profile: DisplayProfile = .single

    private var memoryKey: String { profile.storageKey }

    private var remembered: [String: LayoutRow] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: memoryKey) as? [String: String] ?? [:]
            return raw.compactMapValues(LayoutRow.init(storageValue:))
        }
        set {
            UserDefaults.standard.set(newValue.mapValues(\.storageValue), forKey: memoryKey)
        }
    }

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
    func place(_ key: String, in row: LayoutRow, before beforeKey: String? = nil, isCorrection: Bool = false) async {
        guard !DemoMode.isOn else { return }
        if !isCorrection { limiter.reset(key) }
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
        remembered[key] = row
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

    /// After a scan: put back icons that reappeared in the wrong place, send
    /// new icons where the user wants them, and learn from the user's own
    /// ⌘-drags. Skipped while Barn Owl itself is moving things.
    func reconcile() async {
        guard !DemoMode.isOn else { return }
        guard !isBusy, !isReconciling, !isPaused(), !sections.holdOpen, sections.state == .collapsed,
              !scanner.items.isEmpty else { return }
        isReconciling = true
        defer { isReconciling = false }
        let skipped = temporarilyMoved()
        let snapshot = scanner.items.filter { !skipped.contains($0.key) }.map {
            (key: $0.key, windowID: $0.windowID, row: LayoutRow($0.section), movable: $0.isMovable)
        }
        let result = LayoutKeeper.reconcile(items: snapshot, groupOf: { self.groups.group(containing: $0)?.id },
                                            remembered: remembered, lastWindowIDs: lastWindowIDs,
                                            hasBaseline: hasBaseline, newIcons: Preferences.newIconPlacement)
        remembered = result.remembered
        lastWindowIDs = Dictionary(snapshot.map { ($0.key, $0.windowID) }, uniquingKeysWith: { a, _ in a })
        hasBaseline = true
        for move in result.moves {
            guard limiter.allow(move.key) else {
                Log.menuBar.error("Gave up keeping \(move.key, privacy: .public) in \(move.row.storageValue, privacy: .public): it didn't stay there")
                continue
            }
            Log.menuBar.info("Keeping \(move.key, privacy: .public) in \(move.row.storageValue, privacy: .public)")
            await place(move.key, in: move.row, isCorrection: true)
        }
    }

    /// Icons hidden behind the notch or off screen can't be photographed. This
    /// moves each one without a picture into view for a moment, captures it
    /// and puts it back.
    func refreshMissingPictures() async {
        guard let images, ItemImageCache.hasPermission, !isBusy,
              let divider = StatusItems.windowID(of: statusItems.separator) else { return }
        let missing = scanner.items.filter { $0.isMovable && !images.hasFreshImage(for: $0) }
        guard !missing.isEmpty else { return }
        isBusy = true
        defer {
            isBusy = false
            scanner.updateFrames()
        }
        for item in missing {
            let frames = ItemMover.frames()
            let start = frames[item.windowID] ?? item.frame
            let neighbor = frames.filter { $0.key != item.windowID && $0.value.minX >= start.maxX - 1 }
                .min { $0.value.minX < $1.value.minX }?.key
            guard await mover.move(item.windowID, to: .rightOf(divider)) else { continue }
            scanner.updateFrames()
            if let moved = scanner.items.first(where: { $0.windowID == item.windowID }) {
                await images.capture([moved], pruning: false)
            }
            if let neighbor { await mover.move(item.windowID, to: .leftOf(neighbor)) }
        }
        Log.menuBar.info("Refreshed pictures of \(missing.count) icons")
    }

    private func ensureAlwaysHiddenSection() async {
        guard !Preferences.alwaysHiddenEnabled else { return }
        UserDefaults.standard.set(true, forKey: PrefKey.alwaysHiddenEnabled)
        _ = statusItems.ensureAlwaysHiddenItem()
        sections.refresh()
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// Keys the keeper should leave alone for now (icons shown because they
    /// changed, or hidden for presenting).
    @ObservationIgnored var temporarilyMoved: () -> Set<String> = { [] }
    /// While presenting, nothing is rearranged in the background.
    @ObservationIgnored var isPaused: () -> Bool = { false }

    /// Moves an icon back to its saved row without changing anything saved.
    func returnToRow(_ key: String) async {
        guard let item = scanner.items.first(where: { $0.key == key }) else { return }
        let row = groups.group(containing: key).map { LayoutRow.group($0.id) } ?? remembered[key] ?? .hidden
        guard let destination = await destination(for: row, before: nil, moving: item) else { return }
        await mover.move(item.windowID, to: destination)
        scanner.updateFrames()
    }

    /// Picks the layout for the displays connected now, and if that changed,
    /// moves every icon to where that layout has it.
    func updateProfile() async {
        let next = DisplayProfile.current(enabled: Preferences.displayProfiles,
                                          hasExternalDisplay: SystemConditions.hasExternalDisplay)
        guard next != profile else { return }
        let previous = profile
        profile = next
        // A profile used for the first time starts as a copy of the current layout.
        let defaults = UserDefaults.standard
        if defaults.dictionary(forKey: next.storageKey) == nil {
            defaults.set(defaults.dictionary(forKey: previous.storageKey) ?? [:], forKey: next.storageKey)
        }
        Log.menuBar.info("Display profile: \(next.rawValue)")
        // While presenting, icons stay hidden; presenting ends with a reconcile
        // that puts them where this profile wants them.
        guard !isPaused() else { return }
        await applyRemembered()
    }

    /// Moves every icon that isn't where the current layout wants it.
    private func applyRemembered() async {
        let skipped = temporarilyMoved()
        let memory = remembered
        for item in scanner.items where item.isMovable && !skipped.contains(item.key) {
            if groups.group(containing: item.key) != nil {
                if item.section != .alwaysHidden { await returnToRow(item.key) }
                continue
            }
            guard let wanted = memory[item.key], wanted != LayoutRow(item.section) else { continue }
            await returnToRow(item.key)
        }
        lastWindowIDs = Dictionary(scanner.items.map { ($0.key, $0.windowID) }, uniquingKeysWith: { a, _ in a })
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

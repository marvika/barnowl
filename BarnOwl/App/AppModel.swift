import AppKit
import Observation

/// What the SwiftUI windows and panels need from the controllers.
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let sections: SectionController
    @ObservationIgnored let keepAwake: KeepAwakeController
    let scanner: ItemScanner
    let images: ItemImageCache
    @ObservationIgnored let opener: ItemOpener
    @ObservationIgnored let mover: ItemMover
    let groups: GroupStore
    let layout: LayoutController
    let watcher: ChangeWatcher
    let presenter: PresenterMode
    let appearance = MenuBarAppearance()
    let clipboard = ClipboardHistory()
    let updater = Updater()
    /// Keeps closed-lid mode in step with keep awake; Settings asks it to
    /// catch up when the setting changes.
    @ObservationIgnored var closedLid: ClosedLidController?
    let barn = BarnModel()
    /// The coding agents on this Mac, as owlets.
    let agents = AgentWatcher()
    /// Screenshots and markup.
    @ObservationIgnored let capture: CaptureCoordinator
    @ObservationIgnored var showBarn: () -> Void = {}
    /// Opens the Roost, showing one session if given.
    @ObservationIgnored var showRoost: (String?) -> Void = { _ in }
    /// Opens the tree in its own window.
    @ObservationIgnored var showTree: () -> Void = {}
    /// Opens the week's recap card.
    @ObservationIgnored var showRecap: (WeekSummary) -> Void = { _ in }
    @ObservationIgnored var showSetup: () -> Void = {}
    /// Opens the setup guide at its Capture step.
    @ObservationIgnored var showCaptureSetup: () -> Void = {}
    @ObservationIgnored var openSettingsWindow: () -> Void = {}
    @ObservationIgnored var showSearch: () -> Void = {}
    @ObservationIgnored var syncGroupIcons: () -> Void = {}
    @ObservationIgnored var groupIconWindow: (UUID) -> CGWindowID? = { _ in nil }

    /// The icon whose "Replace Icon…" sheet is open in Settings → Layout.
    var iconToReplace: MenuBarItem? {
        didSet { if iconToReplace != nil { showSettings(.layout) } }
    }

    /// The Settings pane showing; set before opening the window to jump to one.
    var settingsPane: SettingsPane? = .general

    /// Mirrors SectionController.state so views can react to it.
    var sectionState: SectionState = .expanded
    private(set) var accessibilityTrusted = AccessibilityInventory.isTrusted
    private(set) var screenRecordingAllowed = ItemImageCache.hasPermission

    init(sections: SectionController, keepAwake: KeepAwakeController, scanner: ItemScanner, images: ItemImageCache,
         mover: ItemMover, groups: GroupStore) {
        self.sections = sections
        self.keepAwake = keepAwake
        self.scanner = scanner
        self.images = images
        self.mover = mover
        self.groups = groups
        opener = ItemOpener(sections: sections, mover: mover)
        capture = CaptureCoordinator(scanner: scanner)
        layout = LayoutController(scanner: scanner, mover: mover, statusItems: sections.items, sections: sections,
                                  groups: groups)
        layout.images = images
        watcher = ChangeWatcher(scanner: scanner, layout: layout, mover: mover, images: images,
                                statusItems: sections.items)
        presenter = PresenterMode(sections: sections, keepAwake: keepAwake, images: images, scanner: scanner,
                                  mover: mover, layout: layout)
        layout.temporarilyMoved = { [watcher] in Set(watcher.surfaced.keys) }
        layout.isPaused = { [presenter] in presenter.isPresenting || presenter.isChanging }
        watcher.isPaused = { [presenter] in presenter.isPresenting || presenter.isChanging }
    }

    @ObservationIgnored var showClipboard: () -> Void = {}

    func perform(_ command: AppCommand) {
        switch command {
        case .keepAwake(let minutes): keepAwake.start(minutes: minutes)
        case .extendKeepAwake(let minutes): keepAwake.extend(minutes: minutes)
        case .stopKeepAwake: keepAwake.stop()
        case .presenter: Task { await presenter.toggle() }
        case .darkMode: QuickToggles.toggleDarkMode()
        case .microphone: QuickToggles.toggleMicrophone()
        case .desktopIcons: QuickToggles.toggleDesktopIcons()
        case .hiddenFiles: QuickToggles.toggleHiddenFiles()
        case .sleepDisplay: QuickToggles.sleepDisplay()
        case .clipboard: showClipboard()
        case .barn: showBarn()
        case .roost: showRoost(nil)
        case .showAllIcons: sections.showAll()
        case .captureArea: capture.start(.area)
        case .captureScreen: capture.captureScreen()
        case .captureSameArea: capture.captureSameArea()
        case .editLastCapture: capture.editLastCapture()
        case .captureText: capture.captureText()
        case .settings(let pane): showSettings(SettingsPane(rawValue: pane.rawValue))
        }
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        openSettingsWindow()
    }

    /// Replaces an app's icon with one of your choosing: a one-icon group that
    /// opens the real icon's menu directly.
    func setCustomIcon(for item: MenuBarItem, symbol: String, label: String?) async {
        let label = label?.trimmingCharacters(in: .whitespaces)
        if let existing = groups.group(containing: item.key), existing.opensDirectly {
            var changed = existing
            changed.symbol = symbol
            changed.label = (label?.isEmpty ?? true) ? nil : label
            groups.update(changed)
            return
        }
        let group = await createGroup(name: item.name, symbol: symbol,
                                      label: (label?.isEmpty ?? true) ? nil : label, opensDirectly: true)
        await layout.place(item.key, in: .group(group.id))
    }

    /// Adds the group and puts its icon in the menu bar, next to the arrow.
    @discardableResult
    func createGroup(name: String, symbol: String, label: String? = nil, opensDirectly: Bool = false) async
        -> MenuBarGroup {
        let group = groups.create(name: name, symbol: symbol, label: label, opensDirectly: opensDirectly)
        syncGroupIcons()
        // A new status item appears at the far left, usually in a hidden
        // section; bring it next to the arrow.
        try? await Task.sleep(for: .milliseconds(400))
        if let window = groupIconWindow(group.id), let divider = StatusItems.windowID(of: sections.items.separator) {
            await mover.move(window, to: .rightOf(divider))
        }
        return group
    }

    /// Removes the group; its icons go back to the hidden section.
    func deleteGroup(_ id: UUID) async {
        let members = groups.groups.first { $0.id == id }?.memberKeys ?? []
        groups.delete(id)
        syncGroupIcons()
        for key in members {
            await layout.place(key, in: .hidden)
        }
    }

    var engineName: String { sections.engine.displayName }
    var engineNeedsAccessibility: Bool { sections.engine.needsAccessibility }

    func refreshPermissions() {
        let wasTrusted = accessibilityTrusted
        accessibilityTrusted = DemoMode.isOn || AccessibilityInventory.isTrusted
        screenRecordingAllowed = DemoMode.isOn || ItemImageCache.hasPermission
        if accessibilityTrusted && !wasTrusted { scanner.refresh() }
    }

    /// Shows every icon and keeps them up so the user can ⌘-drag them.
    func beginArranging() {
        sections.holdOpen = true
        sections.showAll()
    }

    func endArranging(collapse: Bool) {
        sections.holdOpen = false
        if collapse { sections.collapse() }
    }

    /// Whether the arrow should open the Perch rather than reveal the
    /// hidden icons in the menu bar.
    var hiddenIconsUseBar: Bool {
        let setting = Preferences.hiddenIconsDisplay
        // Without Accessibility the bar can't list anything, so only use it
        // when asked for explicitly (it then explains what it needs).
        guard accessibilityTrusted, !scanner.items.isEmpty else { return setting == .perch }
        let screen = NSScreen.screens.first
        let available: CGFloat
        if let area = screen?.auxiliaryTopRightArea {
            available = area.width
        } else {
            // No notch: assume the app's menus take about half the bar.
            available = (screen?.frame.width ?? 1440) * 0.5
        }
        let width = { (items: [MenuBarItem]) in items.map(\.frame.width).reduce(0, +) }
        let visible = width(scanner.items.filter { $0.section == .visible }) + 60
        let hidden = width(scanner.items.filter { $0.section == .hidden })
        return HiddenIconsDisplay.usesBar(setting, visibleWidth: visible, hiddenWidth: hidden, availableWidth: available)
    }
}

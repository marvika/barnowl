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
    @ObservationIgnored var showSetup: () -> Void = {}
    @ObservationIgnored var showSettings: () -> Void = {}
    @ObservationIgnored var showSearch: () -> Void = {}

    /// Mirrors SectionController.state so views can react to it.
    var sectionState: SectionState = .expanded
    private(set) var accessibilityTrusted = AccessibilityInventory.isTrusted
    private(set) var screenRecordingAllowed = ItemImageCache.hasPermission

    init(sections: SectionController, keepAwake: KeepAwakeController, scanner: ItemScanner, images: ItemImageCache,
         opener: ItemOpener) {
        self.sections = sections
        self.keepAwake = keepAwake
        self.scanner = scanner
        self.images = images
        self.opener = opener
    }

    var engineName: String { sections.engine.displayName }
    var engineNeedsAccessibility: Bool { sections.engine.needsAccessibility }

    func refreshPermissions() {
        let wasTrusted = accessibilityTrusted
        accessibilityTrusted = AccessibilityInventory.isTrusted
        screenRecordingAllowed = ItemImageCache.hasPermission
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

    /// Whether the arrow should open the Barkeep Bar rather than reveal the
    /// hidden icons in the menu bar.
    var hiddenIconsUseBar: Bool {
        let setting = Preferences.hiddenIconsDisplay
        // Without Accessibility the bar can't list anything, so only use it
        // when asked for explicitly (it then explains what it needs).
        guard accessibilityTrusted, !scanner.items.isEmpty else { return setting == .barkeepBar }
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

import AppKit

/// macOS 26 and earlier: widen a divider until everything left of it is pushed
/// past the left edge of the screen. Needs no permissions.
@MainActor
final class LengthEngine: HidingEngine {
    let displayName = "Divider width (macOS 26)"
    let needsAccessibility = false

    private let items: StatusItems

    init(items: StatusItems) {
        self.items = items
    }

    /// Wide enough to cover the widest display. The menu bar is replicated on
    /// every display, so the main screen isn't enough. macOS caps status item
    /// windows at about 5,000 pt on 26.
    private var collapsedLength: CGFloat {
        let widest = NSScreen.screens.map(\.frame.width).max() ?? 1728
        return min(max(widest + 200, 800), 5000)
    }

    func apply(_ state: SectionState, alwaysHiddenEnabled: Bool) async -> Bool {
        let alwaysHidden = alwaysHiddenEnabled ? items.ensureAlwaysHiddenItem() : items.alwaysHidden
        // A display may have been added since presenting began.
        items.curtain?.length = collapsedLength
        switch state {
        case .collapsed:
            items.separator.length = collapsedLength
            items.setDividerVisible(items.separator, false)
            alwaysHidden?.length = alwaysHiddenEnabled ? StatusItems.dividerLength : 0
        case .expanded:
            items.separator.length = StatusItems.dividerLength
            items.setDividerVisible(items.separator, true)
            if let alwaysHidden {
                alwaysHidden.length = alwaysHiddenEnabled ? collapsedLength : 0
                items.setDividerVisible(alwaysHidden, false)
            }
        case .expandedAll:
            items.separator.length = StatusItems.dividerLength
            items.setDividerVisible(items.separator, true)
            if let alwaysHidden {
                alwaysHidden.length = alwaysHiddenEnabled ? StatusItems.dividerLength : 0
                items.setDividerVisible(alwaysHidden, alwaysHiddenEnabled)
            }
        }
        return true
    }

    func invalidateLayout() {
        // Lengths are recomputed from the current screens on the next apply.
    }

    /// A divider can only hide what's left of it, so presenting widens a
    /// curtain placed right of every icon, just left of the arrow. If it can't
    /// be placed there, presenting moves the icons instead. Ending always
    /// reports false, so icons moved that way are put back.
    func setPresenting(_ presenting: Bool) async -> Bool {
        guard presenting else {
            items.lowerCurtain()
            return false
        }
        guard items.raiseCurtain(length: collapsedLength) else { return false }
        // The menu bar lays out on its next pass.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if items.curtainIsLeftOfArrow { return true }
        }
        Log.menuBar.error("Presenter curtain didn't land left of the arrow; moving icons instead")
        items.lowerCurtain()
        return false
    }
}

import AppKit

/// Owns Barkeep's own status items: the toggle and the two dividers.
/// Engines change their lengths but never create or remove them.
@MainActor
final class StatusItems {
    static let dividerLength: CGFloat = 14

    let toggle: NSStatusItem
    let separator: NSStatusItem
    private(set) var alwaysHidden: NSStatusItem?

    static let toggleName = "BarkeepToggle"
    static let separatorName = "BarkeepSeparator"
    static let alwaysHiddenName = "BarkeepAlwaysHidden"

    init() {
        Self.seedPositions()
        // Earlier-created items sit further right, so this order gives
        // [⋮][|][toggle]. The autosave names make macOS remember where the user
        // ⌘-drags them afterwards.
        toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggle.autosaveName = Self.toggleName
        separator = NSStatusBar.system.statusItem(withLength: Self.dividerLength)
        separator.autosaveName = Self.separatorName
        configureDivider(separator, symbol: "line.diagonal", label: "Barkeep divider")
    }

    /// On a busy notched Mac, a new item lands left of every other icon, which
    /// is often behind the notch, leaving the arrow unreachable. On macOS 26 a
    /// Preferred Position (smaller is further right) seeded before the item is
    /// created puts the arrow next to Control Center instead. Every existing
    /// icon then starts in the hidden section, and the user ⌘-drags the ones
    /// they want back to the right of "|". Written only once, so the user's own
    /// arrangement wins afterwards. macOS 27 ignores these keys.
    /// Seed values from Frost (MIT).
    private static func seedPositions() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 else { return }
        let seeds: [(String, Double)] = [(toggleName, 0), (separatorName, 1), (alwaysHiddenName, 10_000)]
        let defaults = UserDefaults.standard
        for (name, position) in seeds {
            let key = "NSStatusItem Preferred Position \(name)"
            if defaults.object(forKey: key) == nil {
                defaults.set(position, forKey: key)
            }
        }
    }

    /// Created lazily so people who never use the section don't get a gap for it.
    func ensureAlwaysHiddenItem() -> NSStatusItem {
        if let alwaysHidden { return alwaysHidden }
        let item = NSStatusBar.system.statusItem(withLength: Self.dividerLength)
        item.autosaveName = Self.alwaysHiddenName
        configureDivider(item, symbol: "ellipsis", label: "Barkeep always-hidden divider")
        item.button?.image?.isTemplate = true
        alwaysHidden = item
        return item
    }

    func setDividerVisible(_ item: NSStatusItem, _ visible: Bool) {
        item.button?.alphaValue = visible ? 0.55 : 0
    }

    private func configureDivider(_ item: NSStatusItem, symbol: String, label: String) {
        guard let button = item.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
        if symbol == "ellipsis" {
            button.image = button.image.map { $0.rotated90() }
        }
        button.alphaValue = 0.55
        button.toolTip = "⌘-drag icons to the left of this divider to hide them."
    }

    /// The x range of an item's window in screen coordinates, if it's on screen.
    static func frame(of item: NSStatusItem?) -> CGRect? {
        guard let window = item?.button?.window, window.screen != nil else { return nil }
        return window.frame
    }
}

private extension NSImage {
    func rotated90() -> NSImage {
        let rotated = NSImage(size: NSSize(width: size.height, height: size.width), flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.width / 2, yBy: rect.height / 2)
            transform.rotate(byDegrees: 90)
            transform.translateX(by: -self.size.width / 2, yBy: -self.size.height / 2)
            transform.concat()
            self.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        rotated.isTemplate = isTemplate
        return rotated
    }
}

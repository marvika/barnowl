import AppKit

/// Owns Barn Owl's own status items: the toggle and the two dividers.
/// Engines change their lengths but never create or remove them.
@MainActor
final class StatusItems {
    static let dividerLength: CGFloat = 14

    let toggle: NSStatusItem
    let separator: NSStatusItem
    private(set) var alwaysHidden: NSStatusItem?

    static let toggleName = "BarnOwlToggle"
    static let separatorName = "BarnOwlSeparator"
    static let alwaysHiddenName = "BarnOwlAlwaysHidden"
    static let curtainName = "BarnOwlPresenterCurtain"

    /// While presenting on macOS 26: an invisible item right next to the arrow.
    private(set) var curtain: NSStatusItem?

    init() {
        Self.seedPositions()
        // Earlier-created items sit further right, so this order gives
        // [⋮][|][toggle]. The autosave names make macOS remember where the user
        // ⌘-drags them afterwards.
        toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggle.autosaveName = Self.toggleName
        separator = NSStatusBar.system.statusItem(withLength: Self.dividerLength)
        separator.autosaveName = Self.separatorName
        configureDivider(separator, symbol: "line.diagonal", label: "Barn Owl divider")
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

    /// Seeds a new item of Barn Owl's own (a group's icon) between the arrow and
    /// the "|" divider, where it shows, rather than left of everything and
    /// perhaps behind the notch. Only before the item first appears.
    static func seedVisiblePosition(for name: String) {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 else { return }
        let defaults = UserDefaults.standard
        let key = "NSStatusItem Preferred Position \(name)"
        guard defaults.object(forKey: key) == nil else { return }
        let toggle = defaults.double(forKey: "NSStatusItem Preferred Position \(toggleName)")
        let separator = defaults.object(forKey: "NSStatusItem Preferred Position \(separatorName)") as? Double
        defaults.set(separator.map { (toggle + $0) / 2 } ?? toggle + 0.5, forKey: key)
    }

    /// Hides every icon left of the arrow at once, for presenting: an invisible
    /// item is made directly left of the arrow and widened, pushing everything
    /// past it off screen, the way the "|" divider hides its section. Nothing is
    /// dragged, so the pointer stays where it is. Made afresh each time, so it
    /// lands next to the arrow wherever the arrow is now. False if it can't be
    /// placed (no remembered arrow position, or macOS 27, which ignores these).
    func raiseCurtain(length: CGFloat) -> Bool {
        lowerCurtain()
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 else { return false }
        let defaults = UserDefaults.standard
        guard let toggle = defaults.object(forKey: Self.positionKey(Self.toggleName)) as? Double else { return false }
        // Smaller is further right: just left of the arrow, before any other icon.
        defaults.set(toggle + 0.5, forKey: Self.positionKey(Self.curtainName))
        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.autosaveName = Self.curtainName
        item.button?.setAccessibilityElement(false)
        item.length = length
        curtain = item
        return true
    }

    /// Whether the curtain is where it should be: left of the arrow, which is
    /// still on screen.
    var curtainIsLeftOfArrow: Bool {
        guard let arrow = Self.frame(of: toggle), let curtain = Self.layoutFrame(of: curtain) else { return false }
        return curtain.maxX <= arrow.minX + 1
    }

    /// Takes the curtain away, and its remembered place with it.
    func lowerCurtain() {
        guard let item = curtain else { return }
        NSStatusBar.system.removeStatusItem(item)
        curtain = nil
        UserDefaults.standard.removeObject(forKey: Self.positionKey(Self.curtainName))
    }

    private static func positionKey(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    /// Created lazily so people who never use the section don't get a gap for it.
    func ensureAlwaysHiddenItem() -> NSStatusItem {
        if let alwaysHidden { return alwaysHidden }
        let item = NSStatusBar.system.statusItem(withLength: Self.dividerLength)
        item.autosaveName = Self.alwaysHiddenName
        configureDivider(item, symbol: "ellipsis", label: "Barn Owl always-hidden divider")
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

    /// The item's window ID, as CGWindowList and event routing know it.
    ///
    /// On macOS 26 status item windows belong to Control Center, and
    /// `NSWindow.windowNumber` isn't that ID. So the window is looked up in the
    /// window list: by its autosave name (readable with Screen Recording),
    /// else by frame.
    static func windowID(of item: NSStatusItem?) -> CGWindowID? {
        guard let item, let window = item.button?.window, let primary = NSScreen.screens.first else { return nil }
        let windows = ItemScanner.statusWindows(includeWide: true)
        if let name = item.autosaveName, let match = windows.first(where: { $0.name == name }) {
            return match.windowID
        }
        let frame = window.frame
        let cgFrame = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        return windows
            .filter { abs($0.frame.width - cgFrame.width) <= 1 && abs($0.frame.minY - cgFrame.minY) <= 2 }
            .min { abs($0.frame.minX - cgFrame.minX) < abs($1.frame.minX - cgFrame.minX) }
            .flatMap { abs($0.frame.minX - cgFrame.minX) <= 2 ? $0.windowID : nil }
    }

    /// The item's frame in top-left screen coordinates (CGWindowList's).
    static func cgFrame(of item: NSStatusItem?) -> CGRect? {
        guard let frame = frame(of: item), let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The item's window frame even when it's off screen, as when a divider
    /// has been pushed past the left edge. Only x is meaningful for sections.
    static func layoutFrame(of item: NSStatusItem?) -> CGRect? {
        guard let window = item?.button?.window, window.frame.width > 0 else { return nil }
        return window.frame
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

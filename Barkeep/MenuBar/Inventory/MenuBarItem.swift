import AppKit
import ApplicationServices

/// An Accessibility element that can cross threads. AXUIElement is a
/// thread-safe CFType, but Swift doesn't know that.
struct AXElement: @unchecked Sendable, Hashable {
    let raw: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.raw, rhs.raw) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(raw)) }
}

/// Another app's menu bar item, as Barkeep knows it.
struct MenuBarItem: Identifiable, Hashable, Sendable {
    /// The item's window. Stable while its app runs; a relaunch gets a new one.
    let windowID: CGWindowID
    /// Screen frame in global coordinates with a top-left origin (as CGWindowList and Accessibility use).
    var frame: CGRect
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    /// What Accessibility calls the item ("Wi‑Fi, connected", "OneDrive — Contoso"…), if anything.
    let title: String?
    let element: AXElement
    var section: MenuBarSection = .visible
    var isBehindNotch = false

    var id: CGWindowID { windowID }

    /// Items macOS draws itself (clock, Control Center, Wi‑Fi…).
    var isSystem: Bool {
        guard let bundleIdentifier else { return false }
        return MenuBarItem.systemBundles.contains(bundleIdentifier)
    }

    /// What to call the item. System items are all owned by a handful of
    /// processes ("Control Center"), so they go by their title instead
    /// ("Wi‑Fi", "Battery", "Clock").
    var name: String {
        if usesTitleAsName, let first = titleParts.first { return first }
        if bundleIdentifier == "com.apple.TextInputMenuAgent" { return "Input Sources" }
        return appName
    }

    /// Extra detail shown under the name, such as a status.
    var detail: String? {
        if usesTitleAsName {
            let rest = titleParts.dropFirst().joined(separator: ", ")
            return rest.isEmpty ? nil : rest
        }
        guard let title, !title.isEmpty, title != appName else { return nil }
        return title
    }

    /// For tooltips and VoiceOver. Many apps start their title with their own
    /// name ("OneDrive — Contoso"), so it isn't repeated.
    var displayName: String {
        guard let detail else { return name }
        return detail.localizedCaseInsensitiveContains(name) ? detail : "\(name) – \(detail)"
    }

    private var usesTitleAsName: Bool {
        isSystem && !(title ?? "").isEmpty
    }

    private var titleParts: [String] {
        (title ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static let systemBundles: Set<String> = [
        "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.Spotlight", "com.apple.TextInputMenuAgent",
    ]
}

/// A status-level window from CGWindowList.
struct StatusWindow: Equatable, Sendable {
    let windowID: CGWindowID
    let frame: CGRect
}

/// An item as Accessibility reports it, before it's matched to a window.
struct AXMenuBarEntry: Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let title: String?
    let frame: CGRect
    let element: AXElement
}

enum ItemMatcher {
    /// How far apart (in points) a window and an Accessibility frame may be
    /// and still count as the same item.
    static let tolerance: CGFloat = 4

    /// Pairs each window with the Accessibility entry whose horizontal centre
    /// is closest, within `tolerance`. Each entry is used once. On macOS 26
    /// every item window is owned by Control Center, so this is the only way
    /// to tell which app a window belongs to. Windows without a match are left
    /// out: they're usually stale windows of apps that quit.
    static func match<Entry>(windows: [StatusWindow], entries: [Entry],
                             frame: (Entry) -> CGRect) -> [(StatusWindow, Entry)] {
        var available = entries
        var result: [(StatusWindow, Entry)] = []
        for window in windows {
            let candidates = available.indices
                .map { index -> (index: Int, distance: CGFloat, rowDistance: CGFloat) in
                    let entryFrame = frame(available[index])
                    return (index, abs(entryFrame.midX - window.frame.midX), abs(entryFrame.midY - window.frame.midY))
                }
                .filter { $0.distance <= tolerance && $0.rowDistance <= 12 }
            guard let best = candidates.min(by: { $0.distance < $1.distance }) else { continue }
            result.append((window, available.remove(at: best.index)))
        }
        return result
    }
}

enum SectionClassifier {
    /// Which section an item at `midX` is in, given the dividers' left edges.
    static func section(midX: CGFloat, separatorMinX: CGFloat, alwaysHiddenMinX: CGFloat?) -> MenuBarSection {
        if let alwaysHiddenMinX, midX < alwaysHiddenMinX { return .alwaysHidden }
        if midX < separatorMinX { return .hidden }
        return .visible
    }
}

/// The notch's horizontal extent on a screen, if it has one.
struct NotchGeometry: Equatable, Sendable {
    let minX: CGFloat
    let maxX: CGFloat

    /// From NSScreen's auxiliary areas: the strips left and right of the notch.
    init?(screenFrame: CGRect, leftArea: CGRect?, rightArea: CGRect?) {
        guard let leftArea, let rightArea, rightArea.minX > leftArea.maxX else { return nil }
        minX = leftArea.maxX
        maxX = rightArea.minX
        _ = screenFrame
    }

    init(minX: CGFloat, maxX: CGFloat) {
        self.minX = minX
        self.maxX = maxX
    }

    @MainActor
    static func of(_ screen: NSScreen?) -> NotchGeometry? {
        guard let screen else { return nil }
        return NotchGeometry(screenFrame: screen.frame, leftArea: screen.auxiliaryTopLeftArea,
                             rightArea: screen.auxiliaryTopRightArea)
    }

    /// Whether more than a third of the item is hidden by the notch.
    func covers(_ frame: CGRect) -> Bool {
        let overlap = min(frame.maxX, maxX) - max(frame.minX, minX)
        return overlap > frame.width / 3
    }
}

/// Where hidden icons appear when the user asks for them.
enum HiddenIconsDisplay: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case menuBar
    case barkeepBar

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .menuBar: "In the menu bar"
        case .barkeepBar: "In the Barkeep Bar"
        }
    }

    /// Automatic picks the Barkeep Bar when revealing the hidden icons inline
    /// wouldn't fit in the space next to the clock, so nothing ends up behind
    /// the notch or under the app's menus.
    static func usesBar(_ setting: HiddenIconsDisplay, visibleWidth: CGFloat, hiddenWidth: CGFloat,
                        availableWidth: CGFloat) -> Bool {
        switch setting {
        case .menuBar: false
        case .barkeepBar: true
        case .automatic: visibleWidth + hiddenWidth > availableWidth
        }
    }
}

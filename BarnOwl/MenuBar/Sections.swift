import CoreGraphics

/// What the user sees. The divider items split the bar into three sections:
///
///     [always hidden] ⋮ [hidden] | [visible]  <toggle>  [system items]
///
/// Items left of the "|" divider are hidden until the toggle is clicked;
/// items left of the "⋮" divider stay hidden until "Show All" is used.
enum SectionState: Equatable, Sendable {
    case collapsed
    case expanded
    case expandedAll
}

enum MenuBarSection: Int, Comparable, Sendable {
    case alwaysHidden
    case hidden
    case visible

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One menu bar item as Accessibility reports it.
struct InventoryItem: Equatable, Sendable {
    var bundleIdentifier: String?
    var frame: CGRect
}

/// Which section each app's items are in, read from an unrestricted bar.
struct SectionLayout: Equatable, Sendable {
    var sectionByBundle: [String: MenuBarSection]

    func bundles(in sections: Set<MenuBarSection>) -> [String] {
        sectionByBundle.filter { sections.contains($0.value) }.map(\.key).sorted()
    }
}

enum SectionLayoutResolver {
    /// Assigns each app to a section by where its items sit relative to the
    /// dividers. An app with items in several sections gets the most visible one,
    /// because the macOS 27 engine can only hide whole apps.
    ///
    /// Assumes a left-to-right menu bar.
    static func resolve(items: [InventoryItem],
                        separatorFrame: CGRect,
                        alwaysHiddenFrame: CGRect?,
                        excluding excludedBundle: String?) -> SectionLayout {
        var result: [String: MenuBarSection] = [:]
        for item in items {
            guard let bundle = item.bundleIdentifier, bundle != excludedBundle else { continue }
            let section: MenuBarSection
            if let alwaysHiddenFrame, item.frame.midX < alwaysHiddenFrame.minX {
                section = .alwaysHidden
            } else if item.frame.midX < separatorFrame.minX {
                section = .hidden
            } else {
                section = .visible
            }
            result[bundle] = max(result[bundle] ?? section, section)
        }
        return SectionLayout(sectionByBundle: result)
    }
}

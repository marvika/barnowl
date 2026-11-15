import CoreGraphics

/// What the user sees. On macOS 26 the divider items split the bar into three
/// sections:
///
///     [always hidden] ⋮ [hidden] | [visible]  <toggle>  [system items]
///
/// Items left of the "|" divider are hidden until the toggle is clicked;
/// items left of the "⋮" divider stay hidden until "Show All" is used.
/// macOS 27 has the same three sections without the dividers: which one an
/// app's icons are in comes from a saved table (`AppRows`).
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

/// macOS 27: what the menu bar shows for now, on top of the rows in view:
/// apps let through for a while, and captures that want every other app's
/// icon out of the picture. Pure, so it can be tested.
struct TemporaryVisibility: Equatable, Sendable {
    /// Apps whose icons show for now whatever row they're in, by who asked
    /// (an icon opened from the Perch, an icon that changed), so one doesn't
    /// undo the other.
    private(set) var peeks: [String: Set<String>] = [:]
    /// The captures under way that want a clean menu bar.
    private(set) var cleanFor: Set<String> = []

    /// Whether a capture has every other app's icon out of view.
    var isClean: Bool { !cleanFor.isEmpty }

    mutating func peek(_ apps: Set<String>, for reason: String) {
        peeks[reason] = apps.isEmpty ? nil : apps
    }

    mutating func holdClean(for reason: String) {
        cleanFor.insert(reason)
    }

    mutating func endClean(for reason: String) {
        cleanFor.remove(reason)
    }

    /// The apps to let through now. While a capture keeps the menu bar clean,
    /// that's only an icon you open yourself (`opening` is the reason it
    /// peeks for): its menu is what you're after. An icon shown because it
    /// changed waits until the capture is over.
    func revealed(opening: String) -> Set<String> {
        let asked = isClean ? peeks.filter { $0.key == opening } : peeks
        return asked.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }
}

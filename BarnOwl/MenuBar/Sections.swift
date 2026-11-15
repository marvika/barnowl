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

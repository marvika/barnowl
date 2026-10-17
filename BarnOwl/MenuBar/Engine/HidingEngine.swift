import AppKit

/// How the menu bar is made to hide a section. SectionController decides what
/// the user wants; an engine decides how macOS is made to do it, so a macOS
/// release that changes the menu bar only needs a new engine.
@MainActor
protocol HidingEngine: AnyObject {
    var displayName: String { get }

    /// Whether this engine needs Accessibility permission to work.
    var needsAccessibility: Bool { get }

    /// Applies a state. Returns false if the engine couldn't hide anything;
    /// the controller then stays expanded rather than guessing.
    func apply(_ state: SectionState, alwaysHiddenEnabled: Bool) async -> Bool

    /// Display geometry changed (screen plugged in, resolution change).
    func invalidateLayout()

    /// Hides every other app's icon, visible ones included, if the engine can
    /// do that by itself. Returns false if it can't, and presenter mode then
    /// moves the visible icons into the hidden section instead.
    func setPresenting(_ presenting: Bool) async -> Bool
}

enum HidingEngineFactory {
    @MainActor
    static func make(items: StatusItems) -> HidingEngine {
        // macOS 27 drops an over-wide divider from the menu bar instead of
        // letting it push items off screen, so it needs the native engine.
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            return NativeVisibilityEngine(items: items)
        }
        return LengthEngine(items: items)
    }
}

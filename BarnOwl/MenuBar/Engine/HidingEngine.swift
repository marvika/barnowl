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

    /// The layout or the running apps changed: hide by the current rules
    /// again, in the state already applied.
    func refresh() async

    /// Display geometry changed (screen plugged in, resolution change).
    func invalidateLayout()

    /// Hides every other app's icon, visible ones included, if the engine can
    /// do that by itself. Returns false if it can't, and presenter mode then
    /// moves the visible icons into the hidden section instead.
    func setPresenting(_ presenting: Bool) async -> Bool

    /// Shows these apps' icons for now, whatever row they're in, and stops
    /// showing any revealed before. With `alone`, every other app's icon goes
    /// out of view as well, the visible ones included: what a capture with a
    /// clean menu bar asks for. Returns false if the engine can't show one
    /// app's icons on their own; the caller then moves the icon or reveals
    /// its whole section.
    func reveal(_ apps: Set<String>, alone: Bool) async -> Bool
}

enum HidingEngineFactory {
    @MainActor
    static func make(items: StatusItems) -> HidingEngine {
        // macOS 27 has no item windows for a divider to push off screen.
        MenuBarPlatform.hidesByApp ? NativeVisibilityEngine() : LengthEngine(items: items)
    }
}

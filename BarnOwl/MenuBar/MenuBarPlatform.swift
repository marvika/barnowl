import AppKit

/// Which kind of menu bar Barn Owl is living in.
///
/// Up to macOS 26 every status item has a window of its own. Barn Owl reads
/// those from the window list, hides them by pushing them off screen with a
/// wide divider, and moves them with a ⌘-drag.
///
/// macOS 27 draws the whole menu bar in one window owned by MenuBarAgent.
/// There are no item windows, so nothing can be pushed or dragged. Icons are
/// found through Accessibility alone, and hidden by telling macOS which apps
/// may show: an app's icons hide or show together, and where an icon sits no
/// longer matters. The layout is a saved table of apps (`AppRows`).
enum MenuBarPlatform {
    /// The process that draws the menu bar on macOS 27, and owns macOS's own
    /// icons there (Sound, Battery, Wi‑Fi, Control Center, the clock).
    static let agentBundle = "com.apple.MenuBarAgent"

    /// macOS 27 and later.
    static let hidesByApp = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
}

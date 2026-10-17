import Foundation

/// UserDefaults keys shared by the controllers and the SwiftUI settings
/// (which read them through @AppStorage).
enum PrefKey {
    static let autoRehide = "autoRehide"
    static let autoRehideDelay = "autoRehideDelay"
    static let alwaysHiddenEnabled = "alwaysHiddenEnabled"
    static let keepAwakeAllowDisplaySleep = "keepAwakeAllowDisplaySleep"
    static let keepAwakeHotkeyMinutes = "keepAwakeHotkeyMinutes"
    static let hasShownWelcome = "hasShownWelcome"
    static let menuShowsDarkMode = "menuShowsDarkMode"
    static let menuShowsDesktopIcons = "menuShowsDesktopIcons"
    static let menuShowsHiddenFiles = "menuShowsHiddenFiles"
    static let hiddenIconsDisplay = "hiddenIconsDisplay"
}

enum Preferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.autoRehide: true,
            PrefKey.autoRehideDelay: 10.0,
            PrefKey.alwaysHiddenEnabled: false,
            PrefKey.keepAwakeAllowDisplaySleep: false,
            PrefKey.keepAwakeHotkeyMinutes: 0,
            PrefKey.hasShownWelcome: false,
            PrefKey.menuShowsDarkMode: true,
            PrefKey.menuShowsDesktopIcons: true,
            PrefKey.menuShowsHiddenFiles: true,
            PrefKey.hiddenIconsDisplay: HiddenIconsDisplay.automatic.rawValue,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var autoRehide: Bool { defaults.bool(forKey: PrefKey.autoRehide) }
    static var autoRehideDelay: TimeInterval { max(2, defaults.double(forKey: PrefKey.autoRehideDelay)) }
    static var alwaysHiddenEnabled: Bool { defaults.bool(forKey: PrefKey.alwaysHiddenEnabled) }
    static var keepAwakeAllowDisplaySleep: Bool {
        get { defaults.bool(forKey: PrefKey.keepAwakeAllowDisplaySleep) }
        set { defaults.set(newValue, forKey: PrefKey.keepAwakeAllowDisplaySleep) }
    }
    /// 0 means "indefinitely".
    static var keepAwakeHotkeyMinutes: Int { defaults.integer(forKey: PrefKey.keepAwakeHotkeyMinutes) }
    static var menuShowsDarkMode: Bool { defaults.bool(forKey: PrefKey.menuShowsDarkMode) }
    static var menuShowsDesktopIcons: Bool { defaults.bool(forKey: PrefKey.menuShowsDesktopIcons) }
    static var menuShowsHiddenFiles: Bool { defaults.bool(forKey: PrefKey.menuShowsHiddenFiles) }
    static var hiddenIconsDisplay: HiddenIconsDisplay {
        HiddenIconsDisplay(rawValue: defaults.string(forKey: PrefKey.hiddenIconsDisplay) ?? "") ?? .automatic
    }
    static var hasShownWelcome: Bool {
        get { defaults.bool(forKey: PrefKey.hasShownWelcome) }
        set { defaults.set(newValue, forKey: PrefKey.hasShownWelcome) }
    }
}

import AppKit

/// One-click system switches shown in Barkeep's menu.
@MainActor
enum QuickToggles {
    // MARK: Dark mode

    static var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// System Events is the only public way to switch appearance. The first
    /// use asks for Automation permission.
    static func toggleDarkMode() {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.app.error("Dark mode toggle failed: \(error)")
        }
    }

    // MARK: Finder settings

    static var desktopIconsHidden: Bool {
        !finderBool("CreateDesktop", default: true)
    }

    static func toggleDesktopIcons() {
        setFinderBool("CreateDesktop", desktopIconsHidden)
    }

    static var hiddenFilesShown: Bool {
        finderBool("AppleShowAllFiles", default: false)
    }

    static func toggleHiddenFiles() {
        setFinderBool("AppleShowAllFiles", !hiddenFilesShown)
    }

    private static func finderBool(_ key: String, default defaultValue: Bool) -> Bool {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let value = CFPreferencesCopyAppValue(key as CFString, "com.apple.finder" as CFString)
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return defaultValue
    }

    /// Writes through `defaults` so cfprefsd sees the change, then restarts
    /// Finder, which only reads these settings at launch.
    private static func setFinderBool(_ key: String, _ value: Bool) {
        run("/usr/bin/defaults", ["write", "com.apple.finder", key, "-bool", value ? "true" : "false"])
        run("/usr/bin/killall", ["Finder"])
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.app.error("\(path) failed: \(error.localizedDescription)")
        }
    }
}

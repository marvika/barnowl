import AppKit

/// Builds the right-click menu fresh each time it opens, so every checkmark
/// reflects the current state.
@MainActor
final class MenuBuilder: NSObject {
    static let durations = [0, 15, 30, 60, 120, 240, 480]

    private let sections: SectionController
    private let keepAwake: KeepAwakeController
    private let openSettings: () -> Void
    private let openSearch: () -> Void

    init(sections: SectionController, keepAwake: KeepAwakeController, openSettings: @escaping () -> Void,
         openSearch: @escaping () -> Void) {
        self.sections = sections
        self.keepAwake = keepAwake
        self.openSettings = openSettings
        self.openSearch = openSearch
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(.sectionHeader(title: "Keep Awake"))
        if let session = keepAwake.session {
            menu.addItem(disabled(KeepAwakeFormatter.status(for: session)))
            menu.addItem(item("Stop Keeping Awake", symbol: "cup.and.saucer", #selector(stopKeepAwake)))
        }
        let durationsMenu = NSMenu()
        for minutes in Self.durations {
            let entry = item(KeepAwakeFormatter.durationLabel(minutes: minutes), #selector(startKeepAwake(_:)))
            entry.tag = minutes
            durationsMenu.addItem(entry)
        }
        menu.addItem(submenu(keepAwake.isActive ? "Restart For" : "Keep Awake For",
                             symbol: "cup.and.heat.waves", durationsMenu))
        menu.addItem(submenu("While App Is Running", symbol: "app.badge.checkmark", runningAppsMenu()))
        let displaySleep = item("Allow Display to Sleep", #selector(toggleDisplaySleep))
        displaySleep.state = Preferences.keepAwakeAllowDisplaySleep ? .on : .off
        menu.addItem(displaySleep)

        var toggles: [NSMenuItem] = []
        if Preferences.menuShowsDarkMode {
            toggles.append(toggle("Dark Mode", symbol: "circle.lefthalf.filled", QuickToggles.isDarkMode,
                                  #selector(toggleDarkMode)))
        }
        if Preferences.menuShowsDesktopIcons {
            toggles.append(toggle("Hide Desktop Icons", symbol: "menubar.dock.rectangle",
                                  QuickToggles.desktopIconsHidden, #selector(toggleDesktopIcons)))
        }
        if Preferences.menuShowsHiddenFiles {
            toggles.append(toggle("Show Hidden Files", symbol: "eye", QuickToggles.hiddenFilesShown,
                                  #selector(toggleHiddenFiles)))
        }
        if !toggles.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Quick Toggles"))
            toggles.forEach(menu.addItem)
        }

        menu.addItem(.separator())
        menu.addItem(item(sections.state == .collapsed ? "Show Hidden Icons" : "Hide Icons",
                          symbol: "chevron.left.2", #selector(toggleSections)))
        menu.addItem(item("Show All Icons", symbol: "eye.circle", #selector(showAll)))
        menu.addItem(item("Search Menu Bar…", symbol: "magnifyingglass", #selector(search)))
        menu.addItem(.separator())
        let settings = item("Settings…", #selector(showSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Barkeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func runningAppsMenu() -> NSMenu {
        let menu = NSMenu()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        for app in apps {
            guard let bundle = app.bundleIdentifier, let name = app.localizedName else { continue }
            let entry = item(name, #selector(startWhileAppRuns(_:)))
            entry.representedObject = [bundle, name]
            entry.image = app.icon.map { icon in
                let small = icon.copy() as! NSImage
                small.size = NSSize(width: 16, height: 16)
                return small
            }
            if case .whileAppRunning(let active, _) = keepAwake.session, active == bundle {
                entry.state = .on
            }
            menu.addItem(entry)
        }
        return menu
    }

    // MARK: Actions

    @objc private func startKeepAwake(_ sender: NSMenuItem) { keepAwake.start(minutes: sender.tag) }
    @objc private func stopKeepAwake() { keepAwake.stop() }
    @objc private func toggleDisplaySleep() {
        Preferences.keepAwakeAllowDisplaySleep.toggle()
    }
    @objc private func startWhileAppRuns(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String], info.count == 2 else { return }
        keepAwake.start(.whileAppRunning(bundleIdentifier: info[0], name: info[1]))
    }
    @objc private func toggleDarkMode() { QuickToggles.toggleDarkMode() }
    @objc private func toggleDesktopIcons() { QuickToggles.toggleDesktopIcons() }
    @objc private func toggleHiddenFiles() { QuickToggles.toggleHiddenFiles() }
    @objc private func toggleSections() { sections.toggle() }
    @objc private func showAll() { sections.showAll() }
    @objc private func showSettings() { openSettings() }
    @objc private func search() { openSearch() }

    // MARK: Helpers

    private func item(_ title: String, symbol: String? = nil, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        if let symbol { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return entry
    }

    private func toggle(_ title: String, symbol: String, _ isOn: Bool, _ action: Selector) -> NSMenuItem {
        let entry = item(title, symbol: symbol, action)
        entry.state = isOn ? .on : .off
        return entry
    }

    private func submenu(_ title: String, symbol: String, _ submenu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        entry.submenu = submenu
        return entry
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }
}

import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var items: StatusItems!
    private var sections: SectionController!
    private let keepAwake = KeepAwakeController()
    private var menuBuilder: MenuBuilder!
    private var model: AppModel!
    private var settingsWindow: SettingsWindowController!
    private var onboardingWindow: OnboardingWindowController!
    private var scanner: ItemScanner!
    private let images = ItemImageCache()
    private var bar: BarkeepBarController!
    private var search: SearchPanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        items = StatusItems()
        sections = SectionController(items: items, engine: HidingEngineFactory.make(items: items))
        Log.app.info("Using hiding engine: \(self.sections.engine.displayName)")
        scanner = ItemScanner(statusItems: items)
        model = AppModel(sections: sections, keepAwake: keepAwake, scanner: scanner, images: images,
                         opener: ItemOpener(sections: sections, scanner: scanner))
        bar = BarkeepBarController(model: model) { [weak self] in self?.items.toggle.button?.window?.frame }
        search = SearchPanelController(model: model)
        model.showSearch = { [weak self] in self?.search.show() }
        settingsWindow = SettingsWindowController(model: model)
        onboardingWindow = OnboardingWindowController(model: model)
        onboardingWindow.onFinish = { [weak self] in
            Preferences.hasShownWelcome = true
            Task {
                guard let self else { return }
                await self.images.capture(await self.scanner.freshItems())
                self.sections.collapse()
            }
        }
        model.showSetup = { [weak self] in self?.onboardingWindow.show() }
        model.showSettings = { [weak self] in self?.settingsWindow.show() }
        menuBuilder = MenuBuilder(sections: sections, keepAwake: keepAwake, openSettings: { [weak self] in
            self?.settingsWindow.show()
        }, openSearch: { [weak self] in
            self?.search.show()
        })

        if let button = items.toggle.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        sections.onStateChange = { [weak self] state in
            self?.model.sectionState = state
            self?.updateToggleIcon()
            self?.sectionsMoved(revealed: state != .collapsed)
        }
        keepAwake.onChange = { [weak self] in self?.updateToggleIcon() }
        updateToggleIcon()

        KeyboardShortcuts.onKeyUp(for: .toggleHiddenItems) { [weak self] in self?.revealHiddenIcons() }
        KeyboardShortcuts.onKeyUp(for: .searchItems) { [weak self] in self?.search.toggle() }
        KeyboardShortcuts.onKeyUp(for: .showAllItems) { [weak self] in self?.sections.showAll() }
        KeyboardShortcuts.onKeyUp(for: .toggleKeepAwake) { [weak self] in
            guard let self else { return }
            if self.keepAwake.isActive {
                self.keepAwake.stop()
            } else {
                self.keepAwake.start(minutes: Preferences.keepAwakeHotkeyMinutes)
            }
        }

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }

        if Preferences.hasShownWelcome {
            // Everything is showing right after launch: list the items and take
            // their pictures before hiding, so the Barkeep Bar has them.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                let items = await self.scanner.freshItems()
                await self.images.capture(items)
                self.sections.collapse()
                self.scanner.start()
            }
        } else {
            scanner.start()
            onboardingWindow.show()
        }
    }

    /// barkeep://settings, barkeep://setup, barkeep://search, barkeep://bar,
    /// barkeep://open?app=NAME, barkeep://toggle, barkeep://show-all,
    /// barkeep://hide, barkeep://keep-awake?minutes=60 (0 or none = indefinitely),
    /// barkeep://keep-awake/stop. For Shortcuts, Raycast and scripts.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "barkeep" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            switch (url.host() ?? "", url.path()) {
            case ("settings", _): settingsWindow.show()
            case ("search", _): search.show()
            case ("bar", _): bar.toggle()
            case ("open", _):
                // barkeep://open?app=OneDrive (app name or bundle ID) opens that app's menu bar item.
                guard let app = query?.first(where: { $0.name == "app" })?.value?.lowercased() else { break }
                Task {
                    let items = await scanner.freshItems()
                    if let item = items.first(where: { $0.bundleIdentifier?.lowercased() == app })
                        ?? items.first(where: { $0.appName.lowercased() == app }) {
                        model.opener.open(item)
                    } else {
                        Log.app.error("No menu bar item for \(app)")
                    }
                }
            case ("setup", _): onboardingWindow.show()
            case ("toggle", _): sections.toggle()
            case ("show-all", _): sections.showAll()
            case ("hide", _): sections.collapse()
            case ("keep-awake", "/stop"): keepAwake.stop()
            case ("keep-awake", _):
                let minutes = query?.first { $0.name == "minutes" }?.value.flatMap(Int.init) ?? 0
                keepAwake.start(minutes: minutes)
            default:
                Log.app.error("Unknown URL: \(url.absoluteString)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keepAwake.stop()
    }

    @objc private func toggleClicked() {
        // Accessibility presses (VoiceOver, AXPress) arrive without a mouse event.
        guard let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .rightMouseUp else {
            sections.toggle()
            return
        }
        let flags = event.modifierFlags
        if event.type == .rightMouseUp || flags.contains(.control) {
            bar.close()
            showMenu()
        } else if flags.contains(.option) {
            bar.close()
            sections.showAll()
        } else {
            revealHiddenIcons()
        }
    }

    /// The arrow and its hotkey: hide what's showing, otherwise reveal the
    /// hidden icons in the menu bar or in the Barkeep Bar.
    private func revealHiddenIcons() {
        if bar.isOpen {
            bar.close()
        } else if sections.state != .collapsed {
            sections.collapse()
        } else if model.hiddenIconsUseBar {
            bar.show()
        } else {
            sections.toggle()
        }
    }

    /// After the dividers move: update where items are, and photograph the
    /// ones that just came into view.
    private func sectionsMoved(revealed: Bool) {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            scanner.updateFrames()
            if revealed { await images.capture(scanner.items) }
        }
    }

    private func showMenu() {
        // Attaching the menu only while it's open keeps left clicks free for toggling.
        items.toggle.menu = menuBuilder.makeMenu()
        items.toggle.button?.performClick(nil)
        items.toggle.menu = nil
    }

    private var lastAlwaysHiddenEnabled: Bool?
    private var lastAllowDisplaySleep: Bool?

    private func preferencesChanged() {
        let alwaysHidden = Preferences.alwaysHiddenEnabled
        if lastAlwaysHiddenEnabled != nil, alwaysHidden != lastAlwaysHiddenEnabled {
            sections.refresh()
        }
        lastAlwaysHiddenEnabled = alwaysHidden

        let allowDisplaySleep = Preferences.keepAwakeAllowDisplaySleep
        if lastAllowDisplaySleep != nil, allowDisplaySleep != lastAllowDisplaySleep {
            keepAwake.refreshAssertion()
        }
        lastAllowDisplaySleep = allowDisplaySleep
    }

    private func updateToggleIcon() {
        guard let button = items.toggle.button else { return }
        let collapsed = sections.state == .collapsed
        button.image = ToggleIcon.make(collapsed: collapsed, keepAwake: keepAwake.isActive)
        var tip = collapsed ? "Click to show hidden icons" : "Click to hide icons"
        tip += "\nOption-click to show everything · Right-click for the menu"
        if let session = keepAwake.session {
            tip += "\n" + KeepAwakeFormatter.status(for: session)
        }
        button.toolTip = tip
    }
}

enum ToggleIcon {
    /// The arrow, plus a small cup while keep-awake is on.
    @MainActor
    static func make(collapsed: Bool, keepAwake: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let arrow = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right",
                                  accessibilityDescription: collapsed ? "Show hidden icons" : "Hide icons")?
            .withSymbolConfiguration(config) else { return nil }
        guard keepAwake,
              let cup = NSImage(systemSymbolName: "cup.and.heat.waves.fill", accessibilityDescription: "Keep awake on")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)) else {
            arrow.isTemplate = true
            return arrow
        }
        let spacing: CGFloat = 4
        let size = NSSize(width: cup.size.width + spacing + arrow.size.width,
                          height: max(cup.size.height, arrow.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            cup.draw(at: NSPoint(x: 0, y: (size.height - cup.size.height) / 2), from: .zero,
                     operation: .sourceOver, fraction: 1)
            arrow.draw(at: NSPoint(x: cup.size.width + spacing, y: (size.height - arrow.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Barkeep, keep awake on"
        return image
    }
}

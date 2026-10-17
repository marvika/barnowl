import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var items: StatusItems!
    private var sections: SectionController!
    private let keepAwake = KeepAwakeController(rules: RuleStore())
    private var quickPanel: QuickPanelController!
    private var model: AppModel!
    private var settingsWindow: SettingsWindowController!
    private var onboardingWindow: OnboardingWindowController!
    private var scanner: ItemScanner!
    private let images = ItemImageCache()
    private var bar: PerchController!
    private var search: SearchPanelController!
    private var groupIcons: GroupController!
    private var pendingURLs: [URL] = []
    private var gestures: RevealGestures!
    private var clipboardPanel: ClipboardPanelController!
    private var dropTray: DropTray!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; don't touch the real menu bar then.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if !DemoMode.isOn { Migration.runIfNeeded() }
        Preferences.registerDefaults()

        items = StatusItems()
        sections = SectionController(items: items, engine: HidingEngineFactory.make(items: items))
        Log.app.info("Using hiding engine: \(self.sections.engine.displayName)")
        scanner = ItemScanner(statusItems: items)
        let groups = GroupStore()
        model = AppModel(sections: sections, keepAwake: keepAwake, scanner: scanner, images: images,
                         mover: ItemMover(statusItems: items), groups: groups)
        groupIcons = GroupController(model: model)
        groups.onChange = { [weak self] in self?.groupIcons.sync() }
        model.syncGroupIcons = { [weak self] in self?.groupIcons.sync() }
        model.groupIconWindow = { [weak self] id in self?.groupIcons.windowID(of: id) }
        groupIcons.sync()
        scanner.ownWindowFrames = { [weak self] in
            guard let self else { return [] }
            let own: [NSStatusItem?] = [self.items.toggle, self.items.separator, self.items.alwaysHidden,
                                        self.quickPanel?.owlItem] + self.groupIcons.allStatusItems
            guard let primary = NSScreen.screens.first else { return [] }
            return own.compactMap { StatusItems.layoutFrame(of: $0) }.map {
                CGRect(x: $0.minX, y: primary.frame.maxY - $0.maxY, width: $0.width, height: $0.height)
            }
        }
        scanner.onScan = { [weak self] in
            Task { await self?.model.layout.reconcile() }
        }
        bar = PerchController(model: model) { [weak self] in self?.items.toggle.button?.window?.frame }
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
                await self.model.layout.applyFirstRunDefaults()
                await self.model.layout.refreshMissingPictures()
            }
        }
        model.showSetup = { [weak self] in self?.onboardingWindow.show() }
        model.openSettingsWindow = { [weak self] in self?.settingsWindow.show() }
        quickPanel = QuickPanelController(model: model)
        quickPanel.syncOwlIcon()
        keepAwake.start()
        model.watcher.start()
        gestures = RevealGestures(statusItems: items, isCollapsed: { [weak self] in
            self?.sections.state == .collapsed && self?.bar.isOpen == false
        }, reveal: { [weak self] in self?.revealHiddenIcons() }, hide: { [weak self] in
            self?.bar.close()
            self?.sections.collapse()
        })
        gestures.start()
        IntentBridge.model = model
        IntentBridge.revealHiddenIcons = { [weak self] in self?.revealHiddenIcons() }
        model.appearance.start()
        model.clipboard.start()
        clipboardPanel = ClipboardPanelController(clipboard: model.clipboard)
        dropTray = DropTray(clipboard: model.clipboard)
        dropTray.start()
        model.showClipboard = { [weak self] in self?.clipboardPanel.show() }
        KeyboardShortcuts.onKeyUp(for: .clipboard) { [weak self] in self?.clipboardPanel.toggle() }
        sections.onScreensChanged = { [weak self] in
            Task {
                // Give macOS a moment to settle the menu bar on the new displays.
                try? await Task.sleep(for: .seconds(2))
                await self?.model.layout.updateProfile()
            }
        }
        model.presenter.start()
        if !DemoMode.isOn { model.updater.start() }
        model.presenter.onChange = { [weak self] _ in
            self?.bar.close()
            self?.updateToggleIcon()
        }

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
        keepAwake.onChange = { [weak self] in
            self?.updateToggleIcon()
            self?.quickPanel.syncOwlIcon()
        }
        updateToggleIcon()

        KeyboardShortcuts.onKeyUp(for: .toggleHiddenItems) { [weak self] in self?.revealHiddenIcons() }
        KeyboardShortcuts.onKeyUp(for: .searchItems) { [weak self] in self?.search.toggle() }
        KeyboardShortcuts.onKeyUp(for: .togglePresenter) { [weak self] in
            Task { await self?.model.presenter.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .showAllItems) { [weak self] in self?.sections.showAll() }
        KeyboardShortcuts.onKeyUp(for: .toggleKeepAwake) { [weak self] in
            guard let self else { return }
            if self.keepAwake.session != nil {
                self.keepAwake.stop()
            } else {
                self.keepAwake.start(minutes: Preferences.keepAwakeHotkeyMinutes)
            }
        }

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs = []
            DispatchQueue.main.async { self.application(NSApp, open: urls) }
        }

        if DemoMode.isOn {
            scanner.loadDemo(DemoMode.items())
            model.refreshPermissions()
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                self.sections.collapse()
            }
            if !Preferences.hasShownWelcome { onboardingWindow.show() }
        } else if Preferences.hasShownWelcome {
            // Everything is showing right after launch: list the items and take
            // their pictures before hiding, so the Perch has them.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                let items = await self.scanner.freshItems()
                await self.images.capture(items)
                self.sections.collapse()
                self.scanner.start()
                await self.model.layout.updateProfile()
                await self.model.layout.applyFirstRunDefaults()
            }
        } else {
            // Setup's layout step shows the real icons, so take their pictures
            // while everything is still showing.
            Task {
                let items = await self.scanner.freshItems()
                await self.images.capture(items)
                self.scanner.start()
            }
            onboardingWindow.show()
        }
    }

    /// barnowl://settings, barnowl://setup, barnowl://search, barnowl://bar,
    /// barnowl://open?app=NAME, barnowl://place?app=NAME&row=hidden, barnowl://watch?app=NAME,
    /// barnowl://icon?app=NAME&label=TEXT, barnowl://presenter, barnowl://toggle, barnowl://show-all,
    /// barnowl://hide, barnowl://keep-awake?minutes=60 (0 or none = indefinitely),
    /// barnowl://keep-awake/stop. For Shortcuts, Raycast and scripts.
    func application(_ application: NSApplication, open urls: [URL]) {
        // A link that launches Barn Owl can arrive before launch has finished.
        guard model != nil else {
            pendingURLs += urls
            return
        }
        for url in urls where url.scheme == "barnowl" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            switch (url.host() ?? "", url.path()) {
            case ("settings", _):
                // barnowl://settings?pane=layout
                let pane = query?.first { $0.name == "pane" }?.value.flatMap(SettingsPane.init(rawValue:))
                model.showSettings(pane)
            case ("search", _): search.show()
            case ("clipboard", _): clipboardPanel.show()
            case ("presenter", _):
                // barnowl://presenter (toggle), ?on=1 or ?on=0
                let on = query?.first { $0.name == "on" }?.value
                Task { await on == nil ? model.presenter.toggle() : model.presenter.set(on == "1", automatically: false) }
            case ("bar", _): bar.toggle()
            case ("place", _):
                // barnowl://place?app=Claude&row=hidden (visible, hidden or alwaysHidden)
                guard let app = query?.first(where: { $0.name == "app" })?.value?.lowercased(),
                      let row = query?.first(where: { $0.name == "row" })?.value.flatMap(LayoutRow.init(storageValue:))
                else { break }
                Task {
                    let items = await scanner.freshItems()
                    if let item = items.first(where: { $0.bundleIdentifier?.lowercased() == app })
                        ?? items.first(where: { $0.appName.lowercased() == app || $0.name.lowercased() == app }) {
                        await model.layout.place(item.key, in: row)
                    }
                }
            case ("icon", _):
                // barnowl://icon?app=Zscaler&label=VPN (or &symbol=lock.fill), &reset=1 to restore the original
                guard let app = query?.first(where: { $0.name == "app" })?.value?.lowercased() else { break }
                let value = { (name: String) in query?.first { $0.name == name }?.value }
                Task {
                    let items = await scanner.freshItems()
                    guard let item = items.first(where: { $0.bundleIdentifier?.lowercased() == app })
                        ?? items.first(where: { $0.appName.lowercased() == app || $0.name.lowercased() == app })
                    else { return }
                    if value("reset") == "1" {
                        if let group = model.groups.group(containing: item.key), group.opensDirectly {
                            await model.deleteGroup(group.id)
                        }
                    } else {
                        await model.setCustomIcon(for: item, symbol: value("symbol") ?? "star.fill", label: value("label"))
                    }
                }
            case ("watch", _):
                // barnowl://watch?app=OneDrive&on=1: show the icon for a while when it changes.
                guard let app = query?.first(where: { $0.name == "app" })?.value?.lowercased() else { break }
                let on = query?.first { $0.name == "on" }?.value != "0"
                Task {
                    let items = await scanner.freshItems()
                    if let item = items.first(where: { $0.bundleIdentifier?.lowercased() == app })
                        ?? items.first(where: { $0.appName.lowercased() == app || $0.name.lowercased() == app }) {
                        model.watcher.setWatching(item.key, on)
                    }
                }
            case ("open", _):
                // barnowl://open?app=OneDrive (app name or bundle ID) opens that app's menu bar item.
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
            case ("keep-awake", "/extend"):
                // barnowl://keep-awake/extend?minutes=30
                let minutes = query?.first { $0.name == "minutes" }?.value.flatMap(Int.init) ?? 15
                keepAwake.extend(minutes: minutes)
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
        // Never leave the Mac unable to sleep after Barn Owl is gone.
        if Preferences.closedLidMode, ClosedLidMode.isEnabled {
            ClosedLidMode.set(false)
        }
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
            quickPanel.toggle(under: items.toggle.button?.window?.frame)
        } else if flags.contains(.option) {
            bar.close()
            sections.showAll()
        } else {
            revealHiddenIcons()
        }
    }

    /// The arrow and its hotkey: hide what's showing, otherwise reveal the
    /// hidden icons in the menu bar or in the Perch.
    private func revealHiddenIcons() {
        // While presenting, never reveal icons on the shared screen by
        // accident: the Perch is a deliberate second step.
        if model.presenter.isPresenting {
            bar.toggle()
        } else if bar.isOpen {
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


    private var lastAlwaysHiddenEnabled: Bool?
    private var lastAllowDisplaySleep: Bool?
    private var askedForNotifications = false

    private var lastDisplayProfiles: Bool?

    private func preferencesChanged() {
        if Preferences.displayProfiles != lastDisplayProfiles {
            if lastDisplayProfiles != nil { Task { await model.layout.updateProfile() } }
            lastDisplayProfiles = Preferences.displayProfiles
        }
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

        quickPanel.syncOwlIcon()
        if Preferences.showKeepAwakeIcon != (quickPanel.owlItem != nil) {
            quickPanel.syncOwlIcon()
            updateToggleIcon()
        }
        dropTray?.refresh()
        if Preferences.keepAwakeNotify, !askedForNotifications {
            askedForNotifications = true
            KeepAwakeController.requestNotificationPermission()
        }
    }

    private func updateToggleIcon() {
        guard let button = items.toggle.button else { return }
        // While presenting the arrow becomes an eye-slash, so it's clear why the bar is empty.
        guard !model.presenter.isPresenting else {
            button.image = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: "Presenting")?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
            button.toolTip = "Presenting: menu bar icons are hidden\nClick for your icons on the Perch"
            return
        }
        let collapsed = sections.state == .collapsed
        // The cup icon shows keep-awake when it's in the menu bar; otherwise the arrow does.
        button.image = ToggleIcon.make(collapsed: collapsed,
                                       keepAwake: keepAwake.isActive && !Preferences.showKeepAwakeIcon)
        var tip = collapsed ? "Click to show hidden icons" : "Click to hide icons"
        tip += "\nOption-click to show everything · Right-click for keep awake and toggles"
        if keepAwake.isActive {
            tip += "\n" + KeepAwakeFormatter.status(of: keepAwake)
        }
        button.toolTip = tip
    }
}

enum ToggleIcon {
    /// The arrow, plus a small awake owl while keep-awake is on (when the owl
    /// isn't in the menu bar by itself).
    @MainActor
    static func make(collapsed: Bool, keepAwake: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let arrow = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right",
                                  accessibilityDescription: collapsed ? "Show hidden icons" : "Hide icons")?
            .withSymbolConfiguration(config) else { return nil }
        guard keepAwake else {
            arrow.isTemplate = true
            return arrow
        }
        let cup = MenuBarOwl.image(openness: 1, height: 15)
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
        image.accessibilityDescription = "Barn Owl, keep awake on"
        return image
    }
}

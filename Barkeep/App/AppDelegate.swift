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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        items = StatusItems()
        sections = SectionController(items: items, engine: HidingEngineFactory.make(items: items))
        Log.app.info("Using hiding engine: \(self.sections.engine.displayName)")
        model = AppModel(sections: sections, keepAwake: keepAwake)
        settingsWindow = SettingsWindowController(model: model)
        onboardingWindow = OnboardingWindowController(model: model)
        onboardingWindow.onFinish = { [weak self] in
            Preferences.hasShownWelcome = true
            self?.sections.collapse()
        }
        model.showSetup = { [weak self] in self?.onboardingWindow.show() }
        menuBuilder = MenuBuilder(sections: sections, keepAwake: keepAwake, openSettings: { [weak self] in
            self?.settingsWindow.show()
        })

        if let button = items.toggle.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        sections.onStateChange = { [weak self] state in
            self?.model.sectionState = state
            self?.updateToggleIcon()
        }
        keepAwake.onChange = { [weak self] in self?.updateToggleIcon() }
        updateToggleIcon()

        KeyboardShortcuts.onKeyUp(for: .toggleHiddenItems) { [weak self] in self?.sections.toggle() }
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
            // Give the status items a moment to get their windows before
            // checking the arrangement.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                self.sections.collapse()
            }
        } else {
            onboardingWindow.show()
        }
    }

    /// barkeep://settings, barkeep://setup, barkeep://toggle, barkeep://show-all,
    /// barkeep://hide, barkeep://keep-awake?minutes=60 (0 or none = indefinitely),
    /// barkeep://keep-awake/stop. For Shortcuts, Raycast and scripts.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "barkeep" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            switch (url.host() ?? "", url.path()) {
            case ("settings", _): settingsWindow.show()
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
            showMenu()
        } else if flags.contains(.option) {
            sections.showAll()
        } else {
            sections.toggle()
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

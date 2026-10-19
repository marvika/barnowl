import KeyboardShortcuts
import SwiftUI

/// Settings laid out like System Settings: a sidebar of panes, each a
/// grouped form.
enum SettingsPane: String, CaseIterable, Identifiable {
    case layout, general, menuBar, appearance, keepAwake, agents, toggles, clipboard, shortcuts, about
    var id: Self { self }

    var title: String {
        switch self {
        case .layout: "Layout"
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .appearance: "Appearance"
        case .clipboard: "Clipboard"
        case .keepAwake: "Keep Awake"
        case .agents: "Agents"
        case .toggles: "Toggles"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .layout: "square.grid.3x1.below.line.grid.1x2"
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .appearance: "paintpalette.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .keepAwake: "eyes"
        case .agents: "bird.fill"
        case .toggles: "switch.2"
        case .shortcuts: "keyboard.fill"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .layout: .indigo
        case .general: .gray
        case .menuBar: .blue
        case .appearance: .pink
        case .clipboard: .teal
        case .keepAwake: .orange
        case .agents: .brown
        case .toggles: .green
        case .shortcuts: .purple
        case .about: .secondary
        }
    }
}

/// Settings laid out like System Settings: a sidebar of panes, each a
/// grouped form.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $model.settingsPane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    IconBadge(symbol: pane.symbol, color: pane.color, size: 20)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(210)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch model.settingsPane ?? .general {
                case .layout: LayoutPane(model: model)
                case .general: GeneralPane(model: model)
                case .menuBar: MenuBarPane(model: model)
                case .appearance: AppearancePane(appearance: model.appearance)
                case .clipboard: ClipboardPane(model: model)
                case .keepAwake: KeepAwakePane(model: model)
                case .agents: AgentsPane(model: model)
                case .toggles: TogglesPane()
                case .shortcuts: ShortcutsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((model.settingsPane ?? .general).title)
        }
        .frame(width: 780, height: 600)
    }
}

// MARK: - Layout

private struct LayoutPane: View {
    @Bindable var model: AppModel
    @AppStorage(PrefKey.displayProfiles) private var displayProfiles = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    CardRow(title: "Separate layout at your desk",
                            subtitle: displayProfiles
                                ? "Editing the \(model.layout.profile.title.lowercased()). Barn Owl switches when you connect or disconnect a display."
                                : "Keep one layout for the laptop screen and another while an external display is connected.",
                            symbol: "display.2", color: .teal) {
                        Toggle("", isOn: $displayProfiles).labelsHidden().toggleStyle(.switch)
                    }
                }
                HStack(alignment: .top) {
                    Text("Drag icons between rows. Your menu bar changes right away. Right-click an icon for more options.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Refresh Pictures") { Task { await model.layout.refreshPictures() } }
                        .help("Shows every icon for a moment to photograph it. Nothing is moved.")
                        .disabled(model.layout.isBusy || !model.screenRecordingAllowed)
                }
                LayoutEditorView(model: model)
            }
            .padding(20)
        }
        .sheet(item: $model.iconToReplace) { item in
            CustomIconSheet(model: model, item: item)
        }
    }
}

// MARK: - Clipboard

private struct ClipboardPane: View {
    let model: AppModel
    @AppStorage(PrefKey.clipboardEnabled) private var enabled = true
    @AppStorage(PrefKey.clipboardLimit) private var limit = 50
    @AppStorage(PrefKey.clipboardRemember) private var remember = true
    @AppStorage(PrefKey.dropTrayEnabled) private var dropTray = true
    @AppStorage(PrefKey.dropTrayTab) private var dropTrayTab = true
    @AppStorage(PrefKey.nestKeepsDraggedFiles) private var nestKeepsFiles = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    BadgeLabel(title: "Keep a clipboard history",
                               subtitle: "Press ⌃⌥⌘V to see it. Return pastes into the app you were using.",
                               symbol: "doc.on.clipboard.fill", color: .teal)
                }
                Picker(selection: $limit) {
                    ForEach([20, 50, 100, 200], id: \.self) { Text("\($0) items").tag($0) }
                } label: {
                    BadgeLabel(title: "Remember up to", symbol: "list.number", color: .blue)
                }
                Toggle(isOn: $remember) {
                    BadgeLabel(title: "Keep history after restarting",
                               subtitle: "Text and files only; images stay in memory.",
                               symbol: "externaldrive.fill", color: .gray)
                }
                LabeledContent("Shortcut") { KeyboardShortcuts.Recorder(for: .clipboard) }
            } footer: {
                Text("Copies from password managers are never recorded: they mark them as private, and Barn Owl skips 1Password, Bitwarden, Passwords and Keychain Access.")
            }
            Section {
                Toggle(isOn: $dropTray) {
                    BadgeLabel(title: "Show the Nest when you drag files",
                               subtitle: "It appears under the notch. Drop files to hold them, then drag them out later.",
                               symbol: "tray.and.arrow.down.fill", color: .orange)
                }
                Toggle(isOn: $dropTrayTab) {
                    BadgeLabel(title: "Keep a tab under the notch while the Nest holds files",
                               subtitle: "Hover or click it to drag the files out.",
                               symbol: "tray.full.fill", color: .orange)
                }
                .disabled(!dropTray)
                Toggle(isOn: $nestKeepsFiles) {
                    BadgeLabel(title: "Keep files in the Nest after dragging them out",
                               subtitle: "Off: a file leaves the Nest once you drop it somewhere else.",
                               symbol: "square.on.square", color: .orange)
                }
            } header: {
                Text("Nest")
            } footer: {
                Text("The Nest only remembers where your files are; it never moves or copies them itself. Files you move or delete elsewhere leave the Nest too.")
            }
            Section {
                LabeledContent("\(model.clipboard.entries.count) items, \(model.clipboard.shelf.count) in the nest") {
                    HStack {
                        Button("Open") { model.showClipboard() }
                        Button("Clear History", role: .destructive) { model.clipboard.clear() }
                    }
                }
            }
        }
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @Bindable var appearance: MenuBarAppearance
    @State private var spacing = Double(IconSpacing.current)
    @State private var spacingChanged = false

    var body: some View {
        Form {
            Section {
                OwlPalettePicker()
                OwlPersonalityPicker()
            } header: {
                Text("Owl")
            } footer: {
                Text("The owl in setup, panels and About. In the menu bar it takes the menu bar's colour.")
            }
            Section {
                ZStack {
                    LinearGradient(colors: [.blue.opacity(0.7), .purple.opacity(0.6)], startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                    if appearance.style.isEnabled {
                        MenuBarBackdrop(style: appearance.style)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo")
                        Text("Finder").bold()
                        Text("File   Edit   View").foregroundStyle(.secondary)
                        Spacer()
                        Image(nsImage: MenuBarOwl.image(openness: 1, height: 13)).renderingMode(.template)
                        ForEach(["wifi", "chevron.left", "battery.75percent"], id: \.self) {
                            Image(systemName: $0)
                        }
                        Text("Fri 9:41")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                }
                .frame(height: 30)
                .clipShape(.rect(cornerRadius: 8))
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .accessibilityLabel("Preview of the menu bar")

                Toggle(isOn: $appearance.style.isEnabled) {
                    BadgeLabel(title: "Tint the menu bar", subtitle: "Drawn behind the icons; menus aren't affected.",
                               symbol: "paintbrush.fill", color: .pink)
                }
            }
            if appearance.style.isEnabled {
                Section("Style") {
                    Picker("Shape", selection: $appearance.style.shape) {
                        Text("Full width").tag(MenuBarStyle.Shape.full)
                        Text("Rounded").tag(MenuBarStyle.Shape.rounded)
                        Text("Split").tag(MenuBarStyle.Shape.split)
                    }
                    .pickerStyle(.segmented)
                    ColorPicker("Colour", selection: color(\.tint), supportsOpacity: true)
                    Toggle("Gradient", isOn: $appearance.style.usesGradient)
                    if appearance.style.usesGradient {
                        ColorPicker("Second colour", selection: color(\.gradientEnd), supportsOpacity: true)
                    }
                    Toggle("Border", isOn: $appearance.style.hasBorder)
                    if appearance.style.hasBorder {
                        ColorPicker("Border colour", selection: color(\.border), supportsOpacity: true)
                    }
                    Toggle("Shadow", isOn: $appearance.style.hasShadow)
                }
            }
            Section {
                LabeledContent {
                    HStack {
                        Slider(value: $spacing, in: 4...20, step: 1) { editing in
                            if !editing {
                                IconSpacing.set(Int(spacing))
                                spacingChanged = true
                            }
                        }
                        Text("\(Int(spacing))").monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
                    }
                    .frame(width: 240)
                } label: {
                    BadgeLabel(title: "Space between icons",
                               subtitle: "Less space fits more icons beside the notch. macOS's default is 16.",
                               symbol: "arrow.left.and.right", color: .indigo)
                }
                if spacingChanged {
                    HStack {
                        Text("Apps use the new spacing when they next start; log out and back in to apply it everywhere.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Apply to System Icons") { IconSpacing.restartSystemMenuBar() }
                    }
                }
                Button("Reset to Default") {
                    IconSpacing.set(nil)
                    spacing = Double(IconSpacing.defaultSpacing)
                    spacingChanged = true
                }
            } header: {
                Text("Icon spacing")
            }
        }
    }

    private func color(_ keyPath: WritableKeyPath<MenuBarStyle, StoredColor>) -> Binding<Color> {
        Binding(get: { appearance.style[keyPath: keyPath].color },
                set: { appearance.style[keyPath: keyPath] = StoredColor($0) })
    }
}

/// How much the owl gets up to.
private struct OwlPersonalityPicker: View {
    @AppStorage(PrefKey.owlPersonality) private var personality = OwlPersonality.lively

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Personality", selection: $personality) {
                ForEach(OwlPersonality.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(personality.summary).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Four owls to choose from; the one you pick hops for joy.
private struct OwlPalettePicker: View {
    @AppStorage(PrefKey.owlPalette) private var palette = OwlPalette.golden
    @State private var justPicked: OwlPalette?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(OwlPalette.allCases) { option in
                let selected = palette == option
                Button {
                    palette = option
                    justPicked = option
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        if justPicked == option { justPicked = nil }
                    }
                } label: {
                    VStack(spacing: 6) {
                        WatchingOwl(happy: justPicked == option, playful: false, palette: option)
                            .frame(width: 56, height: 56)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? Brand.accent.opacity(0.16) : Color.primary.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selected ? Brand.accent : Color.clear, lineWidth: 2))
                        Text(option.title).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.3), value: palette)
    }
}

// MARK: - General

private struct GeneralPane: View {
    let model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(PrefKey.agentsEnabled) private var agents = true
    @AppStorage(PrefKey.clipboardEnabled) private var clipboard = true
    @AppStorage(PrefKey.dropTrayEnabled) private var nest = true
    @AppStorage(PrefKey.presenterAutomatic) private var presenter = true
    @AppStorage(PrefKey.barnLowSpaceWarning) private var diskWarning = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    BadgeLabel(title: "Open at login", subtitle: "Start Barn Owl when you log in.",
                               symbol: "power", color: .gray)
                }
                .accessibilityLabel("Open at login")
                .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) { launchAtLogin = $0 } }
            }
            Section {
                Toggle(isOn: $agents) {
                    BadgeLabel(title: "Coding agents",
                               subtitle: "Owlets for Claude Code, Codex and others, and keep awake while they work.",
                               symbol: "bird.fill", color: .brown)
                }
                Toggle(isOn: $clipboard) {
                    BadgeLabel(title: "Clipboard history", subtitle: "Everything you copy, a shortcut away.",
                               symbol: "doc.on.clipboard.fill", color: .teal)
                }
                Toggle(isOn: $nest) {
                    BadgeLabel(title: "The Nest", subtitle: "A shelf under the notch for files you drag.",
                               symbol: "tray.and.arrow.down.fill", color: .orange)
                }
                Toggle(isOn: $presenter) {
                    BadgeLabel(title: "Automatic presenter mode",
                               subtitle: "Hides your icons while you share your screen.",
                               symbol: "sunglasses.fill", color: .indigo)
                }
                Toggle(isOn: $diskWarning) {
                    BadgeLabel(title: "Disk space warnings", subtitle: "A note when your disk is nearly full.",
                               symbol: "externaldrive.fill", color: .gray)
                }
            } header: {
                Text("Features")
            } footer: {
                Text("A feature that's off doesn't run at all. Menu bar hiding and keep awake are always on.")
            }
            Section {
                @Bindable var updater = model.updater
                Toggle(isOn: $updater.checksAutomatically) {
                    BadgeLabel(title: "Automatically check for updates",
                               subtitle: "Looks once a day and asks before installing.",
                               symbol: "arrow.down.circle.fill", color: .green)
                }
                .accessibilityLabel("Automatically check for updates")
                LabeledContent {
                    Button("Check for Updates…") { model.updater.checkForUpdates() }
                        .disabled(!model.updater.canCheck)
                } label: {
                    BadgeLabel(title: "Version \(Bundle.main.shortVersion)", subtitle: "Updates come from GitHub releases.",
                               symbol: "shippingbox.fill", color: .brown)
                }
            }
            Section {
                LabeledContent {
                    Button("Run Setup Again…") { model.showSetup() }
                } label: {
                    BadgeLabel(title: "Setup guide", subtitle: "Walk through arranging icons and shortcuts again.",
                               symbol: "sparkles", color: .pink)
                }
            }
            Section("How to use Barn Owl") {
                hint("cursorarrow.click", "Click the arrow to show or hide icons.")
                hint("option", "Option-click the arrow to show every icon, including always-hidden ones.")
                hint("moon.zzz", "Click the owl (or right-click the arrow) for Keep Awake and quick toggles.")
                hint("command", "Hold ⌘ and drag icons across the | divider to hide or show them.")
            }
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Menu bar

private struct MenuBarPane: View {
    let model: AppModel
    @AppStorage(PrefKey.autoRehide) private var autoRehide = true
    @AppStorage(PrefKey.autoRehideDelay) private var autoRehideDelay = 10.0
    @AppStorage(PrefKey.alwaysHiddenEnabled) private var alwaysHiddenEnabled = false
    @AppStorage(PrefKey.hiddenIconsDisplay) private var display = HiddenIconsDisplay.automatic
    @AppStorage(PrefKey.newIconPlacement) private var newIcons = NewIconPlacement.hidden
    @AppStorage(PrefKey.changeShowDuration) private var changeDuration = 30.0
    @AppStorage(PrefKey.changeLookInterval) private var lookInterval = 0
    @AppStorage(PrefKey.presenterAutomatic) private var presenterAutomatic = true
    @AppStorage(PrefKey.presenterKeepAwake) private var presenterKeepAwake = true
    @AppStorage(PrefKey.presenterHideDesktopIcons) private var presenterHideDesktop = false
    @AppStorage(PrefKey.revealOnHover) private var revealOnHover = false
    @AppStorage(PrefKey.revealOnScroll) private var revealOnScroll = false

    var body: some View {
        Form {
            Section {
                MenuBarDiagram(collapsed: model.sectionState == .collapsed, showsAlwaysHidden: alwaysHiddenEnabled)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                LabeledContent {
                    Button("Open Layout") { model.settingsPane = .layout }
                        .buttonStyle(.glassProminent)
                } label: {
                    BadgeLabel(title: "Arrange icons and groups",
                               subtitle: "Drag icons between the menu bar, hidden and your groups.",
                               symbol: "hand.draw.fill", color: .blue)
                }
            }
            Section {
                HiddenIconsDisplayPicker(selection: $display)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text("Hidden icons appear")
            }
            Section {
                Picker(selection: $changeDuration) {
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                } label: {
                    BadgeLabel(title: "Show changed icons for",
                               subtitle: "Right-click an icon in Layout or the Perch and choose Show When It Changes.",
                               symbol: "bell.badge.fill", color: .orange)
                }
                Picker(selection: $lookInterval) {
                    Text("Only when the network changes").tag(0)
                    Text("Every 2 minutes").tag(2)
                    Text("Every 10 minutes").tag(10)
                } label: {
                    BadgeLabel(title: "Look at icon-only items",
                               subtitle: "Icons without status text are checked by sliding them into view for a moment.",
                               symbol: "eye", color: .blue)
                }
            } header: {
                Text("Show icons when they change")
            }
            Section {
                Toggle(isOn: $presenterAutomatic) {
                    BadgeLabel(title: "Start when you share your screen",
                               subtitle: "And stop when sharing ends. Detected from macOS's own screen-recording indicator.",
                               symbol: "rectangle.on.rectangle", color: .purple)
                }
                Toggle(isOn: $presenterKeepAwake) {
                    BadgeLabel(title: "Keep the Mac and display awake", symbol: "eyes",
                               color: .orange)
                }
                Toggle(isOn: $presenterHideDesktop) {
                    BadgeLabel(title: "Hide desktop icons too", subtitle: "Restarts Finder, so the screen flickers once.",
                               symbol: "menubar.dock.rectangle", color: .teal)
                }
                LabeledContent("Shortcut") { KeyboardShortcuts.Recorder(for: .togglePresenter) }
            } header: {
                Text("Presenter mode")
            } footer: {
                Text("Hides every menu bar icon except the clock and Control Center. Click the arrow for your icons on the Perch.")
            }
            Section("Hiding") {
                Picker(selection: $newIcons) {
                    Text("Hidden").tag(NewIconPlacement.hidden)
                    Text("In the menu bar").tag(NewIconPlacement.visible)
                } label: {
                    BadgeLabel(title: "New icons go", subtitle: "When an app adds an icon Barn Owl hasn't seen before.",
                               symbol: "sparkle", color: .teal)
                }
                Toggle(isOn: $revealOnHover) {
                    BadgeLabel(title: "Show hidden icons when hovering over the arrow", symbol: "cursorarrow.motionlines",
                               color: .blue)
                }
                Toggle(isOn: $revealOnScroll) {
                    BadgeLabel(title: "Scroll over the menu bar to show or hide",
                               subtitle: "Scroll down to show hidden icons, up to hide them.",
                               symbol: "arrow.up.and.down", color: .blue)
                }
                Toggle(isOn: $autoRehide) {
                    BadgeLabel(title: "Hide icons again automatically", symbol: "timer", color: .blue)
                }
                if autoRehide {
                    LabeledContent {
                        HStack {
                            Slider(value: rehideDelay, in: 3...60)
                            Text("\(Int(autoRehideDelay)) s")
                                .monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .frame(width: 240)
                    } label: {
                        Text("After").padding(.leading, 32)
                    }
                }
                Toggle(isOn: $alwaysHiddenEnabled) {
                    BadgeLabel(title: "Always-hidden section",
                               subtitle: "Adds a ⋮ divider. Icons left of it only show with option-click.",
                               symbol: "eye.slash.fill", color: .indigo)
                }
            }
            Section {
                PermissionRow(permission: .accessibility, model: model)
                PermissionRow(permission: .screenRecording, model: model)
            } header: {
                Text("Permissions")
            } footer: {
                Text("Hiding method: \(model.engineName)")
            }
        }
    }

    /// Whole seconds, without the tick marks a stepped Slider draws.
    private var rehideDelay: Binding<Double> {
        Binding { autoRehideDelay } set: { autoRehideDelay = $0.rounded() }
    }
}

// MARK: - Keep awake

private struct KeepAwakePane: View {
    @AppStorage(PrefKey.agentsEnabled) private var agentsEnabled = true
    let model: AppModel
    @AppStorage(PrefKey.keepAwakeAllowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(PrefKey.keepAwakeHotkeyMinutes) private var defaultMinutes = 0
    @AppStorage(PrefKey.keepAwakeStopBelowBattery) private var stopBelowBattery = 10
    @AppStorage(PrefKey.keepAwakeKeepAvailable) private var keepAvailable = false
    @AppStorage(PrefKey.keepAwakeNotify) private var notify = false
    @AppStorage(PrefKey.showKeepAwakeIcon) private var showIcon = true
    @AppStorage(PrefKey.keepAwakeCountdown) private var countdown = true
    @State private var startMinutes = 60
    @State private var editingRule: KeepAwakeRule?
    @State private var closedLid = Preferences.closedLidMode
    @AppStorage(PrefKey.closedLidLocks) private var closedLidLocks = false

    private var keepAwake: KeepAwakeController { model.keepAwake }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconBadge(symbol: keepAwake.isActive ? "eyes" : "moon.zzz",
                              color: keepAwake.isActive ? .orange : .gray, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(keepAwake.isActive ? "Your Mac is staying awake" : "Keep awake is off").font(.headline)
                        TimelineView(.periodic(from: .now, by: 5)) { _ in
                            Text(KeepAwakeFormatter.status(of: keepAwake)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if keepAwake.session != nil {
                        if keepAwake.endDate != nil {
                            Menu("Add Time") {
                                ForEach(KeepAwakeController.extensions, id: \.self) { minutes in
                                    Button("+" + KeepAwakeFormatter.durationLabel(minutes: minutes)) {
                                        keepAwake.extend(minutes: minutes)
                                    }
                                }
                            }
                            .fixedSize()
                        }
                        Button("Stop") { keepAwake.stop() }.controlSize(.large)
                    } else {
                        Picker("", selection: $startMinutes) {
                            ForEach(KeepAwakeController.durations, id: \.self) { minutes in
                                Text(KeepAwakeFormatter.durationLabel(minutes: minutes)).tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        Button("Start") { keepAwake.start(minutes: startMinutes) }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if keepAwake.rules.rules.isEmpty {
                    Text("Rules keep your Mac awake by themselves, for example on power with an external display, or during calls.")
                        .foregroundStyle(.secondary)
                }
                ForEach(keepAwake.rules.rules) { rule in
                    HStack {
                        Image(systemName: rule.conditions.first?.symbol ?? "wand.and.sparkles")
                            .frame(width: 20)
                            .foregroundStyle(keepAwake.activeRule?.id == rule.id ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rule.title)
                            Text(keepAwake.activeRule?.id == rule.id ? "Keeping your Mac awake now"
                                 : !agentsEnabled && rule.conditions.contains(.agentWorking) ? "Agents are off in Settings → General"
                                 : rule.allowDisplaySleep ? "Display may sleep" : "Display stays on")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingRule = rule }
                        Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                            var changed = rule
                            changed.isEnabled = enabled
                            keepAwake.rules.update(changed)
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
                Menu {
                    ForEach(KeepAwakeRule.presets, id: \.self) { preset in
                        Button(preset.title) {
                            var rule = preset
                            rule.id = UUID()
                            keepAwake.rules.add(rule)
                        }
                    }
                    Divider()
                    Button("Custom Rule…") { editingRule = KeepAwakeRule(conditions: []) }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .fixedSize()
            } header: {
                Text("Keep awake automatically")
            }

            Section("Options") {
                Toggle(isOn: $showIcon) {
                    BadgeLabel(title: "Show the owl in the menu bar",
                               subtitle: "Its eyes open while it keeps your Mac awake. Click it for keep awake and toggles; option-click to start or stop.",
                               symbol: "moon.zzz.fill", color: .orange)
                }
                Toggle(isOn: $countdown) {
                    BadgeLabel(title: "Show time left next to the owl",
                               subtitle: "During a timed session, like 42m or 1:05.",
                               symbol: "timer", color: .orange)
                }
                .disabled(!showIcon)
                Toggle(isOn: $allowDisplaySleep) {
                    BadgeLabel(title: "Let the display sleep", subtitle: "Your Mac keeps running; only the screen turns off.",
                               symbol: "display", color: .blue)
                }
                Toggle(isOn: $keepAvailable) {
                    BadgeLabel(title: "Keep me available",
                               subtitle: "Nudges the pointer every few idle minutes so Teams and Slack don't show you as Away. Paused while the display may sleep.",
                               symbol: "person.crop.circle.badge.checkmark", color: .green)
                }
                Picker(selection: $stopBelowBattery) {
                    Text("Never").tag(0)
                    ForEach([5, 10, 20, 30], id: \.self) { Text("\($0)%").tag($0) }
                } label: {
                    BadgeLabel(title: "Stop when battery is below", subtitle: "So a forgotten session can't drain it.",
                               symbol: "battery.25percent", color: .red)
                }
                Toggle(isOn: $notify) {
                    BadgeLabel(title: "Notify me when a session ends", symbol: "bell.fill", color: .pink)
                }
                Picker(selection: $defaultMinutes) {
                    ForEach(KeepAwakeController.durations, id: \.self) { minutes in
                        Text(KeepAwakeFormatter.durationLabel(minutes: minutes)).tag(minutes)
                    }
                } label: {
                    BadgeLabel(title: "Switch and shortcut keep awake for", symbol: "keyboard", color: .purple)
                }
            }

            Section {
                Toggle(isOn: Binding(get: { closedLid }, set: { enabled in
                    Preferences.closedLidMode = enabled
                    closedLid = enabled
                    model.closedLid?.sync()
                })) {
                    BadgeLabel(title: "Keep running with the lid closed",
                               subtitle: "While Barn Owl keeps your Mac awake, even on battery without an external display.",
                               symbol: "laptopcomputer", color: .gray)
                }
                if closedLid {
                    Toggle(isOn: $closedLidLocks) {
                        BadgeLabel(title: "Lock the screen when the lid closes",
                                   subtitle: "So whoever opens it next needs your password.",
                                   symbol: "lock.fill", color: .gray)
                    }
                }
            } header: {
                Text("Closed-lid mode")
            } footer: {
                Text("Close the lid while keep awake is on and your Mac keeps running, on battery too; otherwise it sleeps as usual. No password needed. A closed Mac that keeps running gets warm, so don't put it in a bag like this.")
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(rules: keepAwake.rules, rule: rule)
        }
    }
}

/// A condition's icon and name, with icons in a fixed-width column so the
/// names line up.
private struct ConditionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title)
        }
    }
}

/// Builds a rule from conditions that must all hold.
private struct RuleEditorSheet: View {
    let rules: RuleStore
    @State var rule: KeepAwakeRule
    @Environment(\.dismiss) private var dismiss
    @State private var appBundle = ""
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var start = Calendar.current.date(from: DateComponents(hour: 8)) ?? Date()
    @State private var end = Calendar.current.date(from: DateComponents(hour: 17)) ?? Date()

    private var isNew: Bool { !rules.rules.contains { $0.id == rule.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Rule" : "Edit Rule").font(.title2.bold())
            Text("Keep my Mac awake while all of these are true:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                check(.onPower)
                check(.externalDisplay)
                check(.microphoneInUse)
                check(.downloading)
                if Preferences.agentsEnabled || rule.conditions.contains(.agentWorking) { check(.agentWorking) }
                appCondition
                scheduleCondition
            }
            Toggle("Let the display sleep", isOn: $rule.allowDisplaySleep)
            HStack {
                if !isNew {
                    Button("Delete Rule", role: .destructive) {
                        rules.delete(rule.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    if isNew { rules.add(rule) } else { rules.update(rule) }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(rule.conditions.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear(perform: loadEditableValues)
    }

    private func check(_ condition: RuleCondition) -> some View {
        Toggle(isOn: Binding(get: { rule.conditions.contains(condition) }, set: { on in
            rule.conditions.removeAll { $0 == condition }
            if on { rule.conditions.append(condition) }
        })) {
            ConditionLabel(title: condition.title, symbol: condition.symbol)
        }
        .toggleStyle(.checkbox)
    }

    private var appCondition: some View {
        HStack {
            Toggle(isOn: Binding(get: { currentApp != nil }, set: { on in
                rule.conditions.removeAll { if case .appRunning = $0 { true } else { false } }
                if on, let app = runningApps.first(where: { $0.bundleIdentifier == appBundle }) ?? runningApps.first {
                    appBundle = app.bundleIdentifier ?? ""
                    rule.conditions.append(.appRunning(bundleIdentifier: appBundle, name: app.localizedName ?? "App"))
                }
            })) {
                ConditionLabel(title: "An app is running:", symbol: "app.badge.checkmark")
            }
            .toggleStyle(.checkbox)
            Picker("", selection: Binding(get: { appBundle }, set: { bundle in
                appBundle = bundle
                if currentApp != nil, let app = runningApps.first(where: { $0.bundleIdentifier == bundle }) {
                    rule.conditions.removeAll { if case .appRunning = $0 { true } else { false } }
                    rule.conditions.append(.appRunning(bundleIdentifier: bundle, name: app.localizedName ?? "App"))
                }
            })) {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Text(app.localizedName ?? "App").tag(app.bundleIdentifier ?? "")
                }
            }
            .labelsHidden()
            .frame(width: 170)
        }
    }

    private var scheduleCondition: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { currentSchedule != nil }, set: { on in
                setSchedule(on)
            })) {
                ConditionLabel(title: "During these hours:", symbol: "calendar")
            }
            .toggleStyle(.checkbox)
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { day in
                    let symbol = Calendar.current.veryShortWeekdaySymbols[day - 1]
                    Button(symbol) {
                        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                        if currentSchedule != nil { setSchedule(true) }
                    }
                    .buttonStyle(.bordered)
                    .tint(weekdays.contains(day) ? Brand.accent : .secondary)
                    .controlSize(.small)
                }
                DatePicker("", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                Text("–")
                DatePicker("", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
            }
            .padding(.leading, 22)
            .onChange(of: start) { if currentSchedule != nil { setSchedule(true) } }
            .onChange(of: end) { if currentSchedule != nil { setSchedule(true) } }
        }
    }

    private var currentApp: RuleCondition? {
        rule.conditions.first { if case .appRunning = $0 { true } else { false } }
    }

    private var currentSchedule: RuleCondition? {
        rule.conditions.first { if case .schedule = $0 { true } else { false } }
    }

    private func setSchedule(_ on: Bool) {
        rule.conditions.removeAll { if case .schedule = $0 { true } else { false } }
        guard on else { return }
        let minute = { (date: Date) in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        rule.conditions.append(.schedule(weekdays: weekdays, startMinute: minute(start), endMinute: minute(end)))
    }

    private func loadEditableValues() {
        for condition in rule.conditions {
            switch condition {
            case .appRunning(let bundle, _): appBundle = bundle
            case .schedule(let days, let startMinute, let endMinute):
                weekdays = days
                start = Calendar.current.date(from: DateComponents(hour: startMinute / 60, minute: startMinute % 60)) ?? start
                end = Calendar.current.date(from: DateComponents(hour: endMinute / 60, minute: endMinute % 60)) ?? end
            default: break
            }
        }
        if appBundle.isEmpty { appBundle = runningApps.first?.bundleIdentifier ?? "" }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }
}

// MARK: - Quick toggles

private struct TogglesPane: View {
    @AppStorage(PrefKey.menuShowsDarkMode) private var darkMode = true
    @AppStorage(PrefKey.menuShowsDesktopIcons) private var desktopIcons = true
    @AppStorage(PrefKey.menuShowsHiddenFiles) private var hiddenFiles = true
    @AppStorage(PrefKey.menuShowsMicrophone) private var microphone = true
    @AppStorage(PrefKey.menuShowsSleepDisplay) private var sleepDisplay = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $darkMode) {
                    BadgeLabel(title: "Dark Mode", subtitle: "Switch between light and dark appearance.",
                               symbol: "circle.lefthalf.filled", color: .indigo)
                }
                Toggle(isOn: $desktopIcons) {
                    BadgeLabel(title: "Hide Desktop Icons", subtitle: "Clean desktop for screen sharing.",
                               symbol: "menubar.dock.rectangle", color: .teal)
                }
                Toggle(isOn: $hiddenFiles) {
                    BadgeLabel(title: "Show Hidden Files", subtitle: "Show dotfiles in Finder.",
                               symbol: "eye.fill", color: .gray)
                }
                Toggle(isOn: $microphone) {
                    BadgeLabel(title: "Mute Microphone", subtitle: "Mute the default input for every app at once.",
                               symbol: "mic.slash.fill", color: .red)
                }
                Toggle(isOn: $sleepDisplay) {
                    BadgeLabel(title: "Sleep Display", subtitle: "Turn the screen off right away.",
                               symbol: "moon.fill", color: .blue)
                }
            } header: {
                Text("Show in the quick panel")
            } footer: {
                Text("Open the quick panel from the owl or by right-clicking the arrow. Desktop and hidden-file toggles restart Finder.")
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section {
                recorder("Show or hide icons", "chevron.left.2", .blue, .toggleHiddenItems)
                recorder("Search the menu bar", "magnifyingglass", .teal, .searchItems)
                recorder("Show every icon", "eye.fill", .purple, .showAllItems)
                recorder("Toggle keep awake", "eyes", .orange, .toggleKeepAwake)
                recorder("Presenter mode", "rectangle.on.rectangle", .purple, .togglePresenter)
                recorder("Clipboard history", "doc.on.clipboard", .teal, .clipboard)
            } footer: {
                Text("Click a shortcut field and press the keys you want. Press Delete to clear it.")
            }
        }
    }

    private func recorder(_ title: String, _ symbol: String, _ color: Color,
                          _ name: KeyboardShortcuts.Name) -> some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name)
        } label: {
            BadgeLabel(title: title, symbol: symbol, color: color)
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    @State private var throwOffset = CGSize.zero
    @State private var owlCue: OwlCue?
    @State private var showingCollection = false
    private var collection: OwlCollection { .shared }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                DuskSky().clipShape(.rect(cornerRadius: 18))
                WatchingOwl(entrance: .greet, cue: owlCue)
                    .frame(width: 130, height: 130)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .rotationEffect(.degrees(Double(throwOffset.width) * 0.15))
                    .offset(throwOffset)
                    // Grab the owl and throw it: it flaps back to its spot.
                    .gesture(DragGesture(minimumDistance: 6)
                        .onChanged { throwOffset = $0.translation }
                        .onEnded { _ in
                            withAnimation(.spring(duration: 0.9, bounce: 0.45)) { throwOffset = .zero }
                            owlCue = OwlCue(.thrown)
                        })
                    .zIndex(1)
            }
            .frame(width: 320, height: 170)
            Text("Barn Owl").font(.title.bold())
            Text("Version \(Bundle.main.shortVersion)").foregroundStyle(.secondary)
            Text("Wise about your menu bar. Wide awake when you need it.\nOpen source under the MIT License.")
                .multilineTextAlignment(.center)
            HStack {
                Link("Source Code", destination: URL(string: "https://github.com/marvika/barnowl")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Report an Issue", destination: URL(string: "https://github.com/marvika/barnowl/issues")!)
            }
            Button {
                showingCollection = true
            } label: {
                Label("You've met \(collection.met.count) of \(OwlMoment.allCases.count) owls", systemImage: "sparkles")
            }
            .buttonStyle(.link)
            .padding(.top, 4)
            .popover(isPresented: $showingCollection, arrowEdge: .bottom) { OwlCollectionView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Every owl moment: the ones you've met, and question marks for the rest.
private struct OwlCollectionView: View {
    private var met: Set<OwlMoment> { OwlCollection.shared.met }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Owls you've met").font(.headline)
            Text("\(met.count) of \(OwlMoment.allCases.count). Hover over one to see how you met it.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 8), count: 5), spacing: 10) {
                    ForEach(OwlMoment.allCases) { moment in
                        let known = met.contains(moment)
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(known ? AnyShapeStyle(Brand.dusk) : AnyShapeStyle(Color.primary.opacity(0.06)))
                                if known {
                                    moment.look.padding(10)
                                } else {
                                    // A silhouette, still to be found.
                                    OwlView(blinks: false).padding(10)
                                        .colorMultiply(.black).opacity(0.25)
                                    Text("?").font(.title2.bold()).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 76, height: 76)
                            Text(known ? moment.title : "???")
                                .font(.caption2).lineLimit(1)
                                .foregroundStyle(known ? .primary : .tertiary)
                        }
                        .help(known ? moment.hint : "Not met yet")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 380)
        }
        .padding(16)
        .frame(width: 480)
    }
}

import KeyboardShortcuts
import SwiftUI

/// Settings laid out like System Settings: a sidebar of panes, each a
/// grouped form.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, menuBar, keepAwake, toggles, shortcuts, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .menuBar: "Menu Bar"
            case .keepAwake: "Keep Awake"
            case .toggles: "Toggles"
            case .shortcuts: "Shortcuts"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .menuBar: "menubar.rectangle"
            case .keepAwake: "cup.and.heat.waves.fill"
            case .toggles: "switch.2"
            case .shortcuts: "keyboard.fill"
            case .about: "info"
            }
        }

        var color: Color {
            switch self {
            case .general: .gray
            case .menuBar: .blue
            case .keepAwake: .orange
            case .toggles: .green
            case .shortcuts: .purple
            case .about: .secondary
            }
        }
    }

    let model: AppModel
    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
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
                switch pane ?? .general {
                case .general: GeneralPane(model: model)
                case .menuBar: MenuBarPane(model: model)
                case .keepAwake: KeepAwakePane(keepAwake: model.keepAwake)
                case .toggles: TogglesPane()
                case .shortcuts: ShortcutsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).title)
        }
        .frame(width: 720, height: 520)
    }
}

// MARK: - General

private struct GeneralPane: View {
    let model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    BadgeLabel(title: "Open at login", subtitle: "Start Barkeep when you log in.",
                               symbol: "power", color: .gray)
                }
                .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) { launchAtLogin = $0 } }
            }
            Section {
                LabeledContent {
                    Button("Run Setup Again…") { model.showSetup() }
                } label: {
                    BadgeLabel(title: "Setup guide", subtitle: "Walk through arranging icons and shortcuts again.",
                               symbol: "sparkles", color: .pink)
                }
            }
            Section("How to use Barkeep") {
                hint("cursorarrow.click", "Click the arrow to show or hide icons.")
                hint("option", "Option-click the arrow to show every icon, including always-hidden ones.")
                hint("cursorarrow.click.2", "Right-click the arrow for Keep Awake, quick toggles and Settings.")
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
    @State private var isArranging = false
    @State private var accessibilityTrusted = AccessibilityInventory.isTrusted

    var body: some View {
        Form {
            Section {
                MenuBarDiagram(collapsed: model.sectionState == .collapsed, showsAlwaysHidden: alwaysHiddenEnabled)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                LabeledContent {
                    Button(isArranging ? "Done" : "Arrange Icons…") {
                        isArranging.toggle()
                        if isArranging { model.beginArranging() } else { model.endArranging(collapse: true) }
                    }
                    .buttonStyle(.borderedProminent)
                } label: {
                    BadgeLabel(title: "Arrange icons",
                               subtitle: isArranging
                                   ? "Hold ⌘ and drag icons across the | divider. Click Done when finished."
                                   : "Shows every icon so you can ⌘-drag them where you want.",
                               symbol: "hand.draw.fill", color: .blue)
                }
            }
            Section("Hiding") {
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
            Section("Engine") {
                LabeledContent("Hiding method", value: model.engineName)
                if model.engineNeedsAccessibility {
                    LabeledContent("Accessibility") {
                        if accessibilityTrusted {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Allow…") { AccessibilityInventory.requestTrust() }
                        }
                    }
                }
            }
        }
        .onDisappear {
            if isArranging { model.endArranging(collapse: true) }
        }
    }

    /// Whole seconds, without the tick marks a stepped Slider draws.
    private var rehideDelay: Binding<Double> {
        Binding { autoRehideDelay } set: { autoRehideDelay = $0.rounded() }
    }
}

// MARK: - Keep awake

private struct KeepAwakePane: View {
    let keepAwake: KeepAwakeController
    @AppStorage(PrefKey.keepAwakeAllowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(PrefKey.keepAwakeHotkeyMinutes) private var hotkeyMinutes = 0
    @State private var startMinutes = 60

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconBadge(symbol: keepAwake.isActive ? "cup.and.heat.waves.fill" : "cup.and.saucer",
                              color: keepAwake.isActive ? .orange : .gray, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(keepAwake.isActive ? "Your Mac is staying awake" : "Keep awake is off")
                            .font(.headline)
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text(keepAwake.session.map { KeepAwakeFormatter.status(for: $0) }
                                 ?? "Your Mac sleeps as usual.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if keepAwake.isActive {
                        Button("Stop") { keepAwake.stop() }
                            .controlSize(.large)
                    } else {
                        Picker("", selection: $startMinutes) {
                            ForEach(MenuBuilder.durations, id: \.self) { minutes in
                                Text(KeepAwakeFormatter.durationLabel(minutes: minutes)).tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        Button("Start") { keepAwake.start(minutes: startMinutes) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Options") {
                Toggle(isOn: $allowDisplaySleep) {
                    BadgeLabel(title: "Let the display sleep",
                               subtitle: "The Mac keeps running; only the screen turns off.",
                               symbol: "display", color: .blue)
                }
                Picker(selection: $hotkeyMinutes) {
                    ForEach(MenuBuilder.durations, id: \.self) { minutes in
                        Text(KeepAwakeFormatter.durationLabel(minutes: minutes)).tag(minutes)
                    }
                } label: {
                    BadgeLabel(title: "Shortcut keeps awake for", symbol: "keyboard", color: .purple)
                }
            }
            Section("Coming soon") {
                roadmap("bolt.fill", "On power with an external display")
                roadmap("video.fill", "During calls and screen sharing")
                roadmap("arrow.down.circle.fill", "While downloading or copying files")
                roadmap("laptopcomputer", "With the lid closed")
            }
        }
    }

    private func roadmap(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).foregroundStyle(.secondary)
    }
}

// MARK: - Quick toggles

private struct TogglesPane: View {
    @AppStorage(PrefKey.menuShowsDarkMode) private var darkMode = true
    @AppStorage(PrefKey.menuShowsDesktopIcons) private var desktopIcons = true
    @AppStorage(PrefKey.menuShowsHiddenFiles) private var hiddenFiles = true

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
            } header: {
                Text("Show in the Barkeep menu")
            } footer: {
                Text("Right-click the arrow to use them. Desktop and hidden-file toggles restart Finder.")
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
                recorder("Show every icon", "eye.fill", .purple, .showAllItems)
                recorder("Toggle keep awake", "cup.and.heat.waves.fill", .orange, .toggleKeepAwake)
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
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 12) {
            AppMark(size: 80)
            Text("Barkeep").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Tidies your menu bar and keeps your Mac awake.\nOpen source under the MIT License.")
                .multilineTextAlignment(.center)
            HStack {
                Link("Source Code", destination: URL(string: "https://github.com/marvika/macos-menubar")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Report an Issue", destination: URL(string: "https://github.com/marvika/macos-menubar/issues")!)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

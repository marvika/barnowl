import KeyboardShortcuts
import SwiftUI

/// Settings laid out like System Settings: a sidebar of panes, each a
/// grouped form.
enum SettingsPane: String, CaseIterable, Identifiable {
    case layout, general, menuBar, keepAwake, toggles, shortcuts, about
    var id: Self { self }

    var title: String {
        switch self {
        case .layout: "Layout"
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
        case .layout: "square.grid.3x1.below.line.grid.1x2"
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
        case .layout: .indigo
        case .general: .gray
        case .menuBar: .blue
        case .keepAwake: .orange
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
                case .keepAwake: KeepAwakePane(model: model)
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
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Drag icons between rows. Your menu bar changes right away. Right-click an icon for more options.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LayoutEditorView(model: model)
            }
            .padding(20)
        }
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
    @AppStorage(PrefKey.hiddenIconsDisplay) private var display = HiddenIconsDisplay.automatic
    @AppStorage(PrefKey.newIconPlacement) private var newIcons = NewIconPlacement.hidden

    var body: some View {
        Form {
            Section {
                MenuBarDiagram(collapsed: model.sectionState == .collapsed, showsAlwaysHidden: alwaysHiddenEnabled)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                LabeledContent {
                    Button("Open Layout") { model.settingsPane = .layout }
                        .buttonStyle(.borderedProminent)
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
            Section("Hiding") {
                Picker(selection: $newIcons) {
                    Text("Hidden").tag(NewIconPlacement.hidden)
                    Text("In the menu bar").tag(NewIconPlacement.visible)
                } label: {
                    BadgeLabel(title: "New icons go", subtitle: "When an app adds an icon Barkeep hasn't seen before.",
                               symbol: "sparkle", color: .teal)
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
    let model: AppModel
    @AppStorage(PrefKey.keepAwakeAllowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(PrefKey.keepAwakeHotkeyMinutes) private var defaultMinutes = 0
    @AppStorage(PrefKey.keepAwakeStopBelowBattery) private var stopBelowBattery = 10
    @AppStorage(PrefKey.keepAwakeKeepAvailable) private var keepAvailable = false
    @AppStorage(PrefKey.keepAwakeNotify) private var notify = false
    @AppStorage(PrefKey.showKeepAwakeIcon) private var showIcon = true
    @State private var startMinutes = 60
    @State private var editingRule: KeepAwakeRule?
    @State private var closedLid = ClosedLidMode.isEnabled

    private var keepAwake: KeepAwakeController { model.keepAwake }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconBadge(symbol: keepAwake.isActive ? "cup.and.heat.waves.fill" : "cup.and.saucer",
                              color: keepAwake.isActive ? .orange : .gray, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(keepAwake.isActive ? "Your Mac is staying awake" : "Keep awake is off").font(.headline)
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text(KeepAwakeFormatter.status(of: keepAwake)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if keepAwake.session != nil {
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
                            .buttonStyle(.borderedProminent)
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
                    BadgeLabel(title: "Show the cup in the menu bar",
                               subtitle: "Click it for keep awake and toggles. Option-click to start or stop.",
                               symbol: "cup.and.saucer.fill", color: .orange)
                }
                Toggle(isOn: $allowDisplaySleep) {
                    BadgeLabel(title: "Let the display sleep", subtitle: "Your Mac keeps running; only the screen turns off.",
                               symbol: "display", color: .blue)
                }
                Toggle(isOn: $keepAvailable) {
                    BadgeLabel(title: "Keep me available",
                               subtitle: "Nudges the pointer every few idle minutes so Teams and Slack don't show you as Away.",
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
                    if ClosedLidMode.set(enabled) {
                        Preferences.closedLidMode = enabled
                    }
                    closedLid = ClosedLidMode.isEnabled
                })) {
                    BadgeLabel(title: "Keep running with the lid closed",
                               subtitle: "Even without an external display. Asks for your password to switch.",
                               symbol: "laptopcomputer", color: .gray)
                }
            } header: {
                Text("Closed-lid mode")
            } footer: {
                Text("A closed Mac that keeps running gets warm and uses battery. Don't put it in a bag like this. Barkeep turns this off again when it quits.")
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(rules: keepAwake.rules, rule: rule)
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
                .buttonStyle(.borderedProminent)
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
            Label(condition.title, systemImage: condition.symbol)
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
                Label("An app is running:", systemImage: "app.badge.checkmark")
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
                Label("During these hours:", systemImage: "calendar")
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
                    .tint(weekdays.contains(day) ? .accentColor : .secondary)
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
                Text("Open the quick panel from the cup icon or by right-clicking the arrow. Desktop and hidden-file toggles restart Finder.")
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

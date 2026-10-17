import KeyboardShortcuts
import SwiftUI

/// Everything for getting work done in one place: keep awake, its rules and
/// the quick toggles. Opens from the cup icon or a right-click on the arrow.
struct QuickPanelView: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KeepAwakeCard(model: model, close: close)
            Divider()
            TogglesGrid(model: model)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .padding(FloatingPanel.shadowInset)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            QuickFooterButton(symbol: "magnifyingglass", help: "Search the menu bar") {
                close()
                model.showSearch()
            }
            QuickFooterButton(symbol: "doc.on.clipboard", help: "Clipboard history") {
                close()
                model.showClipboard()
            }
            QuickFooterButton(symbol: "square.grid.3x1.below.line.grid.1x2", help: "Arrange icons") {
                close()
                model.showSettings(.layout)
            }
            QuickFooterButton(symbol: "gearshape", help: "Settings") {
                close()
                model.showSettings()
            }
            Spacer()
            QuickFooterButton(symbol: "power", help: "Quit Barn Owl") { NSApp.terminate(nil) }
        }
    }
}

private struct KeepAwakeCard: View {
    let model: AppModel
    let close: () -> Void
    @AppStorage(PrefKey.keepAwakeAllowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(PrefKey.keepAwakeKeepAvailable) private var keepAvailable = false
    @AppStorage(PrefKey.keepAwakeHotkeyMinutes) private var defaultMinutes = 0
    @State private var showingUntil = false
    @State private var untilTime = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()

    private var keepAwake: KeepAwakeController { model.keepAwake }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AwakeOwlBadge(keepAwake: keepAwake, presenting: model.presenter.isPresenting)
                    .zIndex(1) // so the owl's speech bubble shows over the title
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake").font(.headline)
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        Text(KeepAwakeFormatter.status(of: keepAwake))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { keepAwake.session != nil },
                    set: { $0 ? keepAwake.start(minutes: defaultMinutes) : keepAwake.stop() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Keep awake")
            }
            if keepAwake.endDate != nil {
                HStack(spacing: 6) {
                    Text("Add").font(.callout).foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .leading)
                    ForEach(KeepAwakeController.extensions, id: \.self) { minutes in
                        DurationChip(title: "+" + KeepAwakeFormatter.durationLabel(minutes: minutes)) {
                            keepAwake.extend(minutes: minutes)
                        }
                        .help("Keep awake \(KeepAwakeFormatter.durationLabel(minutes: minutes)) longer")
                    }
                }
            }
            HStack(spacing: 6) {
                if keepAwake.endDate != nil {
                    // Next to "Add", these start the session over.
                    Text("Set").font(.callout).foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .leading)
                }
                ForEach([15, 60, 120, 240, 0], id: \.self) { minutes in
                    DurationChip(title: minutes == 0 ? "∞" : KeepAwakeFormatter.durationLabel(minutes: minutes)) {
                        keepAwake.start(minutes: minutes)
                    }
                    .help(minutes == 0 ? "Until you stop it" : "For \(KeepAwakeFormatter.durationLabel(minutes: minutes))")
                }
                Menu {
                    Button("Until a Time…") { showingUntil = true }
                    Menu("While an App Is Running") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? "App") {
                                keepAwake.start(.whileAppRunning(bundleIdentifier: app.bundleIdentifier ?? "",
                                                                 name: app.localizedName ?? "App"))
                            }
                        }
                    }
                    Button("Until Downloads Finish") { keepAwake.start(.whileDownloading) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .popover(isPresented: $showingUntil) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Keep awake until").font(.headline)
                        DatePicker("", selection: $untilTime, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.stepperField)
                        Button("Start") {
                            keepAwake.start(.until(Self.nextOccurrence(of: untilTime)))
                            showingUntil = false
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(14)
                }
            }
            HStack(spacing: 14) {
                Toggle("Let display sleep", isOn: $allowDisplaySleep)
                Toggle("Keep me available", isOn: $keepAvailable)
                    .help("Nudges the pointer every few idle minutes so Teams and Slack don't show you as Away.")
            }
            .toggleStyle(.checkbox)
            .font(.callout)

            let rules = keepAwake.rules.rules
            if !rules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RULES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(rules.prefix(4)) { rule in
                        RuleRow(rule: rule, isActive: keepAwake.activeRule?.id == rule.id) { enabled in
                            var changed = rule
                            changed.isEnabled = enabled
                            keepAwake.rules.update(changed)
                        }
                    }
                }
            }
            Button {
                close()
                model.showSettings(.keepAwake)
            } label: {
                Label(rules.isEmpty ? "Keep awake automatically…" : "Edit rules…", systemImage: "wand.and.sparkles")
                    .font(.callout)
            }
            .buttonStyle(.link)
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    /// The picked time today, or tomorrow if it has passed.
    static func nextOccurrence(of time: Date, now: Date = Date()) -> Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return Calendar.current.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? time
    }
}

private struct RuleRow: View {
    let rule: KeepAwakeRule
    let isActive: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: rule.conditions.first?.symbol ?? "wand.and.sparkles")
                .frame(width: 16)
                .foregroundStyle(isActive ? .orange : .secondary)
            Text(rule.title).font(.callout).lineLimit(1)
            Spacer()
            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { setEnabled($0) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .accessibilityLabel(rule.title)
        }
    }
}

private struct DurationChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

/// The quick toggles as tiles, like Control Center.
struct TogglesGrid: View {
    let model: AppModel
    @AppStorage(PrefKey.menuShowsDarkMode) private var showDarkMode = true
    @AppStorage(PrefKey.menuShowsDesktopIcons) private var showDesktop = true
    @AppStorage(PrefKey.menuShowsHiddenFiles) private var showHiddenFiles = true
    @AppStorage(PrefKey.menuShowsMicrophone) private var showMicrophone = true
    @AppStorage(PrefKey.menuShowsSleepDisplay) private var showSleepDisplay = true
    /// Bumped after each toggle so the tiles re-read the system state.
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ToggleTile(title: "Presenting", symbol: "rectangle.on.rectangle", isOn: model.presenter.isPresenting) {
                Task { await model.presenter.toggle() }
            }
            if showDarkMode {
                ToggleTile(title: "Dark Mode", symbol: "circle.lefthalf.filled", isOn: QuickToggles.isDarkMode) {
                    run(QuickToggles.toggleDarkMode)
                }
            }
            if showMicrophone {
                ToggleTile(title: QuickToggles.isMicrophoneMuted ? "Mic Muted" : "Microphone",
                           symbol: QuickToggles.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill",
                           isOn: QuickToggles.isMicrophoneMuted) { run(QuickToggles.toggleMicrophone) }
            }
            if showDesktop {
                ToggleTile(title: "Hide Desktop", symbol: "menubar.dock.rectangle",
                           isOn: QuickToggles.desktopIconsHidden) { run(QuickToggles.toggleDesktopIcons) }
            }
            if showHiddenFiles {
                ToggleTile(title: "Hidden Files", symbol: "eye.fill", isOn: QuickToggles.hiddenFilesShown) {
                    run(QuickToggles.toggleHiddenFiles)
                }
            }
            if showSleepDisplay {
                ToggleTile(title: "Sleep Display", symbol: "moon.fill", isOn: false) {
                    QuickToggles.sleepDisplay()
                }
            }
        }
    }

    private func run(_ action: @escaping @MainActor () -> Void) {
        action()
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            refresh += 1
        }
    }
}

private struct ToggleTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? .white : .primary)
                    .frame(width: 28, height: 28)
                    .background(isOn ? Color.accentColor : Color.primary.opacity(0.1), in: .circle)
                Text(title).font(.callout).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color.primary.opacity(hovering ? 0.12 : 0.06), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct QuickFooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 30, height: 26)
                .background(hovering ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The owl with its eyes open while keeping awake, inside a ring that runs
/// down as a timed session does.
struct AwakeOwlBadge: View {
    let keepAwake: KeepAwakeController
    /// While presenting, the owl wears shades.
    var presenting = false
    var size: CGFloat = 40

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack {
                Circle()
                    .fill(keepAwake.isActive ? Brand.indigo.opacity(0.55) : Color.primary.opacity(0.08))
                if let fraction = keepAwake.remainingFraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Brand.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.5)
                        .animation(.linear(duration: 1), value: fraction)
                }
                WatchingOwl(eyesOpen: keepAwake.isActive, playful: false, snores: false,
                            accessory: presenting ? .sunglasses : nil)
                    .padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.35), value: keepAwake.isActive)
        .accessibilityLabel(keepAwake.isActive ? "Keeping your Mac awake" : "Keep awake is off")
    }
}

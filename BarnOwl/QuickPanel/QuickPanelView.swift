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
            // On a small screen the middle scrolls, so the footer is always in reach.
            ViewThatFits(in: .vertical) {
                middle
                ScrollView { middle }.scrollIndicators(.automatic)
            }
            .frame(maxHeight: Self.roomForMiddle)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .owlPanel()
        .padding(FloatingPanel.shadowInset)
    }

    private var middle: some View {
        VStack(alignment: .leading, spacing: 14) {
            TogglesGrid(model: model)
            // Agents off: no card at all, not even the weekly recap.
            if Preferences.agentsEnabled { OwletsCard(model: model, close: close) }
            DiskGlance(model: model, close: close)
        }
    }

    /// The screen's height less the keep-awake card, the footer and margins.
    private static var roomForMiddle: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return max(240, screen - 330)
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
            if Preferences.captureEnabled {
                QuickFooterButton(symbol: "camera.viewfinder", help: "Capture an area or a window") {
                    close()
                    // Once the panel has gone.
                    Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        model.capture.start(.area)
                    }
                }
            }
            QuickFooterButton(symbol: "menubar.rectangle", help: "Arrange menu bar icons") {
                close()
                model.showSettings(.layout)
            }
            QuickFooterButton(symbol: "gearshape", help: "Settings") {
                close()
                model.showSettings()
            }
            Spacer()
            QuickFooterButton(symbol: "arrow.down.circle", help: "Check for Updates…") {
                close()
                model.updater.checkForUpdates()
            }
            .disabled(!model.updater.canCheck)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AwakeOwlBadge(model: model, size: 60)
                    .zIndex(1) // so the owl's speech bubble shows over the title
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Keep Awake").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(headline(at: context.date))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: headline(at: context.date))
                        Text(detail(at: context.date))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { keepAwake.session != nil },
                    set: { $0 ? keepAwake.start(minutes: defaultMinutes) : keepAwake.stop() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Keep awake")
            }
            // One row: how long, or while a timer runs, how much longer.
            HStack(spacing: 6) {
                if keepAwake.endDate != nil {
                    ForEach(KeepAwakeController.extensions, id: \.self) { minutes in
                        DurationChip(title: "+" + KeepAwakeFormatter.durationLabel(minutes: minutes)) {
                            keepAwake.extend(minutes: minutes)
                        }
                        .help("Keep awake \(KeepAwakeFormatter.durationLabel(minutes: minutes)) longer")
                    }
                } else {
                    ForEach([15, 60, 120, 240, 0], id: \.self) { minutes in
                        DurationChip(title: minutes == 0 ? "∞" : KeepAwakeFormatter.durationLabel(minutes: minutes)) {
                            keepAwake.start(minutes: minutes)
                        }
                        .help(minutes == 0 ? "Until you stop it" : "For \(KeepAwakeFormatter.durationLabel(minutes: minutes))")
                    }
                }
                Spacer(minLength: 0)
                moreMenu
            }
            if allowDisplaySleep || keepAvailable {
                HStack(spacing: 6) {
                    if allowDisplaySleep { OptionTag(title: "Display may sleep", symbol: "moon") }
                    if keepAvailable {
                        OptionTag(title: allowDisplaySleep ? "Available (paused)" : "Staying available",
                                  symbol: "person.wave.2")
                            .help(allowDisplaySleep ? "Keep me available pauses while the display may sleep." : "")
                    }
                }
            }

            let rules = keepAwake.rules.rules.filter { Preferences.agentsEnabled || !$0.conditions.contains(.agentWorking) }
            if !rules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Rules").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit…") {
                            close()
                            model.showSettings(.keepAwake)
                        }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.tint)
                    }
                    ForEach(rules.prefix(3)) { rule in
                        RuleRow(rule: rule, isActive: keepAwake.activeRule?.id == rule.id) { enabled in
                            var changed = rule
                            changed.isEnabled = enabled
                            keepAwake.rules.update(changed)
                        }
                    }
                }
            } else {
                Button {
                    close()
                    model.showSettings(.keepAwake)
                } label: {
                    Label("Keep awake automatically…", systemImage: "wand.and.sparkles").font(.callout)
                }
                .buttonStyle(.plain).foregroundStyle(.tint)
            }
        }
    }

    /// The big line: time left, or simply on or off.
    private func headline(at date: Date) -> String {
        if let end = keepAwake.endDate {
            let left = max(0, Int(end.timeIntervalSince(date)))
            let hours = left / 3600, minutes = left / 60 % 60, seconds = left % 60
            return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                             : String(format: "%d:%02d", minutes, seconds)
        }
        return keepAwake.isActive ? "Awake" : "Off"
    }

    private func detail(at date: Date) -> String {
        if let end = keepAwake.endDate { return "left · ends at \(end.formatted(date: .omitted, time: .shortened))" }
        if !keepAwake.isActive, !keepAwake.stoppedForBattery { return "Your Mac sleeps as usual" }
        return KeepAwakeFormatter.status(of: keepAwake)
    }

    /// Everything else: other ways to stay awake, starting over, and the options.
    private var moreMenu: some View {
        Menu {
            if keepAwake.endDate != nil {
                Menu("Start Over") {
                    ForEach([15, 60, 120, 240, 0], id: \.self) { minutes in
                        Button(minutes == 0 ? "Until I Stop It" : "For \(KeepAwakeFormatter.durationLabel(minutes: minutes))") {
                            keepAwake.start(minutes: minutes)
                        }
                    }
                }
            }
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
            Divider()
            Toggle("Let Display Sleep", isOn: $allowDisplaySleep)
            Toggle("Keep Me Available", isOn: $keepAvailable)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More keep-awake options")
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help("More ways to keep awake, and options")
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
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
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

/// A quiet note that an option is on.
private struct OptionTag: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: .capsule)
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
            Text(rule.title).font(.callout).lineLimit(1).help(rule.title)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
            ToggleTile(title: "Presenting", symbol: model.presenter.isPresenting ? "sunglasses.fill" : "rectangle.on.rectangle", isOn: model.presenter.isPresenting) {
                Task { await model.presenter.toggle() }
            }
            if showDarkMode {
                ToggleTile(title: "Dark Mode", symbol: "circle.lefthalf.filled", isOn: QuickToggles.isDarkMode) {
                    OwlCues.shared.quickPanel(QuickToggles.isDarkMode ? .lightsOn : .lightsOut)
                    run(QuickToggles.toggleDarkMode)
                }
            }
            if showMicrophone {
                ToggleTile(title: QuickToggles.isMicrophoneMuted ? "Muted" : "Mic",
                           symbol: QuickToggles.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill",
                           isOn: QuickToggles.isMicrophoneMuted) {
                    OwlCues.shared.quickPanel(QuickToggles.isMicrophoneMuted ? .listening : .shush)
                    run(QuickToggles.toggleMicrophone)
                }
            }
            if showDesktop {
                ToggleTile(title: "Desktop", symbol: QuickToggles.desktopIconsHidden ? "eye.slash" : "menubar.dock.rectangle",
                           isOn: QuickToggles.desktopIconsHidden) {
                    OwlCues.shared.quickPanel(QuickToggles.desktopIconsHidden ? .backAgain : .peekaboo)
                    run(QuickToggles.toggleDesktopIcons)
                }
            }
            if showHiddenFiles {
                ToggleTile(title: "Hidden Files", symbol: "eye.fill", isOn: QuickToggles.hiddenFilesShown) {
                    OwlCues.shared.quickPanel(QuickToggles.hiddenFilesShown ? .unseen : .secrets)
                    run(QuickToggles.toggleHiddenFiles)
                }
            }
            if showSleepDisplay {
                ToggleTile(title: "Sleep Screen", symbol: "moon.fill", isOn: false) {
                    OwlCues.shared.quickPanel(.nightNight)
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
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? .white : .primary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isOn)
                    .frame(width: 46, height: 46)
                    .background(isOn ? AnyShapeStyle(Brand.accent.gradient)
                                     : AnyShapeStyle(Color.primary.opacity(hovering ? 0.16 : 0.09)), in: .circle)
                    .shadow(color: isOn ? Brand.accent.opacity(0.45) : .clear, radius: 6, y: 2)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.85)
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3), value: isOn)
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
                .background(hovering ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: Theme.rowRadius))
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
    let model: AppModel
    var size: CGFloat = 40
    @State private var power = SystemConditions.power()

    private var keepAwake: KeepAwakeController { model.keepAwake }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
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
                let outfit = outfit(at: context.date)
                WatchingOwl(eyesOpen: keepAwake.isActive, snores: false,
                            tired: outfit.prop == .thermos || batteryLow, accessory: outfit,
                            cue: OwlCues.shared.quickPanel)
                    .padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.35), value: keepAwake.isActive)
        .accessibilityLabel(keepAwake.isActive ? "Keeping your Mac awake" : "Keep awake is off")
        .task {
            // Power changes slowly; a look every few seconds is plenty.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                let now = SystemConditions.power()
                if now.onAC && !power.onAC { OwlCues.shared.quickPanel(.charged) }
                power = now
                if batteryLow { OwlMoment.runningLow.meet() }
            }
        }
    }

    private var batteryLow: Bool {
        !power.onAC && (power.batteryPercent ?? 100) < 20
    }

    /// What the owl wears says what's going on: shades while presenting, a
    /// headset during a call, coffee the longer it stays up, a blanket in
    /// closed-lid mode, glasses at the desk.
    private func outfit(at date: Date) -> OwlOutfit {
        var outfit = OwlOutfit.seasonal
        if model.layout.profile == .desk { outfit = outfit + .glasses }
        if Preferences.closedLidMode { outfit = outfit + .blanket }
        if keepAwake.session != nil, let start = keepAwake.sessionStart {
            let hours = date.timeIntervalSince(start) / 3600
            if hours >= 10 {
                outfit = outfit + .thermos
            } else if hours >= 5 {
                outfit = outfit + .twoCoffees
            } else if hours >= 2 {
                outfit = outfit + .coffee
            }
        }
        if keepAwake.isActive, keepAwake.activeRule?.conditions.contains(.microphoneInUse) == true {
            outfit = outfit + .headset
        }
        if model.presenter.isPresenting { outfit = outfit + .sunglasses }
        return outfit
    }
}

/// How full the disk is, at a glance; opens the Barn.
private struct DiskGlance: View {
    let model: AppModel
    let close: () -> Void
    @State private var space = DemoMode.isOn ? BarnDemo.space : DiskSpace.current()

    /// Under a tenth free, or under 20 GB.
    private var low: Bool {
        guard let space else { return false }
        return space.freeFraction < 0.1 || space.available < 20_000_000_000
    }

    var body: some View {
        if let space {
            Button {
                close()
                model.showBarn()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: 1 - space.freeFraction)
                            .stroke(low ? Brand.amber : Brand.lavender, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Bytes.format(space.available)) free").font(.callout.weight(.semibold)).monospacedDigit()
                        Text(low ? "Your disk is nearly full" : "of \(Bytes.format(space.total))")
                            .font(.caption).foregroundStyle(low ? Brand.amber : .secondary)
                    }
                    Spacer()
                    Text("Tidy Up").font(.callout)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: Theme.cardRadius))
                .contentShape(.rect(cornerRadius: Theme.cardRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Bytes.format(space.available)) free. Open the Barn to free up space.")
        }
    }
}

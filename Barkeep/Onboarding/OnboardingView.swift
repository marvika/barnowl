import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// First-run setup: five short steps, each with one thing to do.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, arrange, shortcuts, preferences, done
    }

    let model: AppModel
    let finish: () -> Void

    @State private var step: Step = .welcome
    @State private var demoCollapsed = true
    @State private var isArranging = false
    @State private var accessibilityTrusted = AccessibilityInventory.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .arrange: arrange
                case .shortcuts: shortcuts
                case .preferences: preferences
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: step == .welcome || step == .done ? .center : .topLeading)
            .padding(.horizontal, 40)
            .padding(.top, step == .welcome || step == .done ? 24 : 52)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            footer
        }
        .frame(width: 600, height: 500)
        .animation(.smooth(duration: 0.35), value: step)
        .onChange(of: step) { _, newStep in
            if newStep != .arrange, isArranging {
                isArranging = false
                model.endArranging(collapse: false)
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            AppMark(size: 84)
            Text("Welcome to Barkeep").font(.largeTitle.bold())
            Text("A tidier menu bar, and a Mac that stays awake when you need it to.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                BadgeLabel(title: "Hide the clutter", subtitle: "Keep only the icons you use in sight.",
                           symbol: "rectangle.compress.vertical", color: .blue)
                BadgeLabel(title: "Keep awake", subtitle: "For an hour, indefinitely, or while an app runs.",
                           symbol: "cup.and.heat.waves.fill", color: .orange)
                BadgeLabel(title: "Quick toggles", subtitle: "Dark mode, desktop icons and more in one click.",
                           symbol: "switch.2", color: .green)
            }
            .padding(.top, 8)
        }
    }

    private var arrange: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Choose what stays visible",
                   "Barkeep put an arrow next to Control Center. Icons to the left of its | divider are hidden until you click the arrow.")
            MenuBarDiagram(collapsed: demoCollapsed)
                .onTapGesture { demoCollapsed.toggle() }
                .task {
                    // Gentle loop so the idea is clear without reading.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1.8))
                        demoCollapsed.toggle()
                    }
                }
            VStack(alignment: .leading, spacing: 10) {
                instruction(1, "Click **Show My Icons** below.")
                instruction(2, "Hold **⌘** and drag the icons you use to the **right** of the | divider.")
                instruction(3, "Leave the rest on the left. They hide when you click the arrow.")
            }
            HStack {
                Button(isArranging ? "Done Arranging" : "Show My Icons") {
                    isArranging.toggle()
                    if isArranging { model.beginArranging() } else { model.endArranging(collapse: true) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if isArranging {
                    Label("Icons stay visible until you're done.", systemImage: "hand.draw")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if model.engineNeedsAccessibility {
                accessibilityRow
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Shortcuts", "Use the keyboard instead of reaching for the arrow. Click a field to record a new shortcut.")
            Card {
                CardRow(title: "Show or hide icons", symbol: "chevron.left.2", color: .blue) {
                    KeyboardShortcuts.Recorder(for: .toggleHiddenItems)
                }
                CardRow(title: "Toggle keep awake", symbol: "cup.and.heat.waves.fill", color: .orange) {
                    KeyboardShortcuts.Recorder(for: .toggleKeepAwake)
                }
                CardRow(title: "Show every icon", symbol: "eye", color: .purple) {
                    KeyboardShortcuts.Recorder(for: .showAllItems)
                }
            }
            Label("Option-click the arrow to show every icon. Right-click it for the Barkeep menu.",
                  systemImage: "lightbulb")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var preferences: some View {
        PreferencesStep()
    }

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .symbolEffect(.bounce, value: step)
            Text("You're all set").font(.largeTitle.bold())
            Text("Right-click the arrow any time for Keep Awake, quick toggles and Settings.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            MenuBarDiagram(collapsed: true).frame(maxWidth: 420).padding(.top, 8)
        }
    }

    // MARK: Pieces

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: s == step ? 18 : 7, height: 7)
                }
            }
            .animation(.smooth, value: step)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            if step != .welcome && step != .done {
                Button("Back") { move(-1) }
                    .controlSize(.large)
            }
            Button(primaryTitle) {
                if step == .done { finish() } else { move(1) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .background(.bar)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .done: "Start Using Barkeep"
        default: "Continue"
        }
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func instruction(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: .circle)
            Text(text)
        }
    }

    private var accessibilityRow: some View {
        HStack {
            BadgeLabel(title: "Accessibility access",
                       subtitle: "macOS 27 needs it to tell which icons you put where.",
                       symbol: "accessibility", color: .blue)
            Spacer()
            if accessibilityTrusted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Allow…") { AccessibilityInventory.requestTrust() }
            }
        }
        .task {
            while !Task.isCancelled && !accessibilityTrusted {
                try? await Task.sleep(for: .seconds(1))
                accessibilityTrusted = AccessibilityInventory.isTrusted
            }
        }
    }
}

private struct PreferencesStep: View {
    @AppStorage(PrefKey.autoRehide) private var autoRehide = true
    @AppStorage(PrefKey.autoRehideDelay) private var autoRehideDelay = 10.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A couple of choices").font(.title.bold())
                Text("You can change these later in Settings.").foregroundStyle(.secondary)
            }
            Card {
                CardRow(title: "Open Barkeep at login", subtitle: "Recommended, so your menu bar stays tidy.",
                        symbol: "power", color: .gray) {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            LaunchAtLogin.set(enabled) { launchAtLogin = $0 }
                        }
                }
                CardRow(title: "Hide icons again after", subtitle: "Once you've revealed them.",
                        symbol: "timer", color: .blue) {
                    Picker("", selection: rehideChoice) {
                        Text("5 s").tag(5.0)
                        Text("10 s").tag(10.0)
                        Text("30 s").tag(30.0)
                        Text("Never").tag(0.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
        }
    }

    private var rehideChoice: Binding<Double> {
        Binding {
            autoRehide ? autoRehideDelay : 0
        } set: { value in
            autoRehide = value > 0
            if value > 0 { autoRehideDelay = value }
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Registers or unregisters, and reports the real state back if it failed.
    @MainActor
    static func set(_ enabled: Bool, correct: (Bool) -> Void) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription)")
            correct(isEnabled)
        }
    }
}

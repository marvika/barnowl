import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// First-run setup: six short steps under a dusk sky, with the owl along.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, display, arrange, shortcuts, preferences, done
    }

    let model: AppModel
    let finish: () -> Void

    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .arrange: arrange
                case .display: DisplayStep(model: model)
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
        .frame(width: 680, height: 600)
        .background(DuskSky())
        // The sky is always dark, so the setup guide is too.
        .environment(\.colorScheme, .dark)
        .tint(Brand.lavender)
        .animation(.smooth(duration: 0.35), value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            WelcomeOwl()
                .frame(width: 160, height: 160)
            Text("Welcome to Barn Owl").font(.largeTitle.bold())
            Text("Wise about your menu bar. Wide awake when you need it.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                BadgeLabel(title: "A tidy menu bar",
                           subtitle: "Arrange, hide and group your icons. Nothing gets lost behind the notch.",
                           symbol: "rectangle.compress.vertical", color: Brand.lavender)
                BadgeLabel(title: "Wide awake", subtitle: "For an hour, while an app runs, or automatically by rules.",
                           symbol: "eyes", color: Brand.amber)
                BadgeLabel(title: "Handy helpers",
                           subtitle: "Search, quick toggles, clipboard history and a nest for your files.",
                           symbol: "sparkles", color: .teal)
            }
            .padding(.top, 6)
        }
    }

    private var arrange: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Choose what stays visible",
                   "Drag icons between the rows. Your menu bar changes as you go. Groups and more are in Settings → Layout.")
            ScrollView {
                LayoutEditorView(model: model, compact: true)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Shortcuts", "Use the keyboard instead of reaching for the arrow. Click a field to record a new shortcut.")
            Card {
                CardRow(title: "Show or hide icons", symbol: "chevron.left.2", color: .blue) {
                    KeyboardShortcuts.Recorder(for: .toggleHiddenItems)
                }
                CardRow(title: "Toggle keep awake", symbol: "eyes", color: .orange) {
                    KeyboardShortcuts.Recorder(for: .toggleKeepAwake)
                }
                CardRow(title: "Search the menu bar", symbol: "magnifyingglass", color: .teal) {
                    KeyboardShortcuts.Recorder(for: .searchItems)
                }
                CardRow(title: "Show every icon", symbol: "eye", color: .purple) {
                    KeyboardShortcuts.Recorder(for: .showAllItems)
                }
            }
            Label("Option-click the arrow to show every icon. Right-click it for the Barn Owl menu.",
                  systemImage: "lightbulb")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var preferences: some View {
        PreferencesStep()
    }

    private var done: some View {
        ZStack {
            VStack(spacing: 18) {
                HoppingOwl()
                    .frame(width: 140, height: 140)
                Text("Hoo-ray, you're all set!").font(.largeTitle.bold())
                Text("Click the owl for Keep Awake and quick toggles. Click the arrow for your hidden icons, or press ⌃⌥⌘M to search them.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                MenuBarDiagram(collapsed: true).frame(maxWidth: 420).padding(.top, 8)
            }
        }
    }

    // MARK: Pieces

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Brand.accent : Color.secondary.opacity(0.3))
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
        .background(.ultraThinMaterial)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .done: "Start Using Barn Owl"
        default: "Continue"
        }
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        StepHeader(title: title, subtitle: subtitle)
    }


}

private struct DisplayStep: View {
    let model: AppModel
    @AppStorage(PrefKey.hiddenIconsDisplay) private var display = HiddenIconsDisplay.automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Where hidden icons appear",
                       subtitle: "Your Mac's notch only leaves room for a few icons. The Perch, a strip under the menu bar, shows the rest, including any stuck behind the notch.")
            HiddenIconsDisplayPicker(selection: $display)
            Card {
                PermissionRow(permission: .accessibility, model: model)
                PermissionRow(permission: .screenRecording, model: model)
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
            StepHeader(title: "A couple of choices", subtitle: "You can change these later in Settings.")
            Card {
                CardRow(title: "Open Barn Owl at login", subtitle: "Recommended, so your menu bar stays tidy.",
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

/// A step's title with a small owl peeking in from the side.
private struct StepHeader: View {
    let title: String
    let subtitle: String
    @State private var peeked = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            WatchingOwl()
                .frame(width: 46, height: 46)
                .offset(y: peeked ? 0 : 12)
                .opacity(peeked ? 1 : 0)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title.bold())
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.45).delay(0.15)) { peeked = true }
        }
    }
}

/// The big owl on the welcome page: pops in, then watches your pointer.
private struct WelcomeOwl: View {
    @State private var arrived = false

    var body: some View {
        WatchingOwl(entrance: .greet)
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .scaleEffect(arrived ? 1 : 0.4)
            .rotationEffect(.degrees(arrived ? 0 : -18))
            .opacity(arrived ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.7, bounce: 0.5)) { arrived = true }
            }
    }
}

/// The owl hopping for joy at the end of setup, flapping, then spinning round.
private struct HoppingOwl: View {
    var body: some View {
        WatchingOwl(happy: true, watches: false, accessory: .partyHat, entrance: .celebrate)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

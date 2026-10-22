import KeyboardShortcuts
import SwiftUI

/// Settings › Capture: every choice in one pane, in plain words.
struct CapturePane: View {
    let model: AppModel
    @AppStorage(PrefKey.captureEnabled) private var enabled = false
    @AppStorage(PrefKey.captureAppleKeys) private var appleKeys = false
    @AppStorage(PrefKey.captureCopies) private var copies = true
    @AppStorage(PrefKey.captureSaves) private var saves = true
    @AppStorage(PrefKey.captureThen) private var then = CaptureThen.card
    @AppStorage(PrefKey.captureAdjusts) private var adjusts = true
    @AppStorage(PrefKey.capturePrivateInfo) private var privateInfo = true
    @AppStorage(PrefKey.captureKeepDays) private var keepDays = 30
    @State private var cleared = false
    @AppStorage(PrefKey.captureFolder) private var folder = ""
    @AppStorage(PrefKey.captureNamePrefix) private var namePrefix = "Screenshot"
    @AppStorage(PrefKey.captureNameIncludesApp) private var nameIncludesApp = false
    @AppStorage(PrefKey.captureFormat) private var format = CaptureFormat.png
    @AppStorage(PrefKey.captureAtOneX) private var atOneX = false
    @AppStorage(PrefKey.captureCleanMenuBar) private var cleanMenuBar = true
    @AppStorage(PrefKey.captureHidesDesktopIcons) private var hidesDesktopIcons = true
    @AppStorage(PrefKey.captureWindowShadow) private var windowShadow = true
    @AppStorage(PrefKey.captureShowsPointer) private var showsPointer = false
    @AppStorage(PrefKey.captureSound) private var sound = true
    @AppStorage(PrefKey.captureCardCorner) private var cardCorner = CardCorner.bottomRight
    @AppStorage(PrefKey.captureCardSeconds) private var cardSeconds = 8
    @State private var others: [String] = []
    @State private var systemKeysOn = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    BadgeLabel(title: "Screenshots and markup",
                               subtitle: "Capture an area, a window or the whole screen, then mark it up and hand it on.",
                               symbol: "camera.viewfinder", color: .red)
                }
                // Until it's allowed, the permission comes first.
                if enabled && !model.screenRecordingAllowed {
                    PermissionRow(permission: .screenRecording, model: model)
                }
            } footer: {
                if let other = others.first {
                    Text(enabled
                         ? "\(other) is installed too. If both use the same shortcut, only one of them answers."
                         : "\(other) is installed. Leave this off to keep using it: Barn Owl then takes no capture shortcuts.")
                }
            }
            Group {
                shortcuts
                afterCapturing
                saving
                inEveryCapture
                card
            }
            .disabled(!enabled)
            Section {
                Picker("Keep captures editable", selection: $keepDays) {
                    Text("For 30 days").tag(30)
                    Text("For 7 days").tag(7)
                    Text("Don't keep them").tag(0)
                }
                LabeledContent("Kept captures") {
                    HStack(spacing: 8) {
                        Button("Show History…") { model.capture.showHistory() }
                        Button(cleared ? "Cleared" : "Clear Now") {
                            // Not one open in the editor: its marks are still being made.
                            CaptureLibrary.clear(keeping: model.capture.editingCaptures)
                            cleared = true
                        }
                        .disabled(cleared)
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text(keepDays > 0
                     ? "⌃⌥⌘E and Capture History reopen captures with their marks still movable. To do that, Barn Owl keeps each original and its text, as captured and before anything was hidden, in Application Support on your Mac."
                     : "Barn Owl keeps nothing, so marks can't be moved again once you're done.")
            }
            .disabled(!enabled)
            if model.screenRecordingAllowed || !enabled {
                Section {
                    PermissionRow(permission: .screenRecording, model: model)
                } footer: {
                    Text("Capturing needs Screen Recording, the same permission Barn Owl uses to picture hidden icons. Barn Owl asks the first time you capture.")
                }
            }
            Section {
                LabeledContent("New to Capture?") {
                    Button("Show Me Around…") { model.showCaptureSetup() }
                }
            }
        }
        .task {
            others = OtherCaptureApps.installed()
            // Notices when you switch macOS's own shortcuts off in System Settings.
            while !Task.isCancelled {
                systemKeysOn = SystemScreenshotShortcuts.anyEnabled
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var shortcuts: some View {
        Section("Shortcuts") {
            LabeledContent("Capture an area or a window") { KeyboardShortcuts.Recorder(for: .captureArea) }
            LabeledContent("Capture the whole screen") { KeyboardShortcuts.Recorder(for: .captureScreen) }
            LabeledContent("Capture the same area again") { KeyboardShortcuts.Recorder(for: .captureSameArea) }
            LabeledContent("Edit the last capture") { KeyboardShortcuts.Recorder(for: .editLastCapture) }
            LabeledContent("Copy text from the screen") { KeyboardShortcuts.Recorder(for: .captureText) }
            LabeledContent("Show capture history") { KeyboardShortcuts.Recorder(for: .captureHistory) }
            Toggle(isOn: $appleKeys) {
                Text("Also answer ⇧⌘4 and ⇧⌘3")
                Text(systemKeysOn
                     ? "macOS's own screenshot shortcuts are still on. Turn them off in Keyboard Shortcuts › Screenshots; Barn Owl notices by itself."
                     : "macOS's own screenshot shortcuts are off, so Barn Owl can take them.")
            }
            if appleKeys && systemKeysOn {
                LabeledContent("Keyboard Shortcuts") {
                    Button("Open…") { NSWorkspace.shared.open(SystemScreenshotShortcuts.settingsURL) }
                }
            }
        }
    }

    private var afterCapturing: some View {
        Section {
            Picker("When you let go", selection: $adjusts) {
                Text("Let me adjust it").tag(true)
                Text("Capture right away").tag(false)
            }
            Toggle("Copy to the clipboard", isOn: $copies)
            Toggle("Save to \(folderTitle)", isOn: $saves)
            Picker("Then", selection: $then) {
                ForEach(CaptureThen.allCases) { Text($0.title).tag($0) }
            }
            Toggle(isOn: $privateInfo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look for private info in captures")
                    Text("Offers to hide keys, passwords, emails and card numbers it finds. Nothing is hidden without asking. Barn Owl reads each capture's text on your Mac either way, for Copy Text, search and smart marks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("After capturing")
        } footer: {
            Text(adjusts
                 ? "Return captures. E opens the editor, P pins it, Esc starts over. Click the card to mark it up, drag it into any app; the file stays saved."
                 : "Captures as soon as you let go. Click the card to mark it up, or drag it into any app.")
        }
    }

    private var saving: some View {
        Section("Saving") {
            LabeledContent("Folder") {
                Menu(folderTitle) {
                    Button("Where macOS Saves Screenshots") { folder = "" }
                    Button("Choose…") { chooseFolder() }
                    Divider()
                    Button("Show in Finder") { NSWorkspace.shared.open(CaptureStore.folder) }
                }
                .fixedSize()
            }
            TextField("Names start with", text: $namePrefix)
            Toggle("Add the app's name", isOn: $nameIncludesApp)
            Picker("Format", selection: $format) {
                ForEach(CaptureFormat.allCases) { Text($0.title).tag($0) }
            }
            Toggle(isOn: $atOneX) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Retina captures at their on-screen size")
                    Text("Half the pixels each way: smaller files, a little less sharp.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Example") {
                Text("\(CaptureStore.baseName(prefix: Preferences.captureNamePrefix, date: Date(), appName: nameIncludesApp ? "Safari" : nil)).\(format.fileExtension)")
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var inEveryCapture: some View {
        Section {
            Toggle(isOn: $cleanMenuBar) {
                BadgeLabel(title: "A clean menu bar",
                           subtitle: "Menu bar icons are left out of the picture; the clock and Control Center stay. Nothing moves on screen.",
                           symbol: "menubar.rectangle", color: .blue)
            }
            Toggle(isOn: $hidesDesktopIcons) {
                BadgeLabel(title: "No desktop icons", subtitle: "Only in the picture: your desktop stays as it is.",
                           symbol: "menubar.dock.rectangle", color: .teal)
            }
            Toggle(isOn: $windowShadow) {
                BadgeLabel(title: "Shadows on windows", subtitle: "A captured window keeps its shadow, on a clear background.",
                           symbol: "macwindow", color: .indigo)
            }
            Toggle(isOn: $showsPointer) {
                BadgeLabel(title: "Show the pointer", symbol: "cursorarrow", color: .gray)
            }
            Toggle(isOn: $sound) {
                BadgeLabel(title: "Play the camera sound", symbol: "speaker.wave.2.fill", color: .pink)
            }
        } header: {
            Text("In every capture")
        }
    }

    private var card: some View {
        Section("Card") {
            Picker("Corner", selection: $cardCorner) {
                ForEach(CardCorner.allCases) { Text($0.title).tag($0) }
            }
            Picker("Close it after", selection: $cardSeconds) {
                ForEach([5, 8, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                Text("Never").tag(0)
            }
        }
    }

    private var folderTitle: String {
        folder.isEmpty ? "\(CaptureStore.systemFolder.lastPathComponent) (like macOS)" : CaptureStore.folder.lastPathComponent
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = CaptureStore.folder
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

/// The setup guide's Capture step: use Barn Owl for screenshots, or keep the app you have.
struct CaptureStep: View {
    let model: AppModel
    @AppStorage(PrefKey.captureEnabled) private var enabled = false
    @AppStorage(PrefKey.captureAppleKeys) private var appleKeys = false
    @State private var others: [String] = []
    @State private var systemKeysOn = false

    private var areaKeys: String { KeyboardShortcuts.getShortcut(for: .captureArea)?.description ?? "⌃⌥⌘4" }
    private var screenKeys: String { KeyboardShortcuts.getShortcut(for: .captureScreen)?.description ?? "⌃⌥⌘3" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Screenshots, with markup",
                       subtitle: "Capture an area, a window or the whole screen, mark it up, and drop it anywhere. Your menu bar stays clean in every shot.")
            HStack(spacing: 12) {
                Choice(title: "Use Barn Owl", subtitle: "Capture turns on, with \(areaKeys) and \(screenKeys).",
                       symbol: "camera.viewfinder", selected: enabled) { enabled = true }
                Choice(title: others.first.map { "Keep \($0)" } ?? "Not now",
                       subtitle: others.isEmpty ? "Turn it on any time in Settings › Capture."
                                                : "Found on this Mac. Capture stays off and out of its way.",
                       symbol: "hand.raised.fill", selected: !enabled) { enabled = false }
            }
            if enabled {
                Card {
                    PermissionRow(permission: .screenRecording, model: model)
                    CardRow(title: "Also answer ⇧⌘4 and ⇧⌘3",
                            subtitle: systemKeysOn ? "First switch off macOS's own, under Keyboard Shortcuts › Screenshots."
                                                   : "macOS's own are off, so Barn Owl can take them.",
                            symbol: "command", color: .purple) {
                        Toggle("", isOn: $appleKeys).labelsHidden().toggleStyle(.switch)
                    }
                    if appleKeys && systemKeysOn {
                        CardRow(title: "Keyboard Shortcuts", subtitle: "Untick the five under Screenshots. Barn Owl notices.",
                                symbol: "keyboard", color: .gray) {
                            Button("Open") { NSWorkspace.shared.open(SystemScreenshotShortcuts.settingsURL) }
                        }
                    }
                }
                Label("Try it now: press \(areaKeys), drag over something, then press E to mark it up.",
                      systemImage: "hand.point.up.left.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .task {
            others = OtherCaptureApps.installed()
            while !Task.isCancelled {
                systemKeysOn = SystemScreenshotShortcuts.anyEnabled
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private struct Choice: View {
        let title: String
        let subtitle: String
        let symbol: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: symbol).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .background(selected ? AnyShapeStyle(Brand.amber.opacity(0.16)) : AnyShapeStyle(.quaternary.opacity(0.6)),
                            in: .rect(cornerRadius: Theme.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(selected ? Brand.amber : .clear, lineWidth: 1.5)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

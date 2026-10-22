import SwiftUI

/// Settings › Capture › Recording: frames, quality, what's shown and heard, and where it goes.
struct RecordingSettingsSection: View {
    let access: any MicrophoneAccess
    @AppStorage(PrefKey.recordingFrameRate) private var frameRate = 30
    @AppStorage(PrefKey.recordingQuality) private var quality = RecordingQuality.standard
    @AppStorage(PrefKey.recordingCodec) private var codec = RecordingCodec.h264
    @AppStorage(PrefKey.recordingShowsPointer) private var showsPointer = true
    @AppStorage(PrefKey.recordingShowsClicks) private var showsClicks = false
    @AppStorage(PrefKey.recordingCountdown) private var countdown = true
    @AppStorage(PrefKey.recordingSystemAudio) private var systemAudio = false
    @AppStorage(PrefKey.recordingMicrophone) private var microphone = ""
    @AppStorage(PrefKey.recordingFolder) private var folder = ""
    @State private var microphones: [Microphone]
    @State private var status: MicrophoneStatus
    /// A mic picked before macOS has been asked: Barn Owl explains first.
    @State private var asking: Microphone?

    init(access: any MicrophoneAccess) {
        self.access = access
        _microphones = State(initialValue: access.devices())
        _status = State(initialValue: access.status)
    }

    var body: some View {
        Section {
            Picker("Frame rate", selection: $frameRate) {
                Text("30 per second").tag(30)
                Text("60 per second · smoother, larger files").tag(60)
            }
            Picker("Quality", selection: $quality) {
                ForEach(RecordingQuality.allCases) { Text($0.title).tag($0) }
            }
            Picker("Format", selection: $codec) {
                ForEach(RecordingCodec.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show the pointer", isOn: $showsPointer)
            Toggle(isOn: $showsClicks) {
                Text("Show clicks")
                Text("A ring where you click, so viewers can follow along.")
            }
            Toggle("Count down 3, 2, 1 before recording", isOn: $countdown)
            Toggle(isOn: $systemAudio) {
                Text("Record computer audio")
                Text("What your Mac plays. Barn Owl's own sounds stay out.")
            }
            microphoneRow
            LabeledContent("Save recordings to") {
                Menu(folderTitle) {
                    Button("Same Folder as Screenshots") { folder = "" }
                    Button("Movies") { folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies").path }
                    Button("Choose…") { chooseFolder() }
                    Divider()
                    Button("Show in Finder") { NSWorkspace.shared.open(RecordingStore.folder()) }
                }
                .fixedSize()
            }
        } header: {
            Text("Recording")
        } footer: {
            Text("Record with R or G after selecting, or ⌃⌥⌘5; press it again to stop. Barn Owl's own controls never show up in a recording.")
        }
        .alert(MicrophoneExplanation.title, isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            Button("Continue") { request() }
            Button("Not Now", role: .cancel) { asking = nil }
        } message: {
            Text(MicrophoneExplanation.message)
        }
    }

    @ViewBuilder private var microphoneRow: some View {
        Picker(selection: microphoneChoice) {
            Text("None").tag("")
            ForEach(microphones) { mic in
                Text(mic.isBluetooth ? "\(mic.name) · lower quality while recording" : mic.name).tag(mic.id)
            }
        } label: {
            Text("Microphone")
            Text(status == .denied ? MicrophoneExplanation.denied
                                   : "Barn Owl hears your mic only while you record, and only when you pick one here.")
        }
        .disabled(status == .denied)
        if status == .denied {
            LabeledContent("Microphone access") {
                Button("Allow in System Settings…") { NSWorkspace.shared.open(SystemMicrophoneAccess.settingsURL) }
            }
        }
    }

    /// The mic you've picked, if it may be heard. Picking one before macOS has asked explains first.
    private var microphoneChoice: Binding<String> {
        Binding(get: { status == .allowed ? microphone : "" }, set: { id in
            guard !id.isEmpty else { return microphone = "" }
            switch status {
            case .allowed: microphone = id
            case .notAsked: asking = microphones.first { $0.id == id }
            case .denied: break
            }
        })
    }

    private func request() {
        guard let mic = asking else { return }
        asking = nil
        Task {
            let allowed = await access.request()
            status = access.status
            microphone = allowed ? mic.id : ""
        }
    }

    private var folderTitle: String {
        folder.isEmpty ? "Same as screenshots" : URL(fileURLWithPath: folder).lastPathComponent
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = RecordingStore.folder()
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

extension CaptureHistory.Item {
    /// A picture, or a recording with its length.
    var media: CaptureMedia { entry.media }
}

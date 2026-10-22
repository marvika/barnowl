import SwiftUI

/// Under a selection made to record: what to hear, video or GIF, and Record. Your sound
/// choices are remembered for next time.
struct RecordBar: View {
    let microphones: [Microphone]
    let micStatus: MicrophoneStatus
    let makesGIF: Bool
    let showsHint: Bool
    let setGIF: (Bool) -> Void
    let record: () -> Void
    /// Opens the place to allow the microphone: Settings › Capture, or System Settings once refused.
    let allowMicrophone: () -> Void
    let cancel: () -> Void
    @AppStorage(PrefKey.recordingMicrophone) private var microphone = ""
    @AppStorage(PrefKey.recordingSystemAudio) private var systemAudio = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Group {
                    micMenu
                    soundButton
                }
                .disabled(makesGIF)
                .opacity(makesGIF ? 0.4 : 1)
                .help(makesGIF ? "GIFs have no sound" : "")
                Divider().frame(height: 18).padding(.horizontal, 3)
                kindPicker
                CaptureActionBar.BarButton(title: makesGIF ? "Record GIF" : "Record", symbol: "record.circle", key: "↩",
                                           prominent: true, action: record)
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Start over (Esc)")
                .accessibilityLabel("Start over")
            }
            if showsHint {
                Text("Return records · drag the edges to adjust · Esc to start over")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(5)
        .glassEffect(.regular.tint(Brand.indigoDeep.opacity(0.5)), in: .rect(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    /// The chosen microphone, if it may be heard and is plugged in.
    private var activeMicrophone: Microphone? {
        guard micStatus == .allowed, !makesGIF else { return nil }
        return microphones.first { $0.id == microphone }
    }

    private var micMenu: some View {
        Menu {
            if micStatus == .allowed {
                Picker("Microphone", selection: $microphone) {
                    Text("No Microphone").tag("")
                    ForEach(microphones) { mic in
                        Text(mic.isBluetooth ? "\(mic.name) · lower quality while recording" : mic.name).tag(mic.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if microphones.isEmpty {
                    Text("No microphones found")
                }
            } else {
                Button(micStatus == .denied ? "Allow in System Settings…" : "Use a Microphone…", action: allowMicrophone)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: activeMicrophone == nil ? "mic.slash" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)
                Text(activeMicrophone.map { Self.shortName($0.name) } ?? "No Mic")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 30)
            .background(.white.opacity(activeMicrophone == nil ? 0.12 : 0.22), in: .capsule)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(activeMicrophone?.isBluetooth == true ? "Bluetooth mics lower the sound quality while recording"
                                                    : "Which microphone to record")
        .accessibilityLabel("Microphone: \(activeMicrophone?.name ?? "none")")
    }

    private var soundButton: some View {
        Button { systemAudio.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: systemAudio ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text("Sound").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(systemAudio ? 1 : 0.8))
            .padding(.horizontal, 10).frame(height: 30)
            .background(.white.opacity(systemAudio ? 0.22 : 0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(PressableStyle())
        .help(systemAudio ? "Recording what your Mac plays" : "Not recording what your Mac plays")
        .accessibilityLabel("Computer audio")
        .accessibilityValue(systemAudio ? "On" : "Off")
    }

    private var kindPicker: some View {
        HStack(spacing: 0) {
            segment("Video", key: "R", selected: !makesGIF) { setGIF(false) }
            segment("GIF", key: "G", selected: makesGIF) { setGIF(true) }
        }
        .padding(2)
        .background(.white.opacity(0.1), in: .capsule)
    }

    private func segment(_ title: String, key: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.7))
                .padding(.horizontal, 11).frame(height: 26)
                .background(selected ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.clear), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("\(title) (\(key))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "MacBook Pro Microphone" → "MacBook Pro"; keeps the bar short.
    static func shortName(_ name: String) -> String {
        let trimmed = name.replacingOccurrences(of: " Microphone", with: "")
        return trimmed.count > 18 ? String(trimmed.prefix(17)) + "…" : trimmed
    }
}

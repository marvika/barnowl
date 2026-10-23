import AVFoundation
import AppKit

/// A microphone you can record with.
struct Microphone: Identifiable, Equatable, Sendable {
    /// `AVCaptureDevice.uniqueID`, which ScreenCaptureKit takes.
    let id: String
    let name: String

    /// AirPods and other Bluetooth headsets drop to call quality while their mic is in use.
    var isBluetooth: Bool {
        let lowered = name.lowercased()
        return lowered.contains("airpods") || lowered.contains("bluetooth") || lowered.contains("beats")
    }
}

/// Whether Barn Owl may hear the microphone.
enum MicrophoneStatus: Equatable, Sendable {
    case allowed, notAsked, denied
}

/// The microphone permission and the devices, behind a protocol so tests never ask macOS.
/// Reading the status never prompts; only `request()` does, and only when you pick a mic.
@MainActor
protocol MicrophoneAccess {
    var status: MicrophoneStatus { get }
    func devices() -> [Microphone]
    /// Shows macOS's own question. Only ever called after Barn Owl has explained why.
    func request() async -> Bool
}

@MainActor
struct SystemMicrophoneAccess: MicrophoneAccess {
    var status: MicrophoneStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func devices() -> [Microphone] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                                       position: .unspecified)
        return session.devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
    }

    func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Privacy & Security › Microphone, where access is turned back on.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
}

/// Barn Owl's own words before macOS asks, used wherever a mic is first picked.
enum MicrophoneExplanation {
    static let title = "Record your microphone?"
    static let message = "Barn Owl hears your mic only while you record, and only when you pick one here. macOS asks next."
    static let denied = "Microphone access is off for Barn Owl."
}

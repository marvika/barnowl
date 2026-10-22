import AVFoundation
import Foundation

/// How a recording is encoded: H.264 plays everywhere, HEVC makes smaller files.
enum RecordingCodec: String, CaseIterable, Identifiable, Sendable {
    case h264, hevc

    var id: String { rawValue }
    var title: String { self == .h264 ? "H.264 · plays everywhere" : "HEVC · smaller files" }
    var videoCodec: AVVideoCodecType { self == .h264 ? .h264 : .hevc }

    /// The largest frame the encoder takes: each side, and the whole area.
    var maxSide: Int { self == .h264 ? 4096 : 8192 }
    var maxArea: Int { self == .h264 ? 4096 * 2304 : 8192 * 4320 }
    /// HEVC needs about 40 % fewer bits for the same look.
    var bitRateFactor: Double { self == .h264 ? 1 : 0.6 }
}

enum RecordingQuality: String, CaseIterable, Identifiable, Sendable {
    case standard, high

    var id: String { rawValue }
    var title: String { self == .standard ? "Standard" : "High" }
    /// Bits per pixel per frame. Text in motion goes soft much below the high setting.
    var bitsPerPixel: Double { self == .standard ? 0.15 : 0.3 }
}

/// Every recording choice in Settings › Capture, read in one go when a recording starts.
struct RecordingSettings: Equatable, Sendable {
    static let frameRates = [30, 60]

    var frameRate = 30
    var quality = RecordingQuality.standard
    var codec = RecordingCodec.h264
    var showsPointer = true
    var showsClicks = false
    var countdown = true
    var systemAudio = false
    /// The microphone's unique ID; nil records none.
    var microphoneID: String?
    /// Where recordings are saved; empty means the screenshot folder.
    var folder = ""

    init() {}

    /// What's stored, with the defaults for anything missing or unreadable.
    init(defaults: UserDefaults) {
        if let rate = defaults.object(forKey: PrefKey.recordingFrameRate) as? Int, Self.frameRates.contains(rate) {
            frameRate = rate
        }
        quality = RecordingQuality(rawValue: defaults.string(forKey: PrefKey.recordingQuality) ?? "") ?? .standard
        codec = RecordingCodec(rawValue: defaults.string(forKey: PrefKey.recordingCodec) ?? "") ?? .h264
        showsPointer = defaults.object(forKey: PrefKey.recordingShowsPointer) as? Bool ?? true
        showsClicks = defaults.object(forKey: PrefKey.recordingShowsClicks) as? Bool ?? false
        countdown = defaults.object(forKey: PrefKey.recordingCountdown) as? Bool ?? true
        systemAudio = defaults.object(forKey: PrefKey.recordingSystemAudio) as? Bool ?? false
        let microphone = defaults.string(forKey: PrefKey.recordingMicrophone) ?? ""
        microphoneID = microphone.isEmpty ? nil : microphone
        folder = defaults.string(forKey: PrefKey.recordingFolder) ?? ""
    }

    static var current: RecordingSettings { RecordingSettings(defaults: .standard) }
}

extension PrefKey {
    static let recordingFrameRate = "recordingFrameRate"
    static let recordingQuality = "recordingQuality"
    static let recordingCodec = "recordingCodec"
    static let recordingShowsPointer = "recordingShowsPointer"
    static let recordingShowsClicks = "recordingShowsClicks"
    static let recordingCountdown = "recordingCountdown"
    static let recordingSystemAudio = "recordingSystemAudio"
    /// The microphone's unique ID, or empty for none.
    static let recordingMicrophone = "recordingMicrophone"
    /// A folder path, or empty for the screenshot folder.
    static let recordingFolder = "recordingFolder"
}

/// What one take records, from the settings and how it was started.
struct RecordingOptions: Equatable, Sendable {
    var frameRate: Int
    var codec: RecordingCodec
    var quality: RecordingQuality
    var showsPointer: Bool
    var showsClicks: Bool
    var systemAudio: Bool
    var microphoneID: String?
    /// Recorded to become a GIF: fewer frames, no sound.
    var makesGIF: Bool

    static let gifFrameRate = 15

    init(settings: RecordingSettings, makesGIF: Bool, microphoneAllowed: Bool) {
        self.makesGIF = makesGIF
        frameRate = makesGIF ? Self.gifFrameRate : settings.frameRate
        codec = makesGIF ? .h264 : settings.codec
        // A GIF is made from this file: give it the sharper frames.
        quality = makesGIF ? .high : settings.quality
        showsPointer = settings.showsPointer
        showsClicks = settings.showsClicks
        systemAudio = !makesGIF && settings.systemAudio
        microphoneID = !makesGIF && microphoneAllowed ? settings.microphoneID : nil
    }

    var hasAudio: Bool { systemAudio || microphoneID != nil }
}

/// Sizes and places for a recording, worked out without touching the screen.
enum RecordingGeometry {
    /// The smallest side a recording is made at; tiny areas are scaled up to it.
    static let minimumSide = 64

    /// The frame size in pixels: the area at the screen's scale, fitted within what the
    /// encoder takes, both sides even, and no side under `minimumSide`.
    static func pixelSize(points: CGSize, scale: CGFloat, codec: RecordingCodec) -> (width: Int, height: Int) {
        let width = max(1, Double(points.width * scale))
        let height = max(1, Double(points.height * scale))
        let bySide = min(Double(codec.maxSide) / width, Double(codec.maxSide) / height)
        let byArea = (Double(codec.maxArea) / (width * height)).squareRoot()
        var factor = min(1, bySide, byArea)
        // Up to the minimum, unless that would break a limit the other way.
        let shortest = min(width, height) * factor
        if shortest < Double(minimumSide) {
            factor = min(factor * Double(minimumSide) / shortest, bySide, byArea)
        }
        return (even(width * factor), even(height * factor))
    }

    /// Rounded down to an even number, at least 2: encoders want even sides.
    static func even(_ value: Double) -> Int {
        max(2, Int(value.rounded(.down)) / 2 * 2)
    }

    /// An area in AppKit screen points (origin bottom left, across displays) as
    /// ScreenCaptureKit's source rect: points within the display, from its top left.
    static func sourceRect(for area: CGRect, on screen: CGRect) -> CGRect {
        let local = area.intersection(screen)
        return CGRect(x: local.minX - screen.minX, y: screen.maxY - local.maxY, width: local.width, height: local.height)
    }

    /// The average bit rate for a frame size, rate and quality, within sensible bounds.
    static func bitRate(width: Int, height: Int, frameRate: Int, quality: RecordingQuality, codec: RecordingCodec) -> Int {
        let pixels = Double(width * height)
        let bits = pixels * Double(frameRate) * quality.bitsPerPixel * codec.bitRateFactor
        return Int(min(max(bits, 1_000_000), 120_000_000))
    }
}

/// "0:42", "12:05", "1:02:03".
enum RecordingTime {
    static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total / 60 % 60, rest = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// "Saved · 0:42 · 12 MB".
    static func status(_ prefix: String, duration: TimeInterval, bytes: Int64?) -> String {
        var parts = [prefix, text(duration)]
        if let bytes, bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }
}

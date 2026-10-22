import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import BarnOwl

/// The recording writer, fed synthetic frames and silence, as ScreenCaptureKit would.
struct RecordingWriterTests {
    static func settings(system: Bool = false, microphone: Bool = false) -> RecordingWriter.Settings {
        RecordingWriter.Settings(width: 320, height: 240, frameRate: 30, codec: .h264, bitRate: 2_000_000,
                                 systemAudio: system, microphone: microphone, realTime: false)
    }

    static func url() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "recording-\(UUID()).mov")
    }

    static func frame(_ shade: UInt8 = 128) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), Int32(shade), CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 1_000_000_000) }

    /// 1024 frames of float audio at 48 kHz (or `rate`), every sample `value`.
    static func audio(at seconds: Double, channels: Int, value: Float = 0, frames: Int = 1024,
                      rate: Double = 48_000) -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let bytes = frames * channels * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        var samples = [Float](repeating: value, count: frames * channels)
        CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue(seconds * rate), timescale: CMTimeScale(rate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        return sample!
    }

    static func finish(_ writer: RecordingWriter, at seconds: Double) async -> Result<RecordingWriter.Output, RecordingWriter.Failure> {
        await withCheckedContinuation { continuation in
            writer.finish(at: time(seconds)) { continuation.resume(returning: $0) }
        }
    }

    static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    @Test func holdsTheLastFrameUntilStop() async throws {
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: Self.settings())
        // A screen that changes three times, then stays still for almost two seconds.
        for (index, seconds) in [100.0, 100.1, 100.2].enumerated() {
            writer.appendVideo(Self.frame(UInt8(40 * index)), at: Self.time(seconds))
        }
        let output = try await Self.finish(writer, at: 102.0).get()
        #expect(abs(output.duration - 2.0) < 0.02)
        #expect(abs(try await Self.duration(of: url) - 2.0) < 0.05)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        #expect(abs(try await track.load(.timeRange).duration.seconds - 2.0) < 0.05)
    }

    @Test func pauseLeavesNoGap() async throws {
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: Self.settings())
        for step in 0...10 { writer.appendVideo(Self.frame(), at: Self.time(Double(step) / 10)) }
        writer.pause(at: Self.time(1.0))
        // Frames while paused are dropped (the newest is kept to resume with).
        for step in 11...29 { writer.appendVideo(Self.frame(200), at: Self.time(Double(step) / 10)) }
        #expect(writer.isPaused)
        writer.resume(at: Self.time(3.0))
        for step in 31...40 { writer.appendVideo(Self.frame(), at: Self.time(Double(step) / 10)) }
        let output = try await Self.finish(writer, at: 4.0).get()
        // Four seconds of wall time, two of them paused.
        #expect(abs(output.duration - 2.0) < 0.02)
        #expect(abs(try await Self.duration(of: url) - 2.0) < 0.05)
    }

    @Test func stoppingWhilePausedEndsWhereThePauseBegan() async throws {
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: Self.settings())
        writer.appendVideo(Self.frame(), at: Self.time(5))
        writer.pause(at: Self.time(6.5))
        let output = try await Self.finish(writer, at: 9).get()
        #expect(abs(output.duration - 1.5) < 0.02)
    }

    @Test func stoppingBeforeTheFirstFrameKeepsNothing() async throws {
        let url = Self.url()
        let writer = try RecordingWriter(url: url, settings: Self.settings(system: true))
        writer.appendAudio(Self.audio(at: 1, channels: 2), from: .system)
        let result = await Self.finish(writer, at: 1.1)
        #expect(result.failure == .noFrames)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func cancelLetsTheFileGo() throws {
        let url = Self.url()
        let writer = try RecordingWriter(url: url, settings: Self.settings())
        writer.appendVideo(Self.frame(), at: Self.time(1))
        writer.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func computerAudioAndTheMicGetTracksOfTheirOwn() async throws {
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: Self.settings(system: true, microphone: true))
        // Audio before the first frame is left out.
        writer.appendAudio(Self.audio(at: 9.9, channels: 2), from: .system)
        for step in 0..<10 { writer.appendVideo(Self.frame(), at: Self.time(10 + Double(step) / 10)) }
        var seconds = 10.0
        while seconds < 11 {
            writer.appendAudio(Self.audio(at: seconds, channels: 2, value: 0.1), from: .system)
            // A stereo mic still goes into a mono track.
            writer.appendAudio(Self.audio(at: seconds, channels: 2, value: 0.2), from: .microphone)
            seconds += 1024.0 / 48_000
        }
        let output = try await Self.finish(writer, at: 11).get()
        #expect(output.audio == [.system, .microphone])
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 2)
        var names: [String] = []
        for track in tracks {
            let metadata = try await track.load(.metadata)
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeUserDataTrackName)
            if let name = try await items.first?.load(.stringValue) { names.append(name) }
        }
        #expect(names == ["Computer audio", "Microphone"])
        let micFormat = try #require(try await tracks[1].load(.formatDescriptions).first)
        #expect(CMAudioFormatDescriptionGetStreamBasicDescription(micFormat)?.pointee.mChannelsPerFrame == 1)
    }

    @Test func mixingMakesOneAudioTrackAndKeepsThePicture() async throws {
        let master = Self.url(), mixed = Self.url()
        defer {
            try? FileManager.default.removeItem(at: master)
            try? FileManager.default.removeItem(at: mixed)
        }
        let writer = try RecordingWriter(url: master, settings: Self.settings(system: true, microphone: true))
        for step in 0..<15 { writer.appendVideo(Self.frame(UInt8(step * 10)), at: Self.time(Double(step) / 10)) }
        var seconds = 0.0
        while seconds < 1.5 {
            writer.appendAudio(Self.audio(at: seconds, channels: 2, value: 0.1), from: .system)
            writer.appendAudio(Self.audio(at: seconds, channels: 1, value: 0.2), from: .microphone)
            seconds += 1024.0 / 48_000
        }
        let output = try await Self.finish(writer, at: 1.5).get()
        #expect(RecordingMixer.needsMixing(output))
        try await RecordingMixer.mix(master, to: mixed)
        let asset = AVURLAsset(url: mixed)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 1.5) < 0.1)
    }

    @Test func pauseDropsAudioFromTheGap() async throws {
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: Self.settings(system: true))
        writer.appendVideo(Self.frame(), at: Self.time(0))
        var seconds = 0.0
        while seconds < 3 {
            if seconds >= 1, !writer.isPaused, seconds < 2 { writer.pause(at: Self.time(1)) }
            if seconds >= 2, writer.isPaused { writer.resume(at: Self.time(2)) }
            writer.appendAudio(Self.audio(at: seconds, channels: 2), from: .system)
            seconds += 1024.0 / 48_000
        }
        _ = try await Self.finish(writer, at: 3).get()
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
        // Two seconds of sound for two seconds of recording, give or take a buffer.
        #expect(abs(try await track.load(.timeRange).duration.seconds - 2) < 0.1)
    }

    @Test func hevcAndAMicAtAnotherRateStillWrite() async throws {
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = Self.settings(microphone: true)
        settings.codec = .hevc
        let writer = try RecordingWriter(url: url, settings: settings)
        for step in 0..<10 { writer.appendVideo(Self.frame(), at: Self.time(Double(step) / 10)) }
        var seconds = 0.0
        while seconds < 1 {
            writer.appendAudio(Self.audio(at: seconds, channels: 1, value: 0.2, rate: 44_100), from: .microphone)
            seconds += 1024.0 / 44_100
        }
        // A Bluetooth mic switching format mid-take is left out, and the file survives.
        writer.appendAudio(Self.audio(at: 1, channels: 2, value: 0.2), from: .microphone)
        _ = try await Self.finish(writer, at: 1).get()
        let asset = AVURLAsset(url: url)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await video.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC)
        let mic = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        #expect(abs(try await mic.load(.timeRange).duration.seconds - 1) < 0.1)
    }

    @Test func framesInsideOneTickAndAStopJustAfterAFrameStillWrite() async throws {
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: Self.settings())
        writer.appendVideo(Self.frame(), at: Self.time(10))
        // Half a millisecond later rounds to the same tick: left out, not a failed file.
        writer.appendVideo(Self.frame(9), at: Self.time(10.0005))
        writer.appendVideo(Self.frame(), at: Self.time(10.1))
        let output = try await Self.finish(writer, at: 10.1004).get()
        #expect(output.frames == 2)
        #expect(abs(output.duration - 0.1) < 0.01)
    }

    @Test func measuresLoudness() {
        #expect(abs(AudioLevel.rms(of: Self.audio(at: 0, channels: 1, value: 0.5)) - 0.5) < 0.001)
        #expect(AudioLevel.rms(of: Self.audio(at: 0, channels: 2, value: 0)) == 0)
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

struct RecordingGeometryTests {
    @Test func evenSidesAtTheScreensScale() {
        let size = RecordingGeometry.pixelSize(points: CGSize(width: 401.5, height: 300.7), scale: 2, codec: .h264)
        #expect(size.width == 802 && size.height == 600)
        #expect(RecordingGeometry.even(7) == 6)
        #expect(RecordingGeometry.even(0.4) == 2)
    }

    @Test func fitsWhatTheEncoderTakes() {
        // A 5K screen at Retina is too big for H.264: scaled to fit, same shape.
        let h264 = RecordingGeometry.pixelSize(points: CGSize(width: 2560, height: 1440), scale: 2, codec: .h264)
        #expect(h264.width <= 4096 && h264.height <= 2304)
        #expect(h264.width % 2 == 0 && h264.height % 2 == 0)
        #expect(abs(Double(h264.width) / Double(h264.height) - 16.0 / 9) < 0.01)
        // HEVC takes it whole.
        let hevc = RecordingGeometry.pixelSize(points: CGSize(width: 2560, height: 1440), scale: 2, codec: .hevc)
        #expect(hevc.width == 5120 && hevc.height == 2880)
        // Tall and narrow keeps within each side too.
        let tall = RecordingGeometry.pixelSize(points: CGSize(width: 300, height: 3000), scale: 2, codec: .h264)
        #expect(tall.height <= 4096 && tall.width * tall.height <= 4096 * 2304)
    }

    @Test func tinyAreasAreScaledUp() {
        let size = RecordingGeometry.pixelSize(points: CGSize(width: 10, height: 20), scale: 1, codec: .h264)
        #expect(size.width == 64 && size.height == 128)
    }

    @Test func sourceRectIsFromTheDisplaysTopLeft() {
        // A second display above the main one, and an area near its top.
        let screen = CGRect(x: 0, y: 1080, width: 1920, height: 1200)
        let area = CGRect(x: 100, y: 2180, width: 400, height: 50)
        #expect(RecordingGeometry.sourceRect(for: area, on: screen) == CGRect(x: 100, y: 50, width: 400, height: 50))
    }

    @Test func bitRateFollowsSizeQualityAndCodec() {
        let standard = RecordingGeometry.bitRate(width: 1920, height: 1080, frameRate: 30, quality: .standard, codec: .h264)
        let high = RecordingGeometry.bitRate(width: 1920, height: 1080, frameRate: 30, quality: .high, codec: .h264)
        let hevc = RecordingGeometry.bitRate(width: 1920, height: 1080, frameRate: 30, quality: .standard, codec: .hevc)
        #expect(high == standard * 2)
        #expect(hevc < standard)
        #expect(RecordingGeometry.bitRate(width: 64, height: 64, frameRate: 15, quality: .standard, codec: .h264) == 1_000_000)
    }

    @Test func timesReadLikeAClock() {
        #expect(RecordingTime.text(0) == "0:00")
        #expect(RecordingTime.text(42.9) == "0:42")
        #expect(RecordingTime.text(725) == "12:05")
        #expect(RecordingTime.text(3723) == "1:02:03")
        #expect(RecordingTime.status("Saved", bytes: nil) == "Saved")
        #expect(RecordingTime.status("GIF", bytes: 2_100_000).hasPrefix("GIF · 2"))
    }
}

struct RecordingStateTests {
    @Test func countsDownRecordsPausesAndStops() {
        var machine = RecordingStateMachine()
        #expect(machine.handle(.begin(countdown: true)) == [.showCountdown])
        #expect(machine.handle(.countdownEnded) == [.startCapture])
        #expect(machine.phase == .starting)
        #expect(machine.handle(.started) == [])
        #expect(machine.phase == .recording)
        #expect(machine.handle(.pause) == [.pauseCapture])
        #expect(machine.handle(.pause) == [])
        #expect(machine.handle(.resume) == [.resumeCapture])
        #expect(machine.handle(.stop) == [.finishCapture(keep: true)])
        // A second stop while the file is written does nothing.
        #expect(machine.handle(.stop) == [])
        #expect(machine.handle(.finished) == [.tearDown])
        #expect(machine.phase == .idle)
    }

    @Test func stoppingRightAfterStartingKeepsNothingAndEndsTheStream() {
        var machine = RecordingStateMachine()
        #expect(machine.handle(.begin(countdown: false)) == [.startCapture])
        #expect(machine.handle(.stop) == [.abortStart])
        #expect(machine.phase == .finishing)
        // The start, cut short, reports back: then everything goes.
        #expect(machine.handle(.started) == [])
        #expect(machine.handle(.failed) == [.tearDown])
        #expect(machine.phase == .idle)
    }

    @Test func escDuringTheCountdownCancels() {
        var machine = RecordingStateMachine()
        _ = machine.handle(.begin(countdown: true))
        #expect(machine.handle(.cancel) == [.tearDown])
        #expect(machine.phase == .idle)
        // Nothing to pause or stop now.
        #expect(machine.handle(.pause) == [])
        #expect(machine.handle(.stop) == [])
    }

    @Test func discardAndRestart() {
        var machine = RecordingStateMachine()
        _ = machine.handle(.begin(countdown: false))
        _ = machine.handle(.started)
        #expect(machine.handle(.restart(countdown: true)) == [.restartCapture(countdown: true)])
        #expect(machine.phase == .countingDown)
        _ = machine.handle(.countdownEnded)
        _ = machine.handle(.started)
        _ = machine.handle(.pause)
        #expect(machine.handle(.discard) == [.finishCapture(keep: false)])
        #expect(machine.handle(.finished) == [.tearDown])
    }

    @Test func aStreamThatStopsByItselfKeepsWhatWasRecorded() {
        var machine = RecordingStateMachine()
        _ = machine.handle(.begin(countdown: false))
        #expect(machine.handle(.failed) == [.tearDown])
        _ = machine.handle(.begin(countdown: false))
        _ = machine.handle(.started)
        #expect(machine.handle(.failed) == [.finishCapture(keep: true)])
    }

    @Test func theClockLeavesOutPauses() {
        var clock = RecordingClock()
        #expect(clock.elapsed(at: 5) == 0)
        clock.start(at: 10)
        #expect(clock.elapsed(at: 12) == 2)
        clock.pause(at: 15)
        #expect(clock.elapsed(at: 18) == 5)
        clock.resume(at: 20)
        #expect(clock.elapsed(at: 25) == 10)
    }

    @Test func noticesASilentMicrophone() {
        var silence = MicrophoneSilence()
        silence.hear(0, at: 0)
        silence.hear(0.0001, at: 2.9)
        #expect(!silence.isSilent)
        silence.hear(0, at: 3.1)
        #expect(silence.isSilent)
        silence.hear(0.2, at: 3.2)
        #expect(!silence.isSilent)
    }
}

struct RecordingSettingsTests {
    static func defaults() -> UserDefaults {
        let name = "recording-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func missingSettingsUseTheDefaults() {
        let settings = RecordingSettings(defaults: Self.defaults())
        #expect(settings == RecordingSettings())
        #expect(settings.frameRate == 30 && settings.codec == .h264 && settings.quality == .standard)
        #expect(settings.showsPointer && settings.countdown)
        #expect(!settings.systemAudio && settings.microphoneID == nil && !settings.showsClicks)
    }

    @Test func readsWhatsStoredAndIgnoresNonsense() {
        let defaults = Self.defaults()
        defaults.set(60, forKey: PrefKey.recordingFrameRate)
        defaults.set("hevc", forKey: PrefKey.recordingCodec)
        defaults.set("high", forKey: PrefKey.recordingQuality)
        defaults.set(true, forKey: PrefKey.recordingSystemAudio)
        defaults.set("BuiltInMicrophoneDevice", forKey: PrefKey.recordingMicrophone)
        defaults.set(false, forKey: PrefKey.recordingCountdown)
        var settings = RecordingSettings(defaults: defaults)
        #expect(settings.frameRate == 60 && settings.codec == .hevc && settings.quality == .high)
        #expect(settings.systemAudio && !settings.countdown)
        #expect(settings.microphoneID == "BuiltInMicrophoneDevice")
        defaults.set(24, forKey: PrefKey.recordingFrameRate)
        defaults.set("av1", forKey: PrefKey.recordingCodec)
        defaults.set("", forKey: PrefKey.recordingMicrophone)
        settings = RecordingSettings(defaults: defaults)
        #expect(settings.frameRate == 30 && settings.codec == .h264 && settings.microphoneID == nil)
    }

    @Test func aGIFIsQuietAndSlower() {
        var settings = RecordingSettings()
        settings.systemAudio = true
        settings.microphoneID = "mic"
        settings.frameRate = 60
        let gif = RecordingOptions(settings: settings, makesGIF: true, microphoneAllowed: true)
        #expect(gif.frameRate == 15 && !gif.hasAudio)
        let video = RecordingOptions(settings: settings, makesGIF: false, microphoneAllowed: true)
        #expect(video.frameRate == 60 && video.systemAudio && video.microphoneID == "mic")
        // A mic that isn't allowed is never asked for.
        #expect(RecordingOptions(settings: settings, makesGIF: false, microphoneAllowed: false).microphoneID == nil)
    }
}

/// Recordings in the library: kept like captures, but for a week and two gigabytes at most.
struct RecordingLibraryTests {
    static func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "recording-library-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func poster() -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// A kept entry `days` old; a recording gets a movie of `bytes`.
    @discardableResult
    static func keep(_ kind: String, daysAgo days: Double, bytes: Int = 1000, now: Date, in root: URL) throws -> UUID {
        let id = UUID()
        let entry = CaptureLibrary.Entry(id: id, date: now.addingTimeInterval(-days * 86_400), scale: 2, kind: kind,
                                         appName: nil, fileURL: nil, edited: false, duration: kind == "selection" ? nil : 12)
        if kind == "selection" {
            try CaptureLibrary.store(poster(), entry: entry, in: root)
        } else {
            let movie = root.appending(path: "incoming-\(id).mov")
            try Data(count: bytes).write(to: movie)
            try CaptureLibrary.storeMovie(movie, poster: poster(), entry: entry, days: 30, in: root)
        }
        return id
    }

    @Test func keepsTheMovieAndThePosterAndSaysWhatItIs() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try Self.keep("video", daysAgo: 0, now: Date(), in: root)
        #expect(CaptureLibrary.movie(id, in: root) != nil)
        #expect(CaptureLibrary.original(id, in: root) != nil)
        let entry = try #require(CaptureLibrary.entry(id, in: root))
        #expect(entry.media == .video(duration: 12))
        #expect(CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 2, kind: "gif", appName: nil, fileURL: nil, edited: false,
                                     duration: 3).media == .gif(duration: 3))
        // Entries from before recordings still read as pictures.
        #expect(CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 2, kind: "selection", appName: nil, fileURL: nil,
                                     edited: false).media == .image)
    }

    @Test func recordingsGoAfterAWeekPicturesStay() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let fresh = try Self.keep("video", daysAgo: 1, now: now, in: root)
        let old = try Self.keep("gif", daysAgo: 8, now: now, in: root)
        let picture = try Self.keep("selection", daysAgo: 8, now: now, in: root)
        CaptureLibrary.prune(now: now, days: 30, in: root)
        #expect(CaptureLibrary.entry(fresh, in: root) != nil)
        #expect(CaptureLibrary.entry(old, in: root) == nil)
        #expect(CaptureLibrary.entry(picture, in: root) != nil)
    }

    @Test func theOldestGoOnceMoviesTakeTooMuchButNeverTheNewest() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let oldest = try Self.keep("video", daysAgo: 3, bytes: 4000, now: now, in: root)
        let middle = try Self.keep("video", daysAgo: 2, bytes: 4000, now: now, in: root)
        let newest = try Self.keep("video", daysAgo: 1, bytes: 9000, now: now, in: root)
        CaptureLibrary.pruneMovies(now: now, days: 30, bytes: 10_000, in: root)
        #expect(CaptureLibrary.entry(newest, in: root) != nil)
        #expect(CaptureLibrary.entry(middle, in: root) == nil)
        #expect(CaptureLibrary.entry(oldest, in: root) == nil)
    }

    @Test func historyFindsRecordingsByWhatTheyAre() {
        let namer = CaptureHistory.DayNamer(now: Date())
        let entry = CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 2, kind: "video", appName: nil, fileURL: nil,
                                         edited: false, duration: 5)
        let item = CaptureHistory.Item(entry: entry, isSaved: false, searchKey: CaptureHistory.searchKey(for: entry, namer: namer))
        #expect(item.subtitle == "Recording")
        #expect(CaptureHistory.filter([item], query: "recording").count == 1)
        #expect(CaptureHistory.filter([item], query: "video").count == 1)
    }
}

import AVFoundation
import CoreMedia
import VideoToolbox

/// Writes a recording to a movie file from the samples ScreenCaptureKit hands over: the
/// picture, and computer audio and the microphone on tracks of their own. Pausing drops what
/// arrives meanwhile and closes the gap. Nothing arrives while the screen is still, so the
/// last frame is held up to the moment you stopped.
///
/// Not thread-safe: use it from one serial queue. It never holds on to audio buffers, since
/// macOS stops delivering audio to apps that keep its buffers.
final class RecordingWriter {
    enum Source: CaseIterable, Sendable {
        case system, microphone

        /// The track's name in the file, which the video editor reads back.
        var trackName: String { self == .system ? "Computer audio" : "Microphone" }
    }

    struct Settings: Sendable {
        var width: Int
        var height: Int
        var frameRate: Int
        var codec: RecordingCodec
        var bitRate: Int
        var systemAudio = false
        var microphone = false
        /// Live samples come in real time; tests hand them over as fast as the writer takes them.
        var realTime = true
    }

    struct Output: Sendable {
        let url: URL
        let duration: TimeInterval
        let frames: Int
        /// The audio tracks, in the order they are in the file.
        let audio: [Source]
    }

    enum Failure: Error, Equatable {
        /// Stopped before the first frame arrived.
        case noFrames
        case couldNotWrite(String)
    }

    /// One timescale everywhere, so trimming never meets a fractional tail.
    static let timescale: CMTimeScale = 600

    let url: URL
    let settings: Settings
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audio: [Source: AVAssetWriterInput] = [:]
    /// The first frame's time, where the file starts.
    private var start: CMTime?
    /// How long it has been paused, taken off every later sample.
    private var offset = CMTime.zero
    private var pausedAt: CMTime?
    /// The last pause, so samples from inside it that arrive late are left out too.
    private var gap: (start: CMTime, end: CMTime)?
    private var lastFrame: CVPixelBuffer?
    private var lastFrameTime: CMTime?
    /// The newest frame that came in while paused: the picture to resume with.
    private var heldFrame: CVPixelBuffer?
    private var audioEnd: [Source: CMTime] = [:]
    private var finished = false
    private(set) var frames = 0
    private(set) var droppedFrames = 0

    var hasStarted: Bool { start != nil }
    var isPaused: Bool { pausedAt != nil }

    init(url: URL, settings: Settings) throws {
        self.url = url
        self.settings = settings
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // A crash leaves a file that plays up to the last two seconds.
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: Self.timescale)
        writer.movieTimeScale = Self.timescale
        video = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(settings))
        video.expectsMediaDataInRealTime = settings.realTime
        video.mediaTimeScale = Self.timescale
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(video) else { throw Failure.couldNotWrite("Can't add the video track") }
        writer.add(video)
        let sources = Source.allCases.filter { $0 == .system ? settings.systemAudio : settings.microphone }
        for source in sources {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(source))
            input.expectsMediaDataInRealTime = settings.realTime
            input.metadata = [Self.trackName(source.trackName)]
            guard writer.canAdd(input) else { throw Failure.couldNotWrite("Can't add the \(source.trackName) track") }
            writer.add(input)
            audio[source] = input
        }
        guard writer.startWriting() else {
            throw Failure.couldNotWrite(writer.error?.localizedDescription ?? "Can't start writing")
        }
    }

    // MARK: Samples

    func appendVideo(_ sample: CMSampleBuffer) {
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        appendVideo(pixels, at: CMSampleBufferGetPresentationTimeStamp(sample))
    }

    /// A frame at its time on the capture clock.
    func appendVideo(_ pixels: CVPixelBuffer, at time: CMTime) {
        guard !finished, time.isValid else { return }
        if pausedAt != nil {
            heldFrame = pixels
            return
        }
        if inGap(time) { return }
        if start == nil {
            writer.startSession(atSourceTime: time)
            start = time
        }
        write(pixels, at: time - offset, nudges: false)
    }

    /// Audio is written at once and never kept. Anything before the first frame is left out.
    func appendAudio(_ sample: CMSampleBuffer, from source: Source) {
        guard !finished, pausedAt == nil, let start, let input = audio[source] else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard time.isValid, time >= start, !inGap(time) else { return }
        let out = time - offset
        // Straddled a pause: it would overlap what's written already.
        if let end = audioEnd[source], out < end - CMTime(value: 1, timescale: 1000) { return }
        let retimed = offset == .zero ? sample : Self.retimed(sample, by: offset)
        guard let retimed, ready(input) else { return }
        if input.append(retimed) {
            audioEnd[source] = out + Self.duration(of: sample)
        }
    }

    private func write(_ pixels: CVPixelBuffer, at time: CMTime, nudges: Bool) {
        var time = time
        if let last = lastFrameTime, time <= last {
            // Frames only go forward; a held frame is placed just after the last one.
            guard nudges else { return }
            time = last + CMTime(value: 1, timescale: Self.timescale)
        }
        guard ready(video) else {
            droppedFrames += 1
            return
        }
        if adaptor.append(pixels, withPresentationTime: time) {
            lastFrame = pixels
            lastFrameTime = time
            frames += 1
        }
    }

    private func inGap(_ time: CMTime) -> Bool {
        guard let gap else { return false }
        return time >= gap.start && time < gap.end
    }

    /// Live, a busy encoder means the sample is dropped; in tests, wait for it.
    private func ready(_ input: AVAssetWriterInput) -> Bool {
        if input.isReadyForMoreMediaData { return true }
        guard !settings.realTime else { return false }
        for _ in 0..<2000 {
            usleep(1000)
            if input.isReadyForMoreMediaData { return true }
        }
        return false
    }

    // MARK: Pause, stop

    func pause(at time: CMTime) {
        guard !finished, pausedAt == nil, time.isValid else { return }
        pausedAt = time
    }

    /// Resumes, starting with whatever the screen showed last, so a change made while paused
    /// shows straight away rather than at the next change.
    func resume(at time: CMTime) {
        guard let pausedAt, time.isValid else { return }
        self.pausedAt = nil
        if start != nil, time > pausedAt {
            offset = offset + (time - pausedAt)
            gap = (pausedAt, time)
        }
        guard let held = heldFrame else { return }
        heldFrame = nil
        if start == nil {
            writer.startSession(atSourceTime: time)
            start = time
        }
        write(held, at: time - offset, nudges: true)
    }

    /// Finishes the file at `time` on the capture clock (or where the pause began, if paused).
    func finish(at time: CMTime, completion: @escaping @Sendable (Result<Output, Failure>) -> Void) {
        guard !finished else { return }
        finished = true
        guard let start else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return completion(.failure(.noFrames))
        }
        let stop = pausedAt ?? (time.isValid ? time : start)
        var end = stop - offset
        if let last = lastFrameTime, end < last { end = last }
        // The screen may not have changed since the last frame: it stays up until the end.
        if let frame = lastFrame, let last = lastFrameTime, end > last {
            write(frame, at: end, nudges: false)
        }
        writer.endSession(atSourceTime: end)
        video.markAsFinished()
        for input in audio.values { input.markAsFinished() }
        let output = Output(url: url, duration: (end - start).seconds, frames: frames,
                            audio: Source.allCases.filter { audio[$0] != nil })
        lastFrame = nil
        heldFrame = nil
        nonisolated(unsafe) let writer = writer
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(output))
            } else {
                completion(.failure(.couldNotWrite(writer.error?.localizedDescription ?? "The movie couldn't be finished")))
            }
        }
    }

    /// Lets the file go.
    func cancel() {
        guard !finished else { return }
        finished = true
        lastFrame = nil
        heldFrame = nil
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Formats

    static func videoSettings(_ settings: Settings) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.bitRate,
            AVVideoExpectedSourceFrameRateKey: settings.frameRate,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            // No B-frames: they blur text, and live encoding gains little from them.
            AVVideoAllowFrameReorderingKey: false,
        ]
        if settings.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        } else {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
        let colour: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        return [
            AVVideoCodecKey: settings.codec.videoCodec,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            AVVideoColorPropertiesKey: colour,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    /// AAC at 48 kHz: computer audio in stereo, the microphone in mono.
    static func audioSettings(_ source: Source) -> [String: Any] {
        let channels = source == .system ? 2 : 1
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
        let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: source == .system ? 128_000 : 96_000,
            AVChannelLayoutKey: layoutData,
        ]
    }

    private static func trackName(_ name: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeUserDataTrackName
        item.value = name as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    // MARK: Timing

    /// A copy of the sample, `offset` earlier.
    static func retimed(_ sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - offset
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - offset
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: count,
                                                           sampleTimingArray: &timing, sampleBufferOut: &copy)
        return status == noErr ? copy : nil
    }

    /// How long an audio sample lasts: its stated duration, or its frames at its sample rate.
    static func duration(of sample: CMSampleBuffer) -> CMTime {
        let stated = CMSampleBufferGetDuration(sample)
        if stated.isValid, stated > .zero { return stated }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mSampleRate > 0 else { return .zero }
        return CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(description.mSampleRate))
    }
}

/// How loud a buffer of audio is, for the microphone's level in the controls.
enum AudioLevel {
    /// Root mean square, from 0 (silence) to about 1 (full scale). Reads 32-bit float and
    /// 16-bit integer samples, interleaved or not.
    static func rms(of sample: CMSampleBuffer) -> Float {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return 0 }
        let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bits = description.mBitsPerChannel
        guard (isFloat && bits == 32) || (!isFloat && bits == 16) else { return 0 }
        let level: Float? = try? sample.withAudioBufferList { list, _ in
            var sum: Double = 0
            var count = 0
            for buffer in list {
                guard let data = buffer.mData else { continue }
                if isFloat {
                    let values = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                     count: Int(buffer.mDataByteSize) / 4)
                    for value in values { sum += Double(value) * Double(value) }
                    count += values.count
                } else {
                    let values = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int16.self),
                                                     count: Int(buffer.mDataByteSize) / 2)
                    for value in values {
                        let scaled = Double(value) / 32_768
                        sum += scaled * scaled
                    }
                    count += values.count
                }
            }
            return count > 0 ? Float((sum / Double(count)).squareRoot()) : 0
        }
        return level ?? 0
    }
}

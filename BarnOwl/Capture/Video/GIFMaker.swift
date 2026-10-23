import AVFoundation
import CoreGraphics

/// Turns a movie, part of one, or an edited movie into a looping GIF. Frames are taken at the
/// chosen rate from the same composition the editor plays, scaled down on the GPU, and streamed
/// into `GIFWriter`: a frame that's the same as the one before only makes that one last longer,
/// so a screen that sits still costs nothing, and delays are kept to the centisecond without
/// drifting. Off the main thread, with progress, and it stops when its task is cancelled.
enum GIFMaker {
    struct Options: Equatable, Sendable {
        static let defaultWidth = 800
        static let defaultFPS = 15
        /// More different frames than this and the GIF is refused: three minutes at 15 fps.
        static let maximumFrames = 2_700

        /// The GIF's width in pixels; never wider than the movie.
        var width = Options.defaultWidth
        var fps = Options.defaultFPS

        static let high = Options(width: 1200, fps: 24)
        static let standard = Options()
        static let small = Options(width: 480, fps: 10)
    }

    struct Result: Sendable {
        let url: URL
        /// Frames written, after identical ones were merged.
        let frameCount: Int
        /// Each frame's delay, in seconds.
        let delays: [Double]
        let duration: Double
        let pixelSize: CGSize
        let byteCount: Int64
    }

    typealias Progress = @Sendable (Double) -> Void

    /// A GIF of the movie at `movie`, or of `range` (in seconds) within it.
    static func make(from movie: URL, range: ClosedRange<Double>? = nil, options: Options = Options(), to url: URL,
                     progress: @escaping Progress = { _ in }) async throws -> Result {
        let info = try await MovieInfo.load(movie)
        var edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size, audioTracks: info.audioTracks.count)
        if let range {
            let start = min(max(0, VideoEdit.ticks(seconds: range.lowerBound)), info.duration - VideoEdit.minimumClip)
            let end = min(max(start + VideoEdit.minimumClip, VideoEdit.ticks(seconds: range.upperBound)), info.duration)
            edit.clips = [VideoEdit.Clip(start: start, duration: end - start)]
        }
        return try await make(info, edit: edit, options: options, to: url, progress: progress)
    }

    /// A GIF of an edited movie: its clips, speeds and crop.
    static func make(_ info: MovieInfo, edit: VideoEdit, options: Options, to url: URL,
                     progress: @escaping Progress = { _ in }) async throws -> Result {
        let crop = edit.crop ?? CGRect(origin: .zero, size: info.size)
        let size = pixelSize(for: crop.size, width: options.width)
        let fps = min(max(options.fps, 1), 50)
        let seconds = VideoEdit.seconds(edit.duration)
        guard Int((seconds * Double(fps)).rounded(.up)) <= Options.maximumFrames else { throw VideoEditError.tooLongForGIF }
        let asset = AVURLAsset(url: info.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let output = VideoComposer.Output(size: size, frameRate: Double(fps), alwaysComposes: true)
        let built = try await VideoComposer.build(asset, info: info, edit: edit, output: output)
        let job = Handoff(value: built)
        try? FileManager.default.removeItem(at: url)
        let delays = try await MediaQueue.run { flag in
            try write(job.value, to: url, flag: flag, progress: progress)
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return Result(url: url, frameCount: delays.count, delays: delays, duration: delays.reduce(0, +), pixelSize: size,
                      byteCount: bytes)
    }

    /// The GIF's size for a picture of `size`: `width` wide at most, never enlarged.
    static func pixelSize(for size: CGSize, width: Int) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let wide = min(CGFloat(width), size.width).rounded()
        let high = max(1, (size.height * wide / size.width).rounded())
        return CGSize(width: max(1, wide), height: high)
    }

    // MARK: Estimate

    /// A quick guess from the picture's size alone, for before the better one is ready.
    static func roughEstimate(pixelSize: CGSize, fps: Int, seconds: Double) -> Int64 {
        let pixels = Double(pixelSize.width * pixelSize.height)
        let first = pixels * 0.25
        let frames = max(0, seconds * Double(fps) - 1)
        let rest = frames * pixels * 0.01
        return Int64(first + rest + 1_000)
    }

    /// A better guess, made by encoding a few one-second stretches (without keeping them) and
    /// scaling up to the whole length.
    static func estimate(_ info: MovieInfo, edit: VideoEdit, options: Options) async -> Int64? {
        let duration = edit.duration
        guard duration > 0 else { return nil }
        let crop = edit.crop ?? CGRect(origin: .zero, size: info.size)
        let size = pixelSize(for: crop.size, width: options.width)
        let fps = min(max(options.fps, 1), 50)
        let sample = min(duration, VideoEdit.ticks(seconds: 1))
        let points: [Int64] = duration <= 3 * sample ? [0] : [0, duration / 2 - sample / 2, duration - sample]
        var clips: [VideoEdit.Clip] = []
        for point in points {
            let source = edit.sourceTime(at: point)
            let speed = edit.clip(at: point).map { edit.clips[$0.index].speed } ?? 1
            let length = min(Int64(Double(sample) * speed), info.duration - source)
            guard length >= VideoEdit.minimumClip else { continue }
            clips.append(VideoEdit.Clip(start: source, duration: length, speed: speed))
        }
        guard !clips.isEmpty else { return nil }
        var sampled = edit
        sampled.clips = clips
        let asset = AVURLAsset(url: info.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let output = VideoComposer.Output(size: size, frameRate: Double(fps), alwaysComposes: true)
        guard let built = try? await VideoComposer.build(asset, info: info, edit: sampled, output: output) else { return nil }
        let job = Handoff(value: built)
        let measured = try? await MediaQueue.run(qos: .utility) { flag -> Int in
            try write(job.value, sink: .count, flag: flag, progress: { _ in }).bytes
        }
        guard let measured else { return nil }
        let sampledSeconds = VideoEdit.seconds(sampled.duration)
        let total = VideoEdit.seconds(duration)
        guard sampledSeconds < total else { return Int64(measured) }
        // The first frame costs the most; the rest grows with time.
        let first = Double(size.width * size.height) * 0.25
        let moving = max(0, Double(measured) - first)
        return Int64(first + moving * total / max(sampledSeconds, 0.1))
    }

    // MARK: Writing

    /// Writes the GIF and returns each frame's delay in seconds. Blocks; call on a media queue.
    private static func write(_ built: VideoComposition, to url: URL, flag: CancelFlag, progress: Progress) throws -> [Double] {
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { throw VideoEditError.writeFailed(nil) }
        do {
            return try write(built, sink: .file(handle), flag: flag, progress: progress).delays
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Streams the frames into a GIF writer: one pass, with two frames in memory.
    private static func write(_ built: VideoComposition, sink: GIFWriter.Sink, flag: CancelFlag,
                              progress: Progress) throws -> (delays: [Double], bytes: Int) {
        let total = max(built.duration.seconds, 0.001)
        let size = built.renderSize
        let writer = GIFWriter(width: Int(size.width), height: Int(size.height), sink: sink)
        var reported = -1.0
        var frames = 0
        try readFrames(built, flag: flag) { buffer, time in
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetWidth(buffer) >= writer.width,
                  CVPixelBufferGetHeight(buffer) >= writer.height else { return }
            if try writer.add(bgra: base, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), at: time) {
                frames += 1
                if frames > Options.maximumFrames { throw VideoEditError.tooLongForGIF }
            }
            let fraction = min(1, time / total)
            if fraction - reported >= 0.01 {
                reported = fraction
                progress(fraction * 0.99)
            }
        }
        guard frames > 0 else { throw VideoEditError.unreadable }
        try writer.finish(at: total)
        progress(1)
        return (writer.delays.map { Double($0) / 100 }, writer.byteCount)
    }

    /// Hands every frame of the composition, at its frame rate, to `body` with its time in seconds.
    private static func readFrames(_ built: VideoComposition, flag: CancelFlag,
                                   _ body: (CVPixelBuffer, Double) throws -> Void) throws {
        let reader = try AVAssetReader(asset: built.composition)
        let tracks = built.composition.tracks(withMediaType: .video)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.videoComposition = built.videoComposition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoEditError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw VideoEditError.unreadable }
        defer { reader.cancelReading() }
        while let sample = output.copyNextSampleBuffer() {
            if flag.isCancelled { throw CancellationError() }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            try body(buffer, time)
        }
        if flag.isCancelled { throw CancellationError() }
        if reader.status == .failed { throw VideoEditError.unreadable }
    }
}

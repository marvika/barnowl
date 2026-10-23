import AVFoundation
import CoreGraphics

/// Writes an edited movie to a file: MP4 or MOV through an asset reader and writer, so the
/// size, codec and bit rate are ours to choose, or a GIF through `GIFMaker`. Runs off the main
/// thread, reports progress from 0 to 1 and stops when its task is cancelled.
enum VideoExporter {
    typealias Progress = @Sendable (Double) -> Void

    /// What the export made.
    struct Result: Sendable {
        let url: URL
        let byteCount: Int64
        let pixelSize: CGSize
        let duration: Double
    }

    /// Exports `edit` of the movie at `info.url` to `url`, as the edit's export settings say.
    /// It's written elsewhere first and only then takes the place of what's at `url`, so a
    /// failed or cancelled export leaves that file as it was. Never over the movie itself.
    static func export(_ info: MovieInfo, edit: VideoEdit, to url: URL, progress: @escaping Progress = { _ in }) async throws -> Result {
        guard !isSameFile(url, info.url) else { throw VideoEditError.overSource }
        let manager = FileManager.default
        // On the same volume, so it moves into place at once.
        let beside = try? manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        let folder = beside ?? manager.temporaryDirectory.appending(path: "Barn Owl Export \(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let written = try await write(info, edit: edit, to: folder.appending(path: url.lastPathComponent), progress: progress)
        try put(written.url, at: url)
        return Result(url: url, byteCount: written.byteCount, pixelSize: written.pixelSize, duration: written.duration)
    }

    /// Whether two URLs name one file, however they're spelled.
    static func isSameFile(_ one: URL, _ other: URL) -> Bool {
        if one.standardizedFileURL.resolvingSymlinksInPath() == other.standardizedFileURL.resolvingSymlinksInPath() {
            return true
        }
        let key = URLResourceKey.fileResourceIdentifierKey
        guard let first = try? one.resourceValues(forKeys: [key]).fileResourceIdentifier,
              let second = try? other.resourceValues(forKeys: [key]).fileResourceIdentifier else { return false }
        return first.isEqual(second)
    }

    /// Moves a finished file into place, over whatever is there.
    static func put(_ file: URL, at url: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: file)
        } else {
            try manager.moveItem(at: file, to: url)
        }
    }

    private static func write(_ info: MovieInfo, edit: VideoEdit, to url: URL,
                              progress: @escaping Progress) async throws -> Result {
        let settings = edit.export
        let crop = edit.crop ?? CGRect(origin: .zero, size: info.size)
        let pixelSize = settings.pixelSize(for: crop.size)
        if settings.format == .gif {
            let options = GIFMaker.Options(width: Int(pixelSize.width), fps: settings.gifFPS)
            let made = try await GIFMaker.make(info, edit: edit, options: options, to: url, progress: progress)
            return Result(url: url, byteCount: made.byteCount, pixelSize: made.pixelSize, duration: made.duration)
        }
        let asset = AVURLAsset(url: info.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let output = VideoComposer.Output(size: pixelSize, frameRate: info.frameRate, alwaysComposes: true)
        let built = try await VideoComposer.build(asset, info: info, edit: edit, output: output)
        let plan = Plan(settings: settings, pixelSize: pixelSize, frameRate: info.frameRate)
        let job = Handoff(value: built)
        try await MediaQueue.run { flag in
            try transcode(job.value, plan: plan, to: url, fileType: settings.format == .mov ? .mov : .mp4, flag: flag,
                          progress: progress)
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return Result(url: url, byteCount: bytes, pixelSize: pixelSize, duration: built.duration.seconds)
    }

    // MARK: Settings

    /// The encoder's settings for one export.
    struct Plan: Sendable {
        let codec: AVVideoCodecType
        let pixelSize: CGSize
        let frameRate: Double
        let videoBitRate: Double
        let audioBitRate: Int

        init(settings: VideoExportSettings, pixelSize: CGSize, frameRate: Double) {
            // H.264 stops at 4096 × 2304; past that, HEVC keeps the size.
            let tooBig = pixelSize.width > 4096 || pixelSize.height > 2304
            codec = settings.quality == .small || tooBig ? .hevc : .h264
            self.pixelSize = pixelSize
            self.frameRate = frameRate
            let fps: Double = min(max(frameRate, 15), 60)
            let pixels: Double = Double(pixelSize.width * pixelSize.height)
            videoBitRate = pixels * fps * Plan.bitsPerPixel(settings.quality)
            audioBitRate = Plan.audioBitRate(settings.quality)
        }

        /// Bits per pixel per frame: high enough that small text stays crisp while it moves.
        static func bitsPerPixel(_ quality: VideoExportSettings.Quality) -> Double {
            switch quality {
            case .high: 0.3
            case .standard: 0.15
            case .small: 0.08
            }
        }

        static func audioBitRate(_ quality: VideoExportSettings.Quality) -> Int {
            switch quality {
            case .high: 192_000
            case .standard: 128_000
            case .small: 96_000
            }
        }

        var videoSettings: [String: Any] {
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: Int(videoBitRate),
                AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                // B-frames blur text; screen recordings are better without them.
                AVVideoAllowFrameReorderingKey: false,
            ]
            if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            return [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: Int(pixelSize.width),
                AVVideoHeightKey: Int(pixelSize.height),
                AVVideoCompressionPropertiesKey: compression,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ]
        }

        var audioSettings: [String: Any] {
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: audioBitRate,
            ]
        }
    }

    // MARK: Size estimate

    /// About how many bytes the export will take. For a movie it follows the source's own data
    /// rate, as screen recordings that mostly sit still never use the bit rate they're allowed.
    static func estimate(_ info: MovieInfo, edit: VideoEdit) -> Int64 {
        let settings = edit.export
        let crop = edit.crop ?? CGRect(origin: .zero, size: info.size)
        let size = settings.pixelSize(for: crop.size)
        let seconds = VideoEdit.seconds(edit.duration)
        if settings.format == .gif {
            return GIFMaker.roughEstimate(pixelSize: size, fps: settings.gifFPS, seconds: seconds)
        }
        let plan = Plan(settings: settings, pixelSize: size, frameRate: info.frameRate)
        let sourcePixels = Double(max(1, info.size.width * info.size.height))
        let ratio = Double(size.width * size.height) / sourcePixels
        let factor: Double = switch settings.quality {
        case .high: 1.4
        case .standard: 1
        case .small: 0.55
        }
        let followed = info.videoDataRate > 0 ? info.videoDataRate * ratio * factor : plan.videoBitRate
        let video = min(plan.videoBitRate, max(followed, 200_000))
        let heard = edit.levels.contains { $0.gain > 0 }
        let audio = heard ? Double(plan.audioBitRate) : 0
        let bytes = (video + audio) * seconds / 8
        return Int64(bytes) + 16_000
    }

    // MARK: Transcoding

    /// Reads the composition and writes it to `url`. Blocks until done; call on a media queue.
    private static func transcode(_ built: VideoComposition, plan: Plan, to url: URL, fileType: AVFileType, flag: CancelFlag,
                                  progress: Progress) throws {
        let reader = try AVAssetReader(asset: built.composition)
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = true

        let videoTracks = built.composition.tracks(withMediaType: .video)
        let videoOut = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOut.videoComposition = built.videoComposition
        videoOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut) else { throw VideoEditError.unreadable }
        reader.add(videoOut)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: plan.videoSettings)
        videoIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoIn) else { throw VideoEditError.writeFailed(nil) }
        writer.add(videoIn)

        var audioOut: AVAssetReaderAudioMixOutput?
        var audioIn: AVAssetWriterInput?
        let audioTracks = built.composition.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            out.audioMix = built.audioMix
            out.audioTimePitchAlgorithm = .spectral
            out.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: plan.audioSettings)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(out), writer.canAdd(input) {
                reader.add(out)
                writer.add(input)
                audioOut = out
                audioIn = input
            }
        }

        guard reader.startReading() else { throw VideoEditError.writeFailed(reader.error?.localizedDescription) }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw VideoEditError.writeFailed(writer.error?.localizedDescription)
        }
        writer.startSession(atSourceTime: .zero)

        let total = max(built.duration.seconds, 0.001)
        var videoDone = false
        var audioDone = audioIn == nil
        var lastReport = -1.0
        // Feeds whichever input is ready, so the writer can interleave sound and picture.
        while !(videoDone && audioDone) {
            if flag.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                throw CancellationError()
            }
            var moved = false
            if !videoDone, videoIn.isReadyForMoreMediaData {
                if let sample = videoOut.copyNextSampleBuffer() {
                    guard videoIn.append(sample) else { break }
                    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    let fraction = min(1, max(0, time / total))
                    if fraction - lastReport >= 0.01 {
                        lastReport = fraction
                        progress(fraction * 0.98)
                    }
                } else {
                    videoIn.markAsFinished()
                    videoDone = true
                }
                moved = true
            }
            if !audioDone, let audioIn, let audioOut, audioIn.isReadyForMoreMediaData {
                if let sample = audioOut.copyNextSampleBuffer() {
                    guard audioIn.append(sample) else { break }
                } else {
                    audioIn.markAsFinished()
                    audioDone = true
                }
                moved = true
            }
            if !moved { usleep(2_000) }
        }

        if reader.status == .failed || writer.status == .failed {
            let reason = writer.error?.localizedDescription ?? reader.error?.localizedDescription
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw VideoEditError.writeFailed(reason)
        }
        writer.endSession(atSourceTime: built.duration)
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw VideoEditError.writeFailed(writer.error?.localizedDescription)
        }
        progress(1)
    }
}

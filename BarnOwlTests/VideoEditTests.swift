import AVFoundation
import CoreGraphics
import ImageIO
import Testing
@testable import BarnOwl

/// Makes small movies to edit: a square moving across a pale picture, then holding still, with
/// tones on named sound tracks if asked.
enum TestMovie {
    static func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "BarnOwlVideoTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `seconds` long at `fps`; the square moves for `moving` seconds and then holds still.
    /// Draws one frame: the context, its size, and how far through the movement (0 to 1).
    typealias Painter = (CGContext, Int, Int, Double) -> Void

    static func make(at url: URL, width: Int = 320, height: Int = 200, seconds: Double = 2, fps: Int = 30,
                     moving: Double = 1, audioTracks: [String] = [], painter: Painter? = nil) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(video)
        var audioInputs: [AVAssetWriterInput] = []
        for name in audioTracks {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ])
            input.expectsMediaDataInRealTime = false
            let title = AVMutableMetadataItem()
            title.identifier = .quickTimeUserDataTrackName
            title.value = name as NSString
            title.dataType = kCMMetadataBaseDataType_UTF8 as String
            input.metadata = [title]
            writer.add(input)
            audioInputs.append(input)
        }
        guard writer.startWriting() else { throw writer.error ?? VideoEditError.writeFailed(nil) }
        writer.startSession(atSourceTime: .zero)

        // Picture and sound go in turn, as the writer interleaves them.
        let frames = Int(seconds * Double(fps))
        let rate = 48_000
        let chunk = 4_800
        let samples = Int(seconds * Double(rate))
        var frame = 0
        var written = [Int](repeating: 0, count: audioInputs.count)
        var videoDone = false
        var audioDone = [Bool](repeating: false, count: audioInputs.count)
        while !videoDone || audioDone.contains(false) {
            var moved = false
            if !videoDone, video.isReadyForMoreMediaData {
                if frame < frames {
                    let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
                    let t = min(Double(frame) / Double(fps), moving)
                    guard let pool = adaptor.pixelBufferPool else { throw VideoEditError.writeFailed("no pool") }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    guard let buffer else { throw VideoEditError.writeFailed("no buffer") }
                    draw(into: buffer, width: width, height: height, progress: moving > 0 ? t / moving : 0,
                         painter: painter)
                    adaptor.append(buffer, withPresentationTime: time)
                    frame += 1
                } else {
                    video.markAsFinished()
                    videoDone = true
                }
                moved = true
            }
            for (index, input) in audioInputs.enumerated() where !audioDone[index] && input.isReadyForMoreMediaData {
                if written[index] < samples {
                    let count = min(chunk, samples - written[index])
                    input.append(try tone(start: written[index], count: count, rate: rate, frequency: 440 * Double(index + 1)))
                    written[index] += count
                } else {
                    input.markAsFinished()
                    audioDone[index] = true
                }
                moved = true
            }
            if writer.status == .failed { throw writer.error ?? VideoEditError.writeFailed(nil) }
            if !moved { usleep(1_000) }
        }
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? VideoEditError.writeFailed(nil) }
    }

    private static func draw(into buffer: CVPixelBuffer, width: Int, height: Int, progress: Double, painter: Painter?) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        if let painter { return painter(context, width, height, progress) }
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.42, green: 0.39, blue: 0.94, alpha: 1))
        let side = CGFloat(height) / 3
        let x = (CGFloat(width) - side) * CGFloat(progress)
        context.fill(CGRect(x: x, y: CGFloat(height) / 3, width: side, height: side))
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.65, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 40, height: 14))
    }

    private static func tone(start: Int, count: Int, rate: Int, frequency: Double) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: Double(rate), mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                                      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                                      mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(start + index) / Double(rate)
            samples[index] = Int16(sin(2 * .pi * frequency * t) * 8_000)
        }
        var block: CMBlockBuffer?
        let length = count * 2
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0,
                                           blockBufferOut: &block)
        guard let block, let format else { throw VideoEditError.writeFailed("audio") }
        _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format,
                                                            sampleCount: count,
                                                            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
                                                            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw VideoEditError.writeFailed("audio sample") }
        return sample
    }
}

struct VideoEditTests {
    static func edit(seconds: Double = 10, tracks: Int = 2) -> VideoEdit {
        VideoEdit(sourceDuration: VideoEdit.ticks(seconds: seconds), sourceSize: CGSize(width: 1920, height: 1080),
                  audioTracks: tracks)
    }

    // MARK: Document

    @Test func freshEditIsTheWholeMovie() {
        let edit = Self.edit()
        #expect(edit.clips.count == 1)
        #expect(edit.duration == 6_000)
        #expect(edit.isUntouched)
        #expect(edit.levels.count == 2)
        #expect(edit.segments == [VideoEdit.Segment(source: CMTimeRange(start: .zero, duration: VideoEdit.time(6_000)),
                                                    at: .zero, duration: VideoEdit.time(6_000))])
    }

    @Test func roundTripsThroughJSON() throws {
        var edit = Self.edit()
        edit.split(at: 1_800)
        edit.crop = CGRect(x: 100, y: 50, width: 800, height: 600)
        edit.levels[1].muted = true
        edit.export.format = .gif
        edit.export.gifWidth = 480
        let data = try JSONEncoder().encode(edit)
        let decoded = try JSONDecoder().decode(VideoEdit.self, from: data)
        #expect(decoded == edit)
    }

    @Test func decodesAnOlderOrDamagedDocument() throws {
        // No levels, export or schema; a clip running past the end and one too short; an odd speed.
        let json = """
        {"sourceDuration": 6000, "sourceSize": [1920, 1080],
         "clips": [{"id": "\(UUID().uuidString)", "start": 5000, "duration": 9000, "speed": 3},
                   {"id": "\(UUID().uuidString)", "start": -50, "duration": 2}],
         "crop": [[0, 0], [1920, 1080]]}
        """
        let decoded = try JSONDecoder().decode(VideoEdit.self, from: Data(json.utf8))
        #expect(decoded.schemaVersion == VideoEdit.currentSchema)
        #expect(decoded.clips.count == 2)
        #expect(decoded.clips[0].end == 6_000)
        #expect(decoded.clips[0].speed == 2 || decoded.clips[0].speed == 4)
        #expect(decoded.clips[1].start == 0)
        #expect(decoded.clips[1].duration == VideoEdit.minimumClip)
        // A crop of the whole picture is no crop.
        #expect(decoded.crop == nil)
        #expect(decoded.export == VideoExportSettings())
    }

    // MARK: Cuts

    @Test func cuttingOutTheMiddleLeavesTwoRanges() {
        var edit = Self.edit()
        let middle = edit.split(at: VideoEdit.ticks(seconds: 3))
        #expect(middle != nil)
        let tail = edit.split(at: VideoEdit.ticks(seconds: 7))
        #expect(tail != nil)
        #expect(edit.clips.count == 3)
        let removed = edit.remove(middle!)
        #expect(removed)
        let segments = edit.segments
        #expect(segments.count == 2)
        #expect(segments[0].source == CMTimeRange(start: .zero, duration: VideoEdit.time(1_800)))
        #expect(segments[0].at == .zero)
        #expect(segments[1].source == CMTimeRange(start: VideoEdit.time(4_200), duration: VideoEdit.time(1_800)))
        #expect(segments[1].at == VideoEdit.time(1_800))
        #expect(edit.duration == 3_600)
        // The cut joins 0:03 straight to 0:07.
        #expect(edit.sourceTime(at: 1_799) == 1_799)
        #expect(edit.sourceTime(at: 1_800) == 4_200)
        #expect(edit.outputTime(ofSource: 4_500) == 2_100)
        #expect(edit.outputTime(ofSource: 3_000) == nil)
    }

    @Test func splitNearAnEdgeIsRefused() {
        var edit = Self.edit()
        let early = edit.split(at: 5)
        let late = edit.split(at: edit.duration - 5)
        #expect(early == nil)
        #expect(late == nil)
        #expect(edit.clips.count == 1)
    }

    @Test func theLastClipStays() {
        var edit = Self.edit()
        let removed = edit.remove(edit.clips[0].id)
        #expect(!removed)
        #expect(edit.clips.count == 1)
    }

    @Test func trimmingKeepsTheOtherEdge() {
        var edit = Self.edit()
        let id = edit.clips[0].id
        edit.trimStart(id, to: 600)
        #expect(edit.clips[0].start == 600)
        #expect(edit.clips[0].end == 6_000)
        edit.trimEnd(id, to: 5_400)
        #expect(edit.clips[0].end == 5_400)
        #expect(edit.duration == 4_800)
        // Never past the movie or shorter than the minimum.
        edit.trimEnd(id, to: 99_999)
        #expect(edit.clips[0].end == 6_000)
        edit.trimStart(id, to: 9_000)
        #expect(edit.clips[0].duration == VideoEdit.minimumClip)
        #expect(!edit.isUntouched)
    }

    @Test func speedChangesHowLongAClipPlays() {
        var edit = Self.edit()
        let tail = edit.split(at: 3_000)!
        edit.setSpeed(2, for: tail)
        #expect(edit.duration == 3_000 + 1_500)
        let segments = edit.segments
        #expect(segments[1].source.duration == VideoEdit.time(3_000))
        #expect(segments[1].duration == VideoEdit.time(1_500))
        // Halfway into the fast clip is three quarters into the movie.
        #expect(edit.sourceTime(at: 3_750) == 4_500)
        #expect(edit.outputTime(ofSource: 4_500) == 3_750)
        edit.setSpeed(0.5, for: tail)
        #expect(edit.duration == 3_000 + 6_000)
    }

    @Test func clipAtFindsTheRightOne() {
        var edit = Self.edit()
        edit.split(at: 1_000)
        edit.split(at: 2_000)
        #expect(edit.clip(at: 0)?.index == 0)
        #expect(edit.clip(at: 999)?.index == 0)
        #expect(edit.clip(at: 1_000)?.index == 1)
        #expect(edit.clip(at: 2_500)?.index == 2)
        #expect(edit.clip(at: edit.duration)?.index == 2)
        #expect(edit.clipStarts == [0, 1_000, 2_000])
    }

    @Test func clocksReadNaturally() {
        #expect(VideoEdit.clock(VideoEdit.ticks(seconds: 42)) == "0:42")
        #expect(VideoEdit.clock(VideoEdit.ticks(seconds: 3_909)) == "1:05:09")
        #expect(VideoEdit.preciseClock(VideoEdit.ticks(seconds: 12.46)) == "0:12.4")
        #expect(VideoTimelineView.rulerLabel(65, step: 5) == "1:05")
        #expect(VideoTimelineView.rulerLabel(1.5, step: 0.5) == "0:01.5")
    }

    // MARK: Export settings

    @Test func exportSizesFitTheirBoxAndAreEven() {
        var settings = VideoExportSettings()
        let retina = CGSize(width: 2940, height: 1912)
        #expect(settings.pixelSize(for: retina) == CGSize(width: 2940, height: 1912))
        settings.size = .hd1080
        let hd = settings.pixelSize(for: retina)
        #expect(hd.height <= 1080 && hd.width <= 1920)
        #expect(Int(hd.width) % 2 == 0 && Int(hd.height) % 2 == 0)
        settings.size = .hd720
        // Never larger than the movie.
        #expect(settings.pixelSize(for: CGSize(width: 640, height: 400)) == CGSize(width: 640, height: 400))
        // Portrait fits the box on its side.
        let portrait = settings.pixelSize(for: CGSize(width: 1080, height: 1920))
        #expect(portrait.width <= 720 && portrait.height <= 1280)
        settings.format = .gif
        settings.gifWidth = 800
        #expect(settings.pixelSize(for: retina).width == 800)
    }

    @Test func movieEstimateFollowsTheSource() {
        let info = MovieInfo(url: URL(fileURLWithPath: "/tmp/x.mov"), duration: VideoEdit.ticks(seconds: 60),
                             size: CGSize(width: 2940, height: 1912), frameRate: 30, videoDataRate: 2_000_000,
                             audioTracks: [], hasVideo: true)
        var edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size)
        let standard = VideoExporter.estimate(info, edit: edit)
        // About 2 Mbit/s for a minute: 15 MB.
        #expect(standard > 12_000_000 && standard < 18_000_000)
        edit.export.quality = .small
        #expect(VideoExporter.estimate(info, edit: edit) < standard)
        edit.export.size = .hd720
        #expect(VideoExporter.estimate(info, edit: edit) < standard / 3)
    }

    @Test func fallbackTrackNames() {
        #expect(MovieInfo.fallbackNames(count: 1) == ["Sound"])
        #expect(MovieInfo.fallbackNames(count: 2) == ["Computer", "Mic"])
        #expect(MovieInfo.fallbackNames(count: 3) == ["Sound 1", "Sound 2", "Sound 3"])
    }

    // MARK: Crop

    @Test func cropDragStaysInsideAndKeepsItsShape() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let start = CGRect(x: 100, y: 100, width: 800, height: 450)
        let moved = CropOverlayView.adjust(start, handle: .move, dx: 5_000, dy: 0, ratio: nil, bounds: bounds)
        #expect(moved.maxX == 1920)
        let wide = CropOverlayView.adjust(start, handle: .bottomRight, dx: 160, dy: 0, ratio: 16.0 / 9, bounds: bounds)
        #expect(abs(wide.width / wide.height - 16.0 / 9) < 0.01)
        #expect(wide.minX == 100 && wide.minY == 100)
        let tiny = CropOverlayView.adjust(start, handle: .left, dx: 5_000, dy: 0, ratio: nil, bounds: bounds)
        #expect(tiny.width >= 32)
    }
}

// MARK: GIF writer

struct GIFWriterTests {
    /// Frames of solid colour with a moving block, as BGRA.
    static func frame(width: Int, height: Int, block: Int, colour: UInt32) -> [UInt32] {
        var pixels = [UInt32](repeating: 0xFFEE_EEF2, count: width * height)
        for y in 10..<min(height, 30) {
            for x in block..<min(width, block + 20) { pixels[y * width + x] = colour }
        }
        return pixels
    }

    @Test func writesFramesThatImageIOReadsBack() throws {
        let url = TestMovie.folder().appending(path: "frames.gif")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let writer = GIFWriter(width: 64, height: 40, sink: .file(try FileHandle(forWritingTo: url)))
        let times = [0.0, 0.1, 0.2, 0.3]
        var added = 0
        for (index, time) in times.enumerated() {
            // Frame 2 repeats frame 1: it only makes frame 1 last longer.
            var pixels = Self.frame(width: 64, height: 40, block: index == 2 ? 10 : index * 10, colour: 0xFF6A_64F0)
            let kept = try pixels.withUnsafeMutableBytes { try writer.add(bgra: $0.baseAddress!, bytesPerRow: 64 * 4, at: time) }
            if kept { added += 1 }
        }
        try writer.finish(at: 0.4)
        #expect(added == 3)
        #expect(writer.delays == [10, 20, 10])

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 3)
        var total = 0.0
        for index in 0..<3 {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        }
        #expect(abs(total - 0.4) < 0.001)
        // The last frame, composed over the ones before, has the block where it should be.
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 2, nil))
        #expect(image.width == 64 && image.height == 40)
        let pixel = Self.colour(of: image, x: 35, y: 20)
        #expect(abs(Int(pixel.r) - 0x6A) <= 2 && abs(Int(pixel.b) - 0xF0) <= 2)
        let background = Self.colour(of: image, x: 2, y: 2)
        #expect(abs(Int(background.r) - 0xEE) <= 2)
    }

    @Test func delaysNeverDriftOrRunShort() throws {
        let writer = GIFWriter(width: 8, height: 8, sink: .count)
        var pixels = [UInt32](repeating: 0, count: 64)
        for frame in 0..<15 {
            pixels[0] = UInt32(frame * 16)
            try pixels.withUnsafeMutableBytes { _ = try writer.add(bgra: $0.baseAddress!, bytesPerRow: 32, at: Double(frame) / 15) }
        }
        try writer.finish(at: 1)
        #expect(writer.delays.count == 15)
        #expect(writer.delays.reduce(0, +) == 100)
        #expect(writer.delays.allSatisfy { $0 == 6 || $0 == 7 })
        #expect(writer.byteCount > 0)
    }

    @Test func manyColoursGetAMedianCutPalette() throws {
        let width = 96, height = 64
        var pixels = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let r = UInt32(x * 255 / width), g = UInt32(y * 255 / height), b = UInt32((x + y) % 256)
                pixels[y * width + x] = 0xFF00_0000 | r << 16 | g << 8 | b
            }
        }
        let url = TestMovie.folder().appending(path: "gradient.gif")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let writer = GIFWriter(width: width, height: height, sink: .file(try FileHandle(forWritingTo: url)))
        try pixels.withUnsafeMutableBytes { _ = try writer.add(bgra: $0.baseAddress!, bytesPerRow: width * 4, at: 0) }
        try writer.finish(at: 1)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let corner = Self.colour(of: image, x: width - 2, y: 2)
        // Close to the original colour, within the palette's reach.
        #expect(abs(Int(corner.r) - (width - 2) * 255 / width) < 24)
    }

    static func colour(of image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[1], data[2])
    }
}

// MARK: Movies

struct VideoMovieTests {
    @Test func readsTheMovieAndNamesItsTracks() async throws {
        let url = TestMovie.folder().appending(path: "named.mov")
        try TestMovie.make(at: url, seconds: 1, audioTracks: ["Computer", "Mic"])
        let info = try await MovieInfo.load(url)
        #expect(info.size == CGSize(width: 320, height: 200))
        #expect(abs(VideoEdit.seconds(info.duration) - 1) < 0.05)
        #expect(info.audioTracks.map(\.name) == ["Computer", "Mic"])
        #expect(abs(info.frameRate - 30) < 1)
        #expect(info.format == .mov)
    }

    @Test func gifMergesStillFramesAndKeepsTime() async throws {
        let folder = TestMovie.folder()
        let movie = folder.appending(path: "moving.mov")
        // One second moving, one second still.
        try TestMovie.make(at: movie, seconds: 2, moving: 1)
        let gif = folder.appending(path: "moving.gif")
        let result = try await GIFMaker.make(from: movie, options: GIFMaker.Options(width: 160, fps: 10), to: gif)
        #expect(result.pixelSize == CGSize(width: 160, height: 100))
        // About 10 moving frames, and the still second as one long frame.
        #expect(result.frameCount >= 9 && result.frameCount <= 12)
        #expect(abs(result.duration - 2) < 0.06)
        // The encoder settles a frame or two after the motion stops; then one long frame.
        #expect(result.delays.last ?? 0 >= 0.7, "delays: \(result.delays)")

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == result.frameCount)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 160 && first.height == 100)
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let loop = (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
        #expect(loop == 0)
    }

    @Test func gifOfARange() async throws {
        let folder = TestMovie.folder()
        let movie = folder.appending(path: "range.mov")
        try TestMovie.make(at: movie, seconds: 2, moving: 2)
        let gif = folder.appending(path: "range.gif")
        let result = try await GIFMaker.make(from: movie, range: 0.5...1.5, options: GIFMaker.Options(width: 800, fps: 10), to: gif)
        // Never wider than the movie.
        #expect(result.pixelSize.width == 320)
        #expect(abs(result.duration - 1) < 0.06)
    }

    @Test func gifEstimateIsInTheRightPlace() async throws {
        let folder = TestMovie.folder()
        let movie = folder.appending(path: "estimate.mov")
        try TestMovie.make(at: movie, seconds: 2, moving: 1)
        let info = try await MovieInfo.load(movie)
        let edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size)
        let options = GIFMaker.Options(width: 320, fps: 15)
        let estimate = try #require(await GIFMaker.estimate(info, edit: edit, options: options))
        let made = try await GIFMaker.make(info, edit: edit, options: options, to: folder.appending(path: "estimate.gif"))
        #expect(Double(estimate) > Double(made.byteCount) * 0.4)
        #expect(Double(estimate) < Double(made.byteCount) * 2.5)
    }

    @Test func exportsATrimmedCutMovie() async throws {
        let folder = TestMovie.folder()
        let movie = folder.appending(path: "source.mov")
        try TestMovie.make(at: movie, seconds: 3, moving: 3, audioTracks: ["Computer", "Mic"])
        let info = try await MovieInfo.load(movie)
        var edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size, audioTracks: 2)
        // Keep 0.5–1.0 and 2.0–2.5: one second in all.
        edit.trimStart(edit.clips[0].id, to: 300)
        let middleID = edit.split(at: 300)
        let tailID = edit.split(at: VideoEdit.ticks(seconds: 1.5))
        let middle = try #require(middleID)
        let tail = try #require(tailID)
        edit.remove(middle)
        edit.trimEnd(tail, to: VideoEdit.ticks(seconds: 2.5))
        edit.levels[1].muted = true
        edit.crop = CGRect(x: 0, y: 0, width: 160, height: 100)
        edit.export.format = .mp4
        #expect(abs(VideoEdit.seconds(edit.duration) - 1) < 0.001)

        let out = folder.appending(path: "out.mp4")
        let result = try await VideoExporter.export(info, edit: edit, to: out)
        #expect(result.pixelSize == CGSize(width: 160, height: 100))
        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.1)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await video.load(.naturalSize)
        #expect(size == CGSize(width: 160, height: 100))
        // The muted mic is left out; the computer's sound is mixed in.
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(result.byteCount > 0)
    }

    @Test func compositionLeavesOutMutedTracksExceptForPreview() async throws {
        let folder = TestMovie.folder()
        let movie = folder.appending(path: "tracks.mov")
        try TestMovie.make(at: movie, seconds: 1, audioTracks: ["Computer", "Mic"])
        let info = try await MovieInfo.load(movie)
        var edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size, audioTracks: 2)
        edit.levels[0].muted = true
        let asset = AVURLAsset(url: movie)
        let export = try await VideoComposer.build(asset, info: info, edit: edit, output: VideoComposer.Output())
        #expect(export.audioTrackIDs.keys.sorted() == [1])
        #expect(export.videoComposition == nil)
        let preview = try await VideoComposer.build(asset, info: info, edit: edit, output: .preview)
        #expect(preview.audioTrackIDs.keys.sorted() == [0, 1])
        #expect(preview.audioMix != nil)
    }

    @Test func gifExportThroughTheExporter() async throws {
        let folder = TestMovie.folder()
        let movie = folder.appending(path: "export.mov")
        try TestMovie.make(at: movie, seconds: 1)
        let info = try await MovieInfo.load(movie)
        var edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size)
        edit.export.format = .gif
        edit.export.gifWidth = 480
        edit.export.gifFPS = 10
        let out = folder.appending(path: "export.gif")
        let result = try await VideoExporter.export(info, edit: edit, to: out)
        #expect(result.pixelSize == CGSize(width: 320, height: 200))
        let source = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetCount(source) >= 2)
    }

    @Test func cancellingStopsTheExport() async throws {
        let folder = TestMovie.folder()
        let movie = folder.appending(path: "cancel.mov")
        try TestMovie.make(at: movie, seconds: 2)
        let info = try await MovieInfo.load(movie)
        let edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size)
        let out = folder.appending(path: "cancel.mp4")
        let task = Task { try await VideoExporter.export(info, edit: edit, to: out) }
        task.cancel()
        let result = await task.result
        if case .success = result {
            // Finished before the cancel landed: fine, as long as the file is whole.
            #expect(FileManager.default.fileExists(atPath: out.path))
        } else {
            #expect(!FileManager.default.fileExists(atPath: out.path))
        }
    }
}

// MARK: Model

@MainActor
struct VideoEditorModelTests {
    static func model(seconds: Double = 10) -> VideoEditorModel {
        let info = MovieInfo(url: URL(fileURLWithPath: "/tmp/none.mov"), duration: VideoEdit.ticks(seconds: seconds),
                             size: CGSize(width: 1280, height: 800), frameRate: 30, videoDataRate: 1_000_000,
                             audioTracks: [.init(trackID: 2, name: "Computer"), .init(trackID: 3, name: "Mic")], hasVideo: true)
        return VideoEditorModel(info: info, scale: 2, edit: nil)
    }

    @Test func splitDeleteUndoRedo() {
        let model = Self.model()
        model.seek(to: 1_800)
        model.split()
        #expect(model.edit.clips.count == 2)
        #expect(model.selection == model.edit.clips[1].id)
        model.seek(to: 3_600)
        model.split()
        #expect(model.edit.clips.count == 3)
        // Select the middle and delete it.
        model.selection = model.edit.clips[1].id
        model.deleteSelection()
        #expect(model.edit.clips.count == 2)
        #expect(model.duration == 6_000 - 1_800)
        #expect(model.isEdited)
        model.undo()
        #expect(model.edit.clips.count == 3)
        model.undo()
        model.undo()
        #expect(model.edit.clips.count == 1)
        #expect(!model.isEdited)
        model.redo()
        #expect(model.edit.clips.count == 2)
    }

    @Test func trimToThePlayhead() {
        let model = Self.model()
        model.seek(to: 600)
        model.trimStartToPlayhead()
        #expect(model.edit.clips[0].start == 600)
        #expect(model.playhead == 0)
        model.seek(to: 3_000)
        model.trimEndToPlayhead()
        #expect(model.edit.clips[0].end == 3_600)
    }

    @Test func exportChoicesAreNotEdits() {
        let model = Self.model()
        model.setExport { $0.format = .gif }
        #expect(model.edit.export.format == .gif)
        #expect(!model.isEdited)
        #expect(!model.canUndo)
    }

    @Test func aVolumeDragIsOneUndoStep() {
        let model = Self.model()
        for volume in [1.0, 0.8, 0.5, 0.2] { model.setVolumeLive(volume, track: 1) }
        model.endLiveChange("Change Volume")
        #expect(abs(model.edit.levels[1].volume - 0.2) < 0.001)
        model.undo()
        #expect(model.edit.levels[1].volume == 1)
    }

    @Test func cropShapesKeepTheirRatio() {
        let model = Self.model()
        model.beginCrop()
        model.setCropShape(.square)
        let draft = try? #require(model.cropDraft)
        #expect(draft?.width == draft?.height)
        model.applyCrop()
        #expect(model.edit.crop?.width == 800)
        #expect(model.outputSize == CGSize(width: 800, height: 800))
        model.undo()
        #expect(model.edit.crop == nil)
    }

    @Test func passthroughFileNames() {
        #expect(VideoEditor.fileName("Screen Recording 2026-10-23 at 14:32:07", format: .mp4)
            == "Screen Recording 2026-10-23 at 14.32.07.mp4")
        #expect(VideoEditor.fileName("  ", format: .gif) == "Video.gif")
    }
}

import AppKit
import ScreenCaptureKit

/// What to record.
enum RecordingTarget: Sendable {
    /// A whole display, or an area of it in AppKit screen points.
    case display(CGDirectDisplayID, frame: CGRect, scale: CGFloat, area: CGRect?)
    /// One window, wherever it goes.
    case window(CGWindowID)
}

/// The live side of a recording: a ScreenCaptureKit stream feeding a `RecordingWriter`.
/// Barn Owl's own windows (the controls, the border, cards) are never in it, nor what a clean
/// menu bar leaves out of screenshots. Stopping or cancelling at any moment, even while it's
/// still starting, ends the stream and lets go of the microphone.
@MainActor
final class ScreenRecorder {
    struct Request {
        var target: RecordingTarget
        var options: RecordingOptions
        /// What to leave out besides Barn Owl, as for screenshots.
        var leftOut: CaptureOptions
        /// "Save Retina captures at their on-screen size".
        var atOneX: Bool
        var url: URL
    }

    enum Failure: LocalizedError {
        case noDisplay, noWindow, noFirstFrame, cancelled

        var errorDescription: String? {
            switch self {
            case .noDisplay: "That display isn't there any more."
            case .noWindow: "That window isn't there any more."
            case .noFirstFrame: "The screen didn't start recording."
            case .cancelled: "Cancelled."
            }
        }
    }

    let request: Request
    /// The stream stopped by itself: a display changed, the Mac slept, the window closed.
    var onStopped: ((Error) -> Void)?
    /// The microphone's level, about ten times a second.
    var onLevel: ((Float) -> Void)?
    /// The size being recorded, in pixels.
    private(set) var pixelSize: (width: Int, height: Int) = (0, 0)
    private var stream: SCStream?
    private var sink: RecordingSink?
    private var starting = false
    private var cancelled = false
    private var refresher: Task<Void, Never>?
    /// Barn Owl's own windows when the filter was made; a new one means a new filter.
    private var ownWindows: Set<Int> = []

    init(request: Request) {
        self.request = request
    }

    static var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    func start() async throws {
        starting = true
        defer { starting = false }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try await stopIfCancelled()
        let (filter, size, area) = try filter(from: content)
        pixelSize = size
        let options = request.options
        let settings = RecordingWriter.Settings(
            width: size.width, height: size.height, frameRate: options.frameRate, codec: options.codec,
            bitRate: RecordingGeometry.bitRate(width: size.width, height: size.height, frameRate: options.frameRate,
                                               quality: options.quality, codec: options.codec),
            systemAudio: options.systemAudio, microphone: options.microphoneID != nil)
        let writer = try RecordingWriter(url: request.url, settings: settings)
        let sink = RecordingSink(writer: writer, onStop: { [weak self] error in
            Task { @MainActor in self?.onStopped?(error) }
        }, onLevel: { [weak self] level in
            Task { @MainActor in self?.onLevel?(level) }
        })
        let stream = SCStream(filter: filter, configuration: configuration(size: size, area: area), delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        if options.systemAudio { try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue) }
        if options.microphoneID != nil { try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue) }
        self.stream = stream
        self.sink = sink
        try await stream.startCapture()
        try await stopIfCancelled()
        // A still screen sends one frame at the start, then nothing until it changes.
        guard await sink.firstFrame(within: 2) else {
            await tearDown()
            throw Failure.noFirstFrame
        }
        try await stopIfCancelled()
        if case .display = request.target { keepFilterCurrent() }
    }

    func pause() { sink?.pause(at: Self.now) }
    func resume() { sink?.resume(at: Self.now) }

    /// Finishes the file at this moment and ends the stream.
    func stop() async throws -> RecordingWriter.Output {
        let now = Self.now
        refresher?.cancel()
        guard let sink else { throw Failure.noFirstFrame }
        // The file first: frames that arrive after this moment aren't wanted.
        let output: RecordingWriter.Output
        do {
            output = try await sink.finish(at: now)
        } catch {
            await endStream()
            throw error
        }
        await endStream()
        return output
    }

    /// Ends the stream and lets the file go. While still starting, `start()` does it at its next step.
    func cancel() async {
        cancelled = true
        guard !starting else { return }
        await tearDown()
    }

    private func stopIfCancelled() async throws {
        guard cancelled else { return }
        await tearDown()
        throw Failure.cancelled
    }

    private func tearDown() async {
        refresher?.cancel()
        sink?.cancel()
        await endStream()
    }

    private func endStream() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    // MARK: Filter and configuration

    private func filter(from content: SCShareableContent) throws -> (SCContentFilter, (width: Int, height: Int), CGRect?) {
        let codec = request.options.codec
        switch request.target {
        case .display(let id, let frame, let scale, let area):
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw Failure.noDisplay }
            let filter = SCContentFilter(display: display, excludingWindows: excluded(in: content))
            let points = area?.size ?? frame.size
            let size = RecordingGeometry.pixelSize(points: points, scale: request.atOneX ? 1 : scale, codec: codec)
            return (filter, size, area.map { RecordingGeometry.sourceRect(for: $0, on: frame) })
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else { throw Failure.noWindow }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let info = SCShareableContent.info(for: filter)
            let scale = request.atOneX ? 1 : CGFloat(info.pointPixelScale)
            let size = RecordingGeometry.pixelSize(points: info.contentRect.size, scale: scale, codec: codec)
            return (filter, size, nil)
        }
    }

    /// Barn Owl's own windows, apart from its desktop cover and pins, and whatever a clean
    /// menu bar or hidden desktop icons leave out of screenshots.
    private func excluded(in content: SCShareableContent) -> [SCWindow] {
        ownWindows = Self.ownWindowNumbers()
        return content.windows.filter { ScreenSnapshotter.leftOut($0, options: request.leftOut) }
    }

    private static func ownWindowNumbers() -> Set<Int> {
        Set(NSApp.windows.filter { $0.windowNumber > 0 }.map(\.windowNumber))
    }

    private func configuration(size: (width: Int, height: Int), area: CGRect?) -> SCStreamConfiguration {
        let options = request.options
        let config = SCStreamConfiguration()
        config.width = size.width
        config.height = size.height
        if let area { config.sourceRect = area }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        config.queueDepth = 6
        // Clicks only show with BGRA.
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.captureResolution = request.atOneX ? .nominal : .best
        config.showsCursor = options.showsPointer
        config.showMouseClicks = options.showsClicks
        if case .window = request.target {
            config.ignoreShadowsSingleWindow = true
            config.preservesAspectRatio = true
            config.includeChildWindows = true
        }
        if options.systemAudio {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            // Barn Owl's own sounds (the countdown, the stop) stay out of the file.
            config.excludesCurrentProcessAudio = true
        }
        if let microphone = options.microphoneID {
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = microphone
        }
        return config
    }

    /// Keeps Barn Owl's windows out as they come and go: a card, a menu, a panel.
    private func keepFilterCurrent() {
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard Self.ownWindowNumbers() != self.ownWindows else { continue }
                await self.refreshFilter()
            }
        }
    }

    private func refreshFilter() async {
        guard let stream, case .display(let id, _, _, _) = request.target,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first(where: { $0.displayID == id }) else { return }
        let filter = SCContentFilter(display: display, excludingWindows: excluded(in: content))
        try? await stream.updateContentFilter(filter)
    }
}

/// Takes ScreenCaptureKit's samples on its own queue and hands them straight to the writer.
private final class RecordingSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "io.github.marvika.BarnOwl.recording", qos: .userInteractive)
    /// Only touched on `queue`.
    private let writer: RecordingWriter
    private var sawFrame = false
    private var waiting: CheckedContinuation<Bool, Never>?
    private var lastLevel = 0.0
    private let onStop: @Sendable (Error) -> Void
    private let onLevel: @Sendable (Float) -> Void

    init(writer: RecordingWriter, onStop: @escaping @Sendable (Error) -> Void, onLevel: @escaping @Sendable (Float) -> Void) {
        self.writer = writer
        self.onStop = onStop
        self.onLevel = onLevel
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            // Idle frames carry no picture: only complete ones are written.
            guard Self.isComplete(sample) else { return }
            writer.appendVideo(sample)
            if !sawFrame {
                sawFrame = true
                waiting?.resume(returning: true)
                waiting = nil
            }
        case .audio:
            writer.appendAudio(sample, from: .system)
        case .microphone:
            writer.appendAudio(sample, from: .microphone)
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastLevel > 0.1 {
                lastLevel = now
                onLevel(AudioLevel.rms(of: sample))
            }
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop(error)
    }

    static func isComplete(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    /// Waits for the first frame, up to `seconds`.
    func firstFrame(within seconds: Double) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.sawFrame { return continuation.resume(returning: true) }
                self.waiting = continuation
                self.queue.asyncAfter(deadline: .now() + seconds) {
                    guard let waiting = self.waiting else { return }
                    self.waiting = nil
                    waiting.resume(returning: false)
                }
            }
        }
    }

    func pause(at time: CMTime) { queue.async { self.writer.pause(at: time) } }
    func resume(at time: CMTime) { queue.async { self.writer.resume(at: time) } }
    func cancel() { queue.async { self.writer.cancel() } }

    func finish(at time: CMTime) async throws -> RecordingWriter.Output {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.writer.finish(at: time) { result in continuation.resume(with: result) }
            }
        }
    }
}

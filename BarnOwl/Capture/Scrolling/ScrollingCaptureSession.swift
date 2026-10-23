import AppKit
import ScreenCaptureKit

/// A scrolling capture of one area. You scroll, or Barn Owl scrolls for you,
/// and the frames become one tall picture. A small glass HUD beside the area
/// shows how tall it is so far; it never takes the keyboard or the scrolling
/// from the app you're in, and Barn Owl's own windows are never in the frames.
///
/// ```
/// let session = ScrollingCaptureSession(rect: rect, display: snapshot.displayID)
/// if let shot = await session.run() { deliver(shot.image, scale: shot.scale) }
/// ```
@MainActor
final class ScrollingCaptureSession {
    /// The tallest picture, in pixels.
    nonisolated static let maxHeight = 30_000

    /// The area, in AppKit screen coordinates.
    let rect: CGRect
    let displayID: CGDirectDisplayID
    /// Starts scrolling by itself as soon as the capture begins.
    var autoScrollsAtStart = false
    /// Why it ended without a picture, when it couldn't start.
    private(set) var failure: String?
    /// Whether it's capturing now: from `run()` until Done or Cancel.
    private(set) var isRunning = false

    private let model = ScrollingHUDModel()
    private var area: CGRect = .zero
    private var scale: CGFloat = 2
    private var stream: SCStream?
    private var output: ScrollStreamOutput?
    private var engine: ScrollStitchEngine?
    private var consumer: Task<Void, Never>?
    private var autoScroller: Task<Void, Never>?
    private var hud: ScrollingHUDPanel?
    private var border: ScrollingBorderPanel?
    private var keys: CaptureKeyTap?
    private var observers: [NSObjectProtocol] = []
    private var waiter: CheckedContinuation<Bool, Never>?
    /// Done (true) or Cancel (false), once chosen.
    private var decision: Bool?
    private var started = false
    private var lastUpdate = ContinuousClock.now
    private var frames = 0
    private var lastOutcome = ScrollStitcher.Outcome.started
    private var bandHeight = 0

    /// `rect` in AppKit screen coordinates (as `SelectionOverlay`'s area), on `display`.
    init(rect: CGRect, display: CGDirectDisplayID) {
        self.rect = rect
        displayID = display
    }

    /// Captures until Done or Cancel: the picture and its scale, or nil if
    /// cancelled or it couldn't start (see `failure`).
    func run() async -> (image: CGImage, scale: CGFloat)? {
        guard !started else { return nil }
        started = true
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            failure = "That display is gone"
            return nil
        }
        scale = screen.backingScaleFactor
        area = Self.pixelAligned(rect.intersection(screen.frame), scale: scale)
        guard area.width >= 16, area.height >= 16 else {
            failure = "That area is too small to scroll"
            return nil
        }
        isRunning = true
        defer { isRunning = false }
        // The HUD goes up first, so it's among the windows the stream leaves out.
        showPanels(on: screen)
        do {
            try await startStream(on: screen)
        } catch {
            failure = "Barn Owl couldn't watch that area"
            await tearDown()
            return nil
        }
        keys = CaptureKeyTap { [weak self] key in
            switch key {
            case .done: self?.finish()
            case .cancel: self?.cancel()
            }
        }
        observe()
        focusAppUnderArea()
        if autoScrollsAtStart { toggleAutoScroll() }
        let keep = await decided()
        await tearDown()
        guard keep, let engine, let image = await engine.picture() else { return nil }
        return (image, scale)
    }

    /// Done: keeps what's stitched so far. Pressing the shortcut again does this.
    func finish() { decide(true) }

    /// Cancel: nothing is kept.
    func cancel() { decide(false) }

    /// Starts or stops scrolling for you.
    func toggleAutoScroll() {
        if let autoScroller {
            autoScroller.cancel()
            return
        }
        guard decision == nil, isRunning, !model.isFull else { return }
        guard AXIsProcessTrusted() else {
            model.hint = .needsAccess
            return
        }
        autoScroller = Task { [weak self] in
            await self?.scrollForYou()
        }
    }

    private func decide(_ keep: Bool) {
        guard decision == nil else { return }
        decision = keep
        autoScroller?.cancel()
        waiter?.resume(returning: keep)
        waiter = nil
    }

    private func decided() async -> Bool {
        if let decision { return decision }
        return await withCheckedContinuation { waiter = $0 }
    }

    // MARK: Frames

    private func startStream(on screen: NSScreen) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CocoaError(.featureUnsupported)
        }
        let config = SCStreamConfiguration()
        config.sourceRect = Self.sourceRect(for: area, on: screen.frame)
        config.width = Int((area.width * scale).rounded())
        config.height = Int((area.height * scale).rounded())
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5

        var stitching = ScrollStitcher.Configuration()
        stitching.maxHeight = Self.maxHeight
        // Overlay scroll bars are about 16 points wide, with their margin.
        stitching.ignoredTrailingColumns = Int(16 * scale)
        let engine = ScrollStitchEngine(configuration: stitching)
        let (frames, continuation) = AsyncStream.makeStream(of: ScrollFrame.self, bufferingPolicy: .bufferingNewest(1))
        let output = ScrollStreamOutput(frames: continuation) { [weak self] in
            Task { @MainActor in self?.finish() }
        }
        let stream = SCStream(filter: Self.filter(content, display: display), configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "Barn Owl scrolling capture"))
        self.engine = engine
        self.output = output
        self.stream = stream
        consumer = Task { [weak self] in
            for await frame in frames {
                let update = await engine.add(frame)
                self?.apply(update)
            }
        }
        try await stream.startCapture()
    }

    /// Everything but Barn Owl, which keeps only its desktop cover, as screenshots do.
    /// Pinned captures stay out: floating over the page, they'd break the stitching.
    private static func filter(_ content: SCShareableContent, display: SCDisplay) -> SCContentFilter {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = content.applications.filter { $0.processID == own }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == own }
        let cover = ownWindows.filter { $0.title == "BarnOwlDesktopCover" }
        if apps.isEmpty {
            let excluded = ownWindows.filter { $0.title != "BarnOwlDesktopCover" }
            return SCContentFilter(display: display, excludingWindows: excluded)
        }
        return SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: cover)
    }

    private func apply(_ update: ScrollStitchUpdate) {
        lastUpdate = .now
        frames += 1
        lastOutcome = update.outcome
        bandHeight = update.bandHeight
        // Presenter mode mustn't take Barn Owl's own stream for a screen share.
        OwnCaptures.last = Date()
        model.height = update.height
        if let preview = update.preview { model.preview = preview }
        model.isFull = update.isFull
        if update.isFull {
            model.hint = .limit
            autoScroller?.cancel()
            return
        }
        switch update.outcome {
        case .mismatch:
            model.hint = .slower
        case .placed:
            if autoScroller != nil {
                model.hint = .auto
            } else {
                model.hint = update.isAtEnd ? .ready : .above
            }
        case .started, .unchanged:
            break
        }
    }

    // MARK: Scrolling for you

    private func scrollForYou() async {
        model.isAutoScrolling = true
        model.hint = .auto
        defer {
            autoScroller = nil
            model.isAutoScrolling = false
        }
        // The picture starts with the first frame: wait for it before moving the page.
        let start = ContinuousClock.now
        while frames == 0, !Task.isCancelled, ContinuousClock.now - start < .seconds(2) {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard frames > 0, !Task.isCancelled else { return }
        // Scroll events go to the window under the pointer.
        let anchor = CGPoint(x: area.midX, y: area.midY)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: anchor.x, y: top - anchor.y)
        CGWarpMouseCursorPosition(point)
        var stalls = 0
        var share = 0.6
        while !Task.isCancelled, decision == nil, !model.isFull {
            let before = model.height
            let rows = bandHeight > 0 ? bandHeight : Int(area.height * scale)
            await scroll(by: CGFloat(rows) / scale * share, at: point)
            await settle()
            if Task.isCancelled || decision != nil { return }
            // You moved the pointer: you're taking over.
            if hypot(NSEvent.mouseLocation.x - anchor.x, NSEvent.mouseLocation.y - anchor.y) > 4 {
                model.hint = .ready
                return
            }
            if lastOutcome == .mismatch { share = max(0.2, share / 2) }
            stalls = model.height > before ? 0 : stalls + 1
            if stalls >= 2 {
                model.hint = .end
                return
            }
        }
    }

    /// A smooth step: a few small, continuous scroll events, like a trackpad's.
    private func scroll(by points: CGFloat, at point: CGPoint) async {
        let pieces = 8
        let delta = Int32((points / CGFloat(pieces)).rounded())
        for _ in 0..<pieces {
            guard !Task.isCancelled else { return }
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                   wheel1: -delta, wheel2: 0, wheel3: 0) {
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.location = point
                event.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Waits until frames stop coming: the page has stopped moving.
    private func settle() async {
        let start = ContinuousClock.now
        try? await Task.sleep(for: .milliseconds(120))
        while !Task.isCancelled, ContinuousClock.now - lastUpdate < .milliseconds(160),
              ContinuousClock.now - start < .milliseconds(1200) {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    // MARK: Around the capture

    private func showPanels(on screen: NSScreen) {
        model.canAutoScroll = AXIsProcessTrusted()
        model.height = Int((area.height * scale).rounded())
        let border = ScrollingBorderPanel(around: area)
        let hud = ScrollingHUDPanel(model: model, autoScroll: { [weak self] in self?.toggleAutoScroll() },
                                    done: { [weak self] in self?.finish() },
                                    cancel: { [weak self] in self?.cancel() })
        hud.place(beside: area, within: screen.visibleFrame)
        border.show()
        hud.show()
        self.border = border
        self.hud = hud
    }

    private func observe() {
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        // The area means something else after a display change or sleep: keep what's there.
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            },
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            },
        ]
    }

    /// The overlay made Barn Owl active; give the keys back to the app being scrolled,
    /// so arrow keys and Space scroll it too.
    private func focusAppUnderArea() {
        guard NSApp.isActive,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: area.midX, y: top - area.midY)
        let own = ProcessInfo.processInfo.processIdentifier
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point) else { continue }
            NSRunningApplication(processIdentifier: pid)?.activate()
            return
        }
    }

    private func tearDown() async {
        autoScroller?.cancel()
        keys?.stop()
        keys = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers = []
        hud?.dismiss()
        border?.dismiss()
        hud = nil
        border = nil
        if let stream { try? await stream.stopCapture() }
        stream = nil
        output?.frames.finish()
        await consumer?.value
        consumer = nil
        OwnCaptures.last = Date()
    }

    // MARK: Geometry

    /// The area in the display's own points from its top left, as ScreenCaptureKit wants it.
    static func sourceRect(for area: CGRect, on screenFrame: CGRect) -> CGRect {
        CGRect(x: area.minX - screenFrame.minX, y: screenFrame.maxY - area.maxY, width: area.width, height: area.height)
    }

    /// Snapped to whole pixels, so frames are exactly the area.
    static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// What the HUD needs after each frame.
struct ScrollStitchUpdate: Sendable {
    let outcome: ScrollStitcher.Outcome
    let height: Int
    let bandHeight: Int
    let isFull: Bool
    /// The frame reaches the end of the picture, rather than somewhere above it.
    let isAtEnd: Bool
    let preview: CGImage?
}

/// Stitches off the main thread, one frame at a time.
actor ScrollStitchEngine {
    private let stitcher: ScrollStitcher

    init(configuration: ScrollStitcher.Configuration) {
        stitcher = ScrollStitcher(configuration: configuration,
                                  colorSpace: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB())
    }

    func add(_ frame: ScrollFrame) -> ScrollStitchUpdate {
        let outcome = stitcher.add(frame)
        var grew = outcome == .started
        if case .placed(_, let added) = outcome, added > 0 { grew = true }
        let atEnd = !stitcher.hasMoved || stitcher.offset + stitcher.bandHeight >= stitcher.height - stitcher.header - stitcher.footer
        // The HUD's strip is 30 × 44 points; twice that for Retina.
        let preview = grew ? stitcher.preview(width: 60, height: 88) : nil
        return ScrollStitchUpdate(outcome: outcome, height: stitcher.height, bandHeight: stitcher.bandHeight,
                                  isFull: stitcher.isFull, isAtEnd: atEnd, preview: preview)
    }

    func picture() -> CGImage? { stitcher.image() }
}

/// Copies each new frame out of ScreenCaptureKit's buffer and passes it on.
private final class ScrollStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, Sendable {
    let frames: AsyncStream<ScrollFrame>.Continuation
    private let stopped: @Sendable () -> Void

    init(frames: AsyncStream<ScrollFrame>.Continuation, stopped: @escaping @Sendable () -> Void) {
        self.frames = frames
        self.stopped = stopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        // Copied at once: ScreenCaptureKit reuses its buffers.
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let frame = ScrollFrame(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), copying: base)
        frames.yield(frame)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        stopped()
    }
}

/// Return and Esc while a capture runs, caught before the app you're scrolling
/// sees them. Needs Accessibility, which Barn Owl has for the menu bar.
@MainActor
final class CaptureKeyTap {
    enum Key { case done, cancel }

    private let handler: (Key) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose press was caught, so their release is too.
    private var caught: Set<Int64> = []

    init?(handler: @escaping (Key) -> Void) {
        guard AXIsProcessTrusted() else { return nil }
        self.handler = handler
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let plain = event.flags.intersection(modifiers).isEmpty
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let swallow = MainActor.assumeIsolated {
                Unmanaged<CaptureKeyTap>.fromOpaque(info).takeUnretainedValue()
                    .handle(type, code: code, plain: plain, repeated: repeated)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return nil }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// True to keep the event from the app.
    fileprivate func handle(_ type: CGEventType, code: Int64, plain: Bool, repeated: Bool) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let key: Key
        switch code {
        case 36, 76: key = .done      // Return, Enter
        case 53: key = .cancel        // Esc
        default: return false
        }
        if type == .keyUp { return caught.remove(code) != nil }
        guard type == .keyDown, plain else { return false }
        caught.insert(code)
        if !repeated {
            // After the event has been dealt with: finishing removes this tap.
            Task { @MainActor [weak self] in self?.handler(key) }
        }
        return true
    }
}

import AppKit
import AVFoundation

/// Where the movie plays: the picture fitted on the editor's backdrop, with a hairline and a
/// soft shadow like a capture on the screenshot canvas. A still stands in until the player's
/// first frame is ready, and while a clip's edge is dragged. While cropping, the whole picture
/// shows with the crop over it.
@MainActor
final class VideoStageView: NSView {
    let model: VideoEditorModel
    let playerLayer: AVPlayerLayer
    private let frameLayer = CALayer()
    private let stillLayer = CALayer()
    private let crop: CropOverlayView
    private var readyObservation: NSKeyValueObservation?
    private var stillTask: Task<Void, Never>?
    private var stillTime: Int64?
    /// Keys go to the editor.
    var onKey: ((NSEvent) -> Bool)?
    /// Room around the picture.
    static let padding: CGFloat = 28

    init(model: VideoEditorModel) {
        self.model = model
        playerLayer = AVPlayerLayer(player: model.playback.player)
        crop = CropOverlayView(model: model)
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        wantsLayer = true
        layer?.masksToBounds = true
        frameLayer.masksToBounds = false
        frameLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        frameLayer.shadowOffset = CGSize(width: 0, height: -2)
        frameLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer?.addSublayer(frameLayer)
        playerLayer.videoGravity = .resize
        layer?.addSublayer(playerLayer)
        stillLayer.contentsGravity = .resize
        stillLayer.isHidden = true
        layer?.addSublayer(stillLayer)
        crop.frame = bounds
        crop.autoresizingMask = [.width, .height]
        addSubview(crop)
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            MainActor.assumeIsolated {
                guard ready, let self, self.stillTime == nil else { return }
                self.stillLayer.isHidden = true
            }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Video")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The picture's size as shown: the crop's, or the whole picture while cropping.
    var shownSize: CGSize { model.isCropping ? model.info.size : model.outputSize }

    /// Where the picture sits, fitted inside the padding.
    var pictureRect: CGRect {
        let size = shownSize
        var room = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        // Room under the picture for the crop bar.
        if model.isCropping {
            room.origin.y += 40
            room.size.height -= 40
        }
        guard size.width > 0, size.height > 0, room.width > 0, room.height > 0 else { return .zero }
        let scale = min(room.width / size.width, room.height / size.height)
        let width = (size.width * scale).rounded()
        let height = (size.height * scale).rounded()
        return CGRect(x: (bounds.midX - width / 2).rounded(), y: (bounds.midY - height / 2).rounded(), width: width,
                      height: height)
    }

    override func layout() {
        super.layout()
        relayout()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        relayout()
    }

    func relayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = pictureRect
        frameLayer.frame = rect
        playerLayer.frame = rect
        stillLayer.frame = rect
        frameLayer.shadowPath = CGPath(rect: frameLayer.bounds, transform: nil)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        frameLayer.shadowOpacity = dark ? 0.45 : 0.18
        frameLayer.shadowRadius = dark ? 16 : 12
        frameLayer.borderWidth = dark ? 1 / max(window?.backingScaleFactor ?? 2, 1) : 0.5
        effectiveAppearance.performAsCurrentDrawingAppearance {
            frameLayer.borderColor = dark ? CGColor(gray: 1, alpha: 0.18) : NSColor.separatorColor.cgColor
        }
        CATransaction.commit()
        crop.needsDisplay = true
    }

    /// A still in place of the player: before its first frame, or while trimming.
    func showStill(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stillLayer.contents = image
        stillLayer.isHidden = image == nil
        CATransaction.commit()
    }

    /// While an edge is dragged: the movie's frame at `time` (movie ticks), or nil to go back.
    func previewSource(_ time: Int64?) {
        stillTime = time
        stillTask?.cancel()
        guard let time else {
            showStill(nil)
            return
        }
        let info = model.info
        let crop = model.edit.crop
        let size = CGSize(width: pictureRect.width * 2, height: pictureRect.height * 2)
        stillTask = Task { [weak self] in
            // Close enough while dragging; exact when the drag pauses.
            guard let image = await VideoMedia.frame(info.url, at: time, maximumSize: size) else { return }
            guard !Task.isCancelled, let self, self.stillTime == time else { return }
            let shown = VideoTimelineView.cropped(image, crop: crop, sourceSize: info.size) ?? image
            self.showStill(shown)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // A click on the picture plays or pauses, as in QuickTime.
        if pictureRect.contains(convert(event.locationInWindow, from: nil)), event.clickCount == 1 {
            model.togglePlay()
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    func cropChanged() {
        crop.isHidden = !model.isCropping
        crop.needsDisplay = true
        relayout()
    }
}

/// The crop over the whole picture: dimmed outside, thirds while dragging, handles at the
/// corners and edges. Drag inside to move it.
@MainActor
final class CropOverlayView: NSView {
    let model: VideoEditorModel
    private var drag: (handle: Handle, start: CGPoint, original: CGRect)?

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move
    }

    init(model: VideoEditorModel) {
        self.model = model
        super.init(frame: .zero)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private var stage: VideoStageView? { superview as? VideoStageView }

    /// The picture's rect in this view (flipped: top left first).
    private var picture: CGRect {
        guard let stage else { return .zero }
        let rect = stage.pictureRect
        return CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private var scale: CGFloat {
        let size = model.info.size
        return size.width > 0 ? picture.width / size.width : 1
    }

    private func viewRect(_ source: CGRect) -> CGRect {
        let origin = picture.origin
        return CGRect(x: origin.x + source.minX * scale, y: origin.y + source.minY * scale, width: source.width * scale,
                      height: source.height * scale)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let draft = model.cropDraft, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = viewRect(draft)
        context.saveGState()
        context.addRect(picture)
        context.addRect(rect)
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.fillPath(using: .evenOdd)
        context.restoreGState()
        if drag != nil {
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
            context.setLineWidth(0.5)
            for third in 1...2 {
                let px = rect.minX + rect.width * CGFloat(third) / 3
                let py = rect.minY + rect.height * CGFloat(third) / 3
                context.move(to: CGPoint(x: px, y: rect.minY))
                context.addLine(to: CGPoint(x: px, y: rect.maxY))
                context.move(to: CGPoint(x: rect.minX, y: py))
                context.addLine(to: CGPoint(x: rect.maxX, y: py))
            }
            context.strokePath()
        }
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1.5)
        context.stroke(rect)
        // Corner brackets, as Photos draws them.
        context.setLineWidth(4)
        let arm: CGFloat = min(20, rect.width / 3, rect.height / 3)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1), (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        ]
        for (corner, dx, dy) in corners {
            context.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            context.addLine(to: corner)
            context.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        context.strokePath()
        // Size, under the crop.
        let label = "\(Int(draft.width)) × \(Int(draft.height))" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attributes)
        // Inside the crop, along its bottom edge.
        let box = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.maxY - 30, width: size.width + 16, height: 20)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.fillPath()
        label.draw(at: CGPoint(x: box.minX + 8, y: box.midY - size.height / 2), withAttributes: attributes)
    }

    private func handle(at point: CGPoint) -> Handle? {
        guard let draft = model.cropDraft else { return nil }
        let rect = viewRect(draft)
        let grab: CGFloat = 10
        let nearLeft = abs(point.x - rect.minX) <= grab, nearRight = abs(point.x - rect.maxX) <= grab
        let nearTop = abs(point.y - rect.minY) <= grab, nearBottom = abs(point.y - rect.maxY) <= grab
        let insideX = point.x > rect.minX - grab && point.x < rect.maxX + grab
        let insideY = point.y > rect.minY - grab && point.y < rect.maxY + grab
        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearRight { return .bottomRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearTop && insideX { return .top }
        if nearBottom && insideX { return .bottom }
        if nearLeft && insideY { return .left }
        if nearRight && insideY { return .right }
        if rect.contains(point) { return .move }
        return nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        switch handle(at: convert(event.locationInWindow, from: nil)) {
        case .left, .right: NSCursor.resizeLeftRight.set()
        case .top, .bottom: NSCursor.resizeUpDown.set()
        case .move: NSCursor.openHand.set()
        case .some: NSCursor.crosshair.set()
        case nil: NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let draft = model.cropDraft else { return }
        if event.clickCount == 2 {
            model.applyCrop()
            return
        }
        let handle = handle(at: point) ?? .move
        drag = (handle, point, draft)
        if handle == .move { NSCursor.closedHand.set() }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = (point.x - drag.start.x) / scale
        let dy = (point.y - drag.start.y) / scale
        let rect = Self.adjust(drag.original, handle: drag.handle, dx: dx, dy: dy, ratio: model.cropShape.ratio,
                               bounds: CGRect(origin: .zero, size: model.info.size))
        model.updateCropDraft(rect)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        needsDisplay = true
    }

    /// The crop after dragging `handle` by (dx, dy) movie pixels, kept inside `bounds`, at
    /// least 32 pixels, and at `ratio` if one is set.
    nonisolated static func adjust(_ original: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat, ratio: CGFloat?, bounds: CGRect) -> CGRect {
        let minimum: CGFloat = 32
        if handle == .move {
            var rect = original.offsetBy(dx: dx, dy: dy)
            rect.origin.x = min(max(bounds.minX, rect.minX), bounds.maxX - rect.width)
            rect.origin.y = min(max(bounds.minY, rect.minY), bounds.maxY - rect.height)
            return rect.integral
        }
        var left = original.minX, right = original.maxX, top = original.minY, bottom = original.maxY
        switch handle {
        case .topLeft, .left, .bottomLeft: left = min(max(bounds.minX, left + dx), right - minimum)
        case .topRight, .right, .bottomRight: right = max(min(bounds.maxX, right + dx), left + minimum)
        default: break
        }
        switch handle {
        case .topLeft, .top, .topRight: top = min(max(bounds.minY, top + dy), bottom - minimum)
        case .bottomLeft, .bottom, .bottomRight: bottom = max(min(bounds.maxY, bottom + dy), top + minimum)
        default: break
        }
        var rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        if let ratio {
            // The edge you pulled leads; the other follows, anchored on the opposite side.
            let byWidth = handle == .left || handle == .right || abs(dx) >= abs(dy)
            var width = rect.width, height = rect.height
            if byWidth { height = width / ratio } else { width = height * ratio }
            if height > bounds.height {
                height = bounds.height
                width = height * ratio
            }
            if width > bounds.width {
                width = bounds.width
                height = width / ratio
            }
            let anchorRight = [.topLeft, .left, .bottomLeft].contains(handle)
            let anchorBottom = [.topLeft, .top, .topRight].contains(handle)
            let x = anchorRight ? original.maxX - width : (handle == .top || handle == .bottom ? original.midX - width / 2 : left)
            let y = anchorBottom ? original.maxY - height : (handle == .left || handle == .right ? original.midY - height / 2 : top)
            rect = CGRect(x: x, y: y, width: width, height: height)
            rect.origin.x = min(max(bounds.minX, rect.minX), bounds.maxX - rect.width)
            rect.origin.y = min(max(bounds.minY, rect.minY), bounds.maxY - rect.height)
        }
        return rect.integral
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
}

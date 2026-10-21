import AppKit

/// Keeps the canvas centred when it's smaller than the window, allowing for the toolbar that
/// the canvas scrolls under.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let zoom: CGFloat = max(enclosingScrollView?.magnification ?? 1, 0.01)
        let insets = contentInsets
        let top: CGFloat = insets.top / zoom
        let bottom: CGFloat = insets.bottom / zoom
        let left: CGFloat = insets.left / zoom
        let right: CGFloat = insets.right / zoom
        let width: CGFloat = rect.width - left - right
        let height: CGFloat = rect.height - top - bottom
        let frame = documentView.frame
        if width > frame.width { rect.origin.x = frame.midX - width / 2 - left }
        if height > frame.height {
            rect.origin.y = isFlipped ? frame.midY - height / 2 - top : frame.midY - height / 2 - bottom
        }
        return rect
    }
}

/// The editor's drawing surface. Its size is the canvas in points; the scroll view around it
/// zooms and pans. Underneath: the frame's background, the image in its own layer (so marks
/// redraw without it), the marks, and on top the handles, guides and crop.
final class EditorCanvas: NSView, NSTextViewDelegate, NSMenuItemValidation {
    let model: EditorModel
    var renderer: AnnotationRenderer { model.renderer }
    /// Leaves the editor (Esc when nothing changed).
    var onClose: (() -> Void)?
    /// A command picked by its key, when there's no menu to catch it.
    var onCommand: ((EditorCommand.ID) -> Void)?
    var onZoomChange: (() -> Void)?
    /// Zoomed to fit, so resizing the window refits.
    private(set) var fitsToWindow = true

    private(set) var layout: FrameLayout
    /// Laid out for cropping: the whole image, unframed.
    private var showsWholeImage = false
    private let paper = PaperView()
    private let imageView = ImageLayerView()
    private let marksView = MarksView()
    private let chrome = ChromeView()

    var gesture: Gesture?
    var gestureStart: EditorDocument?
    var lastPoint: CGPoint?
    /// Where the mouse went down: a drag starts once it's moved a little from here.
    var downPoint: CGPoint?
    var dragged = false
    var spaceHeld = false
    var textView: MarkTextView?
    var textUndo = UndoManager()
    var textBefore: EditorDocument?
    /// A counter just placed: typing gives it a label.
    var labelArmed: UUID?
    /// The text being typed is a counter's label.
    var editsLabel = false
    /// Picking a colour from the capture (I).
    var picksColour = false
    var hoverPoint: CGPoint?
    var hoverMark: UUID?
    var fitPreview: CGRect?
    var hoverTask: Task<Void, Never>?
    var guides: [SnapGuide] = []
    var marquee: CGRect?
    var trackingArea: NSTrackingArea?

    enum Gesture {
        case draw(UUID, origin: CGPoint)
        case words(from: CGPoint, ids: [UUID])
        case move([UUID: Mark], from: CGPoint, duplicate: Bool)
        case adjust(Mark, MarkHandle)
        case marquee(from: CGPoint, base: Set<UUID>)
        case crop(MarkHandle?, from: CGPoint, original: CGRect)
        case pan(from: NSPoint, origin: NSPoint)
    }

    static let accent = NSColor(srgbRed: 0x8C / 255, green: 0x87 / 255, blue: 1, alpha: 1)

    init(model: EditorModel) {
        self.model = model
        layout = FrameLayout(document: model.document)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [paper, imageView, marksView, chrome] as [NSView] {
            addSubview(view)
        }
        paper.canvas = self
        imageView.canvas = self
        marksView.canvas = self
        chrome.canvas = self
        model.endTextEditing = { [weak self] in self?.endTextEditing() }
        relayout()
        setAccessibilityRole(.layoutArea)
        setAccessibilityLabel("Capture")
        updateAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var scale: CGFloat { model.scale }
    var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    /// One screen point, in image pixels.
    var screenPoint: CGFloat { scale / magnification }

    /// What the canvas shows: while cropping, the whole image without its frame.
    var shown: EditorDocument {
        guard model.cropDraft != nil else { return model.document }
        var document = model.document
        document.crop = document.imageBounds
        document.frame.background = .none
        return document
    }

    // MARK: Updates

    /// The crop, frame or crop tool changed: everything moves.
    func relayout() {
        showsWholeImage = model.cropDraft != nil
        layout = FrameLayout(document: shown)
        let size = NSSize(width: layout.canvasSize.width / scale, height: layout.canvasSize.height / scale)
        if frame.size != size {
            setFrameSize(size)
            if fitsToWindow { zoomToFit() }
        }
        for view in [paper, marksView, chrome] as [NSView] {
            view.frame = bounds
            view.needsDisplay = true
        }
        imageView.frame = viewRect(fromCanvas: layout.imageRect)
        imageView.needsDisplay = true
        updateChromeForZoom()
        syncTextView()
        onZoomChange?()
    }

    func documentChanged(from old: EditorDocument, to new: EditorDocument) {
        if old.crop != new.crop || old.frame != new.frame || old.imageSize != new.imageSize {
            relayout()
            return
        }
        marksView.setNeedsDisplay(dirtyRect(from: old, to: new))
        chrome.needsDisplay = true
        syncTextView()
        updateAccessibility()
    }

    /// Selection, crop, review or hover changed.
    func chromeChanged() {
        if (model.cropDraft != nil) != showsWholeImage { relayout() }
        chrome.needsDisplay = true
        updateAccessibility()
    }

    func toolChanged() {
        if (model.cropDraft != nil) != showsWholeImage { relayout() }
        labelArmed = nil
        fitPreview = nil
        updateCursor()
        chrome.needsDisplay = true
    }

    /// Only what changed: both the old and new place of every mark that moved or changed.
    private func dirtyRect(from old: EditorDocument, to new: EditorDocument) -> NSRect {
        let before = Dictionary(old.marks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(new.marks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if old.marks.map(\.id) != new.marks.map(\.id) {
            // Added, removed or reordered: counters may renumber and layers restack.
            let counters = old.marks.contains { $0.kind == .counter } || new.marks.contains { $0.kind == .counter }
            if counters { return bounds }
        }
        var dirty = CGRect.null
        for id in Set(before.keys).union(after.keys) {
            let a = before[id]
            let b = after[id]
            guard a != b else { continue }
            if a?.kind == .spotlight || b?.kind == .spotlight { return bounds }
            if let a { dirty = dirty.union(MarkGeometry.paintedBounds(a, scale: scale)) }
            if let b { dirty = dirty.union(MarkGeometry.paintedBounds(b, scale: scale)) }
        }
        if old.counterStart != new.counterStart { return bounds }
        guard !dirty.isNull else { return .zero }
        return viewRect(fromImage: dirty).insetBy(dx: -2, dy: -2)
    }

    // MARK: Coordinates

    func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return imagePoint(fromView: point)
    }

    func imagePoint(fromView point: CGPoint) -> CGPoint {
        layout.imagePoint(fromCanvas: CGPoint(x: point.x * scale, y: point.y * scale))
    }

    func viewPoint(fromImage point: CGPoint) -> CGPoint {
        let canvas = layout.canvasPoint(fromImage: point)
        return CGPoint(x: canvas.x / scale, y: canvas.y / scale)
    }

    func viewRect(fromImage rect: CGRect) -> CGRect {
        let origin = viewPoint(fromImage: rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width / scale, height: rect.height / scale)
    }

    func viewRect(fromCanvas rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / scale, y: rect.minY / scale, width: rect.width / scale, height: rect.height / scale)
    }

    /// The part of the image on screen, in image pixels.
    var visibleImageRect: CGRect {
        let visible = visibleRect
        let origin = imagePoint(fromView: visible.origin)
        let rect = CGRect(x: origin.x, y: origin.y, width: visible.width * scale, height: visible.height * scale)
        let crop = shown.crop
        let clipped = rect.intersection(crop)
        return clipped.isNull ? crop : clipped
    }

    // MARK: Zoom

    var maxMagnification: CGFloat {
        let backing: CGFloat = window?.backingScaleFactor ?? 2
        let longest: CGFloat = max(bounds.width, bounds.height, 1)
        // Keep the canvas within what a layer can hold.
        let limit: CGFloat = 16000 / (longest * backing)
        return max(1, min(8, limit))
    }

    func setZoom(_ value: CGFloat, fits: Bool = false) {
        guard let scrollView = enclosingScrollView else { return }
        fitsToWindow = fits
        scrollView.maxMagnification = maxMagnification
        let target: CGFloat = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        let clip = scrollView.contentView.bounds
        scrollView.setMagnification(target, centeredAt: NSPoint(x: clip.midX, y: clip.midY))
        zoomChanged()
    }

    func zoom(by factor: CGFloat) {
        setZoom(magnification * factor)
    }

    /// The whole canvas in view, never larger than actual size.
    func zoomToFit() {
        guard let scrollView = enclosingScrollView, bounds.width > 0, bounds.height > 0 else { return }
        let insets = scrollView.contentInsets
        let available = scrollView.contentView.frame.size
        let margin: CGFloat = 32
        let width: CGFloat = available.width - insets.left - insets.right - 2 * margin
        let height: CGFloat = available.height - insets.top - insets.bottom - 2 * margin
        let across: CGFloat = width / bounds.width
        let down: CGFloat = height / bounds.height
        let fit: CGFloat = max(min(across, down, 1), 0.05)
        fitsToWindow = true
        scrollView.maxMagnification = maxMagnification
        scrollView.magnification = fit
        zoomChanged()
    }

    func zoomChanged() {
        updateChromeForZoom()
        chrome.needsDisplay = true
        syncTextView()
        onZoomChange?()
    }

    func viewportDidResize() {
        if fitsToWindow { zoomToFit() }
    }

    override func magnify(with event: NSEvent) {
        fitsToWindow = false
        super.magnify(with: event)
        zoomChanged()
    }

    override func smartMagnify(with event: NSEvent) {
        fitsToWindow = false
        super.smartMagnify(with: event)
        zoomChanged()
    }

    /// Screen-sized details (the image's hairline and shadow, sharp pixels when zoomed right in)
    /// follow the zoom.
    func updateChromeForZoom() {
        let zoom = max(magnification, 0.01)
        let backing: CGFloat = window?.backingScaleFactor ?? 2
        let pixelsPerImagePixel: CGFloat = zoom * backing / scale
        imageView.sharp = pixelsPerImagePixel > 2
        let framed = shown.frame.isOn
        imageView.outlined = !framed
        imageView.cornerRadius = framed ? shown.frame.cornerRadius / scale : 0
        imageView.zoom = zoom
        paper.zoom = zoom
        paper.outlined = framed
        imageView.needsDisplay = true
        paper.updatePageEdge()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChromeForZoom()
    }

    // MARK: Accessibility

    private var markElements: [MarkAccessibilityElement] = []

    func updateAccessibility() {
        markElements = model.document.marks.map { mark in
            let element = MarkAccessibilityElement(mark: mark, canvas: self)
            element.setAccessibilityParent(self)
            return element
        }
        setAccessibilityChildren(markElements)
    }

    func describe(_ mark: Mark) -> String {
        var parts: [String] = [mark.kind.title]
        if mark.kind != .spotlight, mark.kind != .image, mark.kind != .redact || mark.style.redact == .solid {
            parts.append(mark.colour.name.lowercased())
        }
        switch mark.kind {
        case .arrow:
            parts.append(Self.direction(from: mark.start, to: mark.end))
        case .text:
            parts.append("“\(mark.text)”")
        case .counter:
            let number = model.document.counterNumbers[mark.id] ?? 1
            parts.append(mark.style.counterFormat.label(number))
            if !mark.text.isEmpty { parts.append("“\(mark.text)”") }
        case .redact:
            parts.append(mark.style.redact.title.lowercased())
        default:
            break
        }
        return parts.joined(separator: ", ")
    }

    static func direction(from start: CGPoint, to end: CGPoint) -> String {
        let dx: CGFloat = end.x - start.x
        let dy: CGFloat = start.y - end.y
        let angle: CGFloat = atan2(dy, dx) * 180 / .pi
        let names = ["right", "up-right", "up", "up-left", "left", "down-left", "down", "down-right"]
        let step: Int = Int(((angle + 360 + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return names[min(max(step, 0), 7)]
    }

    // MARK: Drawing views

    func drawMarks(in context: CGContext) {
        context.saveGState()
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        renderer.drawMarks(shown, in: context, imageUnderneath: false, editingText: model.editingText)
        context.restoreGState()
    }

    func drawBackdrop(in context: CGContext) {
        context.saveGState()
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        renderer.drawBackdrop(shown, in: context, includingImage: false)
        context.restoreGState()
    }

    func drawChrome(in context: CGContext) {
        CanvasChrome(canvas: self).draw(in: context)
    }

    func redrawChrome() {
        chrome.needsDisplay = true
    }

    func redrawMarks() {
        marksView.needsDisplay = true
    }
}

/// The frame's background, and the image's shadow on it.
final class PaperView: NSView {
    weak var canvas: EditorCanvas?
    var zoom: CGFloat = 1
    /// When framed, the page's edge gets the hairline and shadow instead of the image.
    var outlined = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, let context = NSGraphicsContext.current?.cgContext else { return }
        canvas.drawBackdrop(in: context)
    }

    func updatePageEdge() {
        wantsLayer = true
        guard let layer else { return }
        if outlined {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.borderColor = NSColor.separatorColor.cgColor
            }
            layer.borderWidth = 0.5 / zoom
            layer.shadowColor = CGColor(gray: 0, alpha: 1)
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 12 / zoom
            layer.shadowOffset = CGSize(width: 0, height: -2 / zoom)
            layer.shadowPath = CGPath(rect: bounds, transform: nil)
        } else {
            layer.borderWidth = 0
            layer.shadowOpacity = 0
            layer.shadowPath = nil
        }
    }
}

/// The captured image, as a layer the GPU scales: marks redraw without touching it.
final class ImageLayerView: NSView {
    weak var canvas: EditorCanvas?
    var sharp = false
    var outlined = true
    var cornerRadius: CGFloat = 0
    var zoom: CGFloat = 1

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let canvas, let layer else { return }
        let document = canvas.shown
        let size = document.imageSize
        let crop = document.crop
        layer.contents = canvas.model.image
        layer.contentsGravity = .resize
        if size.width > 0, size.height > 0 {
            // Unit coordinates, from the bottom left on macOS.
            let x: CGFloat = crop.minX / size.width
            let y: CGFloat = (size.height - crop.maxY) / size.height
            layer.contentsRect = CGRect(x: x, y: y, width: crop.width / size.width, height: crop.height / size.height)
        }
        layer.magnificationFilter = sharp ? .nearest : .linear
        layer.minificationFilter = .trilinear
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        if outlined {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.borderColor = NSColor.separatorColor.cgColor
            }
            layer.borderWidth = 0.5 / zoom
            layer.shadowColor = CGColor(gray: 0, alpha: 1)
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 12 / zoom
            layer.shadowOffset = CGSize(width: 0, height: -2 / zoom)
            layer.shadowPath = CGPath(rect: layer.bounds, transform: nil)
        } else {
            layer.borderWidth = 0
            layer.shadowOpacity = 0
            layer.shadowPath = nil
        }
    }
}

/// Every mark, redrawn only where something changed.
final class MarksView: NSView {
    weak var canvas: EditorCanvas?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, let context = NSGraphicsContext.current?.cgContext else { return }
        canvas.drawMarks(in: context)
    }
}

/// Handles, selection outlines, guides, the crop and smart previews: drawn over everything,
/// at screen size whatever the zoom.
final class ChromeView: NSView {
    weak var canvas: EditorCanvas?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, let context = NSGraphicsContext.current?.cgContext else { return }
        canvas.drawChrome(in: context)
    }
}

/// A mark, for VoiceOver.
final class MarkAccessibilityElement: NSAccessibilityElement {
    let markID: UUID
    weak var canvas: EditorCanvas?

    @MainActor
    init(mark: Mark, canvas: EditorCanvas) {
        markID = mark.id
        self.canvas = canvas
        super.init()
        setAccessibilityRole(.image)
        setAccessibilityLabel(canvas.describe(mark))
        setAccessibilitySelected(canvas.model.selection.contains(mark.id))
    }

    override func accessibilityFrameInParentSpace() -> NSRect {
        guard let canvas else { return .zero }
        let markID = markID
        return MainActor.assumeIsolated {
            guard let mark = canvas.model.document[markID] else { return .zero }
            let rect = canvas.viewRect(fromImage: MarkGeometry.bounds(mark, scale: canvas.scale))
            // Parent space is the canvas's own, from the bottom left.
            return NSRect(x: rect.minX, y: canvas.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let canvas else { return false }
        let markID = markID
        MainActor.assumeIsolated { canvas.model.selection = [markID] }
        return true
    }

    override func accessibilityPerformDelete() -> Bool {
        guard let canvas else { return false }
        let markID = markID
        MainActor.assumeIsolated {
            canvas.model.selection = [markID]
            canvas.model.deleteSelection()
        }
        return true
    }
}

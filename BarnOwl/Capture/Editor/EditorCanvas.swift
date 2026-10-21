import AppKit

/// Keeps the canvas centred when it's smaller than the window.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let frame = documentView.frame
        if rect.width > frame.width { rect.origin.x = frame.midX - rect.width / 2 }
        if rect.height > frame.height { rect.origin.y = frame.midY - rect.height / 2 }
        return rect
    }
}

/// The editor's drawing surface. It shows the document through the shared renderer, and turns
/// clicks, drags and keys into marks. Its size is the canvas in points; the scroll view around
/// it zooms and pans.
final class EditorCanvas: NSView, NSTextViewDelegate, NSMenuItemValidation {
    let model: EditorModel
    let renderer: AnnotationRenderer
    /// ⌘W, which has no menu to come from.
    var onClose: (() -> Void)?
    /// Zoomed to fit, so resizing the window refits.
    private(set) var fitsToWindow = true

    private var layout: FrameLayout
    private var gesture: Gesture?
    private var gestureStart: EditorDocument?
    private var lastPoint: CGPoint?
    private var marquee: CGRect?
    private var spaceHeld = false
    private var textView: MarkTextView?
    private var textUndo = UndoManager()
    private var textBefore: EditorDocument?

    private enum Gesture {
        case draw(UUID, origin: CGPoint)
        case move([UUID: Mark], from: CGPoint)
        case adjust(Mark, MarkHandle)
        case marquee(from: CGPoint, base: Set<UUID>)
        case crop(MarkHandle?, from: CGPoint, original: CGRect)
        case pan(from: NSPoint, origin: NSPoint)
    }

    static let background = NSColor(srgbRed: 0x1E / 255, green: 0x1D / 255, blue: 0x33 / 255, alpha: 1)
    static let accent = NSColor(srgbRed: 0x8C / 255, green: 0x87 / 255, blue: 1, alpha: 1)

    init(model: EditorModel, renderer: AnnotationRenderer) {
        self.model = model
        self.renderer = renderer
        layout = FrameLayout(document: model.document)
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        model.willChangeTool = { [weak self] in self?.endTextEditing() }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var scale: CGFloat { model.scale }
    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    /// One screen point, in image pixels.
    private var screenPoint: CGFloat { scale / magnification }

    /// What the canvas shows: while cropping, the whole image without its frame.
    private var shown: EditorDocument {
        guard model.cropDraft != nil else { return model.document }
        var document = model.document
        document.crop = document.imageBounds
        document.frame.background = .none
        return document
    }

    /// Call after the document, selection, tool or crop changes.
    func refresh() {
        layout = FrameLayout(document: shown)
        let size = NSSize(width: layout.canvasSize.width / scale, height: layout.canvasSize.height / scale)
        if frame.size != size {
            setFrameSize(size)
            if fitsToWindow { zoomToFit() }
        }
        needsDisplay = true
        syncTextView()
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Coordinates

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return layout.imagePoint(fromCanvas: CGPoint(x: point.x * scale, y: point.y * scale))
    }

    private func viewPoint(fromImage point: CGPoint) -> CGPoint {
        let canvas = layout.canvasPoint(fromImage: point)
        return CGPoint(x: canvas.x / scale, y: canvas.y / scale)
    }

    private func viewRect(fromImage rect: CGRect) -> CGRect {
        let origin = viewPoint(fromImage: rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width / scale, height: rect.height / scale)
    }

    /// The part of the image on screen, in image pixels.
    private var visibleImageRect: CGRect {
        let visible = visibleRect
        let origin = layout.imagePoint(fromCanvas: CGPoint(x: visible.minX * scale, y: visible.minY * scale))
        let rect = CGRect(x: origin.x, y: origin.y, width: visible.width * scale, height: visible.height * scale)
        let shownCrop = shown.crop
        let clipped = rect.intersection(shownCrop)
        return clipped.isNull ? shownCrop : clipped
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        renderer.draw(shown, in: context, editingText: model.editingText)
        context.restoreGState()
        if let draft = model.cropDraft {
            drawCropOverlay(draft, in: context)
        } else {
            drawSelection(in: context)
        }
        if let marquee {
            let rect = viewRect(fromImage: marquee)
            context.setFillColor(Self.accent.withAlphaComponent(0.12).cgColor)
            context.fill(rect)
            context.setStrokeColor(Self.accent.cgColor)
            context.setLineWidth(1 / magnification)
            context.stroke(rect)
        }
    }

    private func drawSelection(in context: CGContext) {
        let marks = model.selectedMarks
        guard !marks.isEmpty else { return }
        let unit: CGFloat = 1 / magnification
        for mark in marks {
            let outlined = marks.count > 1 || [.text, .counter, .pen, .image].contains(mark.kind)
            if outlined {
                let rect = viewRect(fromImage: MarkGeometry.bounds(mark, scale: scale)).insetBy(dx: -4 * unit, dy: -4 * unit)
                context.addPath(MarkGeometry.roundedRect(rect, radius: 4 * unit))
                context.setStrokeColor(Self.accent.cgColor)
                context.setLineWidth(1.25 * unit)
                context.strokePath()
            }
            guard marks.count == 1, model.editingText == nil else { continue }
            for handle in MarkGeometry.handles(for: mark, scale: scale) {
                drawHandle(at: viewPoint(fromImage: handle.point), filled: handle.handle == .bend, unit: unit, in: context)
            }
        }
    }

    private func drawHandle(at point: CGPoint, filled: Bool, unit: CGFloat, in context: CGContext) {
        let radius: CGFloat = 4.5 * unit
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.35))
        context.setFillColor(filled ? Self.accent.cgColor : CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: rect)
        context.restoreGState()
        context.setStrokeColor(filled ? CGColor(gray: 1, alpha: 1) : Self.accent.cgColor)
        context.setLineWidth(1.5 * unit)
        context.strokeEllipse(in: rect)
    }

    private func drawCropOverlay(_ draft: CGRect, in context: CGContext) {
        let unit: CGFloat = 1 / magnification
        let crop = viewRect(fromImage: draft)
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.addRect(bounds)
        context.addRect(crop)
        context.fillPath(using: .evenOdd)

        // Thirds, to help compose.
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.3))
        context.setLineWidth(unit)
        for step in 1...2 {
            let fraction = CGFloat(step) / 3
            let x: CGFloat = crop.minX + crop.width * fraction
            let y: CGFloat = crop.minY + crop.height * fraction
            context.move(to: CGPoint(x: x, y: crop.minY))
            context.addLine(to: CGPoint(x: x, y: crop.maxY))
            context.move(to: CGPoint(x: crop.minX, y: y))
            context.addLine(to: CGPoint(x: crop.maxX, y: y))
        }
        context.strokePath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.stroke(crop, width: unit)

        // Corner brackets and edge bars, like Photos.
        let arm: CGFloat = min(18 * unit, crop.width / 3, crop.height / 3)
        let bar: CGFloat = 3.5 * unit
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(bar)
        context.setLineCap(.round)
        let inset: CGFloat = bar / 2
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: crop.minX + inset, y: crop.minY + inset), 1, 1),
            (CGPoint(x: crop.maxX - inset, y: crop.minY + inset), -1, 1),
            (CGPoint(x: crop.maxX - inset, y: crop.maxY - inset), -1, -1),
            (CGPoint(x: crop.minX + inset, y: crop.maxY - inset), 1, -1),
        ]
        for (corner, dx, dy) in corners {
            context.move(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
            context.addLine(to: corner)
            context.addLine(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
        }
        let half: CGFloat = arm / 2
        context.move(to: CGPoint(x: crop.midX - half, y: crop.minY + inset))
        context.addLine(to: CGPoint(x: crop.midX + half, y: crop.minY + inset))
        context.move(to: CGPoint(x: crop.midX - half, y: crop.maxY - inset))
        context.addLine(to: CGPoint(x: crop.midX + half, y: crop.maxY - inset))
        context.move(to: CGPoint(x: crop.minX + inset, y: crop.midY - half))
        context.addLine(to: CGPoint(x: crop.minX + inset, y: crop.midY + half))
        context.move(to: CGPoint(x: crop.maxX - inset, y: crop.midY - half))
        context.addLine(to: CGPoint(x: crop.maxX - inset, y: crop.midY + half))
        context.strokePath()
        context.restoreGState()

        drawLabel("\(Int(draft.width)) × \(Int(draft.height))", centredBelow: crop, unit: unit)
    }

    /// A small dark capsule with the crop's size, inside its bottom edge.
    private func drawLabel(_ text: String, centredBelow rect: CGRect, unit: CGFloat) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11 * unit, weight: .medium)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = string.size()
        let width: CGFloat = size.width + 16 * unit
        let height: CGFloat = size.height + 6 * unit
        let capsule = CGRect(x: rect.midX - width / 2, y: rect.maxY - height - 12 * unit, width: width, height: height)
        guard capsule.minY > rect.minY else { return }
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: height / 2, yRadius: height / 2).fill()
        string.draw(at: CGPoint(x: capsule.minX + 8 * unit, y: capsule.minY + 3 * unit))
    }

    // MARK: Zoom

    func zoom(by factor: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        fitsToWindow = false
        let clip = scrollView.contentView.bounds
        let target: CGFloat = min(max(scrollView.magnification * factor, scrollView.minMagnification), scrollView.maxMagnification)
        scrollView.setMagnification(target, centeredAt: NSPoint(x: clip.midX, y: clip.midY))
    }

    /// The whole canvas in view, never larger than actual size.
    func zoomToFit() {
        guard let scrollView = enclosingScrollView, bounds.width > 0, bounds.height > 0 else { return }
        fitsToWindow = true
        let available = scrollView.contentView.frame.size
        let margin: CGFloat = 28
        let across: CGFloat = (available.width - 2 * margin) / bounds.width
        let down: CGFloat = (available.height - 2 * margin) / bounds.height
        scrollView.magnification = max(min(across, down, 1), scrollView.minMagnification)
    }

    /// The window changed size.
    func viewportDidResize() {
        if fitsToWindow { zoomToFit() }
    }

    override func magnify(with event: NSEvent) {
        fitsToWindow = false
        super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        fitsToWindow = false
        super.smartMagnify(with: event)
    }

    // MARK: Mouse

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: cursor)
    }

    private var cursor: NSCursor {
        if spaceHeld { return .openHand }
        switch model.tool {
        case .select: return .arrow
        case .text: return .iBeam
        default: return .crosshair
        }
    }

    private func updateCursor() {
        window?.invalidateCursorRects(for: self)
        cursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        // A click outside the text being typed puts it down, and does nothing else.
        if model.editingText != nil {
            endTextEditing()
            return
        }
        window?.makeFirstResponder(self)
        let point = imagePoint(event)
        gestureStart = model.document
        lastPoint = point
        if spaceHeld, let clip = enclosingScrollView?.contentView {
            gesture = .pan(from: event.locationInWindow, origin: clip.bounds.origin)
            NSCursor.closedHand.set()
            return
        }
        if model.tool == .crop {
            beginCrop(at: point)
            return
        }
        let hit = MarkGeometry.topmost(in: model.document.marks, at: point, tolerance: 8 * screenPoint, scale: scale)
        if event.clickCount == 2, let hit, hit.kind == .text {
            beginTextEditing(hit.id)
            return
        }
        if let (mark, handle) = handle(at: point) {
            gesture = .adjust(mark, handle)
            return
        }
        switch model.tool {
        case .select:
            if let hit {
                if event.modifierFlags.contains(.shift) {
                    if model.selection.contains(hit.id) { model.selection.remove(hit.id) } else { model.selection.insert(hit.id) }
                } else if !model.selection.contains(hit.id) {
                    model.selection = [hit.id]
                }
                beginMove(from: point)
            } else {
                let base = event.modifierFlags.contains(.shift) ? model.selection : []
                model.selection = base
                gesture = .marquee(from: point, base: base)
            }
        case .text:
            if let hit, hit.kind == .text {
                beginTextEditing(hit.id)
            } else {
                placeText(at: point)
            }
        default:
            if let hit, model.selection.contains(hit.id) {
                beginMove(from: point)
            } else {
                beginDrawing(at: point)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let gesture else { return }
        if case .pan(let from, let origin) = gesture, let scrollView = enclosingScrollView {
            let now = event.locationInWindow
            let dx: CGFloat = (now.x - from.x) / magnification
            let dy: CGFloat = (now.y - from.y) / magnification
            scrollView.contentView.scroll(to: NSPoint(x: origin.x - dx, y: origin.y + dy))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }
        autoscroll(with: event)
        let point = imagePoint(event)
        lastPoint = point
        update(gesture, to: point, constrained: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            gesture = nil
            gestureStart = nil
            marquee = nil
            needsDisplay = true
        }
        guard let gesture, let before = gestureStart else { return }
        switch gesture {
        case .draw(let id, _):
            finishDrawing(id, before: before)
        case .move:
            model.commit(from: before, "Move")
        case .adjust(let mark, _):
            model.commit(from: before, "Change \(mark.kind.title)")
        case .pan:
            updateCursor()
        case .marquee, .crop:
            break
        }
    }

    /// ⇧ pressed or let go mid-drag takes effect at once.
    override func flagsChanged(with event: NSEvent) {
        guard let gesture, let lastPoint else { return super.flagsChanged(with: event) }
        update(gesture, to: lastPoint, constrained: event.modifierFlags.contains(.shift))
    }

    /// The handle under `point` on the one selected mark.
    private func handle(at point: CGPoint) -> (Mark, MarkHandle)? {
        guard model.selection.count == 1, let id = model.selection.first, let mark = model.document[id] else { return nil }
        let reach: CGFloat = 7 * screenPoint
        let handles = MarkGeometry.handles(for: mark, scale: scale)
        guard let entry = handles.first(where: { MarkGeometry.distance($0.point, point) <= reach }) else { return nil }
        return (mark, entry.handle)
    }

    private func beginMove(from point: CGPoint) {
        var originals: [UUID: Mark] = [:]
        for mark in model.selectedMarks { originals[mark.id] = mark }
        gesture = .move(originals, from: point)
    }

    private func beginDrawing(at point: CGPoint) {
        guard let kind = model.tool.markKind else { return }
        var mark = model.newMark(kind, at: point)
        if kind == .pen { mark.points = [point] }
        var document = model.document
        document.marks.append(mark)
        model.setLive(document)
        model.selection = [mark.id]
        gesture = .draw(mark.id, origin: point)
    }

    private func update(_ gesture: Gesture, to point: CGPoint, constrained: Bool) {
        switch gesture {
        case .draw(let id, let origin):
            var document = model.document
            let step: CGFloat = 1.5 * scale
            document.update(id) { mark in
                if mark.kind == .pen {
                    if MarkGeometry.distance(mark.points.last ?? origin, point) >= step { mark.points.append(point) }
                    return
                }
                mark.end = constrained ? MarkGeometry.constrainedEnd(point, from: origin, kind: mark.kind) : point
                if mark.kind == .arrow, mark.style.arrow == .curved {
                    mark.control = MarkGeometry.defaultBend(start: mark.start, end: mark.end)
                }
            }
            model.setLive(document)
        case .move(let originals, let from):
            var dx: CGFloat = point.x - from.x
            var dy: CGFloat = point.y - from.y
            if constrained {
                if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
            }
            var document = model.document
            for (id, original) in originals {
                document.update(id) { $0 = MarkGeometry.moved(original, by: dx, dy) }
            }
            model.setLive(document)
        case .adjust(let original, let handle):
            var document = model.document
            document.update(original.id) {
                $0 = MarkGeometry.adjusted(original, handle: handle, to: point, constrained: constrained)
            }
            model.setLive(document)
        case .marquee(let from, let base):
            let rect = CGRect(x: min(from.x, point.x), y: min(from.y, point.y),
                              width: abs(point.x - from.x), height: abs(point.y - from.y))
            marquee = rect
            let inside = model.document.marks.filter { MarkGeometry.bounds($0, scale: scale).intersects(rect) }
            model.selection = base.union(inside.map(\.id))
            needsDisplay = true
        case .crop(let handle, let from, let original):
            model.cropDraft = croppedRect(original, handle: handle, from: from, to: point, constrained: constrained)
        case .pan:
            break
        }
    }

    private func finishDrawing(_ id: UUID, before: EditorDocument) {
        if let lastPoint, model.document[id]?.kind == .pen {
            var document = model.document
            document.update(id) { mark in
                if mark.points.last != lastPoint { mark.points.append(lastPoint) }
            }
            model.setLive(document)
        }
        guard let mark = model.document[id] else { return }
        let minimum: CGFloat = 3 * screenPoint
        let largeEnough: Bool = switch mark.kind {
        case .counter, .pen, .text: true
        case .arrow, .line: MarkGeometry.distance(mark.start, mark.end) >= minimum * 2
        default: mark.rect.width >= minimum && mark.rect.height >= minimum
        }
        guard largeEnough else {
            model.setLive(before)
            model.selection = []
            return
        }
        model.commit(from: before, "Add \(mark.kind.title)")
        if model.selectsAfterDrawing { model.choose(.select) }
    }

    // MARK: Crop

    private func beginCrop(at point: CGPoint) {
        guard let draft = model.cropDraft else { return }
        let reach: CGFloat = 10 * screenPoint
        let handles = MarkGeometry.boxHandles(draft, edges: true)
        if let entry = handles.first(where: { MarkGeometry.distance($0.point, point) <= reach }) {
            gesture = .crop(entry.handle, from: point, original: draft)
        } else if draft.contains(point) {
            gesture = .crop(nil, from: point, original: draft)
        } else {
            let bounds = model.document.imageBounds
            let start = CGPoint(x: min(max(point.x, 0), bounds.maxX), y: min(max(point.y, 0), bounds.maxY))
            gesture = .crop(.bottomRight, from: start, original: CGRect(origin: start, size: .zero))
        }
    }

    private func croppedRect(_ original: CGRect, handle: MarkHandle?, from: CGPoint, to point: CGPoint,
                             constrained: Bool) -> CGRect {
        let bounds = model.document.imageBounds
        guard let handle else {
            // Moving: the whole rectangle slides, staying on the image.
            let dx: CGFloat = min(max(point.x - from.x, bounds.minX - original.minX), bounds.maxX - original.maxX)
            let dy: CGFloat = min(max(point.y - from.y, bounds.minY - original.minY), bounds.maxY - original.maxY)
            return original.offsetBy(dx: dx, dy: dy).integral
        }
        var rect = MarkGeometry.resized(original, handle: handle, to: point)
        if constrained { rect = MarkGeometry.squared(rect, handle: handle, from: original) }
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull else { return original }
        return CGRect(x: clipped.minX.rounded(), y: clipped.minY.rounded(),
                      width: clipped.width.rounded(), height: clipped.height.rounded())
    }

    // MARK: Text

    private func placeText(at point: CGPoint) {
        var mark = model.newMark(.text, at: point)
        // The caret lands where you clicked: the box starts up and to the left of it.
        let probe = MarkGeometry.textLayout(mark, scale: scale)
        let insetX: CGFloat = probe.textRect.minX - probe.boxRect.minX
        let insetY: CGFloat = probe.textRect.minY - probe.boxRect.minY
        mark.start = CGPoint(x: point.x - insetX, y: point.y - insetY - probe.textRect.height / 2)
        mark.end = mark.start
        let before = model.document
        var document = before
        document.marks.append(mark)
        model.setLive(document)
        beginTextEditing(mark.id, before: before)
    }

    /// Opens the text mark for typing; `before` is the document to undo back to.
    func beginTextEditing(_ id: UUID, before: EditorDocument? = nil) {
        guard let mark = model.document[id] else { return }
        if model.editingText != nil { endTextEditing() }
        textBefore = before ?? model.document
        textUndo = UndoManager()
        model.editingText = id
        model.selection = [id]
        let textView = MarkTextView.make()
        textView.delegate = self
        textView.string = mark.text
        addSubview(textView)
        self.textView = textView
        syncTextView()
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (mark.text as NSString).length, length: 0))
        needsDisplay = true
    }

    /// Puts the typed text down: one undo step, and an empty mark goes away.
    func endTextEditing() {
        guard let id = model.editingText else { return }
        if let textView {
            textView.delegate = nil
            textView.removeFromSuperview()
        }
        textView = nil
        model.editingText = nil
        let before = textBefore ?? model.document
        textBefore = nil
        if let mark = model.document[id], mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var document = model.document
            document.remove([id])
            model.setLive(document)
            model.selection.remove(id)
        }
        model.commit(from: before, "Text")
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    /// Keeps the text field over its mark, at the mark's size, as both change.
    private func syncTextView() {
        guard let textView, let id = model.editingText, let mark = model.document[id] else { return }
        let text = MarkGeometry.textLayout(mark, scale: scale)
        let font = MarkGeometry.textFont(size: mark.size.fontSize)
        if textView.font != font {
            textView.font = font
            textView.typingAttributes = [.font: font]
        }
        let origin = viewPoint(fromImage: text.textRect.origin)
        textView.frame = NSRect(x: origin.x, y: origin.y, width: text.textRect.width / scale + 2,
                                height: text.textRect.height / scale)
        let caret: MarkColour = switch mark.style.text {
        case .box: mark.colour.contrasting
        case .halo: mark.colour
        case .outline: mark.colour.luminance > 0.8 ? .ink : .white
        }
        textView.insertionPointColor = NSColor(cgColor: caret.cgColor()) ?? .white
    }

    func textDidChange(_ notification: Notification) {
        guard let textView, let id = model.editingText else { return }
        var document = model.document
        document.update(id) { $0.text = textView.string }
        model.setLive(document)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            // ⇧Return (or ⌥Return) starts a new line; Return puts the text down.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                endTextEditing()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.insertTab(_:)):
            endTextEditing()
            return true
        default:
            return false
        }
    }

    /// Typing keeps its own undo history; the document gets one step when the text is put down.
    func undoManager(for view: NSTextView) -> UndoManager? {
        textUndo
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let fine: CGFloat = scale
        let coarse: CGFloat = 10 * scale
        let step: CGFloat = flags.contains(.shift) ? coarse : fine
        switch event.keyCode {
        case 53: escape()
        case 36, 76: returnKey()
        case 51, 117: model.deleteSelection()
        case 123: model.nudgeSelection(by: -step, 0)
        case 124: model.nudgeSelection(by: step, 0)
        case 125: model.nudgeSelection(by: 0, step)
        case 126: model.nudgeSelection(by: 0, -step)
        case 49:
            if !event.isARepeat, gesture == nil {
                spaceHeld = true
                updateCursor()
            }
        default:
            guard flags.subtracting(.shift).isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() else { return }
            if flags.isEmpty, let tool = EditorTool(key: key) {
                model.choose(tool)
            } else if flags.isEmpty, let digit = Int(key), (1...MarkColour.palette.count).contains(digit) {
                model.setColour(MarkColour.palette[digit - 1])
            } else if key == "[" {
                model.setSize(model.shownSize.smaller)
            } else if key == "]" {
                model.setSize(model.shownSize.larger)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else { return super.keyUp(with: event) }
        spaceHeld = false
        updateCursor()
    }

    private func escape() {
        if gesture != nil, let start = gestureStart {
            gesture = nil
            gestureStart = nil
            marquee = nil
            model.setLive(start)
            needsDisplay = true
        } else if model.tool == .crop {
            model.cancelCrop()
        } else if !model.selection.isEmpty {
            model.selection = []
        }
    }

    private func returnKey() {
        if model.tool == .crop {
            model.applyCrop()
        } else {
            model.perform(.done)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if key == "w", flags == .command {
            onClose?()
            return true
        }
        // While typing, the text field and the Edit menu have these.
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let plain = flags == .command
        let shifted = flags == [.command, .shift]
        switch key {
        case "z" where plain: model.undo()
        case "z" where shifted: model.redo()
        case "c" where plain: model.perform(.copy)
        case "s" where plain: model.perform(.save)
        case "a" where plain: model.selectAll()
        case "d" where plain: model.duplicateSelection()
        case "v" where plain: pasteImage()
        case "=", "+": zoom(by: 1.25)
        case "-" where plain: zoom(by: 0.8)
        case "0" where plain: zoomToFit()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Edit menu

    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    @objc func copy(_ sender: Any?) { model.perform(.copy) }
    @objc func paste(_ sender: Any?) { pasteImage() }
    @objc func delete(_ sender: Any?) { model.deleteSelection() }
    override func selectAll(_ sender: Any?) { model.selectAll() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): model.undoManager.canUndo
        case #selector(redo(_:)): model.undoManager.canRedo
        case #selector(delete(_:)): !model.selection.isEmpty
        case #selector(NSText.cut(_:)): false
        default: true
        }
    }

    /// ⌘V with an image on the pasteboard adds it as a mark, centred in view and at most half its size.
    private func pasteImage() {
        guard let picture = NSImage(pasteboard: .general),
              let bitmap = picture.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]) else {
            NSSound.beep()
            return
        }
        let visible = visibleImageRect
        let width = CGFloat(bitmap.width)
        let height = CGFloat(bitmap.height)
        let factor: CGFloat = min(1, visible.width * 0.5 / max(width, 1), visible.height * 0.5 / max(height, 1))
        let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
        let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
        var mark = model.newMark(.image, at: origin)
        mark.end = CGPoint(x: origin.x + size.width, y: origin.y + size.height)
        mark.imageData = data
        model.add(mark)
    }
}

/// Takes typing for a text mark. The renderer draws the text itself, so this view draws only the
/// caret and selection, and what you type looks exactly like the result.
final class MarkTextView: NSTextView {
    static func make() -> MarkTextView {
        let storage = NSTextStorage()
        let layoutManager = GlyphlessLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 1_000_000, height: 1_000_000))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        let view = MarkTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.focusRingType = .none
        view.usesFindBar = false
        view.selectedTextAttributes = [.backgroundColor: EditorCanvas.accent.withAlphaComponent(0.35)]
        return view
    }
}

/// Lays text out but leaves the glyphs to the renderer.
final class GlyphlessLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {}
}

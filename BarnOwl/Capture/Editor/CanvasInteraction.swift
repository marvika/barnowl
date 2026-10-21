import AppKit

extension NSPasteboard.PasteboardType {
    /// Marks cut from one capture, to paste into this or another.
    static let barnOwlMarks = NSPasteboard.PasteboardType("io.github.marvika.barnowl.marks")
}

extension EditorCanvas {
    // MARK: Hover and cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
                                               .cursorUpdate]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        hover(at: imagePoint(event))
    }

    override func mouseExited(with event: NSEvent) {
        hoverTask?.cancel()
        hoverPoint = nil
        hoverMark = nil
        fitPreview = nil
        redrawChrome()
    }

    func topmost(at point: CGPoint) -> Mark? {
        MarkGeometry.topmost(in: model.document, at: point, tolerance: 8 * screenPoint, scale: scale)
    }

    private func hover(at point: CGPoint) {
        hoverPoint = point
        let hit = topmost(at: point)
        let changed = hit?.id != hoverMark || fitPreview != nil || picksColour
        hoverMark = hit?.id
        fitPreview = nil
        hoverTask?.cancel()
        let fits: Set<EditorTool> = [.rectangle, .ellipse, .spotlight, .highlighter, .redact]
        if hit == nil, fits.contains(model.tool), model.insight != nil, model.review == nil, gesture == nil {
            // A faint preview of what a click would fit, after a short rest.
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self, self.hoverPoint == point else { return }
                self.fitPreview = self.model.fitTarget(at: point)
                self.redrawChrome()
            }
        }
        cursor.set()
        if changed { redrawChrome() }
    }

    var cursor: NSCursor {
        if spaceHeld { return .openHand }
        if picksColour { return .crosshair }
        switch model.tool {
        case .select:
            return .arrow
        case .crop:
            return .crosshair
        case .text:
            if let id = hoverMark, let mark = model.document[id], mark.kind != .text { return .openHand }
            return .iBeam
        default:
            if let id = hoverMark, let mark = model.document[id], movesWithDrawingTool(mark) { return .openHand }
            return .crosshair
        }
    }

    func updateCursor() {
        window?.invalidateCursorRects(for: self)
        cursor.set()
    }

    /// Hovering a mark with a drawing tool picks it up rather than drawing over it; effects
    /// (highlights, redactions) only with their own tool, so you can draw over them.
    private func movesWithDrawingTool(_ mark: Mark) -> Bool {
        guard let kind = model.tool.markKind else { return false }
        if mark.kind.isEffect { return mark.kind == kind }
        return true
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        hoverTask?.cancel()
        fitPreview = nil
        labelArmed = nil
        if model.editingText != nil { endTextEditing() }
        window?.makeFirstResponder(self)
        let point = imagePoint(event)
        gestureStart = model.document
        lastPoint = point
        dragged = false
        guides = []
        if spaceHeld, let clip = enclosingScrollView?.contentView {
            gesture = .pan(from: event.locationInWindow, origin: clip.bounds.origin)
            NSCursor.closedHand.set()
            return
        }
        if picksColour {
            pickColour(at: point)
            return
        }
        if model.tool == .crop {
            beginCrop(at: point)
            return
        }
        if model.review != nil {
            if let item = model.review?.items.first(where: { $0.finding.rect.contains(point) }) {
                model.review?.toggle(item.id)
            }
            return
        }
        let hit = topmost(at: point)
        if event.clickCount == 2, let hit {
            if hit.kind == .text {
                beginTextEditing(hit.id)
                return
            }
            if hit.kind == .counter {
                beginLabelEditing(hit.id, typing: nil)
                return
            }
        }
        if let (mark, handle) = handle(at: point) {
            gesture = .adjust(mark, handle)
            return
        }
        let duplicate = event.modifierFlags.contains(.option)
        switch model.tool {
        case .select:
            if let hit {
                if event.modifierFlags.contains(.shift) {
                    if model.selection.contains(hit.id) { model.selection.remove(hit.id) } else { model.selection.insert(hit.id) }
                } else if !model.selection.contains(hit.id) {
                    model.selection = [hit.id]
                }
                beginMove(from: point, duplicate: duplicate)
            } else {
                let base = event.modifierFlags.contains(.shift) ? model.selection : []
                model.selection = base
                gesture = .marquee(from: point, base: base)
            }
        case .text:
            if let hit {
                if !model.selection.contains(hit.id) { model.selection = [hit.id] }
                beginMove(from: point, duplicate: duplicate)
            } else {
                placeText(at: point)
            }
        default:
            if let hit, movesWithDrawingTool(hit) {
                if !model.selection.contains(hit.id) { model.selection = [hit.id] }
                beginMove(from: point, duplicate: duplicate)
            } else if model.tool == .highlighter, let insight = model.insight,
                      SmartFit.highlights(from: point, to: point, insight: insight) != nil {
                model.selection = []
                gesture = .words(from: point, ids: [])
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
        if let start = lastPoint, !dragged, MarkGeometry.distance(start, point) > 2 * screenPoint { dragged = true }
        lastPoint = point
        let flags = event.modifierFlags
        update(gesture, to: point, constrained: flags.contains(.shift), snaps: !flags.contains(.command))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            gesture = nil
            gestureStart = nil
            marquee = nil
            guides = []
            redrawChrome()
        }
        guard let gesture, let before = gestureStart else { return }
        switch gesture {
        case .draw(let id, let origin):
            finishDrawing(id, origin: origin, before: before)
        case .words(_, let ids):
            if ids.isEmpty {
                model.setLive(before)
                if let point = lastPoint { model.placeFitted(at: point) }
            } else {
                model.commit(from: before, "Highlight")
                model.selection = Set(ids)
            }
        case .move(let originals, _, _):
            if !dragged, model.tool == .text, originals.count == 1, let mark = originals.values.first, mark.kind == .text {
                model.setLive(before)
                beginTextEditing(mark.id)
                return
            }
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
        let flags = event.modifierFlags
        update(gesture, to: lastPoint, constrained: flags.contains(.shift), snaps: !flags.contains(.command))
    }

    /// The handle under `point` on the one selected mark.
    private func handle(at point: CGPoint) -> (Mark, MarkHandle)? {
        guard model.selection.count == 1, let id = model.selection.first, let mark = model.document[id] else { return nil }
        let reach: CGFloat = 7 * screenPoint
        let handles = MarkGeometry.handles(for: mark, scale: scale)
        guard let entry = handles.first(where: { MarkGeometry.distance($0.point, point) <= reach }) else { return nil }
        return (mark, entry.handle)
    }

    private func beginMove(from point: CGPoint, duplicate: Bool) {
        var originals: [UUID: Mark] = [:]
        for mark in model.selectedMarks { originals[mark.id] = mark }
        gesture = .move(originals, from: point, duplicate: duplicate)
    }

    private func beginDrawing(at point: CGPoint) {
        guard let kind = model.tool.markKind else { return }
        model.selection = []
        var mark = model.newMark(kind, at: point)
        if kind == .pen { mark.points = [point] }
        var document = model.document
        document.marks.append(mark)
        model.setLive(document)
        model.selection = [mark.id]
        gesture = .draw(mark.id, origin: point)
    }

    private func update(_ gesture: Gesture, to point: CGPoint, constrained: Bool, snaps: Bool) {
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
                if mark.kind == .arrow, mark.style.curved {
                    mark.control = MarkGeometry.defaultBend(start: mark.start, end: mark.end)
                }
            }
            model.setLive(document)
        case .words(let from, _):
            guard let before = gestureStart, let insight = model.insight else { return }
            let rects = SmartFit.highlights(from: from, to: point, insight: insight) ?? []
            var document = before
            var ids: [UUID] = []
            for rect in rects {
                var mark = model.newMark(.highlighter, at: rect.origin)
                mark.end = CGPoint(x: rect.maxX, y: rect.maxY)
                mark.origin = MarkOrigin(source: .fit, category: nil)
                document.marks.append(mark)
                ids.append(mark.id)
            }
            self.gesture = .words(from: from, ids: ids)
            model.setLive(document)
        case .move(var originals, let from, let duplicate):
            guard dragged else { return }
            if duplicate {
                // ⌥-drag leaves the originals where they were and moves copies.
                var copies: [UUID: Mark] = [:]
                var document = model.document
                for mark in originals.values {
                    var copy = mark
                    copy.id = UUID()
                    copies[copy.id] = copy
                    document.marks.append(copy)
                }
                model.setLive(document)
                model.selection = Set(copies.keys)
                originals = copies
                self.gesture = .move(copies, from: from, duplicate: false)
            }
            var dx: CGFloat = point.x - from.x
            var dy: CGFloat = point.y - from.y
            if constrained {
                if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
            }
            guides = []
            if snaps {
                let moving = originals.values.reduce(CGRect.null) { $0.union(MarkGeometry.bounds($1, scale: scale)) }
                let others = model.document.marks.filter { originals[$0.id] == nil && !$0.kind.isEffect }
                var targets: [CGRect] = [model.document.crop]
                targets += others.map { MarkGeometry.bounds($0, scale: scale) }
                let snap = SnapEngine.snap(moving.offsetBy(dx: dx, dy: dy), to: targets, threshold: 5 * screenPoint)
                dx += snap.offset.x
                dy += snap.offset.y
                guides = snap.guides
            }
            var document = model.document
            for (id, original) in originals {
                document.update(id) { $0 = MarkGeometry.moved(original, by: dx, dy) }
            }
            model.setLive(document)
            redrawChrome()
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
            redrawChrome()
        case .crop(let handle, let from, let original):
            model.cropDraft = croppedRect(original, handle: handle, from: from, to: point, constrained: constrained)
        case .pan:
            break
        }
    }

    private func finishDrawing(_ id: UUID, origin: CGPoint, before: EditorDocument) {
        if let lastPoint, model.document[id]?.kind == .pen {
            var document = model.document
            document.update(id) { mark in
                if mark.points.last != lastPoint { mark.points.append(lastPoint) }
            }
            model.setLive(document)
        }
        guard let mark = model.document[id] else { return }
        let largeEnough: Bool = switch mark.kind {
        case .counter, .pen, .text: true
        case .arrow: dragged
        default: dragged && mark.rect.width >= 3 * screenPoint && mark.rect.height >= 3 * screenPoint
        }
        guard largeEnough else {
            // A click: fit to the text or window under it, if there's one.
            model.setLive(before)
            model.selection = []
            model.placeFitted(at: origin)
            return
        }
        model.commit(from: before, "Add \(mark.kind.title)")
        if mark.kind == .counter {
            labelArmed = id
        } else if model.selectsAfterDrawing {
            model.choose(.select)
        }
    }

    private func pickColour(at point: CGPoint) {
        picksColour = false
        updateCursor()
        redrawChrome()
        guard let colour = ImageSampler.colour(at: point, in: model.image) else { return }
        model.setColour(colour)
        model.noteRecent(colour)
    }

    /// I: the next click takes its colour from the capture.
    func startPickingColour() {
        picksColour = true
        updateCursor()
        redrawChrome()
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
        if let ratio = model.cropAspect.value(imageSize: bounds.size) {
            rect = Self.fitted(rect, ratio: ratio, handle: handle, original: original)
        } else if constrained {
            rect = MarkGeometry.squared(rect, handle: handle, from: original)
        }
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull else { return original }
        return CGRect(x: clipped.minX.rounded(), y: clipped.minY.rounded(),
                      width: clipped.width.rounded(), height: clipped.height.rounded())
    }

    /// `rect` with its height following its width at `ratio`, anchored opposite the handle.
    static func fitted(_ rect: CGRect, ratio: CGFloat, handle: MarkHandle, original: CGRect) -> CGRect {
        let height: CGFloat = rect.width / ratio
        let topAnchored: Bool = switch handle {
        case .topLeft, .topRight, .top: false
        default: true
        }
        let y: CGFloat = topAnchored ? rect.minY : rect.maxY - height
        return CGRect(x: rect.minX, y: y, width: rect.width, height: height)
    }

    /// The crop with its proportions set to `aspect`, as large as fits in the current one.
    func applyCropAspect(_ aspect: CropAspect) {
        model.cropAspect = aspect
        guard let draft = model.cropDraft, let ratio = aspect.value(imageSize: model.document.imageSize) else { return }
        var width: CGFloat = draft.width
        var height: CGFloat = width / ratio
        if height > draft.height {
            height = draft.height
            width = height * ratio
        }
        let x: CGFloat = draft.midX - width / 2
        let y: CGFloat = draft.midY - height / 2
        model.cropDraft = CGRect(x: x, y: y, width: width, height: height).integral
    }

    // MARK: Text

    private func placeText(at point: CGPoint) {
        model.selection = []
        var mark = model.newMark(.text, at: point)
        // The caret lands where you clicked: the box starts up and to the left of it.
        let probe = MarkGeometry.textLayout(mark, scale: scale)
        let insetX: CGFloat = probe.textRect.minX - probe.boxRect.minX
        let insetY: CGFloat = probe.textRect.minY - probe.boxRect.minY
        mark.start = CGPoint(x: point.x - insetX, y: point.y - insetY - probe.lineHeight / 2)
        mark.end = mark.start
        let before = model.document
        var document = before
        document.marks.append(mark)
        model.setLive(document)
        beginTextEditing(mark.id, before: before)
    }

    /// Opens the text mark for typing; `before` is the document to undo back to.
    func beginTextEditing(_ id: UUID, before: EditorDocument? = nil) {
        openTextView(for: id, label: false, before: before, typing: nil)
    }

    /// Opens a counter's label for typing, starting with what was just typed.
    func beginLabelEditing(_ id: UUID, typing: String?) {
        openTextView(for: id, label: true, before: nil, typing: typing)
    }

    private func openTextView(for id: UUID, label: Bool, before: EditorDocument?, typing: String?) {
        guard let mark = model.document[id] else { return }
        if model.editingText != nil { endTextEditing() }
        labelArmed = nil
        textBefore = before ?? model.document
        textUndo = UndoManager()
        editsLabel = label
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
        if let typing { textView.insertText(typing, replacementRange: textView.selectedRange()) }
        redrawMarks()
        redrawChrome()
    }

    /// Puts the typed text down: one undo step, and an empty text mark goes away.
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
        if let mark = model.document[id], mark.kind == .text,
           mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var document = model.document
            document.remove([id])
            model.setLive(document)
            model.selection.remove(id)
        }
        model.commit(from: before, editsLabel ? "Label" : "Text")
        editsLabel = false
        window?.makeFirstResponder(self)
        redrawMarks()
        redrawChrome()
    }

    /// Keeps the text field over its mark, at the mark's size, as both change.
    func syncTextView() {
        guard let textView, let id = model.editingText, let mark = model.document[id] else { return }
        let rect: CGRect
        let font: NSFont
        let caret: MarkColour
        let lineHeight: CGFloat
        let alignment: NSTextAlignment
        if editsLabel {
            let tag = MarkGeometry.counterLabel(mark, scale: scale)
            rect = tag.textRect
            font = tag.font as NSFont
            lineHeight = MarkGeometry.lineHeight(tag.font)
            caret = mark.colour.boxFill.textOnFill
            alignment = .left
        } else {
            let layout = MarkGeometry.textLayout(mark, scale: scale)
            rect = layout.textRect
            font = MarkGeometry.font(mark.style.font, weight: mark.style.fontWeight, size: CGFloat(mark.style.fontSize) * scale)
            lineHeight = layout.lineHeight
            caret = AnnotationRenderer.textColours(mark).text
            alignment = switch mark.style.align {
            case .left: .left
            case .centre: .center
            case .right: .right
            }
        }
        // The field works in canvas points; the scroll view zooms it with everything else.
        let pointFont = NSFont(descriptor: font.fontDescriptor, size: font.pointSize / scale) ?? font
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight / scale
        paragraph.maximumLineHeight = lineHeight / scale
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [.font: pointFont, .paragraphStyle: paragraph]
        if textView.font != pointFont || textView.defaultParagraphStyle != paragraph {
            textView.font = pointFont
            textView.defaultParagraphStyle = paragraph
            textView.typingAttributes = attributes
            if let storage = textView.textStorage {
                storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            }
        }
        let frame = viewRect(fromImage: rect)
        textView.frame = NSRect(x: frame.minX, y: frame.minY, width: frame.width + 2, height: frame.height)
        textView.insertionPointColor = NSColor(cgColor: caret.cgColor()) ?? .labelColor
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
            // Return starts a new line in text; a label is one line, so it puts it down.
            if editsLabel {
                endTextEditing()
                return true
            }
            textView.insertNewlineIgnoringFieldEditor(nil)
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
        let step: CGFloat = flags.contains(.shift) ? 10 * scale : scale
        switch event.keyCode {
        case 53: escape()
        case 36, 76: returnKey(command: flags.contains(.command))
        case 51, 117: model.deleteSelection()
        case 48:
            if let armed = labelArmed {
                beginLabelEditing(armed, typing: nil)
            } else {
                model.selectNext(backwards: flags.contains(.shift))
            }
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
            if let armed = labelArmed, flags.subtracting(.shift).isEmpty, let typed = event.characters, !typed.isEmpty,
               typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                // A counter just placed takes typing as its label.
                beginLabelEditing(armed, typing: typed)
                return
            }
            if let command = Self.bareCommand(for: event) {
                onCommand?(command)
                return
            }
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else { return super.keyUp(with: event) }
        spaceHeld = false
        updateCursor()
    }

    /// A plain key's command, for when no menu caught it.
    @MainActor static func bareCommand(for event: NSEvent) -> EditorCommand.ID? {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty, let typed = event.characters, !typed.isEmpty else { return nil }
        return EditorCommand.all.first { $0.isBareKey && $0.key == typed }?.id
    }

    /// Esc steps back: a drag, a colour pick, then the model's own steps.
    func escape() {
        if gesture != nil, let start = gestureStart {
            gesture = nil
            gestureStart = nil
            marquee = nil
            guides = []
            model.setLive(start)
            redrawChrome()
            return
        }
        if picksColour {
            picksColour = false
            updateCursor()
            redrawChrome()
            return
        }
        labelArmed = nil
        if model.escape() == .close { onClose?() }
    }

    private func returnKey(command: Bool) {
        if command {
            onCommand?(.done)
            return
        }
        switch model.returnStep() {
        case .applyCrop: model.applyCrop()
        case .hideReviewed: model.applyReview()
        case .done: onCommand?(.done)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        // Undo mid-drag would pull the document out from under the gesture.
        if gesture != nil, key == "z" { return true }
        if key == "=", flags == .command, window?.firstResponder === self {
            onCommand?(.zoomIn)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Edit menu

    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    @objc func copy(_ sender: Any?) { model.perform(.copy) }
    @objc func delete(_ sender: Any?) { model.deleteSelection() }
    override func selectAll(_ sender: Any?) { model.selectAll() }

    @objc func cut(_ sender: Any?) {
        let marks = model.selectedMarks
        guard !marks.isEmpty, let data = try? JSONEncoder().encode(marks) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .barnOwlMarks)
        if let text = marks.compactMap({ $0.kind == .text ? $0.text : nil }).first {
            pasteboard.setString(text, forType: .string)
        }
        model.deleteSelection()
    }

    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .barnOwlMarks), let marks = try? JSONDecoder().decode([Mark].self, from: data) {
            let offset: CGFloat = 12 * scale
            let copies: [Mark] = marks.map { mark in
                var copy = MarkGeometry.moved(mark, by: offset, offset)
                copy.id = UUID()
                return copy
            }
            model.add(copies, name: "Paste")
            return
        }
        pasteImage()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return gesture == nil && model.canUndo
        case #selector(redo(_:)): return gesture == nil && model.undoManager.canRedo
        case #selector(delete(_:)), #selector(cut(_:)): return !model.selection.isEmpty
        case #selector(paste(_:)):
            let types: [NSPasteboard.PasteboardType] = [.barnOwlMarks, .png, .tiff]
            return NSPasteboard.general.availableType(from: types) != nil
        default: return true
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
        var mark = Mark(kind: .image, colour: .white, start: origin, end: CGPoint(x: origin.x + size.width, y: origin.y + size.height))
        mark.imageData = data
        model.add(mark)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = imagePoint(event)
        guard model.cropDraft == nil, let hit = topmost(at: point) else { return nil }
        if model.editingText != nil { endTextEditing() }
        if !model.selection.contains(hit.id) { model.selection = [hit.id] }
        return MarkMenu(canvas: self).make()
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
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.focusRingType = .none
        view.usesFindBar = false
        view.selectedTextAttributes = [.backgroundColor: EditorCanvas.accent.withAlphaComponent(0.35)]
        view.setAccessibilityLabel("Text")
        return view
    }
}

/// Lays text out but leaves the glyphs to the renderer.
final class GlyphlessLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {}
}

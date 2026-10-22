import AppKit
import Foundation
import Testing
@testable import BarnOwl

@MainActor
struct CaptureEditorTests {
    static func image(width: Int = 400, height: Int = 300, grey: CGFloat = 0.96) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: grey, green: grey, blue: grey + 0.01, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "CaptureEditorTests-\(UUID().uuidString)")!
    }

    static func model(scale: CGFloat = 1, defaults: UserDefaults? = nil, insight: CaptureInsight? = nil) -> EditorModel {
        EditorModel(image: image(), scale: scale, insight: insight, defaults: defaults ?? Self.defaults())
    }

    static func mark(_ kind: Mark.Kind, _ start: CGPoint, _ end: CGPoint, colour: MarkColour = .red) -> Mark {
        Mark(kind: kind, colour: colour, style: StyleBook.defaultStyle(for: kind), start: start, end: end)
    }

    static func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01
    }

    // MARK: Arrows

    @Test func arrowOutlineIsClosedAndCoversItsEnds() {
        let tail = CGPoint(x: 20, y: 100)
        let tip = CGPoint(x: 220, y: 40)
        let path = MarkGeometry.arrowOutline(from: tail, to: tip, control: nil, width: 10, doubleHeaded: false)
        var closes = 0
        var last: CGPathElementType?
        path.applyWithBlock { element in
            if element.pointee.type == .closeSubpath { closes += 1 }
            last = element.pointee.type
        }
        #expect(closes == 1)
        #expect(last == .closeSubpath)

        let d = MarkGeometry.normalized(CGPoint(x: tip.x - tail.x, y: tip.y - tail.y))
        let n = CGPoint(x: -d.y, y: d.x)
        func along(_ origin: CGPoint, _ distance: CGFloat, across: CGFloat = 0) -> CGPoint {
            CGPoint(x: origin.x + d.x * distance + n.x * across, y: origin.y + d.y * distance + n.y * across)
        }
        #expect(path.contains(along(tip, -4)))
        #expect(path.contains(along(tail, 2)))
        // Fine at the tail, full width into the head, and the head 1.55 widths each side.
        #expect(!path.contains(along(tail, 4, across: 3)))
        #expect(path.contains(along(tip, -40, across: 4)))
        #expect(path.contains(along(tip, -28, across: 13.5)))
        #expect(!path.contains(along(tip, -28, across: 16)))
        #expect(!path.contains(along(tip, -100, across: 12)))
    }

    @Test func curvedAndDoubleHeadedArrowsFollowTheirShape() {
        let start = CGPoint(x: 0, y: 100)
        let end = CGPoint(x: 300, y: 100)
        let control = CGPoint(x: 150, y: -60)
        let curved = MarkGeometry.arrowOutline(from: start, to: end, control: control, width: 10, doubleHeaded: false)
        #expect(curved.contains(MarkGeometry.quadratic(start, control, end, at: 0.5)))
        #expect(!curved.contains(CGPoint(x: 150, y: 100)))

        let double = MarkGeometry.arrowOutline(from: start, to: end, control: nil, width: 10, doubleHeaded: true)
        #expect(double.contains(CGPoint(x: 4, y: 100)))
        #expect(double.contains(CGPoint(x: 296, y: 100)))
        #expect(double.contains(CGPoint(x: 20, y: 110)))
        #expect(double.contains(CGPoint(x: 280, y: 110)))
    }

    @Test func bendHandleCurvesTheArrowAndSnapsBackStraight() {
        let arrow = Self.mark(.arrow, CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0))
        let bent = MarkGeometry.adjusted(arrow, handle: .bend, to: CGPoint(x: 100, y: -40), constrained: false)
        #expect(bent.control != nil)
        #expect(Self.close(MarkGeometry.arrowMidpoint(bent), CGPoint(x: 100, y: -40)))
        let straight = MarkGeometry.adjusted(bent, handle: .bend, to: CGPoint(x: 101, y: 1), constrained: false)
        #expect(straight.control == nil)
    }

    @Test func aLineIsAnArrowWithoutHeads() {
        var line = Self.mark(.arrow, CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50))
        line.style.heads = .none
        #expect(MarkGeometry.hitTest(line, at: CGPoint(x: 50, y: 52), tolerance: 8, scale: 1))
        #expect(!MarkGeometry.hitTest(line, at: CGPoint(x: 50, y: 70), tolerance: 8, scale: 1))
        // No head: its bounds hug the line.
        #expect(MarkGeometry.bounds(line, scale: 1).height < 1)
    }

    // MARK: Hit testing and order

    @Test func strokedMarksHitOnTheStrokeAndFilledOnesInside() {
        let corners = (CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        let rectangle = Self.mark(.rectangle, corners.0, corners.1)
        var filled = Self.mark(.rectangle, corners.0, corners.1)
        filled.style.fill = .solid
        let ellipse = Self.mark(.ellipse, corners.0, corners.1)
        let centre = CGPoint(x: 200, y: 150)
        let onEdge = CGPoint(x: 100, y: 150)

        #expect(MarkGeometry.hitTest(rectangle, at: onEdge, tolerance: 8, scale: 1))
        #expect(!MarkGeometry.hitTest(rectangle, at: centre, tolerance: 8, scale: 1))
        #expect(MarkGeometry.hitTest(filled, at: centre, tolerance: 8, scale: 1))
        #expect(MarkGeometry.hitTest(ellipse, at: onEdge, tolerance: 8, scale: 1))
        #expect(!MarkGeometry.hitTest(ellipse, at: centre, tolerance: 8, scale: 1))
        #expect(!MarkGeometry.hitTest(rectangle, at: CGPoint(x: 112, y: 150), tolerance: 8, scale: 1))
        #expect(MarkGeometry.hitTest(rectangle, at: CGPoint(x: 112, y: 150), tolerance: 32, scale: 1))
    }

    @Test func effectsDrawUnderEverythingAndTheRestInArrayOrder() {
        var document = EditorDocument(imageSize: CGSize(width: 400, height: 300))
        var box = Self.mark(.rectangle, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100))
        box.style.fill = .solid
        var text = Self.mark(.text, CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 10))
        text.text = "Hello"
        let redaction = Self.mark(.redact, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100))
        let highlight = Self.mark(.highlighter, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 20))
        document.marks = [redaction, box, text, highlight]
        #expect(document.drawingOrder.map(\.id) == [highlight.id, redaction.id, box.id, text.id])
        #expect(MarkGeometry.topmost(in: document, at: CGPoint(x: 15, y: 20), tolerance: 8, scale: 1)?.id == text.id)
        #expect(MarkGeometry.topmost(in: document, at: CGPoint(x: 90, y: 90), tolerance: 8, scale: 1)?.id == box.id)
        #expect(MarkGeometry.topmost(in: document, at: CGPoint(x: 200, y: 200), tolerance: 8, scale: 1) == nil)
    }

    @Test func arrangeMovesMarksWithinTheirOrder() {
        let model = Self.model()
        let marks = (0..<4).map { Self.mark(.rectangle, CGPoint(x: $0 * 10, y: 0), CGPoint(x: $0 * 10 + 50, y: 50)) }
        for mark in marks { model.add(mark) }
        let ids = marks.map(\.id)
        model.selection = [ids[0]]
        model.bringToFront()
        #expect(model.document.marks.map(\.id) == [ids[1], ids[2], ids[3], ids[0]])
        model.sendBackward()
        #expect(model.document.marks.map(\.id) == [ids[1], ids[2], ids[0], ids[3]])
        model.sendToBack()
        #expect(model.document.marks.map(\.id) == [ids[0], ids[1], ids[2], ids[3]])
        model.bringForward()
        #expect(model.document.marks.map(\.id) == [ids[1], ids[0], ids[2], ids[3]])
        model.undo()
        #expect(model.document.marks.map(\.id) == ids)
    }

    // MARK: Selection

    @Test func severalMarksAlignWithEachOtherAndOneWithTheImage() {
        let model = Self.model()
        let a = Self.mark(.rectangle, CGPoint(x: 40, y: 20), CGPoint(x: 100, y: 60))
        let b = Self.mark(.rectangle, CGPoint(x: 150, y: 100), CGPoint(x: 230, y: 160))
        model.add(a)
        model.add(b)
        model.selection = [a.id, b.id]
        model.align(.left)
        #expect(model.document[a.id]?.rect.minX == 40)
        #expect(model.document[b.id]?.rect.minX == 40)
        model.align(.bottom)
        #expect(model.document[a.id]?.rect.maxY == 160)
        model.undo()
        model.undo()
        #expect(model.document[b.id]?.rect.minX == 150)

        // One mark lines up with the image: centred in 400 × 300.
        model.selection = [a.id]
        model.align(.centre)
        model.align(.middle)
        #expect(model.document[a.id]?.rect.midX == 200)
        #expect(model.document[a.id]?.rect.midY == 150)
    }

    @Test func movingSnapsToEdgesAndCentresWithinTheThreshold() {
        let image = CGRect(x: 0, y: 0, width: 400, height: 300)
        let other = CGRect(x: 250, y: 40, width: 100, height: 50)
        // 3 px from the other mark's left edge: snaps, with a vertical guide there.
        let near = SnapEngine.snap(CGRect(x: 253, y: 150, width: 40, height: 30), to: [image, other], threshold: 5)
        #expect(near.offset.x == -3)
        #expect(near.guides.contains { $0.axis == .vertical && $0.position == 250 })
        // Its centre near the image's centre line.
        let centred = SnapEngine.snap(CGRect(x: 178, y: 10, width: 40, height: 30), to: [image], threshold: 5)
        #expect(centred.offset.x == 2)
        // Too far: nothing moves, no guides.
        let far = SnapEngine.snap(CGRect(x: 120, y: 100, width: 40, height: 33), to: [image, other], threshold: 5)
        #expect(far.offset == .zero)
        #expect(far.guides.isEmpty)
    }

    @Test func tabCyclesThroughMarks() {
        let model = Self.model()
        let marks = (0..<3).map { Self.mark(.ellipse, CGPoint(x: $0 * 60, y: 0), CGPoint(x: $0 * 60 + 40, y: 40)) }
        for mark in marks { model.add(mark) }
        model.selection = []
        model.selectNext(backwards: false)
        #expect(model.selection == [marks[0].id])
        model.selectNext(backwards: false)
        #expect(model.selection == [marks[1].id])
        model.selectNext(backwards: true)
        model.selectNext(backwards: true)
        #expect(model.selection == [marks[2].id])
    }

    // MARK: Counters

    @Test func countersRenumberFormatAndStartWhereYouSay() {
        let model = Self.model()
        let counters = (0..<3).map { Self.mark(.counter, CGPoint(x: 40 + $0 * 60, y: 40), CGPoint(x: 40 + $0 * 60, y: 40)) }
        for counter in counters { model.add(counter) }
        #expect(model.document.counterNumbers[counters[2].id] == 3)
        model.selection = [counters[1].id]
        model.deleteSelection()
        #expect(model.document.counterNumbers[counters[2].id] == 2)
        model.undo()
        #expect(model.document.counterNumbers[counters[2].id] == 3)

        model.setCounterStart(4)
        #expect(model.document.counterNumbers[counters[0].id] == 4)
        #expect(CounterFormat.upper.label(1) == "A")
        #expect(CounterFormat.upper.label(28) == "AB")
        #expect(CounterFormat.lower.label(3) == "c")
        #expect(CounterFormat.roman.label(14) == "XIV")
    }

    @Test func aCounterLabelTravelsWithItsBadge() {
        var counter = Self.mark(.counter, CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 100))
        let bare = MarkGeometry.bounds(counter, scale: 2)
        counter.text = "Open Settings"
        let tag = MarkGeometry.counterLabel(counter, scale: 2)
        let labelled = MarkGeometry.bounds(counter, scale: 2)
        #expect(labelled.width > bare.width * 3)
        #expect(tag.pill.minX == 100)
        #expect(abs(tag.pill.midY - 100) < 0.01)
        #expect(MarkGeometry.hitTest(counter, at: CGPoint(x: tag.pill.maxX - 4, y: 100), tolerance: 8, scale: 2))
        let moved = MarkGeometry.moved(counter, by: 30, 10)
        #expect(MarkGeometry.counterLabel(moved, scale: 2).pill.minX == 130)
        #expect(moved.text == "Open Settings")
    }

    @Test func aCalloutPointsWhereItsHandleIs() {
        let model = Self.model()
        var text = Self.mark(.text, CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 100))
        text.text = "Look here"
        model.add(text)
        model.selection = [text.id]
        #expect(MarkGeometry.handles(for: model.document[text.id]!, scale: 1).isEmpty)
        // Switching to Callout gives it somewhere to point, below the box.
        model.updateStyle { $0.textStyle = .callout }
        let callout = model.document[text.id]!
        let box = MarkGeometry.textLayout(callout, scale: 1).boxRect
        #expect(callout.end.y > box.maxY)
        #expect(MarkGeometry.handles(for: callout, scale: 1).map(\.handle) == [.end])
        #expect(MarkGeometry.bounds(callout, scale: 1).maxY == callout.end.y)
        // On the pointer, a third of the way back from its tip to the box.
        let tailY: CGFloat = callout.end.y - (callout.end.y - box.maxY) * 0.3
        let onTail = CGPoint(x: callout.end.x, y: tailY)
        #expect(MarkGeometry.hitTest(callout, at: onTail, tolerance: 8, scale: 1))
        let moved = MarkGeometry.adjusted(callout, handle: .end, to: CGPoint(x: 300, y: 40), constrained: false)
        #expect(moved.end == CGPoint(x: 300, y: 40))
        #expect(moved.start == callout.start)
    }

    // MARK: Style memory

    @Test func onePenColourIsSharedAndHighlighterAndRedactionKeepTheirOwn() {
        let defaults = Self.defaults()
        let model = Self.model(defaults: defaults)
        #expect(model.tool == .arrow)
        #expect(model.shownColour == .red)
        model.setColour(.blue)
        for tool in [EditorTool.rectangle, .ellipse, .text, .counter, .pen] {
            model.choose(tool)
            #expect(model.shownColour == .blue)
        }
        model.choose(.highlighter)
        #expect(model.shownColour == .yellow)
        model.setColour(MarkColour.highlighterPalette[1])
        model.choose(.redact)
        #expect(model.shownColour == .ink)
        model.choose(.arrow)
        #expect(model.shownColour == .blue)

        // Remembered for the next capture, tool included.
        let again = Self.model(defaults: defaults)
        #expect(again.tool == .arrow)
        #expect(again.shownColour == .blue)
        #expect(again.styleBook.highlighterColour == MarkColour.highlighterPalette[1])
    }

    @Test func sizeAndStyleAreRememberedPerKind() {
        let model = Self.model()
        model.choose(.text)
        model.updateStyle { $0.textStyle = .outline }
        model.stepSize(up: true)
        #expect(model.shownStyle.fontSize == 24)
        model.choose(.rectangle)
        #expect(model.shownStyle.weight == 4)
        model.stepSize(up: true)
        #expect(model.shownStyle.weight == 6)
        model.choose(.text)
        #expect(model.shownStyle.textStyle == .outline)
        #expect(model.shownStyle.fontSize == 24)
        model.choose(.arrow)
        #expect(model.shownStyle.weight == 5.5)
    }

    @Test func changingASelectedMarkTeachesItsKindNotTheTool() {
        let model = Self.model()
        model.choose(.arrow)
        var text = Self.mark(.text, CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 20))
        text.text = "Hi"
        model.add(text)
        model.selection = [text.id]
        model.updateStyle { $0.fontSize = 32 }
        model.setColour(.green)
        #expect(model.document[text.id]?.style.fontSize == 32)
        #expect(model.document[text.id]?.colour == .green)
        #expect(model.styleBook.style(for: .text).fontSize == 32)
        // The pen colour follows; the arrow's size doesn't change.
        #expect(model.styleBook.penColour == .green)
        #expect(model.styleBook.style(for: .arrow).weight == 5.5)

        // A highlight selected: its colour goes to the highlighter, not the pen.
        let highlight = Self.mark(.highlighter, CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 120), colour: .yellow)
        model.add(highlight)
        model.selection = [highlight.id]
        model.setColour(MarkColour.highlighterPalette[2])
        #expect(model.styleBook.highlighterColour == MarkColour.highlighterPalette[2])
        #expect(model.styleBook.penColour == .green)
    }

    @Test func customColoursBecomeRecents() {
        var book = StyleBook()
        book.remember(colour: .lavender, for: .arrow)
        #expect(book.recents.isEmpty)
        for value in 0..<10 { book.remember(colour: MarkColour(red: Double(value) / 10, green: 0.2, blue: 0.3), for: .arrow) }
        #expect(book.recents.count == StyleBook.recentLimit)
        #expect(book.recents.first == MarkColour(red: 0.9, green: 0.2, blue: 0.3))
    }

    @Test func sizesStepThroughTheLadders() {
        #expect(SizeLadder.step(4, in: SizeLadder.steps(for: .rectangle), up: true) == 6)
        #expect(SizeLadder.step(4, in: SizeLadder.steps(for: .rectangle), up: false) == 2.5)
        #expect(SizeLadder.step(16, in: SizeLadder.steps(for: .pen), up: true) == 16)
        #expect(SizeLadder.step(20, in: SizeLadder.textSizes, up: true) == 24)
        #expect(SizeLadder.step(13, in: SizeLadder.textSizes, up: false) == 12)
        #expect(SizeLadder.presets(for: .arrow) == [3.5, 5.5, 8, 11])
        #expect(SizeLadder.presets(for: .counter) == [22, 28, 36, 46])
    }

    // MARK: Colour

    @Test func textColourIsChosenByContrastRatio() {
        #expect(abs(MarkColour.white.contrast(with: .white) - 1) < 0.001)
        #expect(MarkColour.white.contrast(with: MarkColour(hex: 0x000000)) > 20.9)
        // Deeper fills keep white text at 4.5:1 or better.
        for colour in [MarkColour.red, .green, .blue, .lavender] {
            #expect(colour.boxFill.textOnFill == .white)
            #expect(colour.boxFill.contrast(with: .white) >= 4.5)
        }
        // Light fills take ink.
        for colour in [MarkColour.amber, .yellow, .white] {
            #expect(colour.boxFill.textOnFill == .ink)
        }
        #expect(MarkColour.ink.textOnFill == .white)
        // A mid green where white only reaches about 2:1 takes ink.
        #expect(MarkColour(hex: 0x30D158).textOnFill == .ink)
        // Halos: ink under yellow and white, white under the rest.
        #expect(MarkColour.yellow.isLight)
        #expect(MarkColour.white.isLight)
        #expect(!MarkColour.amber.isLight)
        #expect(!MarkColour.red.isLight)
    }

    @Test func softTextReadsOnItsTint() {
        for colour in MarkColour.palette {
            var mark = Self.mark(.text, .zero, .zero, colour: colour)
            mark.style.textStyle = .soft
            let colours = AnnotationRenderer.textColours(mark)
            #expect(colours.text.contrast(with: colours.box ?? .white) >= 4.5)
        }
    }

    @Test func redactionBarsTakeTheTextsColour() {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 200, height: 60, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.15, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 60))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        for index in 0..<8 { context.fill(CGRect(x: 10 + index * 22, y: 20, width: 6, height: 20)) }
        let image = context.makeImage()!
        let colour = ImageSampler.redactionColour(in: image, rect: CGRect(x: 0, y: 0, width: 200, height: 60))
        #expect(colour.luminance > 0.8)
        // Nothing but background: ink.
        let plain = Self.image()
        #expect(ImageSampler.redactionColour(in: plain, rect: CGRect(x: 0, y: 0, width: 50, height: 50)) == .ink)
    }

    @Test func highlightsLightenDarkAreasInsteadOfVanishing() {
        let dark = AnnotationRenderer(image: Self.image(grey: 0.1), scale: 1)
        let light = AnnotationRenderer(image: Self.image(grey: 0.95), scale: 1)
        let rect = CGRect(x: 20, y: 20, width: 100, height: 30)
        #expect(dark.highlightScreens(rect))
        #expect(!light.highlightScreens(rect))
    }

    // MARK: Keys

    @Test func escStepsBackOneThingAtATime() {
        let model = Self.model()
        let box = Self.mark(.rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
        // Unchanged: the steps run out at Select, then Esc closes.
        model.choose(.crop)
        #expect(model.escape() == .leftCrop)
        #expect(model.tool == .arrow)
        #expect(model.escape() == .choseSelect)
        #expect(model.escape() == .close)

        model.choose(.rectangle)
        model.add(box)
        model.editingText = box.id
        var ended = false
        model.endTextEditing = { ended = true }
        #expect(model.escape() == .finishedText)
        #expect(ended)
        model.review = PrivateInfoReview(items: [])
        #expect(model.escape() == .cancelledReview)
        #expect(model.escape() == .deselected)
        #expect(model.selection.isEmpty)
        #expect(model.escape() == .choseSelect)
        // Changed: Esc explains how to close instead of closing.
        #expect(model.escape() == .explained)
        #expect(model.transientHint != nil)
    }

    @Test func returnFinishesOnlyWhenNothingElseIsGoingOn() {
        let model = Self.model()
        #expect(model.returnStep() == .done)
        model.choose(.crop)
        #expect(model.returnStep() == .applyCrop)
        model.cancelCrop()
        model.review = PrivateInfoReview(items: [])
        #expect(model.returnStep() == .hideReviewed)
        model.review = nil
        #expect(model.returnStep() == .done)
        // ⌘Return is Done in the menu, whatever's going on.
        #expect(EditorCommand.command(.done)?.key == "\r")
        #expect(EditorCommand.command(.done)?.modifiers == .command)
    }

    @Test func plainKeysPickToolsAndColours() {
        func key(_ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: characters, charactersIgnoringModifiers: characters.lowercased(),
                             isARepeat: false, keyCode: 0)!
        }
        #expect(EditorCanvas.bareCommand(for: key("a")) == .arrow)
        #expect(EditorCanvas.bareCommand(for: key("l")) == .line)
        #expect(EditorCanvas.bareCommand(for: key("B", .shift)) == .review)
        #expect(EditorCanvas.bareCommand(for: key("3")) == .colour3)
        #expect(EditorCanvas.bareCommand(for: key("]")) == .bigger)
        #expect(EditorCanvas.bareCommand(for: key("?", .shift)) == .shortcuts)
        #expect(EditorCanvas.bareCommand(for: key("a", .command)) == nil)
        // Every plain key belongs to one command.
        let keys = EditorCommand.all.filter(\.isBareKey).map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test func arrowNudgesAreOneUndoStep() {
        let model = Self.model()
        let box = Self.mark(.rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
        model.add(box)
        let before = model.document
        model.nudgeSelection(by: 1, 0)
        model.nudgeSelection(by: 1, 0)
        model.nudgeSelection(by: 0, 10)
        model.flushNudge()
        #expect(model.document[box.id]?.start == CGPoint(x: 12, y: 20))
        model.undo()
        #expect(model.document == before)
    }

    // MARK: Smart tools

    static func insight() -> CaptureInsight {
        func words(_ line: CGRect, _ texts: [String]) -> [CaptureText.Word] {
            let width: CGFloat = line.width / CGFloat(texts.count)
            return texts.enumerated().map { index, text in
                let rect = CGRect(x: line.minX + CGFloat(index) * width, y: line.minY, width: width - 6, height: line.height)
                return CaptureText.Word(rect: rect, text: text)
            }
        }
        let first = CGRect(x: 40, y: 40, width: 200, height: 16)
        let second = CGRect(x: 40, y: 62, width: 160, height: 16)
        let lines = [
            CaptureText.Line(rect: first, text: "Send the report to", words: words(first, ["Send", "the", "report", "to"])),
            CaptureText.Line(rect: second, text: "me@example.com today", words: words(second, ["me@example.com", "today"])),
        ]
        let email = SensitiveTextFinder.Finding(rect: CGRect(x: 36, y: 60, width: 80, height: 20), kind: .email,
                                                text: "me@example.com")
        let key = SensitiveTextFinder.Finding(rect: CGRect(x: 40, y: 200, width: 150, height: 20), kind: .key,
                                              text: "ghp_abcdefghijklmnopqrstuvwxyz0123456789")
        let address = SensitiveTextFinder.Finding(rect: CGRect(x: 250, y: 200, width: 80, height: 20), kind: .ipAddress,
                                                  text: "8.8.8.8")
        let text = CaptureText(lines: lines, blocks: [first.union(second)], findings: [email, key, address])
        return CaptureInsight(text: text, windowRects: [CGRect(x: 20, y: 20, width: 360, height: 260)], textWasRead: true)
    }

    @Test func aClickFitsTheTextBlockOrTheWindowUnderIt() {
        let insight = Self.insight()
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let block = SmartFit.box(at: CGPoint(x: 60, y: 50), insight: insight, padding: 6, within: bounds)
        #expect(block == CGRect(x: 34, y: 34, width: 212, height: 50))
        // Outside the text, inside the window: the window, with the same room around it.
        let window = SmartFit.box(at: CGPoint(x: 300, y: 250), insight: insight, padding: 6, within: bounds)
        #expect(window == CGRect(x: 14, y: 14, width: 372, height: 272))
        #expect(SmartFit.box(at: CGPoint(x: 5, y: 5), insight: insight, padding: 6, within: bounds) == nil)

        // The highlighter takes the line; Redact the whole finding, or the word.
        let line = SmartFit.line(at: CGPoint(x: 100, y: 70), insight: insight)
        #expect(line.map { $0.minY < 62 && $0.maxY > 78 } == true)
        #expect(SmartFit.redaction(at: CGPoint(x: 60, y: 70), insight: insight)?.finding?.kind == .email)
        let word = SmartFit.redaction(at: CGPoint(x: 165, y: 48), insight: insight)
        #expect(word?.finding == nil)
        #expect(word.map { $0.rect.minX > 130 && $0.rect.maxX < 200 } == true)
    }

    @Test func aHighlighterDragGoesWordByWordOnePerLine() {
        let insight = Self.insight()
        let rects = SmartFit.highlights(from: CGPoint(x: 100, y: 48), to: CGPoint(x: 60, y: 70), insight: insight) ?? []
        #expect(rects.count == 2)
        // From "the" to the end of line one, then the first word of line two.
        #expect(rects[0].minX > 80 && rects[0].maxX > 220)
        #expect(rects[1].minX < 45 && rects[1].maxX < 130)
        #expect(SmartFit.highlights(from: CGPoint(x: 300, y: 150), to: CGPoint(x: 60, y: 70), insight: insight) == nil)
    }

    @Test func hidePrivateInfoBlursLightlyInOneStep() {
        let model = Self.model(insight: Self.insight())
        #expect(model.visibleSecrets.count == 1)
        #expect(model.privateCount == 2)
        #expect(model.asksAboutSecretsOnDone)
        model.beginReview()
        #expect(model.tool == .redact)
        let review = model.review
        #expect(review?.items.count == 3)
        // Keys and emails are in; IP addresses are offered, not included.
        #expect(review?.includedCount == 2)
        #expect(review?.categories.first?.kind == .key)
        let before = model.document
        model.applyReview()
        #expect(model.review == nil)
        let hidden = model.document.marks
        #expect(hidden.count == 2)
        // The Redact tool's own style: a light blur out of the box.
        #expect(hidden.allSatisfy { $0.kind == .redact && $0.style.redact == .blur && $0.style.strength == .light })
        #expect(Set(hidden.compactMap(\.origin?.category)) == ["key", "email"])
        #expect(hidden.allSatisfy { $0.origin?.source == .privateInfo })
        #expect(model.visibleSecrets.isEmpty)
        #expect(!model.asksAboutSecretsOnDone)
        model.undo()
        #expect(model.document == before)
    }

    @Test func aClickWithAShapeToolPlacesAFittedMark() {
        let model = Self.model(insight: Self.insight())
        model.choose(.rectangle)
        let mark = model.placeFitted(at: CGPoint(x: 60, y: 50))
        #expect(mark?.rect == CGRect(x: 34, y: 34, width: 212, height: 50))
        #expect(mark?.origin?.source == .fit)
        model.choose(.arrow)
        #expect(model.placeFitted(at: CGPoint(x: 60, y: 50)) == nil)
        // No scan yet: nothing to fit.
        let early = Self.model()
        early.choose(.rectangle)
        #expect(early.placeFitted(at: CGPoint(x: 60, y: 50)) == nil)
        early.update(insight: Self.insight())
        #expect(early.placeFitted(at: CGPoint(x: 60, y: 50)) != nil)
    }

    // MARK: Crop and frame

    @Test func frameLayoutAddsPaddingAndGrowsToTheRatio() {
        let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
        var frame = FrameSettings(background: .gradient(.dawn), padding: 50)
        var layout = FrameLayout(crop: crop, frame: frame)
        #expect(layout.canvasSize == CGSize(width: 500, height: 400))
        #expect(layout.imageRect == CGRect(x: 50, y: 50, width: 400, height: 300))
        frame.ratio = .wide
        layout = FrameLayout(crop: crop, frame: frame)
        #expect(layout.canvasSize == CGSize(width: 712, height: 400))
        frame.ratio = .square
        layout = FrameLayout(crop: crop, frame: frame)
        #expect(layout.canvasSize == CGSize(width: 500, height: 500))
        let plain = FrameLayout(crop: CGRect(x: 10, y: 20, width: 200, height: 100), frame: FrameSettings(padding: 50, ratio: .square))
        #expect(plain.canvasSize == CGSize(width: 200, height: 100))
        #expect(plain.offset == CGPoint(x: -10, y: -20))
    }

    @Test func croppingKeepsMarksInImageCoordinates() {
        let model = Self.model()
        let arrow = Self.mark(.arrow, CGPoint(x: 150, y: 120), CGPoint(x: 250, y: 180))
        model.add(arrow)
        model.choose(.crop)
        #expect(model.cropDraft == model.document.imageBounds)
        model.cropDraft = CGRect(x: 100, y: 100, width: 200, height: 100)
        model.applyCrop()
        #expect(model.cropDraft == nil)
        #expect(model.tool == .arrow)
        #expect(model.document.crop == CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(model.document[arrow.id]?.start == arrow.start)
        #expect(model.renderer.render(model.document)?.width == 200)
        model.undo()
        #expect(model.document.crop == model.document.imageBounds)
    }

    @Test func cancellingACropLeavesTheImageAlone() {
        let model = Self.model()
        model.choose(.crop)
        model.cropDraft = CGRect(x: 10, y: 10, width: 50, height: 50)
        model.cancelCrop()
        #expect(model.document.crop == model.document.imageBounds)
        #expect(!model.undoManager.canUndo)
        #expect(!model.isEdited)
    }

    // MARK: Undo and change count

    @Test func undoAndRedoRoundTripAndCountChanges() {
        let model = Self.model()
        let original = model.document
        let box = Self.mark(.rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
        model.add(box)
        let added = model.document
        model.setColour(.blue)
        let recoloured = model.document
        #expect(recoloured[box.id]?.colour == .blue)
        #expect(model.changeCount == 2)
        model.undo()
        #expect(model.document == added)
        model.undo()
        #expect(model.document == original)
        #expect(!model.isEdited)
        model.redo()
        model.redo()
        #expect(model.document == recoloured)
        #expect(model.isEdited)
    }

    @Test func aDragIsOneUndoStep() {
        let model = Self.model()
        let box = Self.mark(.rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
        model.add(box)
        let before = model.document
        for _ in 1...5 {
            var document = model.document
            document.update(box.id) { $0 = MarkGeometry.moved($0, by: 3, 1) }
            model.setLive(document)
        }
        model.commit(from: before, "Move")
        #expect(model.document[box.id]?.start == CGPoint(x: 25, y: 15))
        model.undo()
        #expect(model.document == before)
    }

    @Test func duplicatesAreOffsetAndSelected() {
        let model = Self.model(scale: 2)
        let line = Self.mark(.arrow, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
        model.add(line)
        model.duplicateSelection()
        #expect(model.document.marks.count == 2)
        let copy = model.document.marks[1]
        #expect(copy.id != line.id)
        #expect(model.selection == [copy.id])
        #expect(copy.start == CGPoint(x: 34, y: 34))
    }

    // MARK: Rendering

    @Test func renderMatchesTheImageOrTheFrame() async {
        let image = Self.image(width: 320, height: 200)
        let renderer = AnnotationRenderer(image: image, scale: 2)
        var document = EditorDocument(imageSize: CGSize(width: 320, height: 200), scale: 2)
        var text = Self.mark(.text, CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 20))
        text.text = "Look 👀\nTwo lines"
        var pixelate = Self.mark(.redact, CGPoint(x: 200, y: 120), CGPoint(x: 300, y: 180))
        pixelate.style.redact = .pixelate
        var blur = Self.mark(.redact, CGPoint(x: 10, y: 120), CGPoint(x: 120, y: 180))
        blur.style.redact = .blur
        var counter = Self.mark(.counter, CGPoint(x: 280, y: 40), CGPoint(x: 280, y: 40))
        counter.text = "Label"
        document.marks = [
            Self.mark(.arrow, CGPoint(x: 40, y: 160), CGPoint(x: 160, y: 60)), text, pixelate, blur, counter,
            Self.mark(.spotlight, CGPoint(x: 100, y: 40), CGPoint(x: 220, y: 110)),
            Self.mark(.highlighter, CGPoint(x: 20, y: 60), CGPoint(x: 140, y: 80)),
        ]
        let plain = renderer.render(document)
        #expect(plain?.width == 320)
        #expect(plain?.height == 200)
        #expect(plain?.colorSpace?.name == CGColorSpace.sRGB)

        document.frame.background = .gradient(.dusk)
        document.frame.padding = 40
        let framed = renderer.render(document)
        #expect(framed?.width == 400)
        #expect(framed?.height == 280)
    }

    @Test func theEditorRendersOffTheMainThreadAndReportsWhenItCloses() async {
        let host = RecordingHost()
        var document = EditorDocument(imageSize: CGSize(width: 400, height: 300), scale: 1)
        document.frame.background = .solid(.white)
        document.frame.padding = 20
        let editor = CaptureEditor(image: Self.image(), scale: 1, title: "Test", document: document, insight: nil, host: host)
        let image = await editor.render()
        #expect(image?.width == 440)
        #expect(image?.height == 340)
        editor.model.add(Self.mark(.ellipse, CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 60)))
        editor.close()
        #expect(host.changes.last?.marks.count == 1)
        #expect(host.closed == [true])
    }

    // MARK: Saving

    @Test func documentsSurviveEncodingWithEveryField() throws {
        var document = EditorDocument(imageSize: CGSize(width: 100, height: 80))
        var arrow = Self.mark(.arrow, CGPoint(x: 1, y: 2), CGPoint(x: 50, y: 60))
        arrow.control = CGPoint(x: 30, y: 5)
        arrow.style.heads = .both
        arrow.style.dash = .dotted
        arrow.style.opacity = 0.5
        var text = Self.mark(.text, CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5))
        text.text = "Two\nlines"
        text.style.font = .named("Avenir-Heavy")
        text.style.fontWeight = .bold
        text.style.align = .centre
        text.style.textStyle = .soft
        var counter = Self.mark(.counter, .zero, .zero)
        counter.style.counterFormat = .roman
        counter.text = "Label"
        var redaction = Self.mark(.redact, .zero, CGPoint(x: 10, y: 10))
        redaction.origin = MarkOrigin(source: .privateInfo, category: "key")
        var pen = Self.mark(.pen, .zero, .zero)
        pen.points = [CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 9)]
        document.marks = [arrow, text, counter, redaction, pen]
        document.crop = CGRect(x: 5, y: 5, width: 60, height: 40)
        document.frame.background = .desktop
        document.frame.ratio = .portrait
        document.counterStart = 3
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(EditorDocument.self, from: data)
        #expect(decoded == document)
        #expect(decoded.schemaVersion == 2)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["schemaVersion"] as? Int == 2)
    }

    @Test func documentsWithMissingFieldsStillOpen() throws {
        let json = """
        {"imageSize":[100,80],"marks":[{"kind":"arrow","start":[1,2],"style":{"weight":8}}]}
        """
        let document = try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8))
        #expect(document.crop == CGRect(x: 0, y: 0, width: 100, height: 80))
        #expect(document.marks.first?.style.weight == 8)
        #expect(document.marks.first?.style.heads == .end)
        #expect(document.marks.first?.colour == .red)
        #expect(document.frame.background == FrameBackground.none)
    }

    @Test func reopeningKeepsMarksEditable() {
        var document = EditorDocument(imageSize: CGSize(width: 400, height: 300))
        document.marks = [Self.mark(.rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50))]
        let model = EditorModel(image: Self.image(), scale: 1, document: document, defaults: Self.defaults())
        #expect(model.document.marks.count == 1)
        #expect(!model.isEdited)
        model.selection = [document.marks[0].id]
        model.deleteSelection()
        #expect(model.document.marks.isEmpty)
        model.undo()
        #expect(model.document.marks.count == 1)
    }
}

@MainActor
private final class RecordingHost: CaptureEditorHost {
    var changes: [EditorDocument] = []
    var closed: [Bool] = []

    func editor(_ editor: CaptureEditor, copy image: CGImage) {}
    func editor(_ editor: CaptureEditor, save image: CGImage) async -> URL? { nil }
    func editor(_ editor: CaptureEditor, pin image: CGImage) {}
    func editor(_ editor: CaptureEditor, finish image: CGImage) {}
    func editor(_ editor: CaptureEditor, didChange document: EditorDocument) { changes.append(document) }
    func editorDidClose(_ editor: CaptureEditor, edited: Bool) { closed.append(edited) }
}

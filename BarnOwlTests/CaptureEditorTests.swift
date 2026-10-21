import AppKit
import Foundation
import Testing
@testable import BarnOwl

@MainActor
struct CaptureEditorTests {
    static func image(width: Int = 400, height: Int = 300) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func model(scale: CGFloat = 1, defaults: UserDefaults? = nil) -> EditorModel {
        EditorModel(image: image(), scale: scale,
                    defaults: defaults ?? UserDefaults(suiteName: "CaptureEditorTests-\(UUID().uuidString)")!)
    }

    static func mark(_ kind: Mark.Kind, _ start: CGPoint, _ end: CGPoint) -> Mark {
        Mark(kind: kind, colour: .amber, size: .medium, start: start, end: end)
    }

    static func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01
    }

    // MARK: Arrows

    @Test func arrowOutlineIsClosedAndCoversItsEnds() {
        let tail = CGPoint(x: 20, y: 100)
        let tip = CGPoint(x: 220, y: 40)
        let width: CGFloat = 10
        let path = MarkGeometry.arrowOutline(from: tail, to: tip, control: nil, width: width, doubleHeaded: false)
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
        // Just behind the tip, and just ahead of the tail.
        #expect(path.contains(along(tip, -4)))
        #expect(path.contains(along(tail, 2)))
        // Fine at the tail, full width into the head, and the head wider still.
        #expect(!path.contains(along(tail, 4, across: 3)))
        #expect(path.contains(along(tip, -40, across: 4)))
        #expect(path.contains(along(tip, -28, across: 12)))
        #expect(!path.contains(along(tip, -100, across: 12)))
        #expect(!path.contains(CGPoint(x: 120, y: 200)))
    }

    @Test func curvedAndDoubleHeadedArrowsFollowTheirShape() {
        let start = CGPoint(x: 0, y: 100)
        let end = CGPoint(x: 300, y: 100)
        let control = CGPoint(x: 150, y: -60)
        let curved = MarkGeometry.arrowOutline(from: start, to: end, control: control, width: 10, doubleHeaded: false)
        let middle = MarkGeometry.quadratic(start, control, end, at: 0.5)
        #expect(curved.contains(middle))
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

    // MARK: Hit testing

    @Test func strokedMarksHitOnTheStrokeAndFilledOnesInside() {
        let corners = (CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        let rectangle = Self.mark(.rectangle, corners.0, corners.1)
        let box = Self.mark(.filledBox, corners.0, corners.1)
        let ellipse = Self.mark(.ellipse, corners.0, corners.1)
        let centre = CGPoint(x: 200, y: 150)
        let onEdge = CGPoint(x: 100, y: 150)

        #expect(MarkGeometry.hitTest(rectangle, at: onEdge, tolerance: 8, scale: 1))
        #expect(MarkGeometry.hitTest(rectangle, at: CGPoint(x: 103, y: 150), tolerance: 8, scale: 1))
        #expect(!MarkGeometry.hitTest(rectangle, at: centre, tolerance: 8, scale: 1))
        #expect(MarkGeometry.hitTest(box, at: centre, tolerance: 8, scale: 1))
        #expect(MarkGeometry.hitTest(ellipse, at: onEdge, tolerance: 8, scale: 1))
        #expect(!MarkGeometry.hitTest(ellipse, at: centre, tolerance: 8, scale: 1))

        // The band is at least the tolerance wide, which grows as you zoom out.
        let nearby = CGPoint(x: 112, y: 150)
        #expect(!MarkGeometry.hitTest(rectangle, at: nearby, tolerance: 8, scale: 1))
        #expect(MarkGeometry.hitTest(rectangle, at: nearby, tolerance: 32, scale: 1))

        let line = Self.mark(.line, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        #expect(MarkGeometry.hitTest(line, at: CGPoint(x: 50, y: 3), tolerance: 8, scale: 1))
        #expect(!MarkGeometry.hitTest(line, at: CGPoint(x: 50, y: 10), tolerance: 8, scale: 1))
    }

    @Test func clicksFindTheTopmostMark() {
        let box = Self.mark(.filledBox, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100))
        var text = Self.mark(.text, CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 10))
        text.text = "Hello"
        let redaction = Self.mark(.redact, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100))
        // Text draws above boxes, which draw above redactions, whatever order they were added in.
        let marks = [text, box, redaction]
        #expect(MarkGeometry.topmost(in: marks, at: CGPoint(x: 15, y: 20), tolerance: 8, scale: 1)?.id == text.id)
        #expect(MarkGeometry.topmost(in: marks, at: CGPoint(x: 90, y: 90), tolerance: 8, scale: 1)?.id == box.id)
        #expect(MarkGeometry.topmost(in: marks, at: CGPoint(x: 200, y: 200), tolerance: 8, scale: 1) == nil)
    }

    // MARK: Counters

    @Test func countersRenumberAfterDeletion() {
        let model = Self.model()
        let counters = (0..<3).map { Self.mark(.counter, CGPoint(x: 40 + $0 * 60, y: 40), CGPoint(x: 40 + $0 * 60, y: 40)) }
        for counter in counters { model.add(counter) }
        #expect(model.document.counterNumbers[counters[2].id] == 3)

        model.selection = [counters[1].id]
        model.deleteSelection()
        #expect(model.document.counterNumbers[counters[0].id] == 1)
        #expect(model.document.counterNumbers[counters[2].id] == 2)

        model.undo()
        #expect(model.document.counterNumbers[counters[1].id] == 2)
        #expect(model.document.counterNumbers[counters[2].id] == 3)
    }

    // MARK: Frame

    @Test func frameLayoutAddsPaddingAndGrowsToTheRatio() {
        let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
        var frame = FrameSettings(background: .gradient(.dawn), padding: 50)
        var layout = FrameLayout(crop: crop, frame: frame)
        #expect(layout.canvasSize == CGSize(width: 500, height: 400))
        #expect(layout.imageRect == CGRect(x: 50, y: 50, width: 400, height: 300))

        // 500 × 400 is narrower than 16:9, so it widens to 400 × 16/9, rounded up.
        frame.ratio = .wide
        layout = FrameLayout(crop: crop, frame: frame)
        #expect(layout.canvasSize == CGSize(width: 712, height: 400))
        #expect(layout.imageRect.origin == CGPoint(x: 156, y: 50))

        frame.ratio = .square
        layout = FrameLayout(crop: crop, frame: frame)
        #expect(layout.canvasSize == CGSize(width: 500, height: 500))
        #expect(layout.imageRect.origin == CGPoint(x: 50, y: 100))

        // Without a frame, padding and ratio don't apply.
        let plain = FrameLayout(crop: CGRect(x: 10, y: 20, width: 200, height: 100), frame: FrameSettings(padding: 50, ratio: .square))
        #expect(plain.canvasSize == CGSize(width: 200, height: 100))
        #expect(plain.offset == CGPoint(x: -10, y: -20))
    }

    // MARK: Crop

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
        let layout = FrameLayout(document: model.document)
        #expect(layout.canvasPoint(fromImage: arrow.start) == CGPoint(x: 50, y: 20))
        let renderer = AnnotationRenderer(image: model.image, scale: model.scale)
        #expect(renderer.render(model.document)?.width == 200)

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
    }

    // MARK: Undo

    @Test func undoAndRedoRoundTrip() {
        let model = Self.model()
        let original = model.document
        let box = Self.mark(.rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
        model.add(box)
        let added = model.document
        model.nudgeSelection(by: 10, 0)
        let moved = model.document
        model.setColour(.coral)
        let recoloured = model.document
        #expect(recoloured[box.id]?.colour == .coral)

        model.undo()
        #expect(model.document == moved)
        model.undo()
        #expect(model.document == added)
        model.undo()
        #expect(model.document == original)
        #expect(!model.undoManager.canUndo)

        model.redo()
        #expect(model.document == added)
        model.redo()
        #expect(model.document == moved)
        model.redo()
        #expect(model.document == recoloured)
    }

    @Test func aDragIsOneUndoStep() {
        let model = Self.model()
        let box = Self.mark(.filledBox, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
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
        model.redo()
        #expect(model.document[box.id]?.start == CGPoint(x: 25, y: 15))
    }

    @Test func duplicatesAreOffsetAndSelected() {
        let model = Self.model(scale: 2)
        let line = Self.mark(.line, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60))
        model.add(line)
        model.duplicateSelection()
        #expect(model.document.marks.count == 2)
        let copy = model.document.marks[1]
        #expect(copy.id != line.id)
        #expect(model.selection == [copy.id])
        #expect(copy.start == CGPoint(x: 34, y: 34))
    }

    // MARK: Rendering

    @Test func renderMatchesTheImageOrTheFrame() {
        let image = Self.image(width: 320, height: 200)
        let renderer = AnnotationRenderer(image: image, scale: 2)
        var document = EditorDocument(imageSize: CGSize(width: 320, height: 200), scale: 2)
        var text = Self.mark(.text, CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 20))
        text.text = "Look 👀"
        var pixelate = Self.mark(.redact, CGPoint(x: 200, y: 120), CGPoint(x: 300, y: 180))
        pixelate.style.redact = .pixelate
        var blur = Self.mark(.redact, CGPoint(x: 10, y: 120), CGPoint(x: 120, y: 180))
        blur.style.redact = .blur
        document.marks = [
            Self.mark(.arrow, CGPoint(x: 40, y: 160), CGPoint(x: 160, y: 60)), text, pixelate, blur,
            Self.mark(.counter, CGPoint(x: 280, y: 40), CGPoint(x: 280, y: 40)),
            Self.mark(.spotlight, CGPoint(x: 100, y: 40), CGPoint(x: 220, y: 110)),
            Self.mark(.highlighter, CGPoint(x: 20, y: 60), CGPoint(x: 140, y: 80)),
        ]
        let plain = renderer.render(document)
        #expect(plain?.width == 320)
        #expect(plain?.height == 200)
        #expect(plain?.colorSpace?.name == image.colorSpace?.name)

        document.frame.background = .gradient(.dusk)
        document.frame.padding = 40
        let framed = renderer.render(document)
        #expect(framed?.width == 400)
        #expect(framed?.height == 280)
    }

    // MARK: Saving

    @Test func documentsSurviveEncoding() throws {
        var document = EditorDocument(imageSize: CGSize(width: 100, height: 80))
        var arrow = Self.mark(.arrow, CGPoint(x: 1, y: 2), CGPoint(x: 50, y: 60))
        arrow.control = CGPoint(x: 30, y: 5)
        arrow.style.arrow = .double
        var pen = Self.mark(.pen, .zero, .zero)
        pen.points = [CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 9)]
        document.marks = [arrow, pen]
        document.crop = CGRect(x: 5, y: 5, width: 60, height: 40)
        document.frame.background = .solid(.coral)
        document.frame.ratio = .standard
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(EditorDocument.self, from: data) == document)
    }

    @Test func toolsRememberTheirColourSizeAndStyle() {
        let defaults = UserDefaults(suiteName: "CaptureEditorTests-\(UUID().uuidString)")!
        let model = Self.model(defaults: defaults)
        model.choose(.text)
        model.setColour(.lavender)
        model.setSize(.large)
        model.setStyle { $0.text = .outline }
        model.choose(.arrow)
        #expect(model.colour == .amber)
        #expect(model.size == .medium)

        let again = Self.model(defaults: defaults)
        #expect(again.tool == .arrow)
        again.choose(.text)
        #expect(again.colour == .lavender)
        #expect(again.size == .large)
        #expect(again.style.text == .outline)
        #expect(defaults.data(forKey: "captureEditor.tool.text") != nil)
    }
}

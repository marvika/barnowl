import AppKit
import Foundation
import Testing
@testable import BarnOwl

/// Drives the real canvas with mouse and key events, offscreen.
@MainActor
struct CaptureEditorCanvasTests {
    let controller: EditorWindowController
    var model: EditorModel { controller.model }
    var canvas: EditorCanvas { controller.canvas }

    init() {
        let defaults = UserDefaults(suiteName: "CaptureEditorCanvasTests-\(UUID().uuidString)")!
        let image = CaptureEditorTests.image(width: 800, height: 500)
        let model = EditorModel(image: image, scale: 2, insight: CaptureEditorTests.insight(), defaults: defaults)
        controller = EditorWindowController(model: model, title: "Test")
        let window = controller.window!
        window.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        controller.canvas.setZoom(1)
    }

    /// Where an image point is, in the window.
    func windowPoint(_ point: CGPoint) -> NSPoint {
        canvas.convert(canvas.viewPoint(fromImage: point), to: nil)
    }

    func mouse(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: windowPoint(point), modifierFlags: flags, timestamp: 0,
                           windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
                           pressure: 1)!
    }

    func drag(from start: CGPoint, to end: CGPoint, flags: NSEvent.ModifierFlags = []) {
        canvas.mouseDown(with: mouse(.leftMouseDown, start, flags: flags))
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, middle, flags: flags))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, end, flags: flags))
        canvas.mouseUp(with: mouse(.leftMouseUp, end, flags: flags))
    }

    func click(_ point: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) {
        canvas.mouseDown(with: mouse(.leftMouseDown, point, flags: flags, clicks: clicks))
        canvas.mouseUp(with: mouse(.leftMouseUp, point, flags: flags, clicks: clicks))
    }

    func key(_ characters: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: controller.window!.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    static func near(_ a: CGPoint?, _ b: CGPoint, within tolerance: CGFloat = 3) -> Bool {
        guard let a else { return false }
        return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    @Test func dragDrawsAnArrowAsOneUndoStep() {
        #expect(model.tool == .arrow)
        drag(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 150))
        #expect(model.document.marks.count == 1)
        let arrow = model.document.marks.first
        #expect(arrow?.kind == .arrow)
        #expect(Self.near(arrow?.start, CGPoint(x: 100, y: 300)))
        #expect(Self.near(arrow?.end, CGPoint(x: 300, y: 150)))
        #expect(model.changeCount == 1)
        model.undo()
        #expect(model.document.marks.isEmpty)
    }

    @Test func aClickWithoutADragFitsTheTextUnderIt() {
        model.choose(.rectangle)
        click(CGPoint(x: 60, y: 50))
        #expect(model.document.marks.first?.rect == CGRect(x: 28, y: 28, width: 224, height: 62))
        // A click on nothing smart leaves nothing behind.
        model.choose(.ellipse)
        click(CGPoint(x: 780, y: 480))
        #expect(model.document.marks.count == 1)
    }

    @Test func drawingToolsPickUpMarksAndOptionDragCopies() {
        drag(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        let arrow = model.document.marks[0]
        // Hovering the arrow with the Arrow tool moves it rather than drawing a new one.
        // (Its middle is the bend handle, so take it by its shaft.)
        drag(from: CGPoint(x: 150, y: 300), to: CGPoint(x: 150, y: 340), flags: .command)
        #expect(model.document.marks.count == 1)
        #expect(Self.near(model.document[arrow.id]?.start, CGPoint(x: 100, y: 340)))
        drag(from: CGPoint(x: 150, y: 340), to: CGPoint(x: 150, y: 400), flags: [.option, .command])
        #expect(model.document.marks.count == 2)
        #expect(Self.near(model.document[arrow.id]?.start, CGPoint(x: 100, y: 340)))
        #expect(Self.near(model.document.marks.last?.start, CGPoint(x: 100, y: 400)))
        // The middle handle bends it.
        drag(from: CGPoint(x: 200, y: 400), to: CGPoint(x: 200, y: 440))
        #expect(model.document.marks.last?.control != nil)
    }

    @Test func movingSnapsToTheImageCentre() {
        model.choose(.rectangle)
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 180))
        let box = model.document.marks[0]
        model.choose(.select)
        // The box's centre lands 3 px off the image's centre line (x 400): it snaps there.
        // Taken by its left edge (away from the handles).
        drag(from: CGPoint(x: 100, y: 120), to: CGPoint(x: 347, y: 120))
        #expect(model.document[box.id]?.rect.midX == 400)
        // With ⌘ held, it goes exactly where it's put.
        drag(from: CGPoint(x: 350, y: 120), to: CGPoint(x: 356, y: 120), flags: .command)
        #expect(model.document[box.id]?.rect.midX == 406)
    }

    @Test func marqueeSelectsAndShiftClickToggles() {
        model.choose(.ellipse)
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 160))
        drag(from: CGPoint(x: 300, y: 100), to: CGPoint(x: 360, y: 160))
        model.choose(.select)
        drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 500, y: 200))
        #expect(model.selection.count == 2)
        click(CGPoint(x: 100, y: 130), flags: .shift)
        #expect(model.selection.count == 1)
    }

    @Test func typingPlacesTextAndEscPutsItDown() {
        model.choose(.text)
        click(CGPoint(x: 400, y: 300))
        #expect(model.editingText != nil)
        let field = canvas.textView
        field?.insertText("Hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        field?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        field?.insertText("there", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.document.marks.first?.text == "Hello\nthere")
        canvas.escape()
        #expect(model.editingText == nil)
        #expect(model.document.marks.first?.text == "Hello\nthere")
        // One undo step for the whole text.
        model.undo()
        #expect(model.document.marks.isEmpty)
    }

    @Test func typingSurvivesTheToolbarAskingWhatToShare() {
        model.choose(.text)
        click(CGPoint(x: 400, y: 300))
        // AppKit asks the Share item for its items whenever it checks the toolbar.
        let items = controller.items(for: NSSharingServicePickerToolbarItem(itemIdentifier: .init("share")))
        #expect(items.count == 1)
        #expect(model.editingText != nil)
    }

    @Test func typingRightAfterACounterGivesItALabel() {
        model.choose(.counter)
        click(CGPoint(x: 200, y: 200))
        #expect(model.document.marks.first?.kind == .counter)
        canvas.keyDown(with: key("O"))
        #expect(model.editingText == model.document.marks.first?.id)
        canvas.textView?.insertText("pen", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.textView?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(model.editingText == nil)
        #expect(model.document.marks.first?.text == "Open")
        // A tool key afterwards picks the tool again.
        canvas.keyDown(with: key("a"))
        #expect(model.tool == .arrow)
    }

    @Test func escStepsBackThroughTheCanvas() {
        var closed = false
        canvas.onClose = { closed = true }
        model.choose(.rectangle)
        canvas.keyDown(with: key("\u{1b}", code: 53))
        #expect(model.tool == .select)
        canvas.keyDown(with: key("\u{1b}", code: 53))
        #expect(closed)
    }

    @Test func clicksInReviewToggleWhatWillBeHidden() {
        model.beginReview()
        #expect(model.review?.includedCount == 2)
        click(CGPoint(x: 60, y: 70))
        #expect(model.review?.includedCount == 1)
        canvas.keyDown(with: key("\r", code: 36))
        #expect(model.review == nil)
        #expect(model.document.marks.count == 1)
        #expect(model.document.marks.first?.origin?.category == "key")
    }

    @Test func highlighterDragsWordByWord() {
        model.choose(.highlighter)
        drag(from: CGPoint(x: 100, y: 48), to: CGPoint(x: 60, y: 70))
        #expect(model.document.marks.count == 2)
        #expect(model.document.marks.allSatisfy { $0.kind == .highlighter })
        model.undo()
        #expect(model.document.marks.isEmpty)
    }

    @Test func menusComeFromTheCommandTable() {
        let menu = EditorMenus.makeMainMenu()
        let titles = menu.items.map(\.title)
        #expect(titles == ["Barn Owl", "File", "Edit", "View", "Arrange", "Tools", "Format", "Window"])
        let tools = menu.items.first { $0.title == "Tools" }?.submenu
        let arrow = tools?.items.first { $0.title == "Arrow" }
        #expect(arrow?.keyEquivalent == "a")
        #expect(arrow?.keyEquivalentModifierMask == [])
        let view = menu.items.first { $0.title == "View" }?.submenu
        #expect(view?.items.first { $0.title == "Show Frame" }?.keyEquivalentModifierMask == [.command, .option])
        // Plain keys wait while you type.
        #expect(controller.canPerform(.arrow))
        model.choose(.text)
        click(CGPoint(x: 400, y: 300))
        controller.window?.makeFirstResponder(canvas.textView)
        #expect(!controller.canPerform(.arrow))
        #expect(controller.canPerform(.bold))
    }
}

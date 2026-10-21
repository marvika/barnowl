import AppKit
import Foundation
import Testing
@testable import BarnOwl

/// Keys on every layout, Return after a counter, ⌘+ and ⌘−, Revert, ⌘C, and what the window
/// lets go of when it closes. Drives the real canvas offscreen.
@MainActor
struct CaptureEditorShortcutTests {
    let controller: EditorWindowController
    var model: EditorModel { controller.model }
    var canvas: EditorCanvas { controller.canvas }

    init() {
        let defaults = UserDefaults(suiteName: "CaptureEditorShortcutTests-\(UUID().uuidString)")!
        let image = CaptureEditorTests.image(width: 800, height: 500)
        let model = EditorModel(image: image, scale: 2, insight: CaptureEditorTests.insight(), defaults: defaults)
        controller = EditorWindowController(model: model, title: "Test")
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.canvas.setZoom(1)
    }

    func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewPoint(fromImage: point), to: nil), modifierFlags: [],
                           timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    func click(_ point: CGPoint) {
        canvas.mouseDown(with: mouse(.leftMouseDown, point))
        canvas.mouseUp(with: mouse(.leftMouseUp, point))
    }

    func drag(from start: CGPoint, to end: CGPoint) {
        canvas.mouseDown(with: mouse(.leftMouseDown, start))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
        canvas.mouseUp(with: mouse(.leftMouseUp, end))
    }

    static func key(_ characters: String, _ flags: NSEvent.ModifierFlags = [], code: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters.lowercased(), isARepeat: false,
                         keyCode: code)!
    }

    // MARK: Keys

    @Test func sizeKeysWorkOnEveryLayout() {
        // Norwegian types [ and ] with ⌥8 and ⌥9.
        #expect(EditorCanvas.bareCommand(for: Self.key("[", .option)) == .smaller)
        #expect(EditorCanvas.bareCommand(for: Self.key("]", .option)) == .bigger)
        #expect(EditorCanvas.bareCommand(for: Self.key("-")) == .smaller)
        #expect(EditorCanvas.bareCommand(for: Self.key("+", .shift)) == .bigger)
        #expect(EditorCanvas.bareCommand(for: Self.key("=")) == .bigger)
        // ⌥ with anything else is still not a plain key.
        #expect(EditorCanvas.bareCommand(for: Self.key("ª", .option)) == nil)
        #expect(EditorCanvas.bareCommand(for: Self.key("[", [.option, .command])) == nil)

        let before = model.styleBook.style(for: .arrow).weight
        canvas.keyDown(with: Self.key("[", .option))
        let smaller = model.styleBook.style(for: .arrow).weight
        #expect(smaller < before)
        canvas.keyDown(with: Self.key("+", .shift))
        #expect(model.styleBook.style(for: .arrow).weight > smaller)
    }

    @Test func capsLockDoesNotTurnToolKeysIntoShiftedOnes() {
        #expect(EditorCanvas.bareCommand(for: Self.key("B", .capsLock)) == .redact)
        #expect(EditorCanvas.bareCommand(for: Self.key("A", .capsLock)) == .arrow)
        #expect(EditorCanvas.bareCommand(for: Self.key("B", [.shift, .capsLock])) == .review)
        #expect(EditorCanvas.bareCommand(for: Self.key("B", .shift)) == .review)
    }

    @Test func returnAfterACounterStartsItsLabel() {
        var commands: [EditorCommand.ID] = []
        canvas.onCommand = { commands.append($0) }
        model.choose(.counter)
        click(CGPoint(x: 200, y: 200))
        let counter = model.document.marks.first
        #expect(counter?.kind == .counter)
        canvas.keyDown(with: Self.key("\r", code: 36))
        #expect(model.editingText == counter?.id)
        #expect(commands.isEmpty)
        canvas.textView?.insertText("Open", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.textView?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(model.document.marks.first?.text == "Open")
        // Then Return is Done again.
        canvas.keyDown(with: Self.key("\r", code: 36))
        #expect(commands == [.done])
    }

    @Test func commandPlusZoomsUnlessTextIsInHand() {
        model.choose(.text)
        let zoom = canvas.magnification
        let size = model.styleBook.style(for: .text).fontSize
        controller.perform(.zoomIn)
        #expect(canvas.magnification > zoom)
        #expect(model.styleBook.style(for: .text).fontSize == size)
        controller.perform(.zoomOut)

        var text = CaptureEditorTests.mark(.text, CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 100))
        text.text = "Hello"
        model.add(text)
        let zoomed = canvas.magnification
        controller.perform(.fontBigger)
        #expect(canvas.magnification == zoomed)
        #expect((model.document[text.id]?.style.fontSize ?? 0) > text.style.fontSize)
        // ⌘B still works for the Text tool with nothing selected.
        model.selection = []
        #expect(controller.canPerform(.bold))
    }

    // MARK: Marks

    @Test func drawingToolsPlaceTextRightBesideAnArrow() {
        drag(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        let arrow = model.document.marks[0]
        // Just below the shaft: beside it, not on it.
        model.choose(.text)
        click(CGPoint(x: 160, y: 307))
        #expect(model.editingText != nil)
        #expect(model.document[arrow.id] == arrow)
        canvas.escape()
        // The Select tool still reaches it from there.
        model.choose(.select)
        click(CGPoint(x: 160, y: 307))
        #expect(model.selection == [arrow.id])
    }

    @Test func revertTakesEverythingOffInOneStep() {
        #expect(!controller.canPerform(.revert))
        model.add(CaptureEditorTests.mark(.ellipse, CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60)))
        model.setFrame("Frame") { $0.background = .gradient(.dawn) }
        model.choose(.crop)
        model.cropDraft = CGRect(x: 20, y: 20, width: 300, height: 200)
        model.applyCrop()
        let edited = model.document
        #expect(controller.canPerform(.revert))
        controller.perform(.revert)
        #expect(model.document == model.original)
        #expect(model.document.marks.isEmpty && !model.document.frame.isOn)
        #expect(model.undoManager.undoActionName == "Revert to Original")
        model.undo()
        #expect(model.document == edited)
    }

    @Test func commandCCopiesMarksOnlyWhenYouChoseThem() {
        drag(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        // A mark just drawn stays selected, but ⌘C is still the image.
        #expect(!model.selection.isEmpty)
        #expect(!canvas.copiesMarks)
        model.choose(.select)
        #expect(canvas.copiesMarks)
        model.selection = []
        #expect(!canvas.copiesMarks)
        let file = EditorMenus.makeMainMenu().items.first { $0.title == "File" }?.submenu
        let image = file?.items.first { $0.title == "Copy Image" }
        #expect(image?.keyEquivalent == "c")
        #expect(image?.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test func calloutPointersAreSlimAndClearOfTheCorners() throws {
        let scale: CGFloat = 2
        var mark = CaptureEditorTests.mark(.text, CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 200))
        mark.text = "Rotate this key"
        mark.style.textStyle = .callout
        let layout = MarkGeometry.textLayout(mark, scale: scale)
        let box = layout.boxRect
        for end in [CGPoint(x: box.minX - 300, y: box.maxY + 20), CGPoint(x: box.midX, y: box.maxY + 200),
                    CGPoint(x: box.maxX + 10, y: box.minY - 150)] {
            mark.end = end
            let tail = try #require(MarkGeometry.calloutTail(mark, layout: layout, scale: scale))
            var points: [CGPoint] = []
            tail.applyWithBlock { element in
                if element.pointee.type != .closeSubpath { points.append(element.pointee.points[0]) }
            }
            let base = points.filter { $0 != end }
            #expect(base.count == 2)
            #expect(MarkGeometry.distance(base[0], base[1]) <= 18 * scale + 0.01)
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
            for point in base {
                #expect(box.insetBy(dx: -0.01, dy: -0.01).contains(point))
                #expect(corners.allSatisfy { MarkGeometry.distance($0, point) >= layout.cornerRadius })
            }
        }
    }

    // MARK: Window

    @Test func theAppMenuOpensSettingsAndQuitSaysWhatItQuits() {
        let app = EditorMenus.makeMainMenu().items.first?.submenu
        let settings = app?.items.first { $0.title == "Settings…" }
        #expect(settings?.keyEquivalent == ",")
        #expect(settings?.keyEquivalentModifierMask == .command)
        #expect(app?.items.contains { $0.title == "Quit Barn Owl" && $0.keyEquivalent == "q" } == true)
    }

    @Test func closingLetsGoOfTheSharedPanels() {
        NSFontManager.shared.target = controller
        NSColorPanel.shared.setTarget(controller)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(NSFontManager.shared.target == nil)
    }

    @Test func theDesktopPictureIsReadOnlyForTheDesktopBackground() {
        var asked = 0
        controller.onNeedsDesktop = { asked += 1 }
        model.setFrame("Frame") { $0.background = .gradient(.dusk) }
        #expect(asked == 0)
        model.setFrame("Frame") { $0.background = .desktop }
        #expect(asked == 1)
        model.setFrame("Frame") { $0.padding = 20 }
        #expect(asked == 1)
    }
}

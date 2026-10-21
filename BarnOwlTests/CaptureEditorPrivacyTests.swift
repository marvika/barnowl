import AppKit
import CoreText
import Foundation
import Testing
@testable import BarnOwl

/// Private info in the editor: where the real scan's findings land on the canvas, and what the
/// banner, Done and the redaction bars do about them.
@MainActor
struct CaptureEditorPrivacyTests {
    /// A capture with lines of text drawn into it, and where `secrets` ended up, in image
    /// pixels from the top left.
    static func textImage(lines: [String], secrets: [String], dark: Bool = false)
        -> (image: CGImage, glyphs: [String: CGRect]) {
        let width = 1600
        let height = 120 + lines.count * 70
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let background: CGFloat = dark ? 0.12 : 0.98
        context.setFillColor(CGColor(srgbRed: background, green: background, blue: background, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = NSFont.systemFont(ofSize: 30)
        let ink = dark ? NSColor.white : NSColor(white: 0.1, alpha: 1)
        var glyphs: [String: CGRect] = [:]
        for (index, text) in lines.enumerated() {
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
            let line = CTLineCreateWithAttributedString(string)
            // Core Graphics counts from the bottom; the image's rows from the top.
            let baseline = CGPoint(x: 80, y: CGFloat(height) - CGFloat(80 + index * 70))
            context.textPosition = baseline
            CTLineDraw(line, context)
            let ascent = font.ascender
            let descent = -font.descender
            for secret in secrets {
                guard let range = text.range(of: secret) else { continue }
                let nsRange = NSRange(range, in: text)
                let start = CTLineGetOffsetForStringIndex(line, nsRange.location, nil)
                let end = CTLineGetOffsetForStringIndex(line, nsRange.location + nsRange.length, nil)
                let top = CGFloat(height) - (baseline.y + ascent)
                glyphs[secret] = CGRect(x: baseline.x + start, y: top, width: end - start, height: ascent + descent)
            }
        }
        return (context.makeImage()!, glyphs)
    }

    // MARK: Where findings land

    /// The real scan, on text drawn into a capture: its boxes hold the private text, and on the
    /// canvas the review's stripes land where the image shows that text, cropped and framed too.
    @Test func reviewStripesCoverTheTextTheScanFound() async throws {
        let email = "me@example.com"
        let address = "8.8.8.8"
        let made = Self.textImage(lines: ["Send the weekly report to \(email) before Friday.",
                                          "Server \(address) · last deploy 3 minutes ago"],
                                  secrets: [email, address])
        let text = try await SensitiveTextFinder.scan(made.image)
        let found = Dictionary(text.findings.map { ($0.text, $0) }, uniquingKeysWith: { a, _ in a })
        let emailRect = try #require(found[email]?.rect)
        let addressRect = try #require(found[address]?.rect)
        let emailGlyphs = try #require(made.glyphs[email])
        let addressGlyphs = try #require(made.glyphs[address])
        // The boxes hold the whole of each, and don't spill far past it.
        #expect(emailRect.contains(emailGlyphs.insetBy(dx: 2, dy: 2)))
        #expect(addressRect.contains(addressGlyphs.insetBy(dx: 2, dy: 2)))
        #expect(emailRect.width < emailGlyphs.width * 1.6)
        #expect(addressRect.width < addressGlyphs.width * 1.9)

        let insight = CaptureInsight(text: text, windowRects: [], textWasRead: true)
        let model = EditorModel(image: made.image, scale: 2, insight: insight, defaults: CaptureEditorTests.defaults())
        let controller = EditorWindowController(model: model, title: "Test")
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1100, height: 600), display: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let canvas = controller.canvas
        canvas.setZoom(1)
        for framed in [false, true] {
            if framed {
                model.apply("Crop and Frame") { document in
                    document.crop = CGRect(x: 40, y: 20, width: 1200, height: 150)
                    document.frame.background = .gradient(.dusk)
                    document.frame.padding = 60
                }
            }
            model.beginReview()
            let stripes = try #require(model.review?.items.filter(\.included).map(\.finding.rect))
            #expect(stripes.contains(emailRect))
            // Where the image layer puts the capture's pixels.
            let image = try #require(canvas.subviews.first { $0 is ImageLayerView })
            let crop = model.document.crop
            func shown(_ rect: CGRect) -> CGRect {
                let x: CGFloat = image.frame.minX + (rect.minX - crop.minX) / model.scale
                let y: CGFloat = image.frame.minY + (rect.minY - crop.minY) / model.scale
                return CGRect(x: x, y: y, width: rect.width / model.scale, height: rect.height / model.scale)
            }
            #expect(image.frame.size == CGSize(width: crop.width / model.scale, height: crop.height / model.scale))
            for (stripe, glyphs) in [(emailRect, emailGlyphs), (addressRect, addressGlyphs)] {
                #expect(canvas.viewRect(fromImage: stripe).contains(shown(glyphs).insetBy(dx: 1, dy: 1)))
            }
            model.review = nil
        }
    }

    // MARK: Banner and Done

    @Test func theBannerHidesEverythingPrivateNotOnlyKeys() {
        let model = CaptureEditorTests.model(insight: CaptureEditorTests.insight())
        #expect(model.showsSecretBanner)
        #expect(model.privateSentence == "A key or token and an email address are visible.")
        #expect(model.hidePrivateTitle == "Hide Both")
        model.hidePrivate()
        let hidden = model.document.marks
        #expect(Set(hidden.compactMap(\.origin?.category)) == ["key", "email"])
        #expect(model.visiblePrivate.isEmpty)
        #expect(!model.showsSecretBanner)
        #expect(!model.asksAboutSecretsOnDone)
        // An IP address is offered in the review, never hidden unasked.
        #expect(model.uncoveredFindings(minimum: .info).map(\.kind) == [.ipAddress])
        model.undo()
        #expect(model.document.marks.isEmpty)
    }

    @Test func theBannerSaysWhatItSees() {
        func finding(_ kind: SensitiveTextFinder.Kind, x: CGFloat) -> SensitiveTextFinder.Finding {
            SensitiveTextFinder.Finding(rect: CGRect(x: x, y: 10, width: 40, height: 16), kind: kind, text: "x")
        }
        func model(_ findings: [SensitiveTextFinder.Finding]) -> EditorModel {
            let insight = CaptureInsight(text: CaptureText(findings: findings), textWasRead: true)
            return CaptureEditorTests.model(insight: insight)
        }
        let one = model([finding(.key, x: 10)])
        #expect(one.privateSentence == "A key or token is visible.")
        #expect(one.hidePrivateTitle == "Hide")
        let three = model([finding(.email, x: 10), finding(.key, x: 60), finding(.phone, x: 110)])
        #expect(three.privateSentence == "3 private details are visible.")
        #expect(three.hidePrivateTitle == "Hide All")
        // Only a secret interrupts.
        #expect(!model([finding(.email, x: 10)]).showsSecretBanner)
    }

    // MARK: Redaction colours

    static func plain(lightness: CGFloat, width: Int = 800, height: Int = 500) -> CGImage {
        CaptureEditorTests.image(width: width, height: height, grey: lightness)
    }

    static func canvas(image: CGImage, defaults: UserDefaults = CaptureEditorTests.defaults()) -> EditorWindowController {
        let model = EditorModel(image: image, scale: 2, defaults: defaults)
        let controller = EditorWindowController(model: model, title: "Test")
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.canvas.setZoom(1)
        return controller
    }

    static func drag(_ canvas: EditorCanvas, from start: CGPoint, to end: CGPoint) {
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewPoint(fromImage: point), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, start))
        canvas.mouseDragged(with: event(.leftMouseDragged, end))
        canvas.mouseUp(with: event(.leftMouseUp, end))
    }

    @Test func draggedBarsShowOnDarkCaptures() {
        #expect(ImageSampler.redactionColour(in: Self.plain(lightness: 0.1), rect: CGRect(x: 0, y: 0, width: 80, height: 40))
            == ImageSampler.darkRedaction)
        #expect(ImageSampler.redactionColour(in: Self.plain(lightness: 0.95), rect: CGRect(x: 0, y: 0, width: 80, height: 40)) == .ink)

        let dark = Self.canvas(image: Self.plain(lightness: 0.12))
        dark.model.choose(.redact)
        Self.drag(dark.canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 160))
        #expect(dark.model.document.marks.first?.colour == ImageSampler.darkRedaction)
        #expect(dark.model.changeCount == 1)

        let light = Self.canvas(image: Self.plain(lightness: 0.95))
        light.model.choose(.redact)
        Self.drag(light.canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 160))
        #expect(light.model.document.marks.first?.colour == .ink)

        // A colour you pick is kept, on dark captures too.
        let picked = Self.canvas(image: Self.plain(lightness: 0.12))
        picked.model.choose(.redact)
        picked.model.setColour(.red)
        Self.drag(picked.canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 160))
        #expect(picked.model.document.marks.first?.colour == .red)
        picked.model.resetStyle()
        #expect(!picked.model.styleBook.redactColourChosen)
    }

    @Test func barsOverLightTextTakeItsColour() {
        let made = Self.textImage(lines: ["Token: 4f9a2c"], secrets: ["4f9a2c"], dark: true)
        let glyphs = made.glyphs["4f9a2c"]!
        let controller = Self.canvas(image: made.image)
        controller.model.choose(.redact)
        Self.drag(controller.canvas, from: CGPoint(x: glyphs.minX - 4, y: glyphs.minY - 4),
                  to: CGPoint(x: glyphs.maxX + 4, y: glyphs.maxY + 4))
        #expect((controller.model.document.marks.first?.colour.lightness ?? 0) > 0.8)
    }
}

/// A host that saves to a file of a known name.
@MainActor
private final class SavingHost: CaptureEditorHost {
    var saved: URL? = URL(fileURLWithPath: "/tmp/Capture 2026-10-22 at 09.41.png")

    func editor(_ editor: CaptureEditor, copy image: CGImage) {}
    func editor(_ editor: CaptureEditor, save image: CGImage) async -> URL? { saved }
    func editor(_ editor: CaptureEditor, pin image: CGImage) {}
    func editor(_ editor: CaptureEditor, finish image: CGImage) {}
    func editor(_ editor: CaptureEditor, didChange document: EditorDocument) {}
    func editorDidClose(_ editor: CaptureEditor, edited: Bool) {}
}

@MainActor
struct CaptureEditorSaveTests {
    @Test func savingSaysSoInTheWindow() async {
        let host = SavingHost()
        let editor = CaptureEditor(image: CaptureEditorTests.image(), scale: 1, title: "Test", host: host)
        editor.model.perform(.save)
        for _ in 0..<100 where editor.model.transientHint == nil { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(editor.model.transientHint == "Saved · Capture 2026-10-22 at 09.41.png")
        host.saved = nil
        editor.model.transientHint = nil
        editor.model.perform(.save)
        for _ in 0..<100 where editor.model.transientHint == nil { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(editor.model.transientHint == "Couldn't save")
        editor.close()
    }
}

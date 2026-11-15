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
    /// pixels from the top left. `rule` draws a line down the picture at that x, through the text.
    static func textImage(lines: [String], secrets: [String], dark: Bool = false, size: CGFloat = 30, rule: CGFloat? = nil)
        -> (image: CGImage, glyphs: [String: CGRect]) {
        let width = 1600
        let height = 120 + lines.count * 70
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let background: CGFloat = dark ? 0.12 : 0.98
        context.setFillColor(CGColor(srgbRed: background, green: background, blue: background, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = NSFont.systemFont(ofSize: size)
        let ink = dark ? NSColor.white : NSColor(white: 0.1, alpha: 1)
        if let rule {
            context.setFillColor(ink.cgColor)
            context.fill(CGRect(x: rule, y: 0, width: 2, height: CGFloat(height)))
        }
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

    /// The box around everything drawn in `area`, however faint: what a cover mustn't leave
    /// showing. The top left of `area` is plain background.
    static func ink(in image: CGImage, area: CGRect) -> CGRect? {
        let rect = area.integral
        let width = Int(rect.width)
        let bytes = ImageSampler.rgba(in: image, rect: rect)
        guard width > 0, bytes.count >= 4, bytes.count % (width * 4) == 0 else { return nil }
        var box = CGRect.null
        for y in 0..<(bytes.count / (width * 4)) {
            for x in 0..<width where abs(Int(bytes[(y * width + x) * 4]) - Int(bytes[0])) > 6 {
                box = box.union(CGRect(x: rect.minX + CGFloat(x), y: rect.minY + CGFloat(y), width: 1, height: 1))
            }
        }
        return box.isNull ? nil : box
    }

    /// A line's box isn't the same from one macOS to the next: macOS 27's hugs the glyphs and,
    /// on small text, sits inside them; older ones leave room. The cover is fitted to the ink,
    /// so it holds the text whichever box it starts from, and comes out the same.
    @Test(arguments: [30, 13, 11] as [CGFloat])
    func coversHoldTheInkWhateverBoxTheLineCameWith(size: CGFloat) throws {
        let secret = "jp@example.com"
        let made = Self.textImage(lines: ["Send the weekly report to \(secret) today"], secrets: [secret], size: size)
        let glyphs = try #require(made.glyphs[secret])
        let ink = try #require(Self.ink(in: made.image, area: glyphs.insetBy(dx: 0, dy: -4)))
        let inkTop: CGFloat = ink.minY
        let inkBottom: CGFloat = ink.maxY
        let inkHeight: CGFloat = ink.height
        // Cutting a quarter into the glyphs top and bottom, hugging them, and with room to spare.
        let lineLeft: CGFloat = 80
        let boxes: [CGRect] = [0.25, 0, -0.3].map { inset in
            let top: CGFloat = inkTop + inkHeight * inset
            return CGRect(x: lineLeft, y: top, width: glyphs.maxX - lineLeft + 60, height: inkBottom - inkHeight * inset - top)
        }
        var covers: [CGRect] = []
        for line in boxes {
            let word = CGRect(x: glyphs.minX, y: line.minY, width: glyphs.width, height: line.height)
            let fitted = try #require(SensitiveTextFinder.fitted(line, in: made.image))
            // On the ink, give or take the faintest row of smoothing.
            #expect(abs(fitted.minY - inkTop) <= 1 && abs(fitted.maxY - inkBottom) <= 1, "\(line) → \(fitted), ink \(ink)")
            let cover = SensitiveTextFinder.padded(word, line: fitted)
            #expect(cover.minY <= inkTop - 1 && cover.maxY >= inkBottom + 1 && cover.minX < glyphs.minX && cover.maxX > glyphs.maxX)
            // The whole line a text selection would take, as far as the ink lets it be told.
            #expect(cover.contains(glyphs.insetBy(dx: 2, dy: 2)))
            covers.append(cover)
        }
        #expect(covers[0] == covers[1] && covers[1] == covers[2])
    }

    /// Lines close together, and a box that reaches into the ones above and below, as macOS 27's
    /// can in a terminal: the cover stays on its own line.
    @Test func coversStayOnTheirOwnLine() throws {
        let secret = "jp@example.com"
        let lines = ["Agpqy jumped high (gjpqy)", "Send it to \(secret) today", "Ålesund, the Light of gjpqy"]
        let made = Self.textImage(lines: lines, secrets: [secret], size: 58)
        let glyphs = try #require(made.glyphs[secret])
        let ink = try #require(Self.ink(in: made.image, area: glyphs))
        let inkTop: CGFloat = ink.minY
        let inkBottom: CGFloat = ink.maxY
        // Lines 70 apart; ink about 55 tall. This box takes in the tails above and the tops below.
        let loose = CGRect(x: 80, y: inkTop - 22, width: glyphs.maxX, height: inkBottom - inkTop + 44)
        let fitted = try #require(SensitiveTextFinder.fitted(loose, in: made.image))
        #expect(abs(fitted.minY - inkTop) <= 1 && abs(fitted.maxY - inkBottom) <= 1, "\(loose) → \(fitted), ink \(ink)")
        let cover = SensitiveTextFinder.padded(glyphs, line: fitted)
        #expect(cover.height < 70 * 1.25)
    }

    /// A word's box whose ends cut through its first and last letters, as they can on a capture
    /// of a whole screen: the cover reaches past those letters. Ends between letters stay put.
    @Test func coversReachPastLettersTheBoxCutsThrough() throws {
        let secret = "me@example.com"
        let made = Self.textImage(lines: ["Send it to \(secret) today"], secrets: [secret])
        let glyphs = try #require(made.glyphs[secret])
        let ink = try #require(Self.ink(in: made.image, area: glyphs))
        let rough = CGRect(x: 80, y: ink.minY + 6, width: glyphs.maxX, height: ink.height - 12)
        let line = try #require(SensitiveTextFinder.fitted(rough, in: made.image))
        // Six pixels into the m at each end.
        let cut = CGRect(x: ink.minX + 6, y: rough.minY, width: ink.width - 12, height: rough.height)
        let reached = SensitiveTextFinder.reaching(cut, on: line, in: made.image)
        #expect(reached.minX <= ink.minX + 1 && reached.maxX >= ink.maxX - 1, "\(cut) → \(reached), ink \(ink)")
        // No further than the letter: not on into the next word.
        #expect(reached.minX >= ink.minX - 2 && reached.maxX <= ink.maxX + 2, "\(cut) → \(reached), ink \(ink)")
        // In the spaces either side: left as it came.
        let loose = CGRect(x: ink.minX - 3, y: rough.minY, width: ink.width + 6, height: rough.height)
        #expect(SensitiveTextFinder.reaching(loose, on: line, in: made.image) == loose)
        // Both ways at once, from boxes that cut into the text on every side.
        let cover = SensitiveTextFinder.cover(cut, line: rough, in: made.image)
        #expect(cover.contains(glyphs.insetBy(dx: 2, dy: 2)))
        #expect(cover.minX <= ink.minX - 3 && cover.maxX >= ink.maxX + 3)
    }

    @Test func coversKeepTheLinesBoxWhereThePixelsDoNotSay() throws {
        // A rule down through the line: ink on every row, so no telling where the text ends.
        let ruled = Self.textImage(lines: ["Token 4f9a2c is live"], secrets: ["4f9a2c"], rule: 120)
        let glyphs = try #require(ruled.glyphs["4f9a2c"])
        let line = CGRect(x: 80, y: (glyphs.minY + 8).rounded(), width: 300, height: 26)
        #expect(SensitiveTextFinder.fitted(line, in: ruled.image) == line)
        // Nothing drawn there at all.
        let blank = CGRect(x: 900, y: 40, width: 300, height: 30)
        #expect(SensitiveTextFinder.fitted(blank, in: ruled.image) == nil)
        // Text the picture's edge cuts through: its ink ends where the picture does. Right of the rule.
        let edge = try #require(ruled.image.cropping(to: CGRect(x: 0, y: Int(glyphs.midY), width: 600, height: 60)))
        let cutOff = try #require(SensitiveTextFinder.fitted(CGRect(x: 130, y: 3, width: 250, height: 6), in: edge))
        #expect(cutOff.minY == 0)
        #expect(cutOff.maxY > 9 && cutOff.maxY < 15, "\(cutOff)")
    }

    /// A Redact click on a word that isn't a finding gets the same cover.
    @Test func aRedactClickOnAWordCoversItWhole() throws {
        let made = Self.textImage(lines: ["Back on Friday at nine"], secrets: ["Friday"])
        let glyphs = try #require(made.glyphs["Friday"])
        // As macOS 27 gives them: inside the glyphs, top and bottom.
        let line = CGRect(x: 80, y: glyphs.minY + 10, width: 340, height: glyphs.height - 14)
        let word = CaptureText.Word(rect: CGRect(x: glyphs.minX, y: line.minY, width: glyphs.width, height: line.height), text: "Friday")
        let text = CaptureText(lines: [CaptureText.Line(rect: line, text: "Back on Friday at nine", words: [word])])
        let insight = CaptureInsight(text: text, textWasRead: true)
        let point = CGPoint(x: glyphs.midX, y: line.midY)
        let hit = try #require(SmartFit.redaction(at: point, insight: insight, image: made.image))
        #expect(hit.finding == nil)
        #expect(hit.rect.contains(glyphs.insetBy(dx: 2, dy: 2)))
        #expect(hit.rect.height < glyphs.height * 1.4)
        // Through the editor, which has the capture to look at.
        let model = EditorModel(image: made.image, scale: 2, insight: insight, defaults: CaptureEditorTests.defaults())
        model.choose(.redact)
        #expect(model.fitTarget(at: point) == hit.rect)
        let placed = try #require(model.placeFitted(at: point)?.rect)
        #expect(placed.insetBy(dx: -0.01, dy: -0.01).contains(hit.rect) && hit.rect.insetBy(dx: -0.01, dy: -0.01).contains(placed))
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
        // Undone, the key shows again, and so do the banner and Done's question.
        #expect(model.showsSecretBanner)
        #expect(model.asksAboutSecretsOnDone)
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

        // Solid bars, chosen in the options bar (out of the box it's a light blur).
        let dark = Self.canvas(image: Self.plain(lightness: 0.12))
        dark.model.choose(.redact)
        dark.model.updateStyle { $0.redact = .solid }
        Self.drag(dark.canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 160))
        #expect(dark.model.document.marks.first?.colour == ImageSampler.darkRedaction)
        #expect(dark.model.changeCount == 1)

        let light = Self.canvas(image: Self.plain(lightness: 0.95))
        light.model.choose(.redact)
        light.model.updateStyle { $0.redact = .solid }
        Self.drag(light.canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 160))
        #expect(light.model.document.marks.first?.colour == .ink)

        // A colour you pick is kept, on dark captures too.
        let picked = Self.canvas(image: Self.plain(lightness: 0.12))
        picked.model.choose(.redact)
        picked.model.updateStyle { $0.redact = .solid }
        picked.model.setColour(.red)
        Self.drag(picked.canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 160))
        #expect(picked.model.document.marks.first?.colour == .red)
        picked.model.resetStyle()
        #expect(!picked.model.styleBook.redactColourChosen)
    }

    @Test func aRedactionColourPickedBeforeIsStillYours() throws {
        let red = try JSONDecoder().decode(StyleBook.self, from: Data(#"{"redactColour":{"red":1,"green":0,"blue":0}}"#.utf8))
        #expect(red.redactColourChosen)
        let ink = try JSONDecoder().decode(StyleBook.self, from: Data("{}".utf8))
        #expect(!ink.redactColourChosen)
        let saved = try JSONDecoder().decode(StyleBook.self, from: JSONEncoder().encode(red))
        #expect(saved.redactColourChosen)
    }

    @Test func barsOverLightTextTakeItsColour() {
        let made = Self.textImage(lines: ["Token: 4f9a2c"], secrets: ["4f9a2c"], dark: true)
        let glyphs = made.glyphs["4f9a2c"]!
        let controller = Self.canvas(image: made.image)
        controller.model.choose(.redact)
        controller.model.updateStyle { $0.redact = .solid }
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

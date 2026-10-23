import AppKit
import Foundation
import Testing
@testable import BarnOwl

/// The Frame (gradients of your own, matched backgrounds, shadow strength, ratios and position,
/// the remembered look) and the magnifier.
@MainActor
struct CaptureEditorFrameTests {
    typealias Pixel = (red: Double, green: Double, blue: Double, alpha: Double)

    /// The pixel at (`x`, `y`) from the top left, unpremultiplied.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let alpha = Double(bytes[3]) / 255
        let divisor = max(alpha, 1.0 / 255) * 255
        return (Double(bytes[0]) / divisor, Double(bytes[1]) / divisor, Double(bytes[2]) / divisor, alpha)
    }

    static func near(_ pixel: Pixel, _ colour: MarkColour, within tolerance: Double = 4.0 / 255) -> Bool {
        abs(pixel.red - colour.red) <= tolerance && abs(pixel.green - colour.green) <= tolerance
            && abs(pixel.blue - colour.blue) <= tolerance
    }

    static func colour(_ pixel: Pixel) -> MarkColour {
        MarkColour(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }

    static func image(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Top-left origin, like the editor.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)
        return context.makeImage()!
    }

    static func solid(_ colour: MarkColour, width: Int = 300, height: Int = 200) -> CGImage {
        image(width: width, height: height) { context in
            context.setFillColor(colour.cgColor())
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A document with only a frame, for looking at the background around a capture.
    static func framed(_ background: FrameBackground, size: CGSize = CGSize(width: 300, height: 200), padding: CGFloat = 50)
        -> EditorDocument {
        var document = EditorDocument(imageSize: size, scale: 1)
        document.frame.background = background
        document.frame.padding = padding
        document.frame.shadowAmount = 0
        return document
    }

    // MARK: Decoding

    @Test func aSchemaTwoDocumentGetsTheClassicShadowAndACentredCapture() throws {
        func open(shadow: Bool) throws -> EditorDocument {
            let json = """
            {"schemaVersion":2,"imageSize":[100,80],"marks":[{"kind":"arrow","start":[1,2],"end":[30,40]}],
             "frame":{"background":{"gradient":{"_0":"dawn"}},"padding":96,"cornerRadius":20,"shadow":\(shadow),"ratio":"wide"}}
            """
            return try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8))
        }
        let on = try open(shadow: true)
        #expect(on.frame.shadowAmount == 0.5)
        #expect(on.frame.shadow)
        #expect(on.frame.position == .centre)
        #expect(on.frame.background == .gradient(.dawn))
        #expect(on.frame.ratio == .wide)
        #expect(on.marks.count == 1)
        #expect(on.schemaVersion == EditorDocument.currentSchema)
        let off = try open(shadow: false)
        #expect(off.frame.shadowAmount == 0)
        #expect(!off.frame.shadow)
    }

    @Test func unknownValuesFallBackAndKeepTheMarks() throws {
        let json = """
        {"schemaVersion":9,"imageSize":[100,80],
         "marks":[{"kind":"arrow","start":[1,2],"end":[30,40]},{"kind":"hologram","start":[0,0]},
                  {"kind":"rectangle","start":[5,5],"end":[50,50]}],
         "frame":{"background":{"aurora":{}},"padding":40,"ratio":"cinema","position":{"x":0}}}
        """
        let document = try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8))
        #expect(document.marks.map(\.kind) == [.arrow, .rectangle])
        #expect(document.frame.background == FrameBackground.none)
        #expect(document.frame.ratio == .auto)
        #expect(document.frame.padding == 40)
        #expect(document.frame.position == FramePosition(x: 0, y: 0.5))
    }

    @Test func schemaThreeRoundTripsEveryField() throws {
        var document = EditorDocument(imageSize: CGSize(width: 100, height: 80))
        let gradient = CustomGradient(stops: [GradientStop(colour: .blue, location: 0),
                                              GradientStop(colour: MarkColour(hex: 0x5AC8FA), location: 0.3),
                                              GradientStop(colour: .amber, location: 1)],
                                      angle: 200, kind: .radial, softLight: false)
        document.frame = FrameSettings(background: .custom(gradient), padding: 30, cornerRadius: 12, shadowAmount: 0.8,
                                       ratio: .link, position: FramePosition(x: 1, y: 0))
        var loupe = Mark(kind: .magnifier, colour: .white, style: StyleBook.defaultStyle(for: .magnifier),
                         start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 60))
        loupe.style.zoom = 3
        loupe.style.spotlight = .rectangle
        document.marks = [loupe]
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(EditorDocument.self, from: data)
        #expect(decoded == document)
        #expect(decoded.schemaVersion == 3)
        // Earlier builds still find the shadow on or off.
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let frame = json?["frame"] as? [String: Any]
        #expect(frame?["shadow"] as? Bool == true)
        #expect(json?["schemaVersion"] as? Int == 3)
    }

    @Test func customGradientsKeepTwoToFourStopsInOrder() {
        let one = CustomGradient(stops: [GradientStop(colour: .red, location: 0.4)])
        #expect(one.stops.count == 2)
        let five = CustomGradient(colours: [.red, .amber, .yellow, .green, .blue])
        #expect(five.stops.count == 4)
        let unordered = CustomGradient(stops: [GradientStop(colour: .blue, location: 1.4), GradientStop(colour: .red, location: -1)],
                                       angle: -45)
        #expect(unordered.stops.map(\.location) == [0, 1])
        #expect(unordered.stops.first?.colour == .red)
        #expect(unordered.angle == 315)
        let reversed = unordered.reversed
        #expect(reversed.stops.first?.colour == .blue)
        #expect(reversed.reversed == unordered)
    }

    // MARK: Gradients

    @Test func gradientsAreMixedAsTheEyeSeesThem() {
        let gradient = CustomGradient(colours: [.blue, MarkColour(hex: 0xFF9500), .green])
        let ramp = GradientPainter.expanded(gradient.stops)
        #expect(ramp.colours.count == GradientPainter.substeps * 2 + 1)
        #expect(ramp.locations == ramp.locations.sorted())
        #expect(ramp.locations.first == 0)
        #expect(ramp.locations.last == 1)
        #expect(gradient.colour(at: 0) == .blue)
        #expect(gradient.colour(at: 1) == .green)
        // Blue to orange goes round by way of a colour, not through grey.
        let middle = MarkColour.blue.blended(with: MarkColour(hex: 0xFF9500), 0.5)
        let plain = MarkColour.blue.mixed(with: MarkColour(hex: 0xFF9500), 0.5)
        #expect(middle.oklab.chroma > 0.1)
        #expect(plain.oklab.chroma < 0.05)
    }

    @Test func aGradientAtNinetyDegreesRunsLeftToRight() throws {
        let gradient = CustomGradient(colours: [.blue, MarkColour(hex: 0xFF9500)], angle: 90, softLight: false)
        let renderer = AnnotationRenderer(image: Self.solid(.white), scale: 1)
        let image = try #require(renderer.render(Self.framed(.custom(gradient))))
        #expect(image.width == 400)
        let left = Self.pixel(image, 0, 20)
        let right = Self.pixel(image, 399, 20)
        #expect(Self.near(left, .blue, within: 8.0 / 255))
        #expect(Self.near(right, MarkColour(hex: 0xFF9500), within: 8.0 / 255))
        // The middle keeps its colour.
        let middle = Self.colour(Self.pixel(image, 200, 20))
        #expect(middle.oklab.chroma > 0.1)
        let ends = GradientPainter.linearEnds(angle: 90, in: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(CaptureEditorTests.close(ends.start, CGPoint(x: 0, y: 150)))
        #expect(CaptureEditorTests.close(ends.end, CGPoint(x: 400, y: 150)))
    }

    @Test func aRadialGradientStartsAtTheCapturesCentre() throws {
        let gradient = CustomGradient(colours: [.yellow, .ink], kind: .radial, softLight: false)
        let renderer = AnnotationRenderer(image: Self.solid(.white), scale: 1)
        let sample = try #require(renderer.backgroundSample(.custom(gradient), size: CGSize(width: 200, height: 100),
                                                            pixelsPerPoint: 1))
        #expect(Self.near(Self.pixel(sample, 100, 50), .yellow, within: 8.0 / 255))
        #expect(Self.near(Self.pixel(sample, 0, 0), .ink, within: 8.0 / 255))

        // With the capture at the left of a wide frame, the light follows it there.
        var document = Self.framed(.custom(gradient))
        document.frame.ratio = .wide
        document.frame.position = FramePosition(x: 0, y: 0.5)
        let layout = FrameLayout(document: document)
        #expect(layout.imageRect.minX == 50)
        let image = try #require(renderer.render(document))
        let centreY = Int(layout.imageRect.midY)
        let left = Self.colour(Self.pixel(image, 20, centreY))
        let right = Self.colour(Self.pixel(image, Int(layout.canvasSize.width) - 1, centreY))
        #expect(left.lightness > right.lightness + 0.2)
    }

    @Test func rendersAreTheSameEveryTime() throws {
        let gradient = CustomGradient(colours: [MarkColour(hex: 0x3A3A44), MarkColour(hex: 0x121217)])
        let renderer = AnnotationRenderer(image: Self.solid(.white), scale: 2)
        let document = Self.framed(.custom(gradient))
        func bytes(_ document: EditorDocument) throws -> Data {
            let data = try #require(renderer.render(document)?.dataProvider?.data)
            return data as Data
        }
        #expect(try bytes(document) == bytes(document))
        let curated = Self.framed(.gradient(.graphite))
        #expect(try bytes(curated) == bytes(curated))
    }

    @Test func theReadyMadeGradientsLookAsTheyAlwaysHave() throws {
        let renderer = AnnotationRenderer(image: Self.solid(.white), scale: 1)
        let image = try #require(renderer.render(Self.framed(.gradient(.dawn))))
        // Corner to corner in sRGB, with the soft light from the top left.
        let from = MarkColour(hex: 0x8C87FF)
        let to = MarkColour(hex: 0xF5A633)
        // The grain moves a channel by a few levels at most.
        let grain = 7.0 / 255
        #expect(Self.near(Self.pixel(image, 399, 299), to, within: grain))
        func expected(_ x: Double, _ y: Double) -> MarkColour {
            let t = min(max((x * 400 + y * 300) / (400.0 * 400 + 300 * 300), 0), 1)
            let base = from.mixed(with: to, t)
            let glow = 0.2 * max(0, 1 - hypot(x - 72, y) / 300)
            return base.mixed(with: .white, glow)
        }
        for (x, y) in [(200, 30), (20, 280), (380, 10), (120, 20)] {
            #expect(Self.near(Self.pixel(image, x, y), expected(Double(x) + 0.5, Double(y) + 0.5), within: grain))
        }
        #expect(FrameGradient.dawn.stops == [from, to])
        #expect(FrameGradient.allCases.count == 9)
    }

    // MARK: Matched backgrounds

    @Test func aRedCaptureGetsRedBackgrounds() {
        let suggestions = BackgroundHarmony.suggestions(for: Self.solid(MarkColour(hex: 0xE0352B)))
        let red = MarkColour(hex: 0xE0352B).oklab.hue
        #expect(BackgroundHarmony.angle(between: suggestions.hue, and: red) < 10)
        #expect(!suggestions.gradients.isEmpty)
        #expect(suggestions.gradients.contains { BackgroundHarmony.angle(between: $0.stops[0].colour.oklab.hue, and: red) < 15 })
        for gradient in suggestions.gradients {
            // Deep ones lean toward dusk, but none strays far from the capture's red.
            let hue = gradient.stops[0].colour.oklab.hue
            #expect(BackgroundHarmony.angle(between: hue, and: red) < 60)
        }
        #expect(suggestions.colours.first.map { BackgroundHarmony.angle(between: $0.oklab.hue, and: red) < 10 } == true)
    }

    @Test func warmCapturesNeverGetOliveOrMud() {
        for hex: UInt32 in [0xF5A633, 0xFFD60A, 0xFF9500, 0xC8A951] {
            let suggestions = BackgroundHarmony.suggestions(for: Self.solid(MarkColour(hex: hex)))
            for gradient in suggestions.gradients {
                for stop in gradient.stops {
                    let lab = stop.colour.oklab
                    // Yellow-greens that aren't light read as olive; mid-dark oranges as brown.
                    let olive = lab.hue > 95 && lab.hue < 135 && lab.l < 0.8 && lab.chroma > 0.05
                    let mud = lab.hue > 50 && lab.hue < 95 && lab.l < 0.5 && lab.chroma > 0.04
                    #expect(!olive && !mud, "\(stop.colour.hex) from \(String(format: "%06X", hex))")
                }
            }
        }
    }

    @Test func aGreyCaptureFallsBackToLavender() {
        let suggestions = BackgroundHarmony.suggestions(for: CaptureEditorTests.image())
        #expect(abs(suggestions.hue - BackgroundHarmony.fallbackHue) < 0.001)
        #expect(suggestions.gradients.count >= 3)
    }

    @Test func suggestionsAreTheSameEveryTime() {
        // A white page with a blue block and an amber one, as a capture often is.
        let picture = Self.image(width: 120, height: 90) { context in
            context.setFillColor(MarkColour.white.cgColor())
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
            context.setFillColor(MarkColour.blue.cgColor())
            context.fill(CGRect(x: 10, y: 10, width: 50, height: 70))
            context.setFillColor(MarkColour.amber.cgColor())
            context.fill(CGRect(x: 64, y: 10, width: 46, height: 70))
        }
        let first = BackgroundHarmony.suggestions(for: picture)
        #expect(first == BackgroundHarmony.suggestions(for: picture))
        // Two hues: the pair runs from one to the other.
        let pair = first.gradients.last
        let hues = [MarkColour.blue.oklab.hue, MarkColour.amber.oklab.hue]
        let ends = pair.map { [$0.stops[0].colour.oklab.hue, $0.stops[1].colour.oklab.hue] } ?? []
        #expect(ends.count == 2)
        #expect(ends.allSatisfy { end in hues.contains { BackgroundHarmony.angle(between: end, and: $0) < 20 } })
    }

    @Test func everySuggestionStandsApartFromTheCapturesEdge() {
        for colour in [MarkColour.white, .ink, MarkColour(hex: 0xE0352B), MarkColour(hex: 0xBFD9F2)] {
            let suggestions = BackgroundHarmony.suggestions(for: Self.solid(colour))
            #expect(abs(suggestions.edgeLightness - colour.lightness) < 0.03)
            for gradient in suggestions.gradients {
                #expect(abs(BackgroundHarmony.meanLightness(gradient) - suggestions.edgeLightness) > BackgroundHarmony.separation)
            }
        }
    }

    @Test func aWindowIsJudgedByItsOwnEdgeNotTheClearMarginAroundIt() {
        let window = Self.shadowedWindow()
        let suggestions = BackgroundHarmony.suggestions(for: window)
        // White window, dark shadow, clear margin: the edge is light, not the clear margin's black.
        #expect(suggestions.edgeLightness > 0.7)
    }

    /// The same "random" numbers every run.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test func shuffleStaysNearTheCapturesHueAndApartFromItsEdge() {
        var generator = SplitMix(state: 7)
        let hue = MarkColour.blue.oklab.hue
        var seen: Set<CustomGradient> = []
        for _ in 0..<20 {
            let gradient = BackgroundHarmony.shuffled(around: hue, edgeLightness: 0.98, using: &generator)
            seen.insert(gradient)
            #expect(BackgroundHarmony.angle(between: gradient.stops[0].colour.oklab.hue, and: hue) <= 31)
            #expect(abs(BackgroundHarmony.meanLightness(gradient) - 0.98) > BackgroundHarmony.separation)
            #expect(gradient.angle.truncatingRemainder(dividingBy: 45) == 0)
        }
        #expect(seen.count == 20)
    }

    @Test func grainYouCanSeeIsStrongerThanTheDither() throws {
        var gradient = CustomGradient(colours: [MarkColour(hex: 0x808080), MarkColour(hex: 0x808080)], softLight: false)
        let renderer = AnnotationRenderer(image: Self.solid(.white), scale: 1)
        func spread(_ gradient: CustomGradient) throws -> Double {
            let image = try #require(renderer.render(Self.framed(.custom(gradient))))
            let values = (0..<40).map { Self.pixel(image, 5 + $0, 10).red }
            return (values.max() ?? 0) - (values.min() ?? 0)
        }
        let faint = try spread(gradient)
        gradient.grain = true
        let visible = try spread(gradient)
        #expect(faint > 0)
        #expect(faint < 0.05)
        #expect(visible > faint * 2.5)
    }

    // MARK: Layout

    @Test func positionPutsTheSpareRoomWhereYouSay() {
        let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
        var frame = FrameSettings(background: .gradient(.dawn), padding: 50, ratio: .wide)
        let centred = FrameLayout(crop: crop, frame: frame)
        #expect(centred.canvasSize == CGSize(width: 712, height: 400))
        #expect(centred.imageRect.minX == ((712 - 400) / 2 as CGFloat).rounded(.down))
        #expect(centred.imageRect.minY == 50)
        frame.position = FramePosition(x: 0, y: 0.5)
        #expect(FrameLayout(crop: crop, frame: frame).imageRect.minX == 50)
        frame.position = FramePosition(x: 1, y: 1)
        let right = FrameLayout(crop: crop, frame: frame)
        #expect(right.imageRect.minX == CGFloat(712 - 400 - 50))
        // No spare room up and down at 16:9: the padding holds.
        #expect(right.imageRect.minY == 50)
        frame.ratio = .auto
        #expect(FrameLayout(crop: crop, frame: frame).imageRect == CGRect(x: 50, y: 50, width: 400, height: 300))
    }

    @Test func theNewRatiosHaveTheRightShapes() {
        let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
        func size(_ ratio: AspectRatio) -> CGSize {
            FrameLayout(crop: crop, frame: FrameSettings(background: .gradient(.mist), padding: 50, ratio: ratio)).canvasSize
        }
        #expect(size(.threeTwo) == CGSize(width: 600, height: 400))
        #expect(size(.threeFour) == CGSize(width: 500, height: 667))
        #expect(size(.story) == CGSize(width: 500, height: 889))
        #expect(size(.link) == CGSize(width: 764, height: 400))
        #expect(AspectRatio.allCases.map(\.title) == ["Auto", "16:9", "3:2", "4:3", "1:1", "4:5", "3:4", "9:16", "1.91:1"])
    }

    // MARK: Inset

    @Test func anInsetPutsTheCaptureOnACardOfItsOwnEdgeColour() throws {
        let edge = MarkColour(hex: 0xF2EDE4)
        let picture = Self.image(width: 300, height: 200) { context in
            context.setFillColor(edge.cgColor())
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            context.setFillColor(MarkColour.blue.cgColor())
            context.fill(CGRect(x: 40, y: 40, width: 220, height: 120))
        }
        #expect(ImageSampler.edgeColour(in: picture, crop: CGRect(x: 0, y: 0, width: 300, height: 200)) == edge)
        // Cropped into the blue, the edge is blue.
        #expect(ImageSampler.edgeColour(in: picture, crop: CGRect(x: 50, y: 50, width: 100, height: 60)) == .blue)

        var document = Self.framed(.solid(.ink))
        document.frame.inset = 20
        let layout = FrameLayout(document: document)
        #expect(layout.canvasSize == CGSize(width: 440, height: 340))
        #expect(layout.cardRect == CGRect(x: 50, y: 50, width: 340, height: 240))
        #expect(layout.imageRect == CGRect(x: 70, y: 70, width: 300, height: 200))
        document.frame.ratio = .wide
        document.frame.position = FramePosition(x: 1, y: 0.5)
        let right = FrameLayout(document: document)
        #expect(right.cardRect.maxX == right.canvasSize.width - 50)
        #expect(right.imageRect.maxX == right.cardRect.maxX - 20)

        document.frame.ratio = .auto
        // A pen line runs from the capture out across the inset and the padding.
        var line = CaptureEditorTests.mark(.arrow, CGPoint(x: 150, y: -60), CGPoint(x: 150, y: 100), colour: .red)
        line.style.heads = .none
        document.marks = [line]
        let renderer = AnnotationRenderer(image: picture, scale: 1)
        let image = try #require(renderer.render(document))
        // The card shows in the inset, in the edge colour…
        #expect(Self.near(Self.pixel(image, 60, 150), edge))
        // …the marks reach into it, but not past it…
        #expect(Self.near(Self.pixel(image, 220, 55), .red, within: 10.0 / 255))
        #expect(Self.near(Self.pixel(image, 220, 45), .ink))
        // …and the frame's background starts beyond it.
        #expect(Self.near(Self.pixel(image, 45, 150), .ink))
    }

    // MARK: Spotlight

    @Test func aBlurredSpotlightSoftensTheRestButNeverWhatsHidden() throws {
        let renderer = AnnotationRenderer(image: Self.checkerboard(cell: 4), scale: 1)
        var document = EditorDocument(imageSize: CGSize(width: 200, height: 200), scale: 1)
        var spotlight = CaptureEditorTests.mark(.spotlight, CGPoint(x: 100, y: 100), CGPoint(x: 190, y: 190))
        spotlight.style.spotlightEffect = .blur
        var bar = CaptureEditorTests.mark(.redact, CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40), colour: .red)
        bar.style.redact = .solid
        document.marks = [spotlight, bar]
        let image = try #require(renderer.render(document))
        // Outside, the 4 px checks blur to an even grey.
        let a = Self.pixel(image, 30, 70)
        let b = Self.pixel(image, 34, 70)
        #expect(abs(a.red - b.red) < 0.12)
        // Inside, they stay crisp.
        #expect(abs(Self.pixel(image, 141, 141).red - Self.pixel(image, 145, 141).red) > 0.8)
        // The redaction outside stays a solid bar over the blur.
        #expect(Self.near(Self.pixel(image, 35, 25), MarkColour.red.mixed(with: .ink, 0.45 * 0.5), within: 12.0 / 255))
        // Decoding without the field keeps dimming.
        #expect(MarkStyle().spotlightEffect == .dim)
    }

    // MARK: Balance

    @Test func balancingCropsEveryMarginToTheSmallest() {
        // A blue panel on a white page: 30 left, 100 right, 50 above and below.
        let picture = Self.image(width: 300, height: 200) { context in
            context.setFillColor(MarkColour.white.cgColor())
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            context.setFillColor(MarkColour.blue.cgColor())
            context.fill(CGRect(x: 30, y: 50, width: 170, height: 100))
        }
        let content = ImageSampler.contentBounds(in: picture, crop: CGRect(x: 0, y: 0, width: 300, height: 200), background: .white)
        #expect(content == CGRect(x: 30, y: 50, width: 170, height: 100))
        let model = EditorModel(image: picture, scale: 1, defaults: CaptureEditorTests.defaults())
        #expect(model.balancedCrop == CGRect(x: 0, y: 20, width: 230, height: 160))
        model.balanceMargins()
        #expect(model.document.crop == CGRect(x: 0, y: 20, width: 230, height: 160))
        #expect(model.undoManager.undoActionName == "Balance Margins")
        // Even now: nothing more to offer.
        #expect(model.balancedCrop == nil)
        model.undo()
        #expect(model.document.crop == model.document.imageBounds)

        // Margins within 4% of each other, or content at an edge, aren't worth it.
        let even = CGRect(x: 0, y: 0, width: 300, height: 200)
        #expect(AnnotationRenderer.balanced(even, content: CGRect(x: 30, y: 32, width: 242, height: 138)) == nil)
        #expect(AnnotationRenderer.balanced(even, content: CGRect(x: 0, y: 50, width: 170, height: 100)) == nil)
        #expect(AnnotationRenderer.balanced(even, content: nil) == nil)
    }

    // MARK: Shadow

    @Test func theShadowHasAStrength() throws {
        let renderer = AnnotationRenderer(image: Self.solid(.ink), scale: 1)
        func below(_ amount: CGFloat) throws -> Double {
            var document = Self.framed(.solid(.white))
            document.frame.shadowAmount = amount
            let image = try #require(renderer.render(document))
            // Just under the capture, where the shadow falls.
            return Self.pixel(image, 200, 253).red
        }
        let none = try below(0)
        let classic = try below(0.5)
        let strong = try below(1)
        #expect(none > 0.99)
        #expect(classic < none - 0.03)
        #expect(strong < classic - 0.03)
    }

    @Test func aWindowWithItsOwnShadowDoesNotGetASecondOne() throws {
        let window = Self.shadowedWindow()
        #expect(ImageSampler.hasOwnShadow(window))
        #expect(!ImageSampler.hasOwnShadow(Self.solid(.white)))
        // Rounded corners alone (a window caught without its shadow) aren't a shadow.
        let bare = Self.image(width: 200, height: 160) { context in
            context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 160), cornerWidth: 20,
                                   cornerHeight: 20, transform: nil))
            context.setFillColor(MarkColour.white.cgColor())
            context.fillPath()
        }
        #expect(!ImageSampler.hasOwnShadow(bare))

        let renderer = AnnotationRenderer(image: window, scale: 1)
        #expect(renderer.ownShadow)
        var document = Self.framed(.solid(.white), size: CGSize(width: 200, height: 160), padding: 40)
        document.frame.shadowAmount = 1
        document.frame.cornerRadius = 30
        #expect(renderer.cornerRadius(document.frame) == 0)
        let image = try #require(renderer.render(document))
        // Beyond the window's own soft shadow, the frame adds none: the padding stays white.
        #expect(Self.pixel(image, 140, 236).red > 0.99)
    }

    /// A window on a clear background with a soft shadow round it, as a window capture is.
    static func shadowedWindow() -> CGImage {
        image(width: 200, height: 160) { context in
            context.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: CGColor(gray: 0, alpha: 0.5))
            context.addPath(CGPath(roundedRect: CGRect(x: 34, y: 30, width: 132, height: 96), cornerWidth: 10,
                                   cornerHeight: 10, transform: nil))
            context.setFillColor(MarkColour.white.cgColor())
            context.fillPath()
        }
    }

    // MARK: Undo and memory

    @Test func onePopoverIsOneUndoStep() {
        let model = CaptureEditorTests.model()
        model.chooseBackground(.gradient(.mist))
        let before = model.document
        let count = model.changeCount
        model.beginLiveChange()
        for angle in stride(from: 0.0, through: 180, by: 45) {
            let gradient = CustomGradient(colours: [.blue, .lavender], angle: angle)
            model.setFrameLive { $0.background = .custom(gradient) }
        }
        model.endLiveChange("Change Background")
        #expect(model.changeCount == count + 1)
        #expect(model.undoManager.undoActionName == "Change Background")
        model.undo()
        #expect(model.document == before)
    }

    @Test func yoursKeepsEachOnceNewestFirstAndNineAtMost() {
        let defaults = CaptureEditorTests.defaults()
        let model = CaptureEditorTests.model(defaults: defaults)
        let first = FrameBackground.solid(.blue)
        let id = model.saveBackground(first)
        model.saveBackground(.solid(.green))
        #expect(model.saveBackground(first) == id)
        #expect(model.styleBook.saved.map(\.background) == [first, .solid(.green)])
        for index in 0..<12 {
            model.saveBackground(.solid(MarkColour(red: Double(index) / 12, green: 0.3, blue: 0.5)))
        }
        #expect(model.styleBook.saved.count == StyleBook.savedLimit)
        // Editing one puts it back where it was.
        let editedID = model.styleBook.saved[3].id
        model.saveBackground(.custom(FrameGradient.ember.custom), replacing: editedID)
        #expect(model.styleBook.saved[3].id == editedID)
        #expect(model.styleBook.saved[3].background == .custom(FrameGradient.ember.custom))
        model.deleteSavedBackground(editedID)
        #expect(!model.styleBook.saved.contains { $0.id == editedID })
        // And it's all still there next time.
        #expect(EditorModel.savedStyleBook(in: defaults).saved == model.styleBook.saved)
    }

    @Test func theLookIsRememberedInPoints() {
        let defaults = CaptureEditorTests.defaults()
        let retina = EditorModel(image: CaptureEditorTests.image(), scale: 2, defaults: defaults)
        retina.chooseBackground(.gradient(.dusk))
        retina.setFrame("Change Padding") { $0.padding = 64 }
        retina.setFrame("Change Shadow") { $0.shadowAmount = 0.8 }
        retina.setFrame("Change Aspect Ratio") { $0.ratio = .square }
        let look = retina.styleBook.frameLook
        #expect(look?.padding == 32)
        #expect(look?.cornerRadius == 10)
        #expect(look?.background == .gradient(.dusk))

        let plain = EditorModel(image: CaptureEditorTests.image(), scale: 1, defaults: defaults)
        plain.chooseBackground(.gradient(.mist))
        #expect(plain.document.frame.padding == 32)
        #expect(plain.document.frame.cornerRadius == 10)
        #expect(plain.document.frame.shadowAmount == 0.8)
        #expect(plain.document.frame.ratio == .square)
        #expect(plain.document.frame.background == .gradient(.mist))
        // In the same step as the background.
        plain.undo()
        #expect(!plain.document.frame.isOn)
    }

    @Test func openingTheFrameAppliesYourLookOnceAndAFreshEditorStillClosesWithEsc() {
        let defaults = CaptureEditorTests.defaults()
        let first = EditorModel(image: CaptureEditorTests.image(), scale: 1, defaults: defaults)
        // Nothing remembered yet: opening the Frame changes nothing.
        first.showsFrame = true
        #expect(!first.document.frame.isOn)
        first.chooseBackground(.gradient(.lagoon))

        let second = EditorModel(image: CaptureEditorTests.image(), scale: 1, defaults: defaults)
        #expect(!second.document.frame.isOn)
        second.showsFrame = true
        #expect(second.document.frame.background == .gradient(.lagoon))
        #expect(second.undoManager.undoActionName == "Add Frame")
        second.chooseBackground(.none)
        second.showsFrame = false
        second.showsFrame = true
        #expect(!second.document.frame.isOn)

        let third = EditorModel(image: CaptureEditorTests.image(), scale: 1, defaults: defaults)
        #expect(third.escape() == .choseSelect)
        #expect(third.escape() == .close)
    }

    // MARK: Magnifier

    static func checkerboard(cell: Int = 10, side: Int = 200) -> CGImage {
        image(width: side, height: side) { context in
            for row in 0..<(side / cell) {
                for column in 0..<(side / cell) {
                    let light = (row + column) % 2 == 0
                    context.setFillColor(light ? MarkColour.white.cgColor() : MarkColour.ink.cgColor())
                    context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
                }
            }
        }
    }

    static func loupe(_ rect: CGRect, zoom: Double = 2, shape: SpotlightShape = .rectangle) -> Mark {
        var mark = Mark(kind: .magnifier, colour: .white, style: StyleBook.defaultStyle(for: .magnifier), start: rect.origin,
                        end: CGPoint(x: rect.maxX, y: rect.maxY))
        mark.style.zoom = zoom
        mark.style.spotlight = shape
        return mark
    }

    @Test func atTwiceTheSizeTheCellsComeOutTwiceAsLarge() throws {
        let renderer = AnnotationRenderer(image: Self.checkerboard(), scale: 1)
        var document = EditorDocument(imageSize: CGSize(width: 200, height: 200), scale: 1)
        document.marks = [Self.loupe(CGRect(x: 40, y: 40, width: 120, height: 120))]
        let image = try #require(renderer.render(document))
        // Source (70…130) is drawn over 40…160: a 10 px cell becomes 20 px.
        func light(_ x: Int, _ y: Int) -> Bool { Self.pixel(image, x, y).red > 0.5 }
        let y = 90
        #expect(light(45, y) == light(55, y))
        #expect(light(50, y) != light(70, y))
        #expect(light(70, y) != light(90, y))
        #expect(light(62, y) == light(78, y))
        // Outside the loupe, the cells are their own size.
        #expect(light(5, 5) != light(15, 5))
    }

    @Test func aMagnifierNeverShowsWhatARedactionHides() throws {
        let secret = MarkColour(hex: 0x00FF00)
        let picture = Self.image(width: 200, height: 200) { context in
            context.setFillColor(MarkColour.white.cgColor())
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            context.setFillColor(secret.cgColor())
            context.fill(CGRect(x: 80, y: 90, width: 40, height: 20))
        }
        let renderer = AnnotationRenderer(image: picture, scale: 1)
        var document = EditorDocument(imageSize: CGSize(width: 200, height: 200), scale: 1)
        var bar = CaptureEditorTests.mark(.redact, CGPoint(x: 75, y: 85), CGPoint(x: 125, y: 115), colour: .ink)
        bar.style.redact = .solid
        document.marks = [Self.loupe(CGRect(x: 30, y: 30, width: 140, height: 140), zoom: 3, shape: .ellipse), bar]
        let image = try #require(renderer.render(document))
        #expect(Self.near(Self.pixel(image, 100, 100), .ink))
        for y in stride(from: 30, to: 170, by: 3) {
            for x in stride(from: 30, to: 170, by: 3) {
                let pixel = Self.pixel(image, x, y)
                #expect(!(pixel.green > 0.6 && pixel.red < 0.4 && pixel.blue < 0.4), "secret showed at \(x), \(y)")
            }
        }

        // A pixelated bar enlarges as the same blocks it shows unmagnified.
        bar.style.redact = .pixelate
        document.marks = [bar]
        let flat = try #require(renderer.render(document))
        document.marks = [Self.loupe(CGRect(x: 40, y: 40, width: 120, height: 120)), bar]
        let enlarged = try #require(renderer.render(document))
        // Canvas (104, 104) shows source (102, 102) at 2×: the same block.
        let a = Self.pixel(flat, 104, 104)
        let b = Self.pixel(enlarged, 104, 104)
        #expect(abs(a.red - b.red) < 0.06 && abs(a.green - b.green) < 0.06 && abs(a.blue - b.blue) < 0.06)
    }

    @Test func atTheEdgeTheSourceSlidesInsteadOfTheLoupe() {
        let area = CGRect(x: 0, y: 0, width: 400, height: 300)
        let corner = Self.loupe(CGRect(x: -60, y: -50, width: 120, height: 120))
        let source = MarkGeometry.magnifierSource(corner, within: area)
        #expect(source.minX == 0)
        #expect(source.minY == 0)
        #expect(source.width == 60)
        let middle = MarkGeometry.magnifierSource(Self.loupe(CGRect(x: 100, y: 100, width: 120, height: 120)), within: area)
        #expect(middle == CGRect(x: 130, y: 130, width: 60, height: 60))
        // A crop is an edge too: nothing cropped away is shown.
        let cropped = MarkGeometry.magnifierSource(Self.loupe(CGRect(x: 280, y: 100, width: 120, height: 120)),
                                                   within: CGRect(x: 0, y: 0, width: 350, height: 300))
        #expect(cropped.maxX == 350)
    }

    @Test func bracketsStepTheZoom() {
        let model = CaptureEditorTests.model()
        model.choose(.magnifier)
        #expect(model.shownStyle.zoom == 2)
        #expect(model.shownStyle.spotlight == .ellipse)
        model.stepSize(up: true)
        #expect(model.shownStyle.zoom == 3)
        model.stepSize(up: true)
        model.stepSize(up: true)
        #expect(model.shownStyle.zoom == 4)
        model.stepSize(up: false)
        model.stepSize(up: false)
        model.stepSize(up: false)
        model.stepSize(up: false)
        #expect(model.shownStyle.zoom == 1.5)
        // A selected magnifier steps too, as one undo step each.
        model.placeMagnifier(at: CGPoint(x: 200, y: 150))
        let placed = model.selectedMarks.first
        #expect(placed?.kind == .magnifier)
        #expect(placed?.rect.width == 120)
        #expect(placed?.style.zoom == 1.5)
        model.stepSize(up: true)
        #expect(model.selectedMarks.first?.style.zoom == 2)
        model.undo()
        #expect(model.selectedMarks.first?.style.zoom == 1.5)
    }

    @Test func magnifiersSitOverEffectsAndUnderEverythingElse() {
        var document = EditorDocument(imageSize: CGSize(width: 400, height: 300))
        let arrow = CaptureEditorTests.mark(.arrow, CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200))
        let spotlight = CaptureEditorTests.mark(.spotlight, CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50))
        let highlight = CaptureEditorTests.mark(.highlighter, CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 10))
        let loupe = Self.loupe(CGRect(x: 80, y: 80, width: 140, height: 140), shape: .ellipse)
        document.marks = [arrow, loupe, spotlight, highlight]
        #expect(document.drawingOrder.map(\.kind) == [.highlighter, .spotlight, .magnifier, .arrow])
        // The arrow drawn over it is what a click on the arrow picks up; elsewhere, the loupe.
        #expect(MarkGeometry.topmost(in: document, at: CGPoint(x: 150, y: 150), tolerance: 4, scale: 1)?.id == arrow.id)
        #expect(MarkGeometry.topmost(in: document, at: CGPoint(x: 150, y: 110), tolerance: 4, scale: 1)?.id == loupe.id)
        // A circle's corners aren't part of it.
        #expect(!MarkGeometry.hitTest(loupe, at: CGPoint(x: 84, y: 84), tolerance: 4, scale: 1))
        #expect(Mark.Kind.magnifier.isEffect)
        #expect(Mark.Kind.magnifier.isColourless)
    }

    @Test func mPicksMagnifyAndAClickPlacesOne() {
        let defaults = UserDefaults(suiteName: "CaptureEditorFrameTests-\(UUID().uuidString)")!
        let model = EditorModel(image: CaptureEditorTests.image(width: 800, height: 500), scale: 2, defaults: defaults)
        let controller = EditorWindowController(model: model, title: "Test")
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let canvas = controller.canvas
        canvas.setZoom(1)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, characters: "m", charactersIgnoringModifiers: "m", isARepeat: false,
                                   keyCode: 46)!
        #expect(EditorCanvas.bareCommand(for: key) == .magnifier)
        controller.perform(.magnifier)
        #expect(model.tool == .magnifier)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewPoint(fromImage: point), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 400, y: 250)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 250)))
        let placed = model.document.marks.first
        #expect(placed?.kind == .magnifier)
        #expect(placed?.rect == CGRect(x: 280, y: 130, width: 240, height: 240))
        #expect(model.undoManager.undoActionName == "Add Magnifier")
        #expect(EditorWindowController.minimumSize.width >= 980)
    }
}

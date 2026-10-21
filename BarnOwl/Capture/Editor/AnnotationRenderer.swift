import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Draws a document: the frame, the cropped image and every mark. The canvas draws with it on
/// screen and `render` exports with it, so what you see is what you get.
@MainActor
final class AnnotationRenderer {
    let image: CGImage
    /// Pixels per point, so marks have sensible pixel sizes.
    let scale: CGFloat
    private let effects: RedactionEffects
    private var pasted: [UUID: (data: Data, image: CGImage)] = [:]

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = max(scale, 0.5)
        effects = RedactionEffects(image: image)
    }

    /// The document flattened at full resolution, in the image's colour space.
    func render(_ document: EditorDocument) -> CGImage? {
        let layout = FrameLayout(document: document)
        let width = Int(layout.canvasSize.width.rounded())
        let height = Int(layout.canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: outputColourSpace, bitmapInfo: info)
            ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: srgb, bitmapInfo: info) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(document, in: context)
        return context.makeImage()
    }

    private var outputColourSpace: CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput { return space }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Draws `document` into `context`, whose user space is canvas pixels with y pointing down.
    /// `editingText` is the text mark being typed, which keeps room for the caret while empty.
    func draw(_ document: EditorDocument, in context: CGContext, editingText: UUID? = nil) {
        let layout = FrameLayout(document: document)
        let frame = document.frame
        let radius: CGFloat = frame.isOn ? frame.cornerRadius : 0
        let clip = MarkGeometry.roundedRect(layout.imageRect, radius: radius)
        let full = CGRect(x: layout.offset.x, y: layout.offset.y, width: CGFloat(image.width), height: CGFloat(image.height))

        if frame.isOn { drawBackground(frame, size: layout.canvasSize, in: context) }

        // The image, with the frame's shadow following its rounded corners (and any transparency).
        context.saveGState()
        let shadowed = frame.isOn && frame.shadow
        if shadowed {
            let blur: CGFloat = min(28 * scale, max(4 * scale, frame.padding * 0.45))
            setShadow(context, offset: blur * 0.3, blur: blur, colour: CGColor(gray: 0, alpha: 0.4))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        context.saveGState()
        context.addPath(clip)
        context.clip()
        drawImage(image, in: full, context)
        context.restoreGState()
        if shadowed { context.endTransparencyLayer() }
        context.restoreGState()

        // Marks live in image coordinates and stay within the image.
        context.saveGState()
        context.addPath(clip)
        context.clip()
        context.translateBy(x: layout.offset.x, y: layout.offset.y)
        drawMarks(document, in: context, editingText: editingText)
        context.restoreGState()
    }

    private func drawMarks(_ document: EditorDocument, in context: CGContext, editingText: UUID?) {
        let numbers = document.counterNumbers
        let ordered = MarkGeometry.drawingOrder(document.marks)
        var spotlightsDrawn = false
        effects.beginPass()
        for mark in ordered {
            switch mark.kind {
            case .redact:
                drawRedaction(mark, in: context)
            case .spotlight:
                guard !spotlightsDrawn else { continue }
                spotlightsDrawn = true
                drawSpotlights(ordered.filter { $0.kind == .spotlight }, area: document.crop, in: context)
            case .highlighter:
                drawHighlight(mark, in: context)
            case .image:
                drawPasted(mark, in: context)
            case .arrow:
                drawArrow(mark, in: context)
            case .line:
                let path = CGMutablePath()
                path.addLines(between: [mark.start, mark.end])
                strokeWithHalo(path, colour: mark.colour, width: MarkGeometry.lineWidth(mark, scale: scale), in: context)
            case .rectangle:
                let path = MarkGeometry.roundedRect(mark.rect, radius: MarkGeometry.rectangleRadius(mark, scale: scale))
                strokeWithHalo(path, colour: mark.colour, width: MarkGeometry.lineWidth(mark, scale: scale), in: context)
            case .ellipse:
                let path = CGPath(ellipseIn: mark.rect, transform: nil)
                strokeWithHalo(path, colour: mark.colour, width: MarkGeometry.lineWidth(mark, scale: scale), in: context)
            case .pen:
                let path = MarkGeometry.smoothPath(mark.points)
                strokeWithHalo(path, colour: mark.colour, width: MarkGeometry.lineWidth(mark, scale: scale), in: context)
            case .filledBox:
                drawFilledBox(mark, in: context)
            case .counter:
                drawCounter(mark, number: numbers[mark.id] ?? 1, in: context)
            case .text:
                drawText(mark, in: context)
            }
        }
        effects.endPass()
    }

    // MARK: Frame and image

    private func drawBackground(_ frame: FrameSettings, size: CGSize, in context: CGContext) {
        let canvas = CGRect(origin: .zero, size: size)
        switch frame.background {
        case .none, .transparent:
            return
        case .solid(let colour):
            context.setFillColor(colour.cgColor())
            context.fill(canvas)
        case .gradient(let gradient):
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let (from, to) = gradient.colours
            let colours: [CGColor] = [from.cgColor(), to.cgColor()]
            let glowColours: [CGColor] = [CGColor(gray: 1, alpha: 0.2), CGColor(gray: 1, alpha: 0)]
            guard let fill = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: [0, 1]),
                  let glow = CGGradient(colorsSpace: space, colors: glowColours as CFArray, locations: [0, 1]) else { return }
            context.saveGState()
            context.clip(to: canvas)
            context.drawLinearGradient(fill, start: .zero, end: CGPoint(x: canvas.maxX, y: canvas.maxY),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            // A soft light from the top left, as through a window.
            let centre = CGPoint(x: canvas.width * 0.18, y: 0)
            let reach: CGFloat = max(canvas.width, canvas.height) * 0.75
            context.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: reach, options: [])
            context.restoreGState()
        }
    }

    /// Draws a bitmap upright in a y-down context.
    private func drawImage(_ image: CGImage, in rect: CGRect, _ context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: Effects

    private func drawRedaction(_ mark: Mark, in context: CGContext) {
        let rect = mark.rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
        let style = mark.style.redact
        if style != .solid, let effect = effects.image(for: rect, style: style, scale: scale) {
            context.saveGState()
            if style == .pixelate { context.interpolationQuality = .none }
            context.addPath(MarkGeometry.roundedRect(rect, radius: style == .blur ? 3 * scale : 0))
            context.clip()
            drawImage(effect, in: rect, context)
            context.restoreGState()
        } else {
            context.addPath(MarkGeometry.roundedRect(mark.rect, radius: 3 * scale))
            context.setFillColor(mark.colour.cgColor())
            context.fillPath()
        }
    }

    /// Dims everything outside the spotlights, once for all of them so they can overlap.
    private func drawSpotlights(_ marks: [Mark], area: CGRect, in context: CGContext) {
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.fill(area)
        context.setBlendMode(.clear)
        for mark in marks {
            context.addPath(MarkGeometry.spotlightPath(mark, scale: scale))
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawHighlight(_ mark: Mark, in context: CGContext) {
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setFillColor(mark.colour.cgColor(alpha: 0.35))
        context.addPath(MarkGeometry.roundedRect(mark.rect, radius: 2 * scale))
        context.fillPath()
        context.restoreGState()
    }

    private func drawPasted(_ mark: Mark, in context: CGContext) {
        guard let picture = pastedImage(mark) else { return }
        context.saveGState()
        setShadow(context, offset: 2 * scale, blur: 10 * scale, colour: CGColor(gray: 0, alpha: 0.3))
        drawImage(picture, in: mark.rect, context)
        context.restoreGState()
    }

    private func pastedImage(_ mark: Mark) -> CGImage? {
        guard let data = mark.imageData else { return nil }
        if let cached = pasted[mark.id], cached.data == data { return cached.image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        pasted[mark.id] = (data, picture)
        return picture
    }

    // MARK: Shapes

    /// What sits under a stroke so it reads on any background: white, or ink under white marks.
    private func haloColour(for colour: MarkColour) -> CGColor {
        colour.luminance > 0.8 ? MarkColour.ink.cgColor(alpha: 0.75) : CGColor(gray: 1, alpha: 1)
    }

    private func setSoftShadow(_ context: CGContext) {
        setShadow(context, offset: 0.5 * scale, blur: 2.5 * scale, colour: CGColor(gray: 0, alpha: 0.28))
    }

    /// Shadows are set in device space; this takes user-space lengths, with y pointing down.
    private func setShadow(_ context: CGContext, offset: CGFloat, blur: CGFloat, colour: CGColor) {
        let shift = context.convertToDeviceSpace(CGSize(width: 0, height: offset))
        let spread = context.convertToDeviceSpace(CGSize(width: blur, height: 0))
        context.setShadow(offset: shift, blur: hypot(spread.width, spread.height), color: colour)
    }

    private func strokeWithHalo(_ path: CGPath, colour: MarkColour, width: CGFloat, in context: CGContext) {
        let halo = MarkGeometry.haloWidth(forStroke: width, scale: scale)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.saveGState()
        setSoftShadow(context)
        context.addPath(path)
        context.setLineWidth(width + 2 * halo)
        context.setStrokeColor(haloColour(for: colour))
        context.strokePath()
        context.restoreGState()
        context.addPath(path)
        context.setLineWidth(width)
        context.setStrokeColor(colour.cgColor())
        context.strokePath()
        context.restoreGState()
    }

    /// Fills `path` over a halo ring; `soften` rounds the shape's corners a little.
    private func fillWithHalo(_ path: CGPath, colour: MarkColour, halo: CGFloat, soften: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setLineJoin(.round)
        context.saveGState()
        setSoftShadow(context)
        context.addPath(path)
        context.setLineWidth(soften + 2 * halo)
        context.setFillColor(haloColour(for: colour))
        context.setStrokeColor(haloColour(for: colour))
        context.drawPath(using: .fillStroke)
        context.restoreGState()
        context.addPath(path)
        context.setLineWidth(soften)
        context.setFillColor(colour.cgColor())
        context.setStrokeColor(colour.cgColor())
        context.drawPath(using: soften > 0 ? .fillStroke : .fill)
        context.restoreGState()
    }

    private func drawArrow(_ mark: Mark, in context: CGContext) {
        let width = MarkGeometry.arrowWidth(mark, scale: scale)
        let halo = MarkGeometry.haloWidth(forStroke: width, scale: scale)
        fillWithHalo(MarkGeometry.arrowOutline(mark, scale: scale), colour: mark.colour, halo: halo,
                     soften: max(1, width * 0.16), in: context)
    }

    private func drawFilledBox(_ mark: Mark, in context: CGContext) {
        let path = MarkGeometry.roundedRect(mark.rect, radius: MarkGeometry.filledBoxRadius(scale: scale))
        fillWithHalo(path, colour: mark.colour, halo: 1.5 * scale, soften: 0, in: context)
    }

    // MARK: Counters

    private func drawCounter(_ mark: Mark, number: Int, in context: CGContext) {
        let circle = MarkGeometry.counterCircle(mark, scale: scale)
        let radius: CGFloat = circle.width / 2
        let ring: CGFloat = max(1.5 * scale, radius * 0.15)
        let tail = MarkGeometry.counterTail(mark, scale: scale)
        let ringColour = mark.colour.luminance > 0.8 ? MarkColour.ink.cgColor() : CGColor(gray: 1, alpha: 1)

        // The badge and its pointer are drawn one after the other (not as one path, whose
        // overlap could cancel out), with one shadow for the pair.
        context.saveGState()
        context.setLineJoin(.round)
        setShadow(context, offset: 1 * scale, blur: 3.5 * scale, colour: CGColor(gray: 0, alpha: 0.32))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setLineWidth(ring * 2)
        context.setFillColor(ringColour)
        context.setStrokeColor(ringColour)
        context.addEllipse(in: circle)
        context.drawPath(using: .fillStroke)
        if let tail {
            context.addPath(tail)
            context.drawPath(using: .fillStroke)
        }
        context.setFillColor(mark.colour.cgColor())
        context.fillEllipse(in: circle)
        if let tail {
            context.addPath(tail)
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()

        let digits = String(number)
        let factor: CGFloat = digits.count == 1 ? 1.1 : (digits.count == 2 ? 0.92 : 0.74)
        drawCentred(digits, font: Self.numberFont(size: radius * factor), colour: mark.colour.contrasting,
                    at: CGPoint(x: circle.midX, y: circle.midY), in: context)
    }

    static func numberFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Draws a short label with its glyphs (not its line box) centred on `centre`.
    private func drawCentred(_ text: String, font: NSFont, colour: MarkColour, at centre: CGPoint, in context: CGContext) {
        let colourKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let string = NSAttributedString(string: text, attributes: [.font: font, colourKey: colour.cgColor()])
        let line = CTLineCreateWithAttributedString(string)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: centre.x - bounds.midX, y: centre.y + bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: Text

    private func drawText(_ mark: Mark, in context: CGContext) {
        let layout = MarkGeometry.textLayout(mark, scale: scale)
        let em: CGFloat = layout.font.pointSize
        let colour = mark.colour
        let darkOnWhite = colour.luminance > 0.8
        withAppKit(context) {
            switch mark.style.text {
            case .box:
                context.saveGState()
                setShadow(context, offset: em * 0.05, blur: em * 0.22, colour: CGColor(gray: 0, alpha: 0.3))
                context.addPath(MarkGeometry.roundedRect(layout.boxRect, radius: layout.cornerRadius))
                context.setFillColor(colour.cgColor())
                context.fillPath()
                context.restoreGState()
                drawString(mark.text, layout: layout, fill: colour.contrasting)
            case .halo:
                let halo: MarkColour = darkOnWhite ? .ink : .white
                context.saveGState()
                context.setLineJoin(.round)
                // A fine edge with a soft glow beyond it: lighter than the outline style.
                setShadow(context, offset: 0, blur: em * 0.2, colour: halo.cgColor(alpha: darkOnWhite ? 0.7 : 1))
                drawString(mark.text, layout: layout, stroke: halo, strokeWidth: 11)
                context.restoreGState()
                drawString(mark.text, layout: layout, fill: colour)
            case .outline:
                let fill: MarkColour = darkOnWhite ? .ink : .white
                context.saveGState()
                context.setLineJoin(.round)
                setShadow(context, offset: em * 0.03, blur: em * 0.1, colour: CGColor(gray: 0, alpha: 0.3))
                drawString(mark.text, layout: layout, stroke: colour, strokeWidth: 26)
                context.restoreGState()
                drawString(mark.text, layout: layout, fill: fill)
            }
        }
    }

    private func drawString(_ text: String, layout: MarkGeometry.TextLayout, fill: MarkColour) {
        guard !text.isEmpty else { return }
        let colour = NSColor(cgColor: fill.cgColor()) ?? .white
        let string = NSAttributedString(string: text, attributes: [.font: layout.font, .foregroundColor: colour])
        string.draw(with: layout.textRect, options: MarkGeometry.textOptions, context: nil)
    }

    /// Strokes the glyph outlines only; `strokeWidth` is a percentage of the font size.
    private func drawString(_ text: String, layout: MarkGeometry.TextLayout, stroke: MarkColour, strokeWidth: CGFloat) {
        guard !text.isEmpty else { return }
        let colour = NSColor(cgColor: stroke.cgColor()) ?? .white
        let string = NSAttributedString(string: text, attributes: [
            .font: layout.font, .foregroundColor: colour, .strokeColor: colour, .strokeWidth: strokeWidth,
        ])
        string.draw(with: layout.textRect, options: MarkGeometry.textOptions, context: nil)
    }

    /// Runs `body` with AppKit drawing into `context`, upright in its y-down space.
    private func withAppKit(_ context: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Pixelate and blur, made with Core Image from the original pixels under a redaction, and
/// kept until the redaction moves or goes.
@MainActor
final class RedactionEffects {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let source: CIImage
    private let height: CGFloat
    private let colourSpace: CGColorSpace
    private var cache: [Key: CGImage] = [:]
    private var used: Set<Key> = []

    private struct Key: Hashable {
        let x, y, width, height: Int
        let style: RedactStyle
    }

    init(image: CGImage) {
        source = CIImage(cgImage: image)
        height = CGFloat(image.height)
        if let space = image.colorSpace, space.model == .rgb {
            colourSpace = space
        } else {
            colourSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
    }

    func beginPass() {
        used.removeAll()
    }

    /// Lets go of effects no redaction used in this pass.
    func endPass() {
        cache = cache.filter { used.contains($0.key) }
    }

    /// The effect for `rect` (integral, in image pixels, y down).
    func image(for rect: CGRect, style: RedactStyle, scale: CGFloat) -> CGImage? {
        let key = Key(x: Int(rect.minX), y: Int(rect.minY), width: Int(rect.width), height: Int(rect.height), style: style)
        used.insert(key)
        if let cached = cache[key] { return cached }
        guard let made = make(rect, style: style, scale: scale) else { return nil }
        cache[key] = made
        return made
    }

    private func make(_ rect: CGRect, style: RedactStyle, scale: CGFloat) -> CGImage? {
        // Core Image puts the origin at the bottom left.
        let area = CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        let shortSide: CGFloat = min(rect.width, rect.height)
        let input = source.cropped(to: area).clampedToExtent()
        let output: CIImage?
        switch style {
        case .pixelate:
            // Averaging first, so each block hides what's in it rather than sampling one pixel.
            let block: CGFloat = max(8 * scale, shortSide / 6).rounded()
            let soften = CIFilter.gaussianBlur()
            soften.inputImage = input
            soften.radius = Float(block * 0.3)
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = soften.outputImage
            pixellate.scale = Float(block)
            pixellate.center = CGPoint(x: area.minX, y: area.minY)
            output = pixellate.outputImage
        case .blur:
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = input
            blur.radius = Float(max(6 * scale, shortSide / 5))
            output = blur.outputImage
        case .solid:
            output = nil
        }
        guard let output else { return nil }
        return Self.context.createCGImage(output.cropped(to: area), from: area, format: .RGBA8, colorSpace: colourSpace)
    }
}

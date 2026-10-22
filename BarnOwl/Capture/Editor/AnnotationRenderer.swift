import AppKit
import CoreImage
import CoreText
import ImageIO
import Synchronization

/// Draws a document: the frame, the cropped image and every mark. The canvas draws with it on
/// screen and `render` exports with it, so what you see is what you get. It holds no UI state,
/// so exporting runs off the main thread.
final class AnnotationRenderer: Sendable {
    let image: CGImage
    /// Pixels per point, so marks have sensible pixel sizes.
    let scale: CGFloat
    let luminance: LuminanceMap?
    /// A window caught with its shadow on a clear background: the frame leaves its corners and
    /// its shadow alone, rather than drawing a second one.
    let ownShadow: Bool
    private let desktopPicture = Mutex<Picture?>(nil)
    private let edgeColours = Mutex<[EdgeKey: MarkColour]>([:])
    private let effects: RedactionEffects
    private let pasted = Mutex<[UUID: PastedImage]>([:])

    private struct PastedImage: @unchecked Sendable {
        let data: Data
        let image: CGImage
    }

    private struct Picture: @unchecked Sendable {
        let image: CGImage
    }

    private struct EdgeKey: Hashable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    init(image: CGImage, scale: CGFloat, desktop: CGImage? = nil) {
        self.image = image
        self.scale = max(scale, 0.5)
        luminance = LuminanceMap(image: image)
        ownShadow = ImageSampler.hasOwnShadow(image)
        effects = RedactionEffects(image: image)
        if let desktop { desktopPicture.withLock { $0 = Picture(image: desktop) } }
    }

    /// The desktop picture, softened, for the Desktop background; it loads after the editor opens.
    var desktop: CGImage? {
        desktopPicture.withLock { $0?.image }
    }

    func setDesktop(_ picture: CGImage?) {
        desktopPicture.withLock { $0 = picture.map { Picture(image: $0) } }
    }

    /// The current desktop picture, small and softly blurred, or nil if it isn't a picture.
    static func loadDesktopPicture(from url: URL) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1200,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let input = CIImage(cgImage: thumbnail)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: 18).cropped(to: input.extent)
        let context = CIContext(options: [.cacheIntermediates: false])
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: space)
    }

    // MARK: Export

    /// The document flattened at full resolution, in sRGB.
    func render(_ document: EditorDocument) -> CGImage? {
        let layout = FrameLayout(document: document)
        let width = Int(layout.canvasSize.width.rounded())
        let height = Int(layout.canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: srgb, bitmapInfo: info) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        drawBackdrop(document, in: context, includingImage: true)
        drawMarks(document, in: context, imageUnderneath: true)
        return context.makeImage()
    }

    // MARK: Frame and image

    /// The frame's background and the image with its shadow. `includingImage` false draws the
    /// image only to cast the shadow, for the canvas, which shows the image itself in a layer.
    func drawBackdrop(_ document: EditorDocument, in context: CGContext, includingImage: Bool) {
        let layout = FrameLayout(document: document)
        let frame = document.frame
        if frame.isOn { drawBackground(frame, layout: layout, in: context) }
        let shadowed = frame.isOn && frame.shadow && !ownShadow
        let card = hasCard(frame)
        guard includingImage || shadowed || card else { return }
        let clip = MarkGeometry.roundedRect(card ? layout.cardRect : layout.imageRect, radius: cornerRadius(frame))
        let full = CGRect(x: layout.offset.x, y: layout.offset.y, width: CGFloat(image.width), height: CGFloat(image.height))
        context.saveGState()
        if shadowed {
            // 50% is the classic shadow; stronger is darker and softer, weaker lighter and tighter.
            let amount: CGFloat = min(max(frame.shadowAmount, 0), 1)
            let base: CGFloat = min(28 * scale, max(4 * scale, frame.padding * 0.45))
            let blur: CGFloat = base * (0.6 + 0.8 * amount)
            setShadow(context, offset: blur * 0.3, blur: blur, colour: CGColor(gray: 0, alpha: 0.8 * amount))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        context.saveGState()
        context.addPath(clip)
        context.clip()
        if card {
            // The card, in the capture's own edge colour, so the capture runs on into it.
            context.setFillColor(edgeColour(for: document.crop).cgColor())
            context.fill(layout.cardRect)
            context.clip(to: layout.imageRect)
        }
        // Without a card, the image is drawn even for the canvas: its shape casts the shadow.
        if includingImage || !card { drawImage(image, in: full, context) }
        context.restoreGState()
        if shadowed { context.endTransparencyLayer() }
        context.restoreGState()
    }

    /// The capture's corner radius on the frame: none unframed, or when it has its own shadow.
    func cornerRadius(_ frame: FrameSettings) -> CGFloat {
        frame.isOn && !ownShadow ? frame.cornerRadius : 0
    }

    /// Whether the capture sits on a card: an inset, and not a window with its own shadow (whose
    /// clear margin has no colour to carry on).
    func hasCard(_ frame: FrameSettings) -> Bool {
        frame.isOn && frame.inset > 0 && !ownShadow
    }

    /// The colour around the crop's edge, which the card takes: the median of a ring two pixels deep.
    func edgeColour(for crop: CGRect) -> MarkColour {
        let area = crop.integral
        let key = EdgeKey(x: Int(area.minX), y: Int(area.minY), width: Int(area.width), height: Int(area.height))
        if let cached = edgeColours.withLock({ $0[key] }) { return cached }
        let colour = ImageSampler.edgeColour(in: image, crop: area)
        edgeColours.withLock { $0[key] = colour }
        return colour
    }

    /// Every mark, clipped to the image. `imageUnderneath` false (on the canvas, where the image
    /// is a separate layer) makes highlights carry the pixels they blend with.
    func drawMarks(_ document: EditorDocument, in context: CGContext, imageUnderneath: Bool, editingText: UUID? = nil) {
        let layout = FrameLayout(document: document)
        let clip: CGRect = hasCard(document.frame) ? layout.cardRect : layout.imageRect
        context.saveGState()
        context.addPath(MarkGeometry.roundedRect(clip, radius: cornerRadius(document.frame)))
        context.clip()
        context.translateBy(x: layout.offset.x, y: layout.offset.y)
        let numbers = document.counterNumbers
        let ordered = document.drawingOrder
        let spotlights = ordered.filter { $0.kind == .spotlight }
        // What a magnifier enlarges with the image: never anything a redaction hides.
        let underneath = ordered.filter { $0.kind == .highlighter || $0.kind == .redact }
        // Spotlights dim the whole card, its inset too.
        let inset: CGFloat = hasCard(document.frame) ? layout.imageRect.minX - layout.cardRect.minX : 0
        let dimmed = document.crop.insetBy(dx: -inset, dy: -inset)
        var spotlightsDrawn = false
        for mark in ordered {
            switch mark.kind {
            case .highlighter:
                drawHighlight(mark, imageUnderneath: imageUnderneath, in: context)
            case .redact:
                drawRedaction(mark, in: context)
            case .magnifier:
                drawMagnifier(mark, effects: underneath, area: document.crop, in: context)
            case .spotlight:
                guard !spotlightsDrawn else { continue }
                spotlightsDrawn = true
                drawSpotlights(spotlights, area: dimmed, in: context)
            default:
                withOpacity(mark.style.opacity, context) {
                    drawObject(mark, number: numbers[mark.id] ?? 1, editing: mark.id == editingText, in: context)
                }
            }
        }
        context.restoreGState()
    }

    private func drawObject(_ mark: Mark, number: Int, editing: Bool, in context: CGContext) {
        switch mark.kind {
        case .arrow: drawArrow(mark, in: context)
        case .rectangle, .ellipse: drawShape(mark, in: context)
        case .pen:
            let path = MarkGeometry.smoothPath(mark.points)
            strokeWithHalo(path, mark: mark, width: MarkGeometry.lineWidth(mark, scale: scale), in: context)
        case .counter: drawCounter(mark, label: mark.style.counterFormat.label(number), editing: editing, in: context)
        case .text: drawText(mark, in: context)
        case .image: drawPasted(mark, in: context)
        case .highlighter, .redact, .spotlight, .magnifier: break
        }
    }

    private func withOpacity(_ opacity: Double, _ context: CGContext, _ body: () -> Void) {
        guard opacity < 0.999 else { return body() }
        context.saveGState()
        context.setAlpha(CGFloat(max(0.05, opacity)))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawBackground(_ frame: FrameSettings, layout: FrameLayout, in context: CGContext) {
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        let focus = CGPoint(x: layout.imageRect.midX, y: layout.imageRect.midY)
        drawBackground(frame.background, in: canvas, focus: focus, context)
    }

    /// `focus` is where a radial gradient spreads from: the capture's centre.
    private func drawBackground(_ background: FrameBackground, in canvas: CGRect, focus: CGPoint, _ context: CGContext) {
        switch background {
        case .none, .transparent:
            return
        case .solid(let colour):
            context.setFillColor(colour.cgColor())
            context.fill(canvas)
        case .desktop:
            guard let desktop else {
                GradientPainter.paint(.mist, in: canvas, context)
                return
            }
            // Fills the canvas, like the desktop fills the screen.
            let across: CGFloat = canvas.width / CGFloat(desktop.width)
            let down: CGFloat = canvas.height / CGFloat(desktop.height)
            let factor: CGFloat = max(across, down)
            let width: CGFloat = CGFloat(desktop.width) * factor
            let height: CGFloat = CGFloat(desktop.height) * factor
            let x: CGFloat = (canvas.width - width) / 2
            let y: CGFloat = (canvas.height - height) / 2
            let rect = CGRect(x: x, y: y, width: width, height: height)
            context.saveGState()
            context.clip(to: canvas)
            drawImage(desktop, in: rect, context)
            context.restoreGState()
        case .gradient(let gradient):
            GradientPainter.paint(gradient, in: canvas, context)
        case .custom(let gradient):
            GradientPainter.paint(gradient, in: canvas, focus: focus, context)
        }
    }

    /// Draws a bitmap upright in a y-down context.
    private func drawImage(_ picture: CGImage, in rect: CGRect, _ context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(picture, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: Effects

    /// A loupe: the image under it enlarged about its centre, with the highlights and redactions
    /// on it enlarged too, so it never shows what a redaction hides. At the edge of `area` (the
    /// crop) the source slides inward rather than reaching past it.
    private func drawMagnifier(_ mark: Mark, effects underneath: [Mark], area: CGRect, in context: CGContext) {
        let rect = mark.rect
        guard rect.width >= 2, rect.height >= 2 else { return }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let source = MarkGeometry.magnifierSource(mark, within: area.intersection(bounds))
        guard source.width > 0, source.height > 0 else { return }
        let shape = MarkGeometry.magnifierPath(mark, scale: scale)
        let ring: CGFloat = 3 * scale

        // A soft shadow lifts it off the capture.
        context.saveGState()
        setShadow(context, offset: 2 * scale, blur: 8 * scale, colour: CGColor(gray: 0, alpha: 0.3))
        context.addPath(shape)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / source.width, y: rect.height / source.height)
        context.translateBy(x: -source.minX, y: -source.minY)
        context.interpolationQuality = .high
        drawImage(image, in: bounds, context)
        for effect in underneath {
            if effect.kind == .redact {
                drawRedaction(effect, in: context)
            } else {
                drawHighlight(effect, imageUnderneath: true, in: context)
            }
        }
        context.restoreGState()

        // A white ring with an ink hairline either side, as Preview's loupe has.
        context.saveGState()
        context.addPath(shape)
        context.setStrokeColor(MarkColour.ink.cgColor(alpha: 0.28))
        context.setLineWidth(ring + scale)
        context.strokePath()
        context.addPath(shape)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(ring)
        context.strokePath()
        context.restoreGState()
    }

    private func drawRedaction(_ mark: Mark, in context: CGContext) {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = mark.rect.intersection(bounds)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
        let style = mark.style.redact
        switch style {
        case .solid:
            context.addPath(MarkGeometry.roundedRect(mark.rect, radius: 2 * scale))
            context.setFillColor(mark.colour.cgColor())
            context.fillPath()
        case .pixelate:
            let block = max(2, Int((mark.style.strength.block * scale).rounded()))
            guard let small = effects.pixelated(block: block) else { return }
            context.saveGState()
            context.interpolationQuality = .none
            context.clip(to: rect)
            drawImage(small, in: bounds, context)
            context.restoreGState()
        case .blur:
            let radius = max(2, Int((mark.style.strength.radius * scale).rounded()))
            guard let small = effects.blurred(radius: radius) else { return }
            context.saveGState()
            context.interpolationQuality = .high
            context.addPath(MarkGeometry.roundedRect(rect, radius: 3 * scale))
            context.clip()
            drawImage(small, in: bounds, context)
            context.restoreGState()
        }
    }

    /// Dims everything outside the spotlights, once for all of them so they can overlap.
    private func drawSpotlights(_ marks: [Mark], area: CGRect, in context: CGContext) {
        let dim: Double = marks.last?.style.dim ?? 0.5
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(CGColor(gray: 0, alpha: CGFloat(dim)))
        context.fill(area)
        context.setBlendMode(.clear)
        for mark in marks {
            context.addPath(MarkGeometry.spotlightPath(mark, scale: scale))
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Whether a highlight over `rect` screens (lightens) rather than multiplies: on dark areas,
    /// where multiplying would vanish.
    func highlightScreens(_ rect: CGRect) -> Bool {
        (luminance?.mean(in: rect) ?? 1) < 0.35
    }

    private func drawHighlight(_ mark: Mark, imageUnderneath: Bool, in context: CGContext) {
        let path = MarkGeometry.roundedRect(mark.rect, radius: 2 * scale)
        let screens = highlightScreens(mark.rect)
        context.saveGState()
        context.addPath(path)
        context.clip()
        if !imageUnderneath {
            // Blend with the image's own pixels, so the canvas looks like the export. Only the
            // part under the highlight is drawn (a crop shares the image's pixels, no copy).
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let area = mark.rect.integral.intersection(bounds)
            if !area.isNull, let part = image.cropping(to: area) {
                drawImage(part, in: area, context)
            }
        }
        if screens {
            // On dark areas the highlight adds light; yellow leans amber, which reads as a
            // highlight there, where a dimmed yellow turns olive.
            let colour = mark.colour.isLight ? mark.colour.mixed(with: .amber, 0.4) : mark.colour
            context.setBlendMode(.plusLighter)
            context.setFillColor(colour.cgColor(alpha: 0.42))
        } else {
            context.setBlendMode(.multiply)
            context.setFillColor(mark.colour.cgColor(alpha: 0.6))
        }
        context.fill(mark.rect)
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
        if let cached = pasted.withLock({ $0[mark.id] }), cached.data == data { return cached.image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        pasted.withLock { $0[mark.id] = PastedImage(data: data, image: picture) }
        return picture
    }

    // MARK: Shapes

    /// What sits under a stroke so it reads on any background: ink at 55% under light colours
    /// (yellow, white); white under the rest, except on dark areas, where a white rim would look
    /// like a sticker and a soft ink one keeps the mark crisp instead.
    func haloIsInk(_ mark: Mark) -> Bool {
        if mark.colour.isLight { return true }
        let area = MarkGeometry.bounds(mark, scale: scale)
        guard !area.isNull, let luminance else { return false }
        // The map is gamma-encoded grey: 0.3 is a dark area, well below mid grey.
        return luminance.mean(in: area) < 0.3
    }

    private func haloColour(_ mark: Mark) -> CGColor {
        guard haloIsInk(mark) else { return CGColor(gray: 1, alpha: 1) }
        return MarkColour.ink.cgColor(alpha: mark.colour.isLight ? 0.55 : 0.6)
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

    private func strokeWithHalo(_ path: CGPath, mark: Mark, width: CGFloat, in context: CGContext) {
        let halo = MarkGeometry.haloWidth(mark, scale: scale)
        let dash = MarkGeometry.dashPattern(mark.style.dash, width: width)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if let dash { context.setLineDash(phase: 0, lengths: dash) }
        context.saveGState()
        setSoftShadow(context)
        context.addPath(path)
        context.setLineWidth(width + 2 * halo)
        context.setStrokeColor(haloColour(mark))
        context.strokePath()
        context.restoreGState()
        context.addPath(path)
        context.setLineWidth(width)
        context.setStrokeColor(mark.colour.cgColor())
        context.strokePath()
        context.restoreGState()
    }

    /// Fills `path` over a halo ring; `soften` rounds the shape's corners a little.
    private func fillWithHalo(_ path: CGPath, mark: Mark, halo: CGFloat, soften: CGFloat, in context: CGContext) {
        let colour = mark.colour
        let ring = haloColour(mark)
        context.saveGState()
        context.setLineJoin(.round)
        context.saveGState()
        setSoftShadow(context)
        context.addPath(path)
        context.setLineWidth(soften + 2 * halo)
        context.setFillColor(ring)
        context.setStrokeColor(ring)
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
        if mark.style.heads == .none {
            strokeWithHalo(MarkGeometry.linePath(mark), mark: mark, width: MarkGeometry.plainLineWidth(mark, scale: scale),
                           in: context)
            return
        }
        let width = MarkGeometry.arrowWidth(mark, scale: scale)
        fillWithHalo(MarkGeometry.arrowOutline(mark, scale: scale), mark: mark,
                     halo: MarkGeometry.haloWidth(mark, scale: scale), soften: max(1, width * 0.16), in: context)
    }

    private func drawShape(_ mark: Mark, in context: CGContext) {
        let path: CGPath = mark.kind == .ellipse
            ? CGPath(ellipseIn: mark.rect, transform: nil)
            : MarkGeometry.roundedRect(mark.rect, radius: MarkGeometry.rectangleRadius(mark, scale: scale))
        switch mark.style.fill {
        case .solid:
            fillWithHalo(path, mark: mark, halo: MarkGeometry.haloWidth(mark, scale: scale), soften: 0, in: context)
        case .tinted:
            context.saveGState()
            context.addPath(path)
            context.setFillColor(mark.colour.cgColor(alpha: 0.2))
            context.fillPath()
            context.restoreGState()
            strokeWithHalo(path, mark: mark, width: MarkGeometry.lineWidth(mark, scale: scale), in: context)
        case .none:
            strokeWithHalo(path, mark: mark, width: MarkGeometry.lineWidth(mark, scale: scale), in: context)
        }
    }

    // MARK: Counters

    private func drawCounter(_ mark: Mark, label: String, editing: Bool, in context: CGContext) {
        let circle = MarkGeometry.counterCircle(mark, scale: scale)
        let radius: CGFloat = circle.width / 2
        let large = SizeLadder.isLarge(mark.style.weight, kind: .counter)
        let ring: CGFloat = (large ? 2.5 : 2) * scale
        let tail = MarkGeometry.counterTail(mark, scale: scale)
        let fill = mark.colour.boxFill
        let ringColour = mark.colour.isLight ? MarkColour.ink.cgColor(alpha: 0.55) : CGColor(gray: 1, alpha: 1)
        let tag: MarkGeometry.CounterLabel? = (mark.text.isEmpty && !editing) ? nil : MarkGeometry.counterLabel(mark, scale: scale)

        // The tag, badge and pointer are drawn one after the other (not as one path, whose
        // overlap could cancel out), with one shadow for them all.
        context.saveGState()
        context.setLineJoin(.round)
        setShadow(context, offset: 1 * scale, blur: 3.5 * scale, colour: CGColor(gray: 0, alpha: 0.32))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setLineWidth(ring * 2)
        context.setFillColor(ringColour)
        context.setStrokeColor(ringColour)
        if let tag {
            let pill = MarkGeometry.roundedRect(tag.pill, radius: tag.pill.height / 2)
            context.addPath(pill)
            context.drawPath(using: .fillStroke)
            context.addPath(pill)
            context.setFillColor(fill.cgColor())
            context.fillPath()
            context.setFillColor(ringColour)
        }
        context.addEllipse(in: circle)
        context.drawPath(using: .fillStroke)
        if let tail {
            context.addPath(tail)
            context.drawPath(using: .fillStroke)
        }
        context.setFillColor(fill.cgColor())
        context.fillEllipse(in: circle)
        if let tail {
            context.addPath(tail)
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()

        let factor: CGFloat = label.count == 1 ? 1.1 : (label.count == 2 ? 0.88 : 0.68)
        let font = MarkGeometry.counterFont(size: radius * factor) as CTFont
        drawCentred(label, font: font, colour: fill.textOnFill, at: CGPoint(x: circle.midX, y: circle.midY), in: context)
        if let tag, !mark.text.isEmpty {
            drawLine(tag.line, at: tag.baseline, fill: fill.textOnFill.cgColor(), in: context)
        }
    }

    /// Draws a short label with its glyphs (not its line box) centred on `centre`.
    private func drawCentred(_ text: String, font: CTFont, colour: MarkColour, at centre: CGPoint, in context: CGContext) {
        let line = MarkGeometry.line(text, font: font)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let origin = CGPoint(x: centre.x - bounds.midX, y: centre.y + bounds.midY)
        drawLine(line, at: origin, fill: colour.cgColor(), in: context)
    }

    /// Draws one line upright in a y-down context, with its baseline at `origin`.
    private func drawLine(_ line: CTLine, at origin: CGPoint, fill: CGColor? = nil, stroke: CGColor? = nil,
                          strokeWidth: CGFloat = 0, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = origin
        if let stroke {
            context.setTextDrawingMode(.stroke)
            context.setLineJoin(.round)
            context.setLineWidth(strokeWidth)
            context.setStrokeColor(stroke)
        } else {
            context.setTextDrawingMode(.fill)
            context.setFillColor(fill ?? CGColor(gray: 0, alpha: 1))
        }
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: Text

    /// The colours a text mark uses: the box behind it (if any) and the glyphs.
    struct TextColours {
        let box: MarkColour?
        let text: MarkColour
    }

    static func textColours(_ mark: Mark) -> TextColours {
        let colour = mark.colour
        switch mark.style.textStyle {
        case .plain:
            return TextColours(box: nil, text: colour)
        case .box, .callout:
            return TextColours(box: colour.boxFill, text: colour.boxFill.textOnFill)
        case .soft:
            let box = colour.mixed(with: .white, 0.84)
            var text = colour.mixed(with: .ink, 0.3)
            var step = 0
            while text.contrast(with: box) < 4.5, step < 6 {
                text = text.mixed(with: .ink, 0.3)
                step += 1
            }
            return TextColours(box: box, text: text)
        case .outline:
            return TextColours(box: nil, text: colour.isLight ? .ink : .white)
        }
    }

    private func drawText(_ mark: Mark, in context: CGContext) {
        let layout = MarkGeometry.textLayout(mark, scale: scale)
        let em: CGFloat = CGFloat(mark.style.fontSize) * scale
        let colours = Self.textColours(mark)
        let colour = mark.colour
        if let box = colours.box {
            // The box and a callout's pointer share one shadow.
            context.saveGState()
            setShadow(context, offset: em * 0.05, blur: em * 0.22, colour: CGColor(gray: 0, alpha: 0.28))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setFillColor(box.cgColor())
            if mark.style.textStyle == .callout, let tail = MarkGeometry.calloutTail(mark, layout: layout, scale: scale) {
                context.addPath(tail)
                context.fillPath()
            }
            context.addPath(MarkGeometry.roundedRect(layout.boxRect, radius: layout.cornerRadius))
            context.fillPath()
            context.endTransparencyLayer()
            context.restoreGState()
        }
        guard !mark.text.isEmpty else { return }
        switch mark.style.textStyle {
        case .plain where colour.isLight:
            // Yellow and white text: a fine ink edge and a soft shadow, not a thick ring that
            // makes it look like a sticker.
            context.saveGState()
            setShadow(context, offset: 1 * scale, blur: 2 * scale, colour: CGColor(gray: 0, alpha: 0.3))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawLines(layout, stroke: MarkColour.ink.cgColor(alpha: 0.4), strokeWidth: 2 * scale, in: context)
            context.endTransparencyLayer()
            context.restoreGState()
        case .plain:
            let large: Bool = mark.style.fontSize >= 32
            let halo: CGFloat = (large ? 2 : 1.5) * scale
            context.saveGState()
            // A soft glow beyond the crisp edge; lighter under ink halos so light text stays clean.
            let ink = haloIsInk(mark)
            let glow: CGColor = ink ? MarkColour.ink.cgColor(alpha: 0.25) : CGColor(gray: 1, alpha: 0.9)
            setShadow(context, offset: 0, blur: em * 0.12, colour: glow)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawLines(layout, stroke: haloColour(mark), strokeWidth: halo * 2, in: context)
            context.endTransparencyLayer()
            context.restoreGState()
        case .outline:
            context.saveGState()
            setShadow(context, offset: em * 0.03, blur: em * 0.1, colour: CGColor(gray: 0, alpha: 0.3))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawLines(layout, stroke: colour.cgColor(), strokeWidth: em * 0.24, in: context)
            context.endTransparencyLayer()
            context.restoreGState()
        case .box, .soft, .callout:
            break
        }
        drawLines(layout, fill: colours.text.cgColor(), in: context)
    }

    private func drawLines(_ layout: MarkGeometry.TextLayout, fill: CGColor? = nil, stroke: CGColor? = nil,
                           strokeWidth: CGFloat = 0, in context: CGContext) {
        for index in layout.lines.indices {
            drawLine(layout.lines[index], at: layout.baseline(index), fill: fill, stroke: stroke, strokeWidth: strokeWidth,
                     in: context)
        }
    }

    // MARK: Pictures for the options bar and the Frame inspector

    /// A background on its own at `size` points, as the frame would draw it behind a capture in
    /// the middle. Nil for backgrounds that aren't painted (none, transparent) or a desktop
    /// picture that hasn't loaded.
    func backgroundSample(_ background: FrameBackground, size: CGSize, pixelsPerPoint: CGFloat) -> CGImage? {
        switch background {
        case .none, .transparent: return nil
        case .desktop where desktop == nil: return nil
        default: break
        }
        let width = Int((size.width * pixelsPerPoint).rounded())
        let height = Int((size.height * pixelsPerPoint).rounded())
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        drawBackground(background, in: canvas, focus: CGPoint(x: canvas.midX, y: canvas.midY), context)
        return context.makeImage()
    }

    /// A small picture of `mark` on a clear background, for style and size choices.
    func sample(_ mark: Mark, size: CGSize, pixelsPerPoint: CGFloat) -> CGImage? {
        let width = Int((size.width * pixelsPerPoint).rounded())
        let height = Int((size.height * pixelsPerPoint).rounded())
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: pixelsPerPoint / scale, y: -pixelsPerPoint / scale)
        withOpacity(mark.style.opacity, context) {
            drawObject(mark, number: 1, editing: false, in: context)
        }
        return context.makeImage()
    }
}

/// Pixelate and blur, made once per strength from the whole image at low resolution, and drawn
/// clipped to each redaction. Moving a redaction never recomputes anything, and the blocks stay
/// on the image's own grid.
final class RedactionEffects: Sendable {
    private let source: CGImage
    private let cache = Mutex<[Key: Entry]>([:])

    private struct Key: Hashable {
        let blur: Bool
        let size: Int
    }

    private struct Entry: @unchecked Sendable {
        let image: CGImage
    }

    init(image: CGImage) {
        source = image
    }

    /// The image averaged into blocks of about `block` pixels: one pixel per block.
    func pixelated(block: Int) -> CGImage? {
        let key = Key(blur: false, size: block)
        if let cached = cache.withLock({ $0[key] }) { return cached.image }
        let width = max(1, Int((Double(source.width) / Double(block)).rounded(.up)))
        let height = max(1, Int((Double(source.height) / Double(block)).rounded(.up)))
        guard let made = downsampled(width: width, height: height) else { return nil }
        cache.withLock { $0[key] = Entry(image: made) }
        return made
    }

    /// The image blurred by `radius` pixels, at a quarter of its size.
    func blurred(radius: Int) -> CGImage? {
        let key = Key(blur: true, size: radius)
        if let cached = cache.withLock({ $0[key] }) { return cached.image }
        let width = max(1, source.width / 4)
        let height = max(1, source.height / 4)
        guard let small = downsampled(width: width, height: height) else { return nil }
        let input = CIImage(cgImage: small)
        let sigma: Double = max(1, Double(radius) / 4)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        let context = CIContext(options: [.cacheIntermediates: false])
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let made = context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: space) else { return nil }
        cache.withLock { $0[key] = Entry(image: made) }
        return made
    }

    /// The whole source averaged down into `width` × `height`: every small pixel is opaque,
    /// so nothing under a redaction shows through at the edges.
    private func downsampled(width: Int, height: Int) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

import AppKit

/// Draws what sits over the marks: handles and selection outlines, the marquee, alignment
/// guides, the crop, smart previews and Hide Private Info's pending bars. All sizes are screen
/// points, whatever the zoom.
@MainActor
struct CanvasChrome {
    let canvas: EditorCanvas
    var model: EditorModel { canvas.model }
    var unit: CGFloat { 1 / max(canvas.magnification, 0.01) }
    var accent: NSColor { EditorCanvas.accent }

    func draw(in context: CGContext) {
        if let draft = model.cropDraft {
            drawCrop(draft, in: context)
            return
        }
        if let review = model.review { drawReview(review, in: context) }
        if let preview = canvas.fitPreview { drawFitPreview(preview, in: context) }
        drawHover(in: context)
        drawSelection(in: context)
        if let marquee = canvas.marquee {
            let rect = canvas.viewRect(fromImage: marquee)
            context.setFillColor(accent.withAlphaComponent(0.12).cgColor)
            context.fill(rect)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(unit)
            context.stroke(rect)
        }
        drawGuides(in: context)
        if canvas.picksColour, let point = canvas.hoverPoint { drawColourPicker(at: point, in: context) }
    }

    // MARK: Selection

    private func drawHover(in context: CGContext) {
        guard model.tool == .select, canvas.gesture == nil, let id = canvas.hoverMark, !model.selection.contains(id),
              let mark = model.document[id] else { return }
        let rect = canvas.viewRect(fromImage: MarkGeometry.bounds(mark, scale: canvas.scale)).insetBy(dx: -3 * unit, dy: -3 * unit)
        context.addPath(MarkGeometry.roundedRect(rect, radius: 4 * unit))
        context.setStrokeColor(accent.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(unit)
        context.strokePath()
    }

    private func drawSelection(in context: CGContext) {
        let marks = model.selectedMarks
        guard !marks.isEmpty else { return }
        let scale = canvas.scale
        if marks.count > 1 {
            var union = CGRect.null
            for mark in marks {
                let box = canvas.viewRect(fromImage: MarkGeometry.bounds(mark, scale: scale))
                union = union.union(box)
                outline(box.insetBy(dx: -3 * unit, dy: -3 * unit), dashed: false, alpha: 0.6, in: context)
            }
            outline(union.insetBy(dx: -7 * unit, dy: -7 * unit), dashed: true, alpha: 1, in: context)
            return
        }
        guard let mark = marks.first else { return }
        let outlined: Set<Mark.Kind> = [.text, .counter, .pen, .image]
        if outlined.contains(mark.kind) {
            let box = canvas.viewRect(fromImage: MarkGeometry.bounds(mark, scale: scale))
            outline(box.insetBy(dx: -4 * unit, dy: -4 * unit), dashed: false, alpha: 1, in: context)
        }
        guard model.editingText == nil, canvas.gesture.map(isDrawing) != true else { return }
        for handle in MarkGeometry.handles(for: mark, scale: scale) {
            drawHandle(at: canvas.viewPoint(fromImage: handle.point), filled: handle.handle == .bend, in: context)
        }
    }

    private func isDrawing(_ gesture: EditorCanvas.Gesture) -> Bool {
        if case .draw = gesture { return true }
        return false
    }

    private func outline(_ rect: CGRect, dashed: Bool, alpha: CGFloat, in context: CGContext) {
        context.saveGState()
        context.addPath(MarkGeometry.roundedRect(rect, radius: 4 * unit))
        context.setStrokeColor(accent.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(1.25 * unit)
        if dashed { context.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit]) }
        context.strokePath()
        context.restoreGState()
    }

    private func drawHandle(at point: CGPoint, filled: Bool, in context: CGContext) {
        let radius: CGFloat = 4.5 * unit
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.35))
        context.setFillColor(filled ? accent.cgColor : CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: rect)
        context.restoreGState()
        context.setStrokeColor(filled ? CGColor(gray: 1, alpha: 1) : accent.cgColor)
        context.setLineWidth(1.5 * unit)
        context.strokeEllipse(in: rect)
    }

    private func drawGuides(in context: CGContext) {
        guard !canvas.guides.isEmpty else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.systemPink.cgColor)
        context.setLineWidth(unit)
        for guide in canvas.guides {
            switch guide.axis {
            case .vertical:
                let top = canvas.viewPoint(fromImage: CGPoint(x: guide.position, y: guide.from))
                let bottom = canvas.viewPoint(fromImage: CGPoint(x: guide.position, y: guide.to))
                context.move(to: top)
                context.addLine(to: bottom)
            case .horizontal:
                let left = canvas.viewPoint(fromImage: CGPoint(x: guide.from, y: guide.position))
                let right = canvas.viewPoint(fromImage: CGPoint(x: guide.to, y: guide.position))
                context.move(to: left)
                context.addLine(to: right)
            }
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: Smart

    private func drawFitPreview(_ rect: CGRect, in context: CGContext) {
        let view = canvas.viewRect(fromImage: rect)
        context.saveGState()
        context.addPath(MarkGeometry.roundedRect(view, radius: 3 * unit))
        context.setFillColor(accent.withAlphaComponent(0.08).cgColor)
        context.fillPath()
        context.addPath(MarkGeometry.roundedRect(view, radius: 3 * unit))
        context.setStrokeColor(accent.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1.25 * unit)
        context.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit])
        context.strokePath()
        context.restoreGState()
    }

    /// Pending bars: striped where they'll hide, dashed where you've left them out.
    private func drawReview(_ review: PrivateInfoReview, in context: CGContext) {
        // Everything else steps back a little.
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.3))
        let image = canvas.viewRect(fromImage: model.document.crop)
        context.addRect(image)
        for item in review.items where item.included {
            context.addPath(MarkGeometry.roundedRect(canvas.viewRect(fromImage: item.finding.rect), radius: 2 * unit))
        }
        context.fillPath(using: .evenOdd)
        context.restoreGState()
        for item in review.items {
            let rect = canvas.viewRect(fromImage: item.finding.rect)
            let path = MarkGeometry.roundedRect(rect, radius: 2 * unit)
            context.saveGState()
            if item.included {
                context.addPath(path)
                context.setFillColor(MarkColour.ink.cgColor(alpha: 0.72))
                context.fillPath()
                context.addPath(path)
                context.clip()
                context.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
                context.setLineWidth(3 * unit)
                let step: CGFloat = 8 * unit
                var x: CGFloat = rect.minX - rect.height
                while x < rect.maxX {
                    context.move(to: CGPoint(x: x, y: rect.maxY))
                    context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                    x += step
                }
                context.strokePath()
            } else {
                context.addPath(path)
                context.setStrokeColor(accent.cgColor)
                context.setLineWidth(1.25 * unit)
                context.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit])
                context.strokePath()
            }
            context.restoreGState()
        }
    }

    private func drawColourPicker(at point: CGPoint, in context: CGContext) {
        guard let colour = ImageSampler.colour(at: point, in: model.image) else { return }
        let centre = canvas.viewPoint(fromImage: point)
        let radius: CGFloat = 16 * unit
        let diameter: CGFloat = radius * 2
        let x: CGFloat = centre.x + 14 * unit
        let y: CGFloat = centre.y - diameter - 6 * unit
        let swatch = CGRect(x: x, y: y, width: diameter, height: diameter)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: CGColor(gray: 0, alpha: 0.35))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: swatch.insetBy(dx: -2.5 * unit, dy: -2.5 * unit))
        context.restoreGState()
        context.setFillColor(colour.cgColor())
        context.fillEllipse(in: swatch)
    }

    // MARK: Crop

    private func drawCrop(_ draft: CGRect, in context: CGContext) {
        let crop = canvas.viewRect(fromImage: draft)
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.addRect(canvas.bounds)
        context.addRect(crop)
        context.fillPath(using: .evenOdd)

        // Thirds, to help compose.
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.3))
        context.setLineWidth(unit)
        for step in 1...2 {
            let fraction = CGFloat(step) / 3
            let x: CGFloat = crop.minX + crop.width * fraction
            let y: CGFloat = crop.minY + crop.height * fraction
            context.move(to: CGPoint(x: x, y: crop.minY))
            context.addLine(to: CGPoint(x: x, y: crop.maxY))
            context.move(to: CGPoint(x: crop.minX, y: y))
            context.addLine(to: CGPoint(x: crop.maxX, y: y))
        }
        context.strokePath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.stroke(crop, width: unit)

        // Corner brackets and edge bars, like Photos: white, with a thin dark outline and a faint
        // shadow so they read on white captures too.
        let arm: CGFloat = min(18 * unit, crop.width / 3, crop.height / 3)
        let bar: CGFloat = 3.5 * unit
        let inset: CGFloat = bar / 2
        let brackets = cropBrackets(crop, arm: arm, inset: inset)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShadow(offset: .zero, blur: 3, color: CGColor(gray: 0, alpha: 0.3))
        context.addPath(brackets)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
        context.setLineWidth(bar + 2 * unit)
        context.strokePath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(brackets)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(bar)
        context.strokePath()
        context.restoreGState()

        drawLabel("\(Int(draft.width)) × \(Int(draft.height))", inside: crop)
    }

    /// The crop's corner brackets and the bars at the middle of each edge, just inside it.
    private func cropBrackets(_ crop: CGRect, arm: CGFloat, inset: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: crop.minX + inset, y: crop.minY + inset), 1, 1),
            (CGPoint(x: crop.maxX - inset, y: crop.minY + inset), -1, 1),
            (CGPoint(x: crop.maxX - inset, y: crop.maxY - inset), -1, -1),
            (CGPoint(x: crop.minX + inset, y: crop.maxY - inset), 1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
        }
        let half: CGFloat = arm / 2
        path.move(to: CGPoint(x: crop.midX - half, y: crop.minY + inset))
        path.addLine(to: CGPoint(x: crop.midX + half, y: crop.minY + inset))
        path.move(to: CGPoint(x: crop.midX - half, y: crop.maxY - inset))
        path.addLine(to: CGPoint(x: crop.midX + half, y: crop.maxY - inset))
        path.move(to: CGPoint(x: crop.minX + inset, y: crop.midY - half))
        path.addLine(to: CGPoint(x: crop.minX + inset, y: crop.midY + half))
        path.move(to: CGPoint(x: crop.maxX - inset, y: crop.midY - half))
        path.addLine(to: CGPoint(x: crop.maxX - inset, y: crop.midY + half))
        return path
    }

    /// A small dark capsule with the crop's size, inside its bottom edge.
    private func drawLabel(_ text: String, inside rect: CGRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11 * unit, weight: .medium)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = string.size()
        let width: CGFloat = size.width + 16 * unit
        let height: CGFloat = size.height + 6 * unit
        let left: CGFloat = rect.midX - width / 2
        let top: CGFloat = rect.maxY - height - 12 * unit
        let capsule = CGRect(x: left, y: top, width: width, height: height)
        guard capsule.minY > rect.minY else { return }
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: height / 2, yRadius: height / 2).fill()
        let textX: CGFloat = capsule.minX + 8 * unit
        let textY: CGFloat = capsule.minY + 3 * unit
        string.draw(at: CGPoint(x: textX, y: textY))
    }
}

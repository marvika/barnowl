import AppKit

/// A draggable point on a selected mark.
enum MarkHandle: Hashable, Sendable {
    case start, end, bend
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// Shapes, sizes, handles and hit testing for marks. Everything is in image pixels; `scale`
/// (pixels per point) turns the point sizes of `StrokeSize` into pixels.
enum MarkGeometry {
    // MARK: Sizes

    static func lineWidth(_ mark: Mark, scale: CGFloat) -> CGFloat { mark.size.lineWidth * scale }
    static func arrowWidth(_ mark: Mark, scale: CGFloat) -> CGFloat { mark.size.arrowWidth * scale }
    static func counterRadius(_ mark: Mark, scale: CGFloat) -> CGFloat { mark.size.counterRadius * scale }
    static func fontSize(_ mark: Mark, scale: CGFloat) -> CGFloat { mark.size.fontSize * scale }

    /// The halo each side of a stroke, so it reads on any background.
    static func haloWidth(forStroke width: CGFloat, scale: CGFloat) -> CGFloat {
        max(1.5 * scale, width * 0.36)
    }

    /// Rectangles round their corners in proportion to the line, but never past half a side.
    static func rectangleRadius(_ mark: Mark, scale: CGFloat) -> CGFloat {
        lineWidth(mark, scale: scale) * 3
    }

    static func filledBoxRadius(scale: CGFloat) -> CGFloat { 4 * scale }
    static func spotlightRadius(scale: CGFloat) -> CGFloat { 8 * scale }

    /// A rounded rectangle whose radius is clamped to fit, as Core Graphics requires.
    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let limit: CGFloat = min(rect.width, rect.height) / 2
        let corner: CGFloat = max(0, min(radius, limit))
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    // MARK: Drawing order

    /// Marks draw in layers: redactions, spotlights, highlights, pasted images, shapes, counters,
    /// then text. Within a layer, later marks are on top.
    static func layer(_ kind: Mark.Kind) -> Int {
        switch kind {
        case .redact: 0
        case .spotlight: 1
        case .highlighter: 2
        case .image: 3
        case .arrow, .line, .rectangle, .filledBox, .ellipse, .pen: 4
        case .counter: 5
        case .text: 6
        }
    }

    static func drawingOrder(_ marks: [Mark]) -> [Mark] {
        marks.enumerated()
            .sorted { (layer($0.element.kind), $0.offset) < (layer($1.element.kind), $1.offset) }
            .map(\.element)
    }

    /// The mark drawn on top at `point`, if any.
    static func topmost(in marks: [Mark], at point: CGPoint, tolerance: CGFloat, scale: CGFloat) -> Mark? {
        drawingOrder(marks).reversed().first { hitTest($0, at: point, tolerance: tolerance, scale: scale) }
    }

    // MARK: Arrows

    /// The arrow's centre line, sampled; a straight arrow is just its two ends.
    static func spine(from tail: CGPoint, to tip: CGPoint, control: CGPoint?) -> [CGPoint] {
        guard let control else { return [tail, tip] }
        let steps = 48
        return (0...steps).map { quadratic(tail, control, tip, at: CGFloat($0) / CGFloat(steps)) }
    }

    static func quadratic(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, at t: CGFloat) -> CGPoint {
        let u: CGFloat = 1 - t
        let a: CGFloat = u * u
        let b: CGFloat = 2 * u * t
        let d: CGFloat = t * t
        let x: CGFloat = a * p0.x + b * c.x + d * p1.x
        let y: CGFloat = a * p0.y + b * c.y + d * p1.y
        return CGPoint(x: x, y: y)
    }

    /// The point halfway along the arrow, where its bend handle sits.
    static func arrowMidpoint(_ mark: Mark) -> CGPoint {
        guard let control = mark.control else { return midpoint(mark.start, mark.end) }
        return quadratic(mark.start, control, mark.end, at: 0.5)
    }

    /// The control point that puts the curve's midpoint at `midpoint`.
    static func control(throughMidpoint midpoint: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
        let chord = Self.midpoint(start, end)
        return CGPoint(x: 2 * midpoint.x - chord.x, y: 2 * midpoint.y - chord.y)
    }

    /// A gentle upward arc, for arrows drawn in the curved style.
    static func defaultBend(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx: CGFloat = end.x - start.x
        let dy: CGFloat = end.y - start.y
        let length: CGFloat = hypot(dx, dy)
        guard length > 0 else { return start }
        var normal = CGPoint(x: -dy / length, y: dx / length)
        if normal.y > 0 || (normal.y == 0 && normal.x < 0) { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let mid = midpoint(start, end)
        let lift: CGFloat = length * 0.22
        return control(throughMidpoint: CGPoint(x: mid.x + normal.x * lift, y: mid.y + normal.y * lift),
                       start: start, end: end)
    }

    static func arrowOutline(_ mark: Mark, scale: CGFloat) -> CGPath {
        arrowOutline(from: mark.start, to: mark.end, control: mark.control, width: arrowWidth(mark, scale: scale),
                     doubleHeaded: mark.style.arrow == .double)
    }

    /// A closed outline: a shaft that tapers from a fine tail to `width` at the head, and a
    /// triangular head with a swept-back base. Curved arrows follow the quadratic Bézier.
    static func arrowOutline(from tail: CGPoint, to tip: CGPoint, control: CGPoint?, width: CGFloat,
                             doubleHeaded: Bool) -> CGPath {
        let samples = spine(from: tail, to: tip, control: control)
        let lengths = cumulativeLengths(samples)
        let total: CGFloat = lengths.last ?? 0
        let path = CGMutablePath()
        guard total > width * 0.5 else {
            path.addEllipse(in: CGRect(x: tip.x - width / 2, y: tip.y - width / 2, width: width, height: width))
            return path
        }
        let headLimit: CGFloat = total * (doubleHeaded ? 0.4 : 0.55)
        let headLength: CGFloat = min(width * 3.4, headLimit)
        let headHalf: CGFloat = headLength * 0.6
        let fullHalf: CGFloat = min(width / 2, headHalf * 0.5)
        let tailHalf: CGFloat = doubleHeaded ? fullHalf : fullHalf * 0.24
        // The shaft tucks into the head's swept-back base.
        let joinDepth: CGFloat = headLength * 0.76
        let shaftStart: CGFloat = doubleHeaded ? joinDepth : 0
        let shaftEnd: CGFloat = total - joinDepth
        let steps = control == nil ? 1 : 40

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for step in 0...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let distance: CGFloat = shaftStart + (shaftEnd - shaftStart) * fraction
            let (point, direction) = sample(samples, lengths, at: distance)
            let half: CGFloat = tailHalf + (fullHalf - tailHalf) * fraction
            let normal = CGPoint(x: -direction.y, y: direction.x)
            left.append(CGPoint(x: point.x + normal.x * half, y: point.y + normal.y * half))
            right.append(CGPoint(x: point.x - normal.x * half, y: point.y - normal.y * half))
        }

        let endJoin = sample(samples, lengths, at: shaftEnd).point
        let endHead = head(tip: tip, from: endJoin, length: headLength, half: headHalf)
        path.addLines(between: left + [endHead.0, tip, endHead.1] + right.reversed())
        if doubleHeaded {
            let startJoin = sample(samples, lengths, at: shaftStart).point
            let startHead = head(tip: tail, from: startJoin, length: headLength, half: headHalf)
            path.addLine(to: startHead.0)
            path.addLine(to: tail)
            path.addLine(to: startHead.1)
        } else {
            // A round cap on the fine tail.
            let direction = sample(samples, lengths, at: 0).direction
            let normal = CGPoint(x: -direction.y, y: direction.x)
            for step in 1..<8 {
                let angle = CGFloat.pi * CGFloat(step) / 8
                let c: CGFloat = cos(angle)
                let s: CGFloat = sin(angle)
                let x: CGFloat = tail.x + tailHalf * (-normal.x * c - direction.x * s)
                let y: CGFloat = tail.y + tailHalf * (-normal.y * c - direction.y * s)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    /// The head's two wing tips, on the same sides as the shaft's left and right edges.
    private static func head(tip: CGPoint, from join: CGPoint, length: CGFloat, half: CGFloat) -> (CGPoint, CGPoint) {
        let direction = normalized(CGPoint(x: tip.x - join.x, y: tip.y - join.y))
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let base = CGPoint(x: tip.x - direction.x * length, y: tip.y - direction.y * length)
        return (CGPoint(x: base.x + normal.x * half, y: base.y + normal.y * half),
                CGPoint(x: base.x - normal.x * half, y: base.y - normal.y * half))
    }

    static func cumulativeLengths(_ points: [CGPoint]) -> [CGFloat] {
        var lengths: [CGFloat] = [0]
        for index in points.indices.dropFirst() {
            lengths.append(lengths[index - 1] + distance(points[index - 1], points[index]))
        }
        return lengths
    }

    /// The point `distance` along a polyline, and the direction there.
    static func sample(_ points: [CGPoint], _ lengths: [CGFloat], at distance: CGFloat) -> (point: CGPoint, direction: CGPoint) {
        guard points.count > 1 else { return (points.first ?? .zero, CGPoint(x: 1, y: 0)) }
        var index = 0
        while index < points.count - 2 && lengths[index + 1] < distance { index += 1 }
        let a = points[index]
        let b = points[index + 1]
        let span: CGFloat = max(lengths[index + 1] - lengths[index], 0.0001)
        let t: CGFloat = min(max((distance - lengths[index]) / span, 0), 1)
        let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        return (point, normalized(CGPoint(x: b.x - a.x, y: b.y - a.y)))
    }

    // MARK: Freehand

    /// A smooth curve through every point (Catmull-Rom, as cubic Béziers).
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    // MARK: Text

    /// How a text mark lays out: the glyphs' box, and the whole mark around it.
    struct TextLayout {
        let font: NSFont
        let string: NSAttributedString
        let textRect: CGRect
        let boxRect: CGRect
        let cornerRadius: CGFloat
    }

    /// SF Pro Rounded, semibold: friendly, and clear at small sizes.
    static func textFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static let textOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    static func textLayout(_ mark: Mark, scale: CGFloat) -> TextLayout {
        let font = textFont(size: fontSize(mark, scale: scale))
        let string = NSAttributedString(string: mark.text, attributes: [.font: font])
        let unbounded = CGSize(width: 1_000_000, height: 1_000_000)
        let measured = string.boundingRect(with: unbounded, options: textOptions)
        let lineHeight: CGFloat = font.ascender - font.descender + font.leading
        var width: CGFloat = ceil(measured.width)
        var height: CGFloat = max(ceil(measured.height), ceil(lineHeight))
        if mark.text.isEmpty { width = ceil(font.pointSize * 0.35) }
        if mark.text.hasSuffix("\n") { height += ceil(lineHeight) }
        let em: CGFloat = font.pointSize
        let boxed = mark.style.text == .box
        let padX: CGFloat = (boxed ? em * 0.45 : em * 0.14).rounded()
        let padY: CGFloat = (boxed ? em * 0.2 : em * 0.06).rounded()
        let boxRect = CGRect(x: mark.start.x, y: mark.start.y, width: width + 2 * padX, height: height + 2 * padY)
        let textRect = CGRect(x: mark.start.x + padX, y: mark.start.y + padY, width: width, height: height)
        return TextLayout(font: font, string: string, textRect: textRect, boxRect: boxRect, cornerRadius: em * 0.32)
    }

    // MARK: Counters

    static func counterCircle(_ mark: Mark, scale: CGFloat) -> CGRect {
        let radius = counterRadius(mark, scale: scale)
        return CGRect(x: mark.start.x - radius, y: mark.start.y - radius, width: radius * 2, height: radius * 2)
    }

    /// A counter's pointer, a wedge from the badge to `end`, when it was dragged out far enough.
    static func counterTail(_ mark: Mark, scale: CGFloat) -> CGPath? {
        let radius = counterRadius(mark, scale: scale)
        let dx: CGFloat = mark.end.x - mark.start.x
        let dy: CGFloat = mark.end.y - mark.start.y
        let length: CGFloat = hypot(dx, dy)
        guard length > radius * 1.4 else { return nil }
        let direction = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let half: CGFloat = radius * 0.72
        let inset: CGFloat = radius * 0.2
        let base = CGPoint(x: mark.start.x + direction.x * inset, y: mark.start.y + direction.y * inset)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: base.x + normal.x * half, y: base.y + normal.y * half))
        path.addLine(to: mark.end)
        path.addLine(to: CGPoint(x: base.x - normal.x * half, y: base.y - normal.y * half))
        path.closeSubpath()
        return path
    }

    // MARK: Shapes

    static func spotlightPath(_ mark: Mark, scale: CGFloat) -> CGPath {
        switch mark.style.spotlight {
        case .rectangle: roundedRect(mark.rect, radius: spotlightRadius(scale: scale))
        case .ellipse: CGPath(ellipseIn: mark.rect, transform: nil)
        }
    }

    static func penBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect
    }

    /// Everything a mark covers, for selection outlines and redrawing.
    static func bounds(_ mark: Mark, scale: CGFloat) -> CGRect {
        switch mark.kind {
        case .arrow:
            return arrowOutline(mark, scale: scale).boundingBoxOfPath
        case .line:
            return CGRect(x: min(mark.start.x, mark.end.x), y: min(mark.start.y, mark.end.y),
                          width: abs(mark.end.x - mark.start.x), height: abs(mark.end.y - mark.start.y))
        case .pen:
            return penBounds(mark.points)
        case .text:
            return textLayout(mark, scale: scale).boxRect
        case .counter:
            let circle = counterCircle(mark, scale: scale)
            guard counterTail(mark, scale: scale) != nil else { return circle }
            return circle.union(CGRect(origin: mark.end, size: .zero))
        case .rectangle, .filledBox, .ellipse, .highlighter, .redact, .spotlight, .image:
            return mark.rect
        }
    }

    // MARK: Hit testing

    /// Whether a click at `point` lands on the mark. Filled shapes count their whole area;
    /// stroked ones count a band along the stroke at least `tolerance` wide.
    static func hitTest(_ mark: Mark, at point: CGPoint, tolerance: CGFloat, scale: CGFloat) -> Bool {
        let stroke = max(lineWidth(mark, scale: scale), tolerance)
        switch mark.kind {
        case .arrow:
            if arrowOutline(mark, scale: scale).contains(point) { return true }
            let line = CGMutablePath()
            line.addLines(between: spine(from: mark.start, to: mark.end, control: mark.control))
            return strokedContains(line, width: max(arrowWidth(mark, scale: scale), tolerance), point)
        case .line:
            let line = CGMutablePath()
            line.addLines(between: [mark.start, mark.end])
            return strokedContains(line, width: stroke, point)
        case .pen:
            return strokedContains(smoothPath(mark.points), width: stroke, point)
        case .rectangle:
            return strokedContains(roundedRect(mark.rect, radius: rectangleRadius(mark, scale: scale)), width: stroke, point)
        case .ellipse:
            return strokedContains(CGPath(ellipseIn: mark.rect, transform: nil), width: stroke, point)
        case .filledBox, .highlighter, .redact, .image:
            return mark.rect.insetBy(dx: -tolerance / 4, dy: -tolerance / 4).contains(point)
        case .spotlight:
            return spotlightPath(mark, scale: scale).contains(point)
        case .text:
            return textLayout(mark, scale: scale).boxRect.insetBy(dx: -tolerance / 4, dy: -tolerance / 4).contains(point)
        case .counter:
            let radius = counterRadius(mark, scale: scale) + tolerance / 4
            if distance(point, mark.start) <= radius { return true }
            return counterTail(mark, scale: scale)?.contains(point) ?? false
        }
    }

    private static func strokedContains(_ path: CGPath, width: CGFloat, _ point: CGPoint) -> Bool {
        path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
    }

    // MARK: Handles

    static func handles(for mark: Mark, scale: CGFloat) -> [(handle: MarkHandle, point: CGPoint)] {
        switch mark.kind {
        case .arrow:
            return [(.start, mark.start), (.end, mark.end), (.bend, arrowMidpoint(mark))]
        case .line:
            return [(.start, mark.start), (.end, mark.end)]
        case .counter:
            return counterTail(mark, scale: scale) == nil ? [] : [(.end, mark.end)]
        case .text:
            return []
        case .pen:
            return boxHandles(penBounds(mark.points), edges: false)
        case .image:
            return boxHandles(mark.rect, edges: false)
        case .rectangle, .filledBox, .ellipse, .highlighter, .redact, .spotlight:
            return boxHandles(mark.rect, edges: true)
        }
    }

    static func boxHandles(_ rect: CGRect, edges: Bool) -> [(handle: MarkHandle, point: CGPoint)] {
        var handles: [(handle: MarkHandle, point: CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)), (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)), (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
        ]
        if edges {
            handles += [
                (.top, CGPoint(x: rect.midX, y: rect.minY)), (.right, CGPoint(x: rect.maxX, y: rect.midY)),
                (.bottom, CGPoint(x: rect.midX, y: rect.maxY)), (.left, CGPoint(x: rect.minX, y: rect.midY)),
            ]
        }
        return handles
    }

    // MARK: Editing

    static func moved(_ mark: Mark, by dx: CGFloat, _ dy: CGFloat) -> Mark {
        var mark = mark
        mark.start = CGPoint(x: mark.start.x + dx, y: mark.start.y + dy)
        mark.end = CGPoint(x: mark.end.x + dx, y: mark.end.y + dy)
        if let control = mark.control { mark.control = CGPoint(x: control.x + dx, y: control.y + dy) }
        mark.points = mark.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return mark
    }

    /// `original` with `handle` dragged to `point`. ⇧ (`constrained`) keeps lines at 45° steps and
    /// boxes square; pasted images always keep their proportions.
    static func adjusted(_ original: Mark, handle: MarkHandle, to point: CGPoint, constrained: Bool) -> Mark {
        var mark = original
        switch handle {
        case .start, .end:
            let fixed = handle == .start ? original.end : original.start
            let target = constrained ? snappedTo45(point, around: fixed) : point
            if handle == .start { mark.start = target } else { mark.end = target }
            if let control = original.control {
                // The bend follows its end halfway, so the curve keeps its feel.
                let moved = handle == .start ? original.start : original.end
                let dx: CGFloat = (target.x - moved.x) / 2
                let dy: CGFloat = (target.y - moved.y) / 2
                mark.control = CGPoint(x: control.x + dx, y: control.y + dy)
            }
        case .bend:
            let chord = midpoint(original.start, original.end)
            let length = distance(original.start, original.end)
            // Close to the chord, it snaps straight.
            mark.control = distance(point, chord) < max(length * 0.02, 2) ? nil
                : control(throughMidpoint: point, start: original.start, end: original.end)
        default:
            let from = original.kind == .pen ? penBounds(original.points) : original.rect
            var rect = resized(from, handle: handle, to: point)
            if original.kind == .image {
                rect = keepingAspect(rect, of: from, handle: handle)
            } else if constrained {
                rect = squared(rect, handle: handle, from: from)
            }
            if original.kind == .pen {
                mark.points = original.points.map { mapped($0, from: from, to: rect) }
            } else {
                mark.start = rect.origin
                mark.end = CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
        return mark
    }

    static func resized(_ rect: CGRect, handle: MarkHandle, to point: CGPoint) -> CGRect {
        var minX: CGFloat = rect.minX
        var minY: CGFloat = rect.minY
        var maxX: CGFloat = rect.maxX
        var maxY: CGFloat = rect.maxY
        switch handle {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        case .start, .end, .bend: break
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// The corner opposite the handle stays put.
    private static func anchor(of rect: CGRect, handle: MarkHandle) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.maxX, y: rect.minY)
        default: CGPoint(x: rect.minX, y: rect.minY)
        }
    }

    private static func keepingAspect(_ rect: CGRect, of original: CGRect, handle: MarkHandle) -> CGRect {
        guard original.width > 0, original.height > 0 else { return rect }
        let factor: CGFloat = max(rect.width / original.width, rect.height / original.height, 0.02)
        let width: CGFloat = original.width * factor
        let height: CGFloat = original.height * factor
        let fixed = anchor(of: original, handle: handle)
        let x: CGFloat = fixed.x == original.minX ? fixed.x : fixed.x - width
        let y: CGFloat = fixed.y == original.minY ? fixed.y : fixed.y - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func squared(_ rect: CGRect, handle: MarkHandle, from original: CGRect) -> CGRect {
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let side: CGFloat = max(rect.width, rect.height)
            let fixed = anchor(of: original, handle: handle)
            let x: CGFloat = rect.minX < fixed.x ? fixed.x - side : fixed.x
            let y: CGFloat = rect.minY < fixed.y ? fixed.y - side : fixed.y
            return CGRect(x: x, y: y, width: side, height: side)
        default:
            return rect
        }
    }

    private static func mapped(_ point: CGPoint, from: CGRect, to: CGRect) -> CGPoint {
        let fx: CGFloat = from.width > 0 ? (point.x - from.minX) / from.width : 0.5
        let fy: CGFloat = from.height > 0 ? (point.y - from.minY) / from.height : 0.5
        return CGPoint(x: to.minX + fx * to.width, y: to.minY + fy * to.height)
    }

    /// Where a drag from `start` should end with ⇧ held: lines at 45° steps, boxes square.
    static func constrainedEnd(_ end: CGPoint, from start: CGPoint, kind: Mark.Kind) -> CGPoint {
        switch kind {
        case .arrow, .line, .counter:
            return snappedTo45(end, around: start)
        default:
            let dx: CGFloat = end.x - start.x
            let dy: CGFloat = end.y - start.y
            let side: CGFloat = max(abs(dx), abs(dy))
            let x: CGFloat = start.x + (dx < 0 ? -side : side)
            let y: CGFloat = start.y + (dy < 0 ? -side : side)
            return CGPoint(x: x, y: y)
        }
    }

    static func snappedTo45(_ point: CGPoint, around origin: CGPoint) -> CGPoint {
        let dx: CGFloat = point.x - origin.x
        let dy: CGFloat = point.y - origin.y
        let length: CGFloat = hypot(dx, dy)
        let step: CGFloat = .pi / 4
        let angle: CGFloat = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
    }

    // MARK: Points

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    static func normalized(_ vector: CGPoint) -> CGPoint {
        let length: CGFloat = hypot(vector.x, vector.y)
        guard length > 0 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
}

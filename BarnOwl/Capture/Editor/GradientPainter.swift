import CoreGraphics
import Foundation

/// Paints the frame's gradients: the ready-made ones corner to corner, as they always have been,
/// and your own along any angle or out from the capture. Each segment of your own is mixed as
/// the eye sees it, and every gradient gets a faint, fixed grain so 8-bit output doesn't band.
enum GradientPainter {
    /// Sub-stops per segment of a gradient of your own, mixed in Oklab; sRGB in between is close
    /// enough at this spacing.
    static let substeps = 6

    // MARK: Ready-made

    static func paint(_ gradient: FrameGradient, in canvas: CGRect, _ context: CGContext) {
        let colours: [CGColor] = gradient.stops.map { $0.cgColor() }
        let last: CGFloat = CGFloat(max(colours.count - 1, 1))
        let locations: [CGFloat] = colours.indices.map { CGFloat($0) / last }
        guard let fill = CGGradient(colorsSpace: srgb, colors: colours as CFArray, locations: locations) else { return }
        context.saveGState()
        context.clip(to: canvas)
        context.drawLinearGradient(fill, start: canvas.origin, end: CGPoint(x: canvas.maxX, y: canvas.maxY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        drawSoftLight(in: canvas, context)
        drawGrain(in: canvas, context)
        context.restoreGState()
    }

    // MARK: Your own

    /// A gradient of your own over `canvas`; a radial one spreads from `focus` (the capture's centre).
    static func paint(_ gradient: CustomGradient, in canvas: CGRect, focus: CGPoint, _ context: CGContext) {
        let ramp = expanded(gradient.stops)
        let colours: [CGColor] = ramp.colours.map { $0.cgColor() }
        guard let fill = CGGradient(colorsSpace: srgb, colors: colours as CFArray, locations: ramp.locations) else { return }
        context.saveGState()
        context.clip(to: canvas)
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch gradient.kind {
        case .linear:
            let ends = linearEnds(angle: gradient.angle, in: canvas)
            context.drawLinearGradient(fill, start: ends.start, end: ends.end, options: options)
        case .radial:
            let radius = farthestCorner(from: focus, in: canvas)
            context.drawRadialGradient(fill, startCenter: focus, startRadius: 0, endCenter: focus, endRadius: radius,
                                       options: options)
        }
        if gradient.softLight { drawSoftLight(in: canvas, context) }
        drawGrain(in: canvas, context, alpha: gradient.grain ? visibleGrainAlpha : grainAlpha)
        context.restoreGState()
    }

    /// The stops with `substeps` mixed in between each pair, in order.
    static func expanded(_ stops: [GradientStop]) -> (colours: [MarkColour], locations: [CGFloat]) {
        let sorted: [GradientStop] = stops.sorted { $0.location < $1.location }
        guard let first = sorted.first else { return ([.lavender, .lavender], [0, 1]) }
        guard sorted.count > 1 else { return ([first.colour, first.colour], [0, 1]) }
        var colours: [MarkColour] = []
        var locations: [CGFloat] = []
        for (from, to) in zip(sorted, sorted.dropFirst()) {
            let start = from.colour.oklab
            let end = to.colour.oklab
            for step in 0..<substeps {
                let t: Double = Double(step) / Double(substeps)
                let location: Double = from.location + (to.location - from.location) * t
                colours.append(start.mixed(with: end, t).colour)
                locations.append(CGFloat(min(max(location, 0), 1)))
            }
        }
        if let last = sorted.last {
            colours.append(last.colour)
            locations.append(CGFloat(min(max(last.location, 0), 1)))
        }
        return (colours, locations)
    }

    /// Where a linear gradient at `angle` (CSS degrees: 0 up, 90 right) starts and ends: on a
    /// line through the middle, just long enough that both far corners take the end colours.
    static func linearEnds(angle: Double, in canvas: CGRect) -> (start: CGPoint, end: CGPoint) {
        let radians: Double = angle * .pi / 180
        let dx: CGFloat = CGFloat(sin(radians))
        // Up is negative y here.
        let dy: CGFloat = CGFloat(-cos(radians))
        let across: CGFloat = abs(canvas.width * dx)
        let down: CGFloat = abs(canvas.height * dy)
        let half: CGFloat = (across + down) / 2
        let centre = CGPoint(x: canvas.midX, y: canvas.midY)
        let start = CGPoint(x: centre.x - dx * half, y: centre.y - dy * half)
        let end = CGPoint(x: centre.x + dx * half, y: centre.y + dy * half)
        return (start, end)
    }

    static func farthestCorner(from point: CGPoint, in canvas: CGRect) -> CGFloat {
        let corners = [CGPoint(x: canvas.minX, y: canvas.minY), CGPoint(x: canvas.maxX, y: canvas.minY),
                       CGPoint(x: canvas.minX, y: canvas.maxY), CGPoint(x: canvas.maxX, y: canvas.maxY)]
        let distances: [CGFloat] = corners.map { hypot($0.x - point.x, $0.y - point.y) }
        return max(distances.max() ?? 1, 1)
    }

    // MARK: Light and grain

    /// A soft light from the top left, as through a window.
    static func drawSoftLight(in canvas: CGRect, _ context: CGContext) {
        let glowColours: [CGColor] = [CGColor(gray: 1, alpha: 0.2), CGColor(gray: 1, alpha: 0)]
        guard let glow = CGGradient(colorsSpace: srgb, colors: glowColours as CFArray, locations: [0, 1]) else { return }
        let centre = CGPoint(x: canvas.minX + canvas.width * 0.18, y: canvas.minY)
        let reach: CGFloat = max(canvas.width, canvas.height) * 0.75
        context.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: reach, options: [])
    }

    /// The grain's strength: a level or two of 8-bit either way, so it dithers without showing.
    static let grainAlpha: CGFloat = 0.04
    /// Grain you can see, when you ask for it.
    static let visibleGrainAlpha: CGFloat = 0.16

    /// A fixed noise tile laid over the gradient in overlay mode, so the same document always
    /// renders to the same bytes.
    static func drawGrain(in canvas: CGRect, _ context: CGContext, alpha: CGFloat = grainAlpha) {
        guard let tile = noise.image else { return }
        context.saveGState()
        context.clip(to: canvas)
        context.setBlendMode(.overlay)
        context.setAlpha(alpha)
        context.interpolationQuality = .none
        let size = CGFloat(Noise.side)
        context.draw(tile, in: CGRect(x: 0, y: 0, width: size, height: size), byTiling: true)
        context.restoreGState()
    }

    private struct Noise: @unchecked Sendable {
        static let side = 64
        let image: CGImage?
    }

    private static let noise = Noise(image: makeNoise())

    /// 64 × 64 grey values from a seeded linear congruential generator: random to the eye, the
    /// same every time.
    private static func makeNoise() -> CGImage? {
        let side = Noise.side
        var state: UInt32 = 0x0B_A2_0E_17
        var values = [UInt8](repeating: 0, count: side * side)
        for index in values.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            values[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        let data = Data(values) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static var srgb: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}

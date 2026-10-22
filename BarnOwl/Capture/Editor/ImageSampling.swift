import CoreGraphics
import Foundation

/// A small greyscale copy of the capture, for quick questions about how light an area is.
struct LuminanceMap: Sendable {
    let width: Int
    let height: Int
    /// Image pixels per map pixel.
    let factor: Int
    let values: [UInt8]

    init?(image: CGImage, factor: Int = 8) {
        let width = max(1, image.width / factor)
        let height = max(1, image.height / factor)
        var values = [UInt8](repeating: 0, count: width * height)
        let made: Bool = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard made else { return nil }
        self.width = width
        self.height = height
        self.factor = factor
        self.values = values
    }

    /// The mean lightness (0 to 1) in `rect`, in image pixels from the top left.
    func mean(in rect: CGRect) -> Double {
        let f = CGFloat(factor)
        let minX: Int = max(0, min(width - 1, Int(rect.minX / f)))
        let maxX: Int = max(minX, min(width - 1, Int(rect.maxX / f)))
        let minY: Int = max(0, min(height - 1, Int(rect.minY / f)))
        let maxY: Int = max(minY, min(height - 1, Int(rect.maxY / f)))
        var total = 0
        var count = 0
        for y in minY...maxY {
            // The bitmap's first row is the image's top row.
            let row: Int = y * width
            for x in minX...maxX {
                total += Int(values[row + x])
                count += 1
            }
        }
        guard count > 0 else { return 1 }
        return Double(total) / Double(count) / 255
    }
}

/// Reads colours out of the capture.
enum ImageSampler {
    /// The colours in `rect` (image pixels, top left): the background, the most common shade,
    /// and the ink, the pixels furthest from it. Nil when the area is empty.
    static func textColours(in image: CGImage, rect: CGRect) -> (background: MarkColour, ink: MarkColour)? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = rect.integral.intersection(bounds)
        guard !area.isNull, area.width >= 1, area.height >= 1, let part = image.cropping(to: area) else { return nil }
        let longest: CGFloat = max(area.width, area.height)
        let shrink: CGFloat = min(1, 240 / longest)
        let width = max(1, Int(area.width * shrink))
        let height = max(1, Int(area.height * shrink))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let made: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard made else { return nil }
        var colours: [MarkColour] = []
        colours.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            colours.append(MarkColour(red: r, green: g, blue: b))
        }
        let shades: [Double] = colours.map(\.luminance)
        let sorted = shades.sorted()
        let median: Double = sorted[sorted.count / 2]
        var background: [MarkColour] = []
        var distant: [(Double, MarkColour)] = []
        for (shade, colour) in zip(shades, colours) {
            let gap: Double = abs(shade - median)
            if gap < 0.06 { background.append(colour) }
            distant.append((gap, colour))
        }
        distant.sort { $0.0 > $1.0 }
        // The glyphs' cores: clearly apart from the background, leaving out anti-aliased edges.
        let widest: Double = distant.first?.0 ?? 0
        var ink: [MarkColour] = distant.filter { $0.0 >= widest * 0.6 }.map(\.1)
        if ink.isEmpty { ink = distant.prefix(max(1, distant.count / 8)).map(\.1) }
        return (average(background.isEmpty ? colours : background), average(ink))
    }

    /// The colour of the pixel at `point` (image pixels, top left).
    static func colour(at point: CGPoint, in image: CGImage) -> MarkColour? {
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let made: Bool = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard made else { return nil }
        return MarkColour(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255)
    }

    static func average(_ colours: [MarkColour]) -> MarkColour {
        guard !colours.isEmpty else { return .ink }
        var r = 0.0
        var g = 0.0
        var b = 0.0
        for colour in colours {
            r += colour.red
            g += colour.green
            b += colour.blue
        }
        let n = Double(colours.count)
        return MarkColour(red: r / n, green: g / n, blue: b / n)
    }

    /// Whether the capture is a window caught with its shadow on a clear background: its corners
    /// are clear, and walking in from the middle of most edges passes through the shadow's soft,
    /// part-clear pixels before reaching the window. A window caught without its shadow has
    /// clear corners too, but its edges are solid.
    static func hasOwnShadow(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let width = image.width
        let height = image.height
        guard width >= 16, height >= 16 else { return false }
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: width - 1, y: 0), CGPoint(x: 0, y: height - 1),
                       CGPoint(x: width - 1, y: height - 1)]
        for corner in corners {
            let alpha: Double = alphas(in: image, rect: CGRect(origin: corner, size: CGSize(width: 1, height: 1))).first ?? 1
            if alpha >= 0.1 { return false }
        }
        // From each edge's middle, a quarter of the way in.
        let reachX = max(4, width / 4)
        let reachY = max(4, height / 4)
        let lines: [(CGRect, Bool)] = [
            (CGRect(x: 0, y: height / 2, width: reachX, height: 1), false),
            (CGRect(x: width - reachX, y: height / 2, width: reachX, height: 1), true),
            (CGRect(x: width / 2, y: 0, width: 1, height: reachY), false),
            (CGRect(x: width / 2, y: height - reachY, width: 1, height: reachY), true),
        ]
        var soft = 0
        for (rect, fromEnd) in lines {
            var values = alphas(in: image, rect: rect)
            if fromEnd { values.reverse() }
            guard let first = values.first, first < 0.5 else { continue }
            // The shadow: several part-clear pixels before anything solid.
            let ramp = values.prefix { $0 < 0.95 }
            if ramp.filter({ $0 > 0.02 && $0 < 0.9 }).count >= 3 { soft += 1 }
        }
        return soft >= 3
    }

    /// The alpha of each pixel in `rect` (image pixels, top left), row by row.
    private static func alphas(in image: CGImage, rect: CGRect) -> [Double] {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = rect.integral.intersection(bounds)
        guard !area.isNull, area.width >= 1, area.height >= 1, let part = image.cropping(to: area) else { return [] }
        let width = Int(area.width)
        let height = Int(area.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let made: Bool = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard made else { return [] }
        return stride(from: 3, to: bytes.count, by: 4).map { Double(bytes[$0]) / 255 }
    }

    /// What hides things on dark areas, where an ink bar would vanish.
    static let darkRedaction = MarkColour(hex: 0x8E8E93)

    /// The colour a redaction bar over `rect` should be: the text's own colour when there's
    /// clearly text there, so the bar reads as hidden text; otherwise ink, or grey on dark areas.
    static func redactionColour(in image: CGImage, rect: CGRect) -> MarkColour {
        guard let colours = textColours(in: image, rect: rect) else { return .ink }
        if colours.ink.contrast(with: colours.background) >= 2 { return colours.ink }
        return plainRedaction(onLightness: colours.background.lightness)
    }

    /// A bar on an area without text: ink, or grey where the area is dark (below 0.3).
    static func plainRedaction(onLightness lightness: Double) -> MarkColour {
        lightness < 0.3 ? darkRedaction : .ink
    }
}

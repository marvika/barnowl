import CoreGraphics
import Foundation

/// Backgrounds that suit a capture: gradients built around its own colours, and those colours as
/// chips for making your own. Pure and deterministic, so it runs off the main thread.
enum BackgroundHarmony {
    struct Suggestions: Equatable, Sendable {
        /// Up to four: soft, vivid, deep, and a pair of the capture's two main hues.
        var gradients: [CustomGradient]
        /// Up to five of the capture's own colours, most prominent first.
        var colours: [MarkColour]
        /// The hue everything is built around, in Oklab degrees.
        var hue: Double
        /// How light the capture's outer edge is (gamma-encoded, 0 to 1).
        var edgeLightness: Double
    }

    /// The hue grey captures (code, documents) are given: the owl's lavender.
    static let fallbackHue: Double = MarkColour.lavender.oklab.hue

    /// A suggestion this close in lightness to the capture's edge would let the capture melt into it.
    static let separation: Double = 0.12

    static let side = 48
    static let bins = 24

    /// Where gradients lean as they darken: an indigo dusk, as shadows lean blue in a painting.
    /// Leaning this way keeps warm hues out of olive and mud.
    static let shadeHue: Double = 285

    static func suggestions(for image: CGImage) -> Suggestions {
        let pixels = sample(image)
        let edge = edgeLightness(pixels)
        let histogram = hueHistogram(pixels)
        let peaks = histogram.peaks
        let hue: Double = peaks.first?.hue ?? fallbackHue
        let second: Double? = peaks.dropFirst().first { angle(between: $0.hue, and: hue) >= 40 }?.hue
        // Vivid sits where its hue is most vivid: yellows light, blues deeper.
        let vivid: Double = min(max(cusp(hue), 0.6), 0.8)
        // The pair: the two main hues, or a muted partner opposite when there's only one.
        let pair: CustomGradient
        if let second {
            pair = gradient((0.72, 0.13, hue), (0.62, 0.14, second))
        } else {
            pair = gradient((0.72, 0.13, hue), (0.7, 0.06, hue + 150))
        }
        let candidates: [CustomGradient] = [
            gradient((0.93, 0.045, hue), (0.84, 0.07, toward(hue, by: 20))),
            gradient((vivid, 0.17, hue), (vivid - 0.13, 0.17, toward(hue, by: 35))),
            gradient((0.36, 0.09, toward(hue, fraction: 0.5)), (0.2, 0.07, toward(hue, fraction: 0.75))),
            pair,
        ]
        let kept = candidates.filter { abs(meanLightness($0) - edge) > separation }
        var colours: [MarkColour] = []
        let found: [MarkColour] = peaks.prefix(5).map(\.colour) + [pixels.edgeColour].compactMap { $0 }
        for colour in found where !colours.contains(where: { distance($0, colour) < 0.04 }) {
            colours.append(colour)
        }
        return Suggestions(gradients: kept, colours: Array(colours.prefix(5)), hue: hue, edgeLightness: edge)
    }

    /// `hue` turned `degrees` toward the shade hue, the shorter way, stopping there.
    static func toward(_ hue: Double, by degrees: Double) -> Double {
        let gap = signedTurn(from: hue, to: shadeHue)
        let turn: Double = gap < 0 ? max(gap, -degrees) : min(gap, degrees)
        return hue + turn
    }

    /// `hue` turned part of the way to the shade hue.
    static func toward(_ hue: Double, fraction: Double) -> Double {
        hue + signedTurn(from: hue, to: shadeHue) * fraction
    }

    /// The shorter turn from one hue to another, from −180 to 180 degrees.
    static func signedTurn(from a: Double, to b: Double) -> Double {
        var turn: Double = (b - a).truncatingRemainder(dividingBy: 360)
        if turn > 180 { turn -= 360 }
        if turn < -180 { turn += 360 }
        return turn
    }

    /// The lightness at which `hue` reaches its most vivid in sRGB.
    static func cusp(_ hue: Double) -> Double {
        var best: (lightness: Double, chroma: Double) = (0.6, 0)
        for step in 6...19 {
            let lightness: Double = Double(step) * 0.05
            let chroma: Double = OKLab.lch(lightness, 0.4, hue).colour.oklab.chroma
            if chroma > best.chroma { best = (lightness, chroma) }
        }
        return best.lightness
    }

    /// How far apart two colours look, in Oklab.
    static func distance(_ a: MarkColour, _ b: MarkColour) -> Double {
        let x = a.oklab
        let y = b.oklab
        let dl: Double = x.l - y.l
        let da: Double = x.a - y.a
        let db: Double = x.b - y.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// The mean of the stops' gamma-encoded lightness: how light the gradient looks as a whole.
    static func meanLightness(_ gradient: CustomGradient) -> Double {
        let values: [Double] = gradient.stops.map(\.colour.lightness)
        return values.reduce(0, +) / Double(max(values.count, 1))
    }

    /// The shorter way round between two hues, in degrees.
    static func angle(between a: Double, and b: Double) -> Double {
        let difference: Double = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func gradient(_ from: (Double, Double, Double), _ to: (Double, Double, Double)) -> CustomGradient {
        let start = OKLab.lch(from.0, from.1, from.2).colour
        let end = OKLab.lch(to.0, to.1, to.2).colour
        return CustomGradient(colours: [start, end])
    }

    // MARK: Pixels

    struct Pixel {
        let colour: MarkColour
        let lab: OKLab
        let opaque: Bool
    }

    struct Pixels {
        let side: Int
        let pixels: [Pixel]

        /// The silhouette's rim: opaque pixels at the image's edge or next to a clear one, so a
        /// window caught with its shadow is judged by its own edge, not the clear margin.
        var rim: [Pixel] {
            var rim: [Pixel] = []
            for y in 0..<side {
                for x in 0..<side {
                    let pixel = pixels[y * side + x]
                    guard pixel.opaque else { continue }
                    let atEdge: Bool = x == 0 || y == 0 || x == side - 1 || y == side - 1
                    if atEdge || !isOpaque(x - 1, y) || !isOpaque(x + 1, y) || !isOpaque(x, y - 1) || !isOpaque(x, y + 1) {
                        rim.append(pixel)
                    }
                }
            }
            return rim
        }

        private func isOpaque(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < side, y < side else { return false }
            return pixels[y * side + x].opaque
        }

        var edgeColour: MarkColour? {
            let rim = self.rim
            guard !rim.isEmpty else { return nil }
            return ImageSampler.average(rim.map(\.colour))
        }
    }

    static func sample(_ image: CGImage) -> Pixels {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let made: Bool = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard made else { return Pixels(side: side, pixels: []) }
        var pixels: [Pixel] = []
        pixels.reserveCapacity(side * side)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha: Double = Double(bytes[index + 3]) / 255
            let opaque: Bool = alpha >= 0.5
            let divisor: Double = max(alpha, 1.0 / 255) * 255
            let red: Double = min(Double(bytes[index]) / divisor, 1)
            let green: Double = min(Double(bytes[index + 1]) / divisor, 1)
            let blue: Double = min(Double(bytes[index + 2]) / divisor, 1)
            let colour = MarkColour(red: red, green: green, blue: blue)
            pixels.append(Pixel(colour: colour, lab: colour.oklab, opaque: opaque))
        }
        return Pixels(side: side, pixels: pixels)
    }

    private static func edgeLightness(_ pixels: Pixels) -> Double {
        let rim = pixels.rim
        guard !rim.isEmpty else { return 0.5 }
        let total: Double = rim.reduce(0) { $0 + $1.colour.lightness }
        return total / Double(rim.count)
    }

    // MARK: Hues

    struct Peak {
        let hue: Double
        let weight: Double
        let colour: MarkColour
    }

    struct Histogram {
        var weights = [Double](repeating: 0, count: BackgroundHarmony.bins)
        var sums = [OKLab](repeating: OKLab(l: 0, a: 0, b: 0), count: BackgroundHarmony.bins)
        var colourful = 0
        var opaque = 0

        /// The hues that stand out, strongest first, at least 30° apart. None when the capture
        /// is all but grey.
        var peaks: [Peak] {
            guard opaque > 0, Double(colourful) >= Double(opaque) * 0.03 else { return [] }
            let count = weights.count
            // Neighbouring bins count a little, so a hue split across two still wins.
            let smoothed: [Double] = weights.indices.map { index in
                let before: Double = weights[(index + count - 1) % count]
                let after: Double = weights[(index + 1) % count]
                return weights[index] * 2 + before + after
            }
            let order: [Int] = smoothed.indices.sorted { a, b in
                smoothed[a] == smoothed[b] ? a < b : smoothed[a] > smoothed[b]
            }
            let strongest: Double = order.first.map { smoothed[$0] } ?? 0
            var peaks: [Peak] = []
            for index in order where weights[index] > 0 && smoothed[index] >= strongest * 0.12 {
                let sum = sums[index]
                let mean = OKLab(l: sum.l / weights[index], a: sum.a / weights[index], b: sum.b / weights[index])
                let hue = mean.hue
                guard !peaks.contains(where: { BackgroundHarmony.angle(between: $0.hue, and: hue) < 30 }) else { continue }
                peaks.append(Peak(hue: hue, weight: smoothed[index], colour: mean.colour))
            }
            return peaks
        }
    }

    /// Hues weighted by how colourful each pixel is; greys, near-blacks and near-whites don't count.
    static func hueHistogram(_ pixels: Pixels) -> Histogram {
        var histogram = Histogram()
        for pixel in pixels.pixels where pixel.opaque {
            histogram.opaque += 1
            let lab = pixel.lab
            let chroma = lab.chroma
            guard chroma >= 0.04, lab.l >= 0.15, lab.l <= 0.95 else { continue }
            histogram.colourful += 1
            let bin: Int = min(Int(lab.hue / (360 / Double(bins))), bins - 1)
            histogram.weights[bin] += chroma
            let sum = histogram.sums[bin]
            histogram.sums[bin] = OKLab(l: sum.l + lab.l * chroma, a: sum.a + lab.a * chroma, b: sum.b + lab.b * chroma)
        }
        return histogram
    }
}

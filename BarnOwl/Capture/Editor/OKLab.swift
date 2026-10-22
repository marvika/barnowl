import Foundation

/// A colour as the eye sees it: Oklab (Björn Ottosson, 2020), where equal steps look equal.
/// Gradients mixed here stay bright through the middle, and hues can be named and turned.
struct OKLab: Equatable, Sendable {
    /// Lightness, from 0 (black) to 1 (white).
    var l: Double
    /// Green (negative) to red (positive).
    var a: Double
    /// Blue (negative) to yellow (positive).
    var b: Double

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ colour: MarkColour) {
        let red: Double = Self.linear(colour.red)
        let green: Double = Self.linear(colour.green)
        let blue: Double = Self.linear(colour.blue)
        let lms0: Double = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
        let lms1: Double = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
        let lms2: Double = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
        let c0: Double = cbrt(lms0)
        let c1: Double = cbrt(lms1)
        let c2: Double = cbrt(lms2)
        l = 0.2104542553 * c0 + 0.7936177850 * c1 - 0.0040720468 * c2
        a = 1.9779984951 * c0 - 2.4285922050 * c1 + 0.4505937099 * c2
        b = 0.0259040371 * c0 + 0.7827717662 * c1 - 0.8086757660 * c2
    }

    /// From lightness, chroma and hue (in degrees).
    static func lch(_ lightness: Double, _ chroma: Double, _ hue: Double) -> OKLab {
        let radians: Double = hue * .pi / 180
        return OKLab(l: lightness, a: chroma * cos(radians), b: chroma * sin(radians))
    }

    /// How colourful it is: 0 is grey; the most vivid sRGB colours reach about 0.32.
    var chroma: Double { hypot(a, b) }

    /// The hue, in degrees from 0 to 360: red near 30, yellow 110, green 140, blue 265.
    var hue: Double {
        let degrees: Double = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Linear-light sRGB, which strays outside 0...1 when the colour is out of gamut.
    private var linearRGB: (red: Double, green: Double, blue: Double) {
        let c0: Double = l + 0.3963377774 * a + 0.2158037573 * b
        let c1: Double = l - 0.1055613458 * a - 0.0638541728 * b
        let c2: Double = l - 0.0894841775 * a - 1.2914855480 * b
        let lms0: Double = c0 * c0 * c0
        let lms1: Double = c1 * c1 * c1
        let lms2: Double = c2 * c2 * c2
        let red: Double = 4.0767416621 * lms0 - 3.3077115913 * lms1 + 0.2309699292 * lms2
        let green: Double = -1.2684380046 * lms0 + 2.6097574011 * lms1 - 0.3413193965 * lms2
        let blue: Double = -0.0041960863 * lms0 - 0.7034186147 * lms1 + 1.7076147010 * lms2
        return (red, green, blue)
    }

    /// Whether sRGB can show it.
    var inGamut: Bool {
        let rgb = linearRGB
        let low: Double = -0.0001
        let high: Double = 1.0001
        return rgb.red >= low && rgb.red <= high && rgb.green >= low && rgb.green <= high && rgb.blue >= low
            && rgb.blue <= high
    }

    /// The colour in sRGB. Out-of-gamut colours first lose chroma, keeping their lightness and
    /// hue, so a too-vivid blue becomes the most vivid blue there is rather than a different one.
    var colour: MarkColour {
        let fitted = inGamut ? self : gamutMapped
        let rgb = fitted.linearRGB
        return MarkColour(red: Self.encoded(rgb.red), green: Self.encoded(rgb.green), blue: Self.encoded(rgb.blue))
    }

    private var gamutMapped: OKLab {
        let lightness: Double = min(max(l, 0), 1)
        let hue = self.hue
        var low: Double = 0
        var high: Double = chroma
        for _ in 0..<24 {
            let middle: Double = (low + high) / 2
            if OKLab.lch(lightness, middle, hue).inGamut { low = middle } else { high = middle }
        }
        return OKLab.lch(lightness, low, hue)
    }

    /// Part way to `other`. Lightness and hue travel in a straight line through Oklab, but the
    /// chroma is carried across too, so blue to orange goes by way of a pink rather than
    /// through grey. Towards a grey it fades as plain Oklab does.
    func mixed(with other: OKLab, _ t: Double) -> OKLab {
        let keep: Double = 1 - t
        let lightness: Double = l * keep + other.l * t
        let mixA: Double = a * keep + other.a * t
        let mixB: Double = b * keep + other.b * t
        let straight: Double = hypot(mixA, mixB)
        let carried: Double = chroma * keep + other.chroma * t
        guard carried > 0.0001 else { return OKLab(l: lightness, a: mixA, b: mixB) }
        guard straight > carried * 0.02 else {
            // Exactly opposite hues: turn the shorter way round, which here is either.
            let turn: Double = hue + 90 * t * 2
            return OKLab.lch(lightness, carried, turn)
        }
        let factor: Double = carried / straight
        return OKLab(l: lightness, a: mixA * factor, b: mixB * factor)
    }

    // MARK: sRGB transfer

    static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func encoded(_ value: Double) -> Double {
        let clamped: Double = min(max(value, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}

extension MarkColour {
    var oklab: OKLab { OKLab(self) }

    /// This colour part way to `other`, mixed as the eye sees it (see `OKLab.mixed`).
    func blended(with other: MarkColour, _ t: Double) -> MarkColour {
        oklab.mixed(with: other.oklab, t).colour
    }

    /// A plain word or two for the colour, for labels and VoiceOver: "blue", "light pink",
    /// "dark grey".
    var plainName: String {
        let lab = oklab
        if lab.chroma < 0.035 {
            switch lab.l {
            case 0.96...: return "white"
            case 0.78...: return "light grey"
            case 0.45...: return "grey"
            case 0.22...: return "dark grey"
            default: return "black"
            }
        }
        let hue = Self.hueName(lab.hue)
        if lab.l > 0.84 { return "light \(hue)" }
        if lab.l < 0.4 { return "dark \(hue)" }
        return hue
    }

    /// The name for an Oklab hue, in degrees.
    static func hueName(_ hue: Double) -> String {
        switch hue {
        case 18..<48: "red"
        case 48..<78: "orange"
        case 78..<118: "yellow"
        case 118..<168: "green"
        case 168..<225: "teal"
        case 225..<272: "blue"
        case 272..<302: "violet"
        case 302..<345: "purple"
        default: "pink"
        }
    }
}

import CoreGraphics
import Foundation

/// A colour for marks, kept as sRGB components so a document can be saved and opened again.
struct MarkColour: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    static let red = MarkColour(hex: 0xFF3B30)
    static let amber = MarkColour(hex: 0xF5A633)
    static let yellow = MarkColour(hex: 0xFFD60A)
    static let green = MarkColour(hex: 0x30D158)
    static let blue = MarkColour(hex: 0x0A84FF)
    static let lavender = MarkColour(hex: 0x8C87FF)
    static let white = MarkColour(hex: 0xFFFFFF)
    static let ink = MarkColour(hex: 0x16151F)

    /// The eight swatches, in order (keys 1 to 8).
    static let palette: [MarkColour] = [.red, .amber, .yellow, .green, .blue, .lavender, .white, .ink]
    static let paletteNames = ["Red", "Amber", "Yellow", "Green", "Blue", "Lavender", "White", "Ink"]

    /// The highlighter's own colours: light enough to read text through.
    static let highlighterPalette: [MarkColour] = [.yellow, MarkColour(hex: 0x5BE37D), MarkColour(hex: 0xFF7EB6),
                                                   MarkColour(hex: 0x64D2FF)]
    static let highlighterNames = ["Yellow", "Green", "Pink", "Blue"]

    var name: String {
        if let index = Self.palette.firstIndex(of: self) { return Self.paletteNames[index] }
        if let index = Self.highlighterPalette.firstIndex(of: self) { return Self.highlighterNames[index] }
        return "Colour \(hex)"
    }

    var hex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Relative luminance, as WCAG defines it.
    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r: Double = 0.2126 * linear(red)
        let g: Double = 0.7152 * linear(green)
        let b: Double = 0.0722 * linear(blue)
        return r + g + b
    }

    /// The WCAG contrast ratio between two colours, from 1 to 21.
    func contrast(with other: MarkColour) -> Double {
        let a: Double = luminance + 0.05
        let b: Double = other.luminance + 0.05
        return max(a, b) / min(a, b)
    }

    /// Light colours (yellow, white) get an ink halo; the rest a white one.
    var isLight: Bool { luminance > 0.6 }

    /// What fills a box or counter in this colour: a little deeper for the bright palette
    /// colours, so white text on them reads.
    var boxFill: MarkColour {
        switch self {
        case .red: MarkColour(hex: 0xD92D20)
        case .green: MarkColour(hex: 0x1A7F37)
        case .blue: MarkColour(hex: 0x0064D2)
        case .lavender: MarkColour(hex: 0x5E58E0)
        default: self
        }
    }

    /// Text on a fill of this colour: white when it reaches 4.5:1, otherwise whichever of
    /// white and ink reads better.
    var textOnFill: MarkColour {
        let white = contrast(with: .white)
        if white >= 4.5 { return .white }
        return contrast(with: .ink) > white ? .ink : .white
    }

    /// This colour mixed toward `other` by `amount` (0 keeps it, 1 is `other`).
    func mixed(with other: MarkColour, _ amount: Double) -> MarkColour {
        let keep: Double = 1 - amount
        return MarkColour(red: red * keep + other.red * amount, green: green * keep + other.green * amount,
                          blue: blue * keep + other.blue * amount)
    }
}

// MARK: Style

enum ArrowHeads: String, Codable, CaseIterable, Sendable {
    case none, end, both
}

enum ShapeFill: String, Codable, CaseIterable, Sendable {
    /// Just the outline.
    case none
    /// The outline over a light wash of the colour.
    case tinted
    /// Filled in the colour.
    case solid

    var title: String {
        switch self {
        case .none: "Outline"
        case .tinted: "Tinted"
        case .solid: "Filled"
        }
    }
}

enum LineDash: String, Codable, CaseIterable, Sendable {
    case solid, dashed, dotted

    var title: String {
        switch self {
        case .solid: "Solid"
        case .dashed: "Dashed"
        case .dotted: "Dotted"
        }
    }
}

/// A text mark's typeface.
enum TextFont: Codable, Hashable, Sendable {
    /// SF Pro Rounded: friendly and clear, the default.
    case rounded
    /// SF Pro.
    case sans
    /// New York.
    case serif
    /// SF Mono.
    case mono
    /// Any installed font, by PostScript name.
    case named(String)

    static let builtIn: [TextFont] = [.rounded, .sans, .serif, .mono]

    var title: String {
        switch self {
        case .rounded: "Rounded"
        case .sans: "Sans"
        case .serif: "Serif"
        case .mono: "Mono"
        case .named(let name): name
        }
    }
}

enum FontWeight: String, Codable, CaseIterable, Sendable {
    case regular, semibold, bold

    var title: String {
        switch self {
        case .regular: "Regular"
        case .semibold: "Semibold"
        case .bold: "Bold"
        }
    }
}

enum TextStyle: String, Codable, CaseIterable, Sendable {
    /// Coloured text with a crisp halo.
    case plain
    /// Text on a rounded box of the colour.
    case box
    /// Darker text on a soft tint of the colour.
    case soft
    /// White text outlined in the colour.
    case outline
    /// A box with a pointer reaching out to `end`.
    case callout

    var title: String {
        switch self {
        case .plain: "Plain"
        case .box: "Box"
        case .soft: "Soft"
        case .outline: "Outline"
        case .callout: "Callout"
        }
    }
}

enum TextAlign: String, Codable, CaseIterable, Sendable {
    case left, centre, right

    var title: String {
        switch self {
        case .left: "Left"
        case .centre: "Centre"
        case .right: "Right"
        }
    }
}

enum CounterFormat: String, Codable, CaseIterable, Sendable {
    case number, upper, lower, roman

    var title: String {
        switch self {
        case .number: "1, 2, 3"
        case .upper: "A, B, C"
        case .lower: "a, b, c"
        case .roman: "I, II, III"
        }
    }

    /// The label for the `n`th counter (from 1).
    func label(_ n: Int) -> String {
        let n = max(n, 1)
        switch self {
        case .number: return String(n)
        case .upper: return Self.letters(n)
        case .lower: return Self.letters(n).lowercased()
        case .roman: return Self.roman(n)
        }
    }

    /// A, B … Z, AA, AB …
    static func letters(_ n: Int) -> String {
        var n = n
        var result = ""
        while n > 0 {
            let index = (n - 1) % 26
            result = String(UnicodeScalar(UInt8(65 + index))) + result
            n = (n - 1) / 26
        }
        return result
    }

    static func roman(_ n: Int) -> String {
        guard n < 4000 else { return String(n) }
        let values: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                       (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n
        var result = ""
        for (value, numeral) in values {
            while n >= value {
                result += numeral
                n -= value
            }
        }
        return result
    }
}

enum RedactStyle: String, Codable, CaseIterable, Sendable {
    case solid, pixelate, blur

    var title: String {
        switch self {
        case .solid: "Solid"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        }
    }
}

enum RedactStrength: String, Codable, CaseIterable, Sendable {
    case light, medium, strong

    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    /// Pixel block size, in points.
    var block: Double {
        switch self {
        case .light: 6
        case .medium: 10
        case .strong: 16
        }
    }

    /// Blur radius, in points.
    var radius: Double {
        switch self {
        case .light: 6
        case .medium: 12
        case .strong: 20
        }
    }
}

enum SpotlightShape: String, Codable, CaseIterable, Sendable {
    case rectangle, ellipse

    var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        }
    }
}

/// How a mark looks, apart from its colour. Lengths are in points; marks multiply them by
/// the capture's scale. Every kind reads only the fields it uses.
struct MarkStyle: Codable, Equatable, Sendable {
    /// The stroke's width; an arrow's shaft where it meets the head; a counter's diameter.
    var weight: Double = 4
    var opacity: Double = 1
    var dash = LineDash.solid
    var heads = ArrowHeads.end
    /// New arrows start with a gentle bend.
    var curved = false
    var fill = ShapeFill.none
    var font = TextFont.rounded
    var fontWeight = FontWeight.semibold
    var fontSize: Double = 20
    var textStyle = TextStyle.box
    var align = TextAlign.left
    var counterFormat = CounterFormat.number
    var redact = RedactStyle.solid
    var strength = RedactStrength.medium
    var spotlight = SpotlightShape.rectangle
    /// How dark a spotlight makes everything around it, from 0 to 1.
    var dim: Double = 0.5

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = MarkStyle()
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? base.weight
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? base.opacity
        dash = try c.decodeIfPresent(LineDash.self, forKey: .dash) ?? base.dash
        heads = try c.decodeIfPresent(ArrowHeads.self, forKey: .heads) ?? base.heads
        curved = try c.decodeIfPresent(Bool.self, forKey: .curved) ?? base.curved
        fill = try c.decodeIfPresent(ShapeFill.self, forKey: .fill) ?? base.fill
        font = try c.decodeIfPresent(TextFont.self, forKey: .font) ?? base.font
        fontWeight = try c.decodeIfPresent(FontWeight.self, forKey: .fontWeight) ?? base.fontWeight
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? base.fontSize
        textStyle = try c.decodeIfPresent(TextStyle.self, forKey: .textStyle) ?? base.textStyle
        align = try c.decodeIfPresent(TextAlign.self, forKey: .align) ?? base.align
        counterFormat = try c.decodeIfPresent(CounterFormat.self, forKey: .counterFormat) ?? base.counterFormat
        redact = try c.decodeIfPresent(RedactStyle.self, forKey: .redact) ?? base.redact
        strength = try c.decodeIfPresent(RedactStrength.self, forKey: .strength) ?? base.strength
        spotlight = try c.decodeIfPresent(SpotlightShape.self, forKey: .spotlight) ?? base.spotlight
        dim = try c.decodeIfPresent(Double.self, forKey: .dim) ?? base.dim
    }
}

/// Where a mark came from when a smart tool made it, so it can be found again.
struct MarkOrigin: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Hide Private Info.
        case privateInfo
        /// A click that fitted the mark to text or a window.
        case fit
    }

    var source: Source
    /// For private info, the kind of thing hidden (`SensitiveTextFinder.Kind`'s raw value).
    var category: String?
}

/// One annotation. Coordinates are in the captured image's pixels, with y pointing down,
/// so marks stay put when the image is cropped or framed.
struct Mark: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case arrow, rectangle, ellipse, text, counter, highlighter, pen, redact, spotlight, image

        /// Marks drawn as the rectangle between `start` and `end`.
        var isBoxed: Bool {
            switch self {
            case .rectangle, .ellipse, .highlighter, .redact, .spotlight, .image: true
            case .arrow, .text, .counter, .pen: false
            }
        }

        /// Effects (highlights, redactions, spotlights) sit on the image, under every other mark.
        var isEffect: Bool {
            switch self {
            case .highlighter, .redact, .spotlight: true
            default: false
            }
        }

        var title: String {
            switch self {
            case .arrow: "Arrow"
            case .rectangle: "Rectangle"
            case .ellipse: "Ellipse"
            case .text: "Text"
            case .counter: "Counter"
            case .highlighter: "Highlight"
            case .pen: "Drawing"
            case .redact: "Redaction"
            case .spotlight: "Spotlight"
            case .image: "Image"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var colour: MarkColour
    var style = MarkStyle()
    /// Where the drag began and ended. Boxed marks fill the rectangle between them; a counter's
    /// badge sits at `start` with its pointer reaching `end`; text's top-left corner is `start`.
    var start: CGPoint
    var end: CGPoint
    /// An arrow's bend: the control point of a quadratic Bézier, or nil when straight.
    var control: CGPoint?
    /// A freehand stroke's points.
    var points: [CGPoint] = []
    /// A text mark's text, or a counter's label.
    var text = ""
    /// A pasted image, as PNG.
    var imageData: Data?
    var origin: MarkOrigin?

    init(id: UUID = UUID(), kind: Kind, colour: MarkColour, style: MarkStyle = MarkStyle(), start: CGPoint, end: CGPoint) {
        self.id = id
        self.kind = kind
        self.colour = colour
        self.style = style
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        colour = try c.decodeIfPresent(MarkColour.self, forKey: .colour) ?? .red
        style = try c.decodeIfPresent(MarkStyle.self, forKey: .style) ?? MarkStyle()
        start = try c.decode(CGPoint.self, forKey: .start)
        end = try c.decodeIfPresent(CGPoint.self, forKey: .end) ?? start
        control = try c.decodeIfPresent(CGPoint.self, forKey: .control)
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points) ?? []
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        origin = try c.decodeIfPresent(MarkOrigin.self, forKey: .origin)
    }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

// MARK: Frame

enum FrameGradient: String, Codable, CaseIterable, Sendable {
    case dawn, dusk, meadow, mist

    var title: String {
        switch self {
        case .dawn: "Dawn"
        case .dusk: "Dusk"
        case .meadow: "Meadow"
        case .mist: "Mist"
        }
    }

    /// From the top-left corner to the bottom-right.
    var colours: (MarkColour, MarkColour) {
        switch self {
        case .dawn: (MarkColour(hex: 0x8C87FF), MarkColour(hex: 0xF5A633))
        case .dusk: (MarkColour(hex: 0x5A55C8), MarkColour(hex: 0x1C1A40))
        case .meadow: (MarkColour(hex: 0x34C759), MarkColour(hex: 0x2AA6B8))
        case .mist: (MarkColour(hex: 0xF4F3F8), MarkColour(hex: 0xD5D3DE))
        }
    }
}

enum FrameBackground: Codable, Equatable, Sendable {
    /// No frame: the output is just the (cropped) image.
    case none
    case gradient(FrameGradient)
    case solid(MarkColour)
    /// Your desktop picture, softly blurred.
    case desktop
    /// A frame with nothing behind it, so the padding and shadow stay transparent.
    case transparent
}

enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case auto, wide, standard, square, portrait

    var title: String {
        switch self {
        case .auto: "Auto"
        case .wide: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        case .portrait: "4:5"
        }
    }

    /// Width over height, or nil to follow the image.
    var value: CGFloat? {
        switch self {
        case .auto: nil
        case .wide: 16.0 / 9.0
        case .standard: 4.0 / 3.0
        case .square: 1
        case .portrait: 4.0 / 5.0
        }
    }
}

/// The frame around the image. Lengths are in image pixels.
struct FrameSettings: Codable, Equatable, Sendable {
    var background = FrameBackground.none
    var padding: CGFloat = 0
    var cornerRadius: CGFloat = 0
    var shadow = true
    var ratio = AspectRatio.auto

    var isOn: Bool { background != .none }

    init(background: FrameBackground = .none, padding: CGFloat = 0, cornerRadius: CGFloat = 0, shadow: Bool = true,
         ratio: AspectRatio = .auto) {
        self.background = background
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.ratio = ratio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(FrameBackground.self, forKey: .background) ?? .none
        padding = try c.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 0
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? true
        ratio = try c.decodeIfPresent(AspectRatio.self, forKey: .ratio) ?? .auto
    }
}

// MARK: Document

/// Everything the editor makes: the marks, the crop and the frame. A value, so undo can keep
/// whole snapshots cheaply, and `Codable` so a capture can be opened again with its marks
/// still editable.
struct EditorDocument: Codable, Equatable, Sendable {
    /// 2: weights in points, arrow heads, fills, fonts, counter formats, smart origins.
    static let currentSchema = 2

    var schemaVersion = EditorDocument.currentSchema
    /// The captured image's size in pixels.
    var imageSize: CGSize
    /// The part of the image kept, in image pixels.
    var crop: CGRect
    /// Effects draw first, then everything else; within each, later marks are on top.
    var marks: [Mark] = []
    var frame: FrameSettings
    /// The first counter's number.
    var counterStart = 1

    /// A fresh document; `scale` (pixels per point) sets the frame's default padding and corners
    /// for when it's turned on.
    init(imageSize: CGSize, scale: CGFloat = 2) {
        self.imageSize = imageSize
        crop = CGRect(origin: .zero, size: imageSize)
        frame = FrameSettings(padding: (48 * scale).rounded(), cornerRadius: (10 * scale).rounded())
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        imageSize = try c.decode(CGSize.self, forKey: .imageSize)
        crop = try c.decodeIfPresent(CGRect.self, forKey: .crop) ?? CGRect(origin: .zero, size: imageSize)
        marks = try c.decodeIfPresent([Mark].self, forKey: .marks) ?? []
        frame = try c.decodeIfPresent(FrameSettings.self, forKey: .frame) ?? FrameSettings()
        counterStart = try c.decodeIfPresent(Int.self, forKey: .counterStart) ?? 1
        // Read in the current shape from here on.
        schemaVersion = Self.currentSchema
    }

    var imageBounds: CGRect { CGRect(origin: .zero, size: imageSize) }

    subscript(id: UUID) -> Mark? {
        marks.first { $0.id == id }
    }

    mutating func update(_ id: UUID, _ change: (inout Mark) -> Void) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        change(&marks[index])
    }

    mutating func remove(_ ids: Set<UUID>) {
        marks.removeAll { ids.contains($0.id) }
    }

    /// Counters are numbered in the order they were placed, from `counterStart`, so deleting
    /// one renumbers the rest.
    var counterNumbers: [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        var next = counterStart
        for mark in marks where mark.kind == .counter {
            numbers[mark.id] = next
            next += 1
        }
        return numbers
    }

    /// The marks in the order they're drawn: highlights, redactions and spotlights on the image,
    /// then everything else, each in array order. Nothing ever sits between the image and a
    /// highlight, and a highlight never shows what a redaction hides.
    var drawingOrder: [Mark] {
        let highlights: [Mark] = marks.filter { $0.kind == .highlighter }
        let redactions: [Mark] = marks.filter { $0.kind == .redact }
        let spotlights: [Mark] = marks.filter { $0.kind == .spotlight }
        let objects: [Mark] = marks.filter { !$0.kind.isEffect }
        return highlights + redactions + spotlights + objects
    }
}

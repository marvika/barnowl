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

    static let amber = MarkColour(hex: 0xF5A633)
    static let coral = MarkColour(hex: 0xFF6B5A)
    static let lavender = MarkColour(hex: 0x8C87FF)
    static let green = MarkColour(hex: 0x34C759)
    static let white = MarkColour(hex: 0xFFFFFF)
    static let ink = MarkColour(hex: 0x16151F)

    /// The six swatches, in toolbar order (keys 1 to 6).
    static let palette: [MarkColour] = [.amber, .coral, .lavender, .green, .white, .ink]
    static let paletteNames = ["Amber", "Coral", "Lavender", "Green", "White", "Ink"]

    var name: String {
        Self.palette.firstIndex(of: self).map { Self.paletteNames[$0] } ?? "Colour"
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

    /// Whether ink reads better on this colour than white does.
    var isLight: Bool { luminance > 0.45 }

    /// Text on a box of this colour: ink on light colours, white on the rest.
    var contrasting: MarkColour { isLight ? .ink : .white }
}

/// The three stroke sizes. Measurements are in points; marks multiply them by the capture's scale.
enum StrokeSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .small: 2.5
        case .medium: 4
        case .large: 6.5
        }
    }

    /// An arrow's shaft at its widest, where it meets the head.
    var arrowWidth: CGFloat {
        switch self {
        case .small: 3.5
        case .medium: 5.5
        case .large: 8.5
        }
    }

    var counterRadius: CGFloat {
        switch self {
        case .small: 10
        case .medium: 13
        case .large: 17
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: 15
        case .medium: 20
        case .large: 28
        }
    }

    var smaller: StrokeSize {
        switch self {
        case .small, .medium: .small
        case .large: .medium
        }
    }

    var larger: StrokeSize {
        switch self {
        case .small: .medium
        case .medium, .large: .large
        }
    }
}

enum ArrowStyle: String, Codable, CaseIterable, Sendable {
    case straight, curved, double

    var title: String {
        switch self {
        case .straight: "Straight"
        case .curved: "Curved"
        case .double: "Double-Headed"
        }
    }
}

enum TextStyle: String, Codable, CaseIterable, Sendable {
    /// Coloured text with a soft halo.
    case halo
    /// Text on a rounded box of the colour.
    case box
    /// Light text with a thick outline in the colour.
    case outline

    var title: String {
        switch self {
        case .halo: "Plain"
        case .box: "Box"
        case .outline: "Outline"
        }
    }
}

enum RedactStyle: String, Codable, CaseIterable, Sendable {
    case pixelate, blur, solid

    var title: String {
        switch self {
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .solid: "Solid"
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

/// The style choices for every kind of mark; each mark reads the one for its kind.
struct MarkStyle: Codable, Equatable, Sendable {
    var arrow = ArrowStyle.straight
    var text = TextStyle.box
    var redact = RedactStyle.solid
    var spotlight = SpotlightShape.rectangle
}

/// One annotation. Coordinates are in the captured image's pixels, with y pointing down,
/// so marks stay put when the image is cropped or framed.
struct Mark: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case arrow, line, rectangle, filledBox, ellipse, text, counter, highlighter, pen, redact, spotlight, image

        /// Marks drawn as the rectangle between `start` and `end`.
        var isBoxed: Bool {
            switch self {
            case .rectangle, .filledBox, .ellipse, .highlighter, .redact, .spotlight, .image: true
            case .arrow, .line, .text, .counter, .pen: false
            }
        }

        var title: String {
            switch self {
            case .arrow: "Arrow"
            case .line: "Line"
            case .rectangle: "Rectangle"
            case .filledBox: "Filled Box"
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
    var size: StrokeSize
    var style = MarkStyle()
    /// Where the drag began and ended. Boxed marks fill the rectangle between them; a counter's
    /// badge sits at `start` with its pointer reaching `end`; text's top-left corner is `start`.
    var start: CGPoint
    var end: CGPoint
    /// An arrow's bend: the control point of a quadratic Bézier, or nil when straight.
    var control: CGPoint?
    /// A freehand stroke's points.
    var points: [CGPoint] = []
    var text = ""
    /// A pasted image, as PNG.
    var imageData: Data?

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

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
    /// A frame with nothing behind it, so the padding and shadow stay transparent.
    case transparent
}

enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case auto, wide, standard, square

    var title: String {
        switch self {
        case .auto: "Auto"
        case .wide: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        }
    }

    /// Width over height, or nil to follow the image.
    var value: CGFloat? {
        switch self {
        case .auto: nil
        case .wide: 16.0 / 9.0
        case .standard: 4.0 / 3.0
        case .square: 1
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
}

/// Everything the editor makes: the marks, the crop and the frame. A value, so undo can keep
/// whole snapshots cheaply.
struct EditorDocument: Codable, Equatable, Sendable {
    /// The captured image's size in pixels.
    var imageSize: CGSize
    /// The part of the image kept, in image pixels.
    var crop: CGRect
    /// Bottom to top within each layer; see `AnnotationRenderer.drawingOrder`.
    var marks: [Mark] = []
    var frame: FrameSettings

    /// A fresh document; `scale` (pixels per point) sets the frame's default padding and corners
    /// for when it's turned on.
    init(imageSize: CGSize, scale: CGFloat = 2) {
        self.imageSize = imageSize
        crop = CGRect(origin: .zero, size: imageSize)
        frame = FrameSettings(padding: (48 * scale).rounded(), cornerRadius: (10 * scale).rounded())
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

    /// Counters are numbered 1, 2, 3… in the order they were placed, so deleting one renumbers the rest.
    var counterNumbers: [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        for mark in marks where mark.kind == .counter {
            numbers[mark.id] = numbers.count + 1
        }
        return numbers
    }
}

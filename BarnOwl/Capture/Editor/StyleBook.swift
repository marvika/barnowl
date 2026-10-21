import Foundation

/// A tool in the editor's toolbar, with the key that picks it.
enum EditorTool: String, CaseIterable, Codable, Sendable {
    case select, arrow, rectangle, ellipse, text, counter, highlighter, pen, redact, spotlight, crop

    /// The tools in the toolbar's main group, in order.
    static let group: [EditorTool] = [.select, .arrow, .rectangle, .ellipse, .text, .counter, .highlighter, .pen,
                                      .redact, .spotlight]

    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .text: "t"
        case .counter: "n"
        case .highlighter: "h"
        case .pen: "p"
        case .redact: "b"
        case .spotlight: "s"
        case .crop: "c"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .counter: "Counter"
        case .highlighter: "Highlighter"
        case .pen: "Pen"
        case .redact: "Redact"
        case .spotlight: "Spotlight"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .counter: "1.circle"
        case .highlighter: "highlighter"
        case .pen: "scribble.variable"
        case .redact: "checkerboard.rectangle"
        case .spotlight: "camera.metering.spot"
        case .crop: "crop"
        }
    }

    /// The mark this tool draws, if it draws one.
    var markKind: Mark.Kind? {
        switch self {
        case .select, .crop: nil
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .counter: .counter
        case .highlighter: .highlighter
        case .pen: .pen
        case .redact: .redact
        case .spotlight: .spotlight
        }
    }

    /// The tool that draws `kind`.
    init?(kind: Mark.Kind) {
        guard let tool = Self.allCases.first(where: { $0.markKind == kind }) else { return nil }
        self = tool
    }
}

/// The sizes each kind of mark steps through. Values are in points.
enum SizeLadder {
    /// The four sizes in the options bar (S, M, L, XL), or none for kinds without a size.
    static func presets(for kind: Mark.Kind) -> [Double] {
        switch kind {
        case .arrow: [3.5, 5.5, 8, 11]
        case .rectangle, .ellipse, .pen: [2.5, 4, 6, 9]
        case .counter: [22, 28, 36, 46]
        case .text, .highlighter, .redact, .spotlight, .image: []
        }
    }

    /// What [ and ] step through: a little beyond the presets each way.
    static func steps(for kind: Mark.Kind) -> [Double] {
        switch kind {
        case .arrow: [2.5, 3.5, 5.5, 8, 11, 14, 18]
        case .rectangle, .ellipse, .pen: [1.5, 2.5, 4, 6, 9, 12, 16]
        case .counter: [18, 22, 28, 36, 46, 56]
        case .text: textSizes
        case .highlighter, .redact, .spotlight, .image: []
        }
    }

    static let textSizes: [Double] = [12, 14, 16, 20, 24, 32, 40, 48, 64, 96]
    static let presetNames = ["Small", "Medium", "Large", "Extra Large"]

    /// The next size up or down from `value`, or `value` at either end.
    static func step(_ value: Double, in steps: [Double], up: Bool) -> Double {
        if up {
            return steps.first { $0 > value + 0.01 } ?? value
        }
        return steps.last { $0 < value - 0.01 } ?? value
    }

    /// Large and extra large get a slightly wider halo.
    static func isLarge(_ weight: Double, kind: Mark.Kind) -> Bool {
        let presets = presets(for: kind)
        guard presets.count == 4 else { return false }
        return weight >= presets[2] - 0.01
    }

    /// The preset's index, if `value` is one of them.
    static func presetIndex(_ value: Double, kind: Mark.Kind) -> Int? {
        presets(for: kind).firstIndex { abs($0 - value) < 0.01 }
    }
}

/// What the editor remembers between marks and between captures: one shared pen colour for
/// arrows, shapes, text, counters and drawings (as CleanShot does); the highlighter's and the
/// redaction's own colours; each kind's size and style; and recent custom colours.
struct StyleBook: Codable, Equatable, Sendable {
    var penColour = MarkColour.red
    var highlighterColour = MarkColour.yellow
    var redactColour = MarkColour.ink
    /// You chose the redaction's colour; until then solid bars take theirs from the capture.
    var redactColourChosen = false
    /// Keyed by `Mark.Kind`'s raw value.
    var styles: [String: MarkStyle] = [:]
    /// Custom colours, newest first.
    var recents: [MarkColour] = []

    static let recentLimit = 8

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        penColour = try c.decodeIfPresent(MarkColour.self, forKey: .penColour) ?? .red
        highlighterColour = try c.decodeIfPresent(MarkColour.self, forKey: .highlighterColour) ?? .yellow
        redactColour = try c.decodeIfPresent(MarkColour.self, forKey: .redactColour) ?? .ink
        // From before this was kept: anything but ink was chosen.
        redactColourChosen = try c.decodeIfPresent(Bool.self, forKey: .redactColourChosen) ?? (redactColour != .ink)
        styles = try c.decodeIfPresent([String: MarkStyle].self, forKey: .styles) ?? [:]
        recents = try c.decodeIfPresent([MarkColour].self, forKey: .recents) ?? []
    }

    static func defaultStyle(for kind: Mark.Kind) -> MarkStyle {
        var style = MarkStyle()
        switch kind {
        case .arrow: style.weight = 5.5
        case .rectangle, .ellipse, .pen: style.weight = 4
        case .counter: style.weight = 28
        case .text: style.fontSize = 20
        case .highlighter, .redact, .spotlight, .image: break
        }
        return style
    }

    /// Whether `kind` shares the pen colour.
    static func usesPenColour(_ kind: Mark.Kind) -> Bool {
        switch kind {
        case .arrow, .rectangle, .ellipse, .text, .counter, .pen: true
        case .highlighter, .redact, .spotlight, .image: false
        }
    }

    func style(for kind: Mark.Kind) -> MarkStyle {
        styles[kind.rawValue] ?? Self.defaultStyle(for: kind)
    }

    func colour(for kind: Mark.Kind) -> MarkColour {
        switch kind {
        case .highlighter: highlighterColour
        case .redact: redactColour
        default: penColour
        }
    }

    mutating func remember(colour: MarkColour, for kind: Mark.Kind) {
        switch kind {
        case .highlighter: highlighterColour = colour
        case .redact:
            redactColour = colour
            redactColourChosen = true
        case .spotlight, .image: return
        default: penColour = colour
        }
        noteRecent(colour)
    }

    mutating func remember(style: MarkStyle, for kind: Mark.Kind) {
        styles[kind.rawValue] = style
    }

    /// Back to how it was out of the box, colour included.
    mutating func reset(_ kind: Mark.Kind) {
        styles[kind.rawValue] = nil
        switch kind {
        case .highlighter: highlighterColour = .yellow
        case .redact:
            redactColour = .ink
            redactColourChosen = false
        case .spotlight, .image: break
        default: penColour = .red
        }
    }

    /// Keeps a custom colour (not one of the swatches) at the front of the recents.
    mutating func noteRecent(_ colour: MarkColour) {
        guard !MarkColour.palette.contains(colour), !MarkColour.highlighterPalette.contains(colour) else { return }
        recents.removeAll { $0 == colour }
        recents.insert(colour, at: 0)
        if recents.count > Self.recentLimit { recents.removeLast(recents.count - Self.recentLimit) }
    }
}

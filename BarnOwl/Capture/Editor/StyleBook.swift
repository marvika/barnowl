import Foundation

/// A tool in the editor's toolbar, with the key that picks it.
enum EditorTool: String, CaseIterable, Codable, Sendable {
    case select, arrow, rectangle, ellipse, text, counter, highlighter, pen, redact, spotlight, magnifier, crop

    /// The tools in the toolbar's main group, in order.
    static let group: [EditorTool] = [.select, .arrow, .rectangle, .ellipse, .text, .counter, .highlighter, .pen,
                                      .redact, .spotlight, .magnifier]

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
        case .magnifier: "m"
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
        case .magnifier: "Magnify"
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
        case .magnifier: "plus.magnifyingglass"
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
        case .magnifier: .magnifier
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
        case .text, .highlighter, .redact, .spotlight, .image, .magnifier: []
        }
    }

    /// What [ and ] step through: a little beyond the presets each way.
    static func steps(for kind: Mark.Kind) -> [Double] {
        switch kind {
        case .arrow: [2.5, 3.5, 5.5, 8, 11, 14, 18]
        case .rectangle, .ellipse, .pen: [1.5, 2.5, 4, 6, 9, 12, 16]
        case .counter: [18, 22, 28, 36, 46, 56]
        case .text: textSizes
        case .highlighter, .redact, .spotlight, .image, .magnifier: []
        }
    }

    static let textSizes: [Double] = [12, 14, 16, 20, 24, 32, 40, 48, 64, 96]
    /// A magnifier's zooms, which [ and ] step through.
    static let zooms: [Double] = [1.5, 2, 3, 4]

    /// "1.5×", "2×".
    static func zoomTitle(_ zoom: Double) -> String {
        let whole = zoom.rounded()
        let number: String = abs(zoom - whole) < 0.01 ? String(Int(whole)) : String(format: "%.1f", zoom)
        return "\(number)×"
    }
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

/// A background you made, kept to use again.
struct SavedBackground: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var background: FrameBackground

    init(id: UUID = UUID(), background: FrameBackground) {
        self.id = id
        self.background = background
    }
}

/// The last frame you used, with lengths in points so it looks the same on any display.
struct FrameLook: Codable, Equatable, Sendable {
    var background: FrameBackground
    var padding: Double
    var cornerRadius: Double
    var shadowAmount: Double
    var ratio: AspectRatio
    var position: FramePosition
    var inset: Double

    init(_ frame: FrameSettings, scale: CGFloat) {
        let scale: Double = Double(max(scale, 0.5))
        background = frame.background
        padding = Double(frame.padding) / scale
        cornerRadius = Double(frame.cornerRadius) / scale
        shadowAmount = Double(frame.shadowAmount)
        ratio = frame.ratio
        position = frame.position
        inset = Double(frame.inset) / scale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode(FrameBackground.self, forKey: .background)
        padding = (try? c.decodeIfPresent(Double.self, forKey: .padding)) ?? 48
        cornerRadius = (try? c.decodeIfPresent(Double.self, forKey: .cornerRadius)) ?? 10
        shadowAmount = (try? c.decodeIfPresent(Double.self, forKey: .shadowAmount)) ?? 0.5
        ratio = (try? c.decodeIfPresent(AspectRatio.self, forKey: .ratio)) ?? .auto
        position = (try? c.decodeIfPresent(FramePosition.self, forKey: .position)) ?? .centre
        inset = (try? c.decodeIfPresent(Double.self, forKey: .inset)) ?? 0
    }

    /// The frame in pixels at `scale`.
    func settings(scale: CGFloat) -> FrameSettings {
        let scale: CGFloat = max(scale, 0.5)
        let padding: CGFloat = (CGFloat(self.padding) * scale).rounded()
        let corners: CGFloat = (CGFloat(cornerRadius) * scale).rounded()
        let inset: CGFloat = (CGFloat(self.inset) * scale).rounded()
        return FrameSettings(background: background, padding: padding, cornerRadius: corners,
                             shadowAmount: CGFloat(shadowAmount), ratio: ratio, position: position, inset: inset)
    }
}

/// What the editor remembers between marks and between captures: one shared pen colour for
/// arrows, shapes, text, counters and drawings (as CleanShot does); the highlighter's and the
/// redaction's own colours; each kind's size and style; recent custom colours; backgrounds you
/// made; and the last frame you used.
struct StyleBook: Codable, Equatable, Sendable {
    var penColour = MarkColour.red
    var highlighterColour = MarkColour.yellow
    var redactColour = MarkColour.ink
    /// You chose the redaction's colour; until then solid redactions take theirs from the capture.
    var redactColourChosen = false
    /// Keyed by `Mark.Kind`'s raw value.
    var styles: [String: MarkStyle] = [:]
    /// Custom colours, newest first.
    var recents: [MarkColour] = []
    /// Backgrounds you made, newest first.
    var saved: [SavedBackground] = []
    /// The last frame you used, for framing the next capture the same way.
    var frameLook: FrameLook?

    static let recentLimit = 8
    /// As many as fill the Yours rows beside the ＋.
    static let savedLimit = 9

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
        let saved: [Lossy<SavedBackground>] = (try? c.decodeIfPresent([Lossy<SavedBackground>].self, forKey: .saved)) ?? []
        self.saved = saved.compactMap(\.value)
        frameLook = try? c.decodeIfPresent(FrameLook.self, forKey: .frameLook)
    }

    static func defaultStyle(for kind: Mark.Kind) -> MarkStyle {
        var style = MarkStyle()
        switch kind {
        case .arrow: style.weight = 5.5
        case .rectangle, .ellipse, .pen: style.weight = 4
        case .counter: style.weight = 28
        case .text: style.fontSize = 20
        case .redact:
            style.redact = .pixelate
        case .magnifier:
            style.spotlight = .ellipse
            style.zoom = 2
        case .highlighter, .spotlight, .image: break
        }
        return style
    }

    /// Whether `kind` shares the pen colour.
    static func usesPenColour(_ kind: Mark.Kind) -> Bool {
        switch kind {
        case .arrow, .rectangle, .ellipse, .text, .counter, .pen: true
        case .highlighter, .redact, .spotlight, .image, .magnifier: false
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
        case .spotlight, .image, .magnifier: return
        default: penColour = colour
        }
        noteRecent(colour)
    }

    /// How Hide covers private info, as Settings › Capture says: a light blur out of the box,
    /// which looks like hidden text and keeps it unreadable. The Redact tool has its own style.
    static func hideStyle(_ redact: RedactStyle = Preferences.captureHideStyle) -> MarkStyle {
        var style = defaultStyle(for: .redact)
        style.redact = redact
        style.strength = redact == .blur ? .light : .medium
        return style
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
        case .spotlight, .image, .magnifier: break
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

    /// Keeps a background you made at the front of Yours, or puts it back in place of the one
    /// you edited. Returns its id.
    @discardableResult
    mutating func save(_ background: FrameBackground, replacing id: UUID? = nil) -> UUID {
        if let id, let index = saved.firstIndex(where: { $0.id == id }) {
            saved[index].background = background
            // The same background elsewhere in the list goes, so each shows once.
            saved.removeAll { $0.id != id && $0.background == background }
            return id
        }
        if let index = saved.firstIndex(where: { $0.background == background }) {
            let existing = saved.remove(at: index)
            saved.insert(existing, at: 0)
            return existing.id
        }
        let entry = SavedBackground(background: background)
        saved.insert(entry, at: 0)
        if saved.count > Self.savedLimit { saved.removeLast(saved.count - Self.savedLimit) }
        return entry.id
    }

    mutating func deleteSaved(_ id: UUID) {
        saved.removeAll { $0.id == id }
    }
}

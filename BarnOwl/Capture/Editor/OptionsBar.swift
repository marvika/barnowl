import AppKit
import SwiftUI

extension Color {
    init(_ colour: MarkColour) {
        self.init(.sRGB, red: colour.red, green: colour.green, blue: colour.blue)
    }
}

/// What the options bar asks the window to do.
@MainActor
struct OptionsBarActions {
    var pickColour: () -> Void = {}
    var moreColours: () -> Void = {}
    var showFonts: () -> Void = {}
    var cropAspect: (CropAspect) -> Void = { _ in }
    /// Back to the canvas, so the keys work again after typing in a field.
    var focusCanvas: () -> Void = {}
}

/// Where the options bar starts, so it lines up with the tools above it.
@MainActor
@Observable
final class OptionsBarLayout {
    var leading: CGFloat = 12
}

/// The second row under the toolbar: colour, size, style and extras for the tool or the
/// selection. What doesn't apply is left out, never dimmed.
struct OptionsBar: View {
    let model: EditorModel
    let actions: OptionsBarActions
    let layout: OptionsBarLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 38

    var body: some View {
        HStack(spacing: 0) {
            content
                .id(contentID)
                .transition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.leading, layout.leading)
        .padding(.trailing, 12)
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: contentID)
        .controlSize(.small)
    }

    /// Changes when the bar's sections change, for the crossfade.
    private var contentID: String {
        if model.tool == .crop { return "crop" }
        if model.review != nil { return "review" }
        if model.selection.isEmpty, model.tool == .select { return "select" }
        let kind = model.activeKind?.rawValue ?? "mixed"
        return model.selection.isEmpty ? "tool.\(kind)" : "selection.\(kind)"
    }

    @ViewBuilder private var content: some View {
        if model.tool == .crop {
            CropOptions(model: model, actions: actions)
        } else if let review = model.review {
            ReviewOptions(model: model, review: review)
        } else if model.selection.isEmpty, model.tool == .select {
            Text("Click a mark to change it · drag to select several")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            MarkOptions(model: model, actions: actions)
        }
    }
}

// MARK: Marks

private struct MarkOptions: View {
    let model: EditorModel
    let actions: OptionsBarActions

    var body: some View {
        let kind = model.activeKind
        HStack(spacing: 14) {
            Text(title(kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            if let kind {
                sections(for: kind)
            } else if usesColour {
                ColourSection(model: model, kind: nil, actions: actions)
            }
        }
    }

    private func title(_ kind: Mark.Kind?) -> String {
        let count = model.selection.count
        if count > 1 { return "\(count) Marks" }
        if let kind, count == 1 { return kind.title }
        return model.tool.title
    }

    private var usesColour: Bool {
        model.selectedMarks.allSatisfy { !$0.kind.isColourless }
    }

    @ViewBuilder private func sections(for kind: Mark.Kind) -> some View {
        let style = model.shownStyle
        switch kind {
        case .arrow:
            ColourSection(model: model, kind: kind, actions: actions)
            SizeSection(model: model, kind: kind)
            ArrowStyleSection(model: model)
            MoreButton(model: model, kind: kind)
        case .rectangle, .ellipse:
            ColourSection(model: model, kind: kind, actions: actions)
            if style.fill != .solid { SizeSection(model: model, kind: kind) }
            FillSection(model: model, kind: kind)
            MoreButton(model: model, kind: kind)
        case .text:
            ColourSection(model: model, kind: kind, actions: actions)
            TextStyleSection(model: model)
            FontSection(model: model, actions: actions)
            MoreButton(model: model, kind: kind)
        case .counter:
            ColourSection(model: model, kind: kind, actions: actions)
            SizeSection(model: model, kind: kind)
            MoreButton(model: model, kind: kind)
        case .pen:
            ColourSection(model: model, kind: kind, actions: actions)
            SizeSection(model: model, kind: kind)
            SmoothingSection(model: model)
            MoreButton(model: model, kind: kind)
        case .highlighter:
            ColourSection(model: model, kind: kind, actions: actions)
        case .redact:
            RedactSection(model: model, actions: actions)
        case .spotlight:
            SpotlightSection(model: model)
        case .magnifier:
            MagnifierSection(model: model)
        case .image:
            MoreButton(model: model, kind: kind)
        }
    }
}

// MARK: Colour

private struct ColourSection: View {
    let model: EditorModel
    let kind: Mark.Kind?
    let actions: OptionsBarActions
    @State private var showsWell = false

    var body: some View {
        let palette: [MarkColour] = kind == .highlighter ? MarkColour.highlighterPalette : MarkColour.palette
        let current = model.shownColour
        HStack(spacing: 0) {
            ForEach(Array(palette.enumerated()), id: \.offset) { index, colour in
                let key: String = kind == .highlighter ? "" : " (\(index + 1))"
                SwatchButton(colour: colour, selected: current == colour, help: colour.name + key) {
                    model.setColour(colour)
                }
            }
            if kind != .highlighter {
                ForEach(Array(model.styleBook.recents.prefix(3).enumerated()), id: \.offset) { _, colour in
                    SwatchButton(colour: colour, selected: current == colour, help: colour.hex) {
                        model.setColour(colour)
                    }
                }
                Button {
                    showsWell.toggle()
                } label: {
                    ColourWellLabel(colour: current, custom: !palette.contains(current))
                }
                .buttonStyle(.plain)
                .help("More colours")
                .accessibilityLabel("More Colours")
                .popover(isPresented: $showsWell, arrowEdge: .bottom) {
                    ColourPopover(model: model, actions: actions) { showsWell = false }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour")
    }
}

struct SwatchButton: View {
    let colour: MarkColour
    let selected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // The ring keeps white on a light bar, and ink on a dark one, from vanishing.
                Circle()
                    .fill(Color(colour))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
                    .frame(width: 18, height: 18)
                if selected {
                    Circle()
                        .strokeBorder(Color(nsColor: .labelColor), lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 26, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(colour.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ColourWellLabel: View {
    let colour: MarkColour
    let custom: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 18, height: 18)
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 10, height: 10)
            Circle()
                .fill(Color(colour))
                .frame(width: 7, height: 7)
            if custom {
                Circle()
                    .strokeBorder(Color(nsColor: .labelColor), lineWidth: 2)
                    .frame(width: 26, height: 26)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
}

/// The colour well's popover: the palette, recent colours, the eyedropper and the system panel.
struct ColourPopover: View {
    let model: EditorModel
    let actions: OptionsBarActions
    let dismiss: () -> Void

    var body: some View {
        let current = model.shownColour
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(MarkColour.palette.enumerated()), id: \.offset) { index, colour in
                    SwatchButton(colour: colour, selected: current == colour, help: "\(colour.name) (\(index + 1))") {
                        model.setColour(colour)
                    }
                }
            }
            if !model.styleBook.recents.isEmpty {
                Text("Recent").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(Array(model.styleBook.recents.enumerated()), id: \.offset) { _, colour in
                        SwatchButton(colour: colour, selected: current == colour, help: colour.hex) {
                            model.setColour(colour)
                        }
                    }
                }
            }
            Divider()
            Button {
                dismiss()
                actions.pickColour()
            } label: {
                HStack {
                    Label("Pick from Capture", systemImage: "eyedropper")
                    Spacer()
                    ShortcutKey(key: "I")
                }
            }
            .buttonStyle(.plain)
            Button {
                dismiss()
                actions.moreColours()
            } label: {
                Label("More Colours…", systemImage: "paintpalette")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .padding(14)
        .frame(width: 244)
    }
}

/// A key, drawn as a small key cap so a lone letter doesn't read as a text cursor.
private struct ShortcutKey: View {
    let key: String

    var body: some View {
        Text(verbatim: key)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 2)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
            .accessibilityLabel("Key \(key)")
    }
}

// MARK: Size

private struct SizeSection: View {
    let model: EditorModel
    let kind: Mark.Kind

    var body: some View {
        let presets = SizeLadder.presets(for: kind)
        let current = SizeLadder.presetIndex(model.shownStyle.weight, kind: kind)
        Picker("Size", selection: Binding<Int?>(get: { current }, set: { index in
            guard let index, presets.indices.contains(index) else { return }
            let weight = presets[index]
            model.updateStyle("Change Size") { $0.weight = weight }
        })) {
            ForEach(presets.indices, id: \.self) { index in
                Image(nsImage: SizeSamples.image(kind: kind, index: index))
                    .accessibilityLabel(SizeLadder.presetNames[index])
                    .help("\(SizeLadder.presetNames[index]) ([ ] or − + step the size)")
                    .tag(Optional(index))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Size ([ ] or − +)")
    }
}

/// Line and dot samples for the size control, drawn as templates so they follow the appearance.
@MainActor
enum SizeSamples {
    private static var cache: [String: NSImage] = [:]

    static func image(kind: Mark.Kind, index: Int) -> NSImage {
        let dots = kind == .counter
        let key = "\(dots)-\(index)"
        if let cached = cache[key] { return cached }
        let widths: [CGFloat] = [1.5, 2.5, 3.5, 5]
        let diameters: [CGFloat] = [6, 8, 10.5, 13]
        let width: CGFloat = widths[min(index, 3)]
        let diameter: CGFloat = diameters[min(index, 3)]
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { rect in
            NSColor.black.set()
            if dots {
                let dot = NSRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
                NSBezierPath(ovalIn: dot).fill()
            } else {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 4, y: rect.midY))
                path.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY))
                path.lineWidth = width
                path.lineCapStyle = .round
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }
}

// MARK: Styles

/// A segmented choice whose segments are pictures of the real result.
private struct SampleChoice<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let selection: Option?
    let label: (Option) -> String
    let picture: (Option) -> NSImage?
    let choose: (Option) -> Void

    var body: some View {
        Picker(title, selection: Binding<Option?>(get: { selection }, set: { value in
            if let value { choose(value) }
        })) {
            ForEach(options, id: \.self) { option in
                Group {
                    if let image = picture(option) {
                        Image(nsImage: image).renderingMode(.original)
                    } else {
                        Text(label(option))
                    }
                }
                .accessibilityLabel(label(option))
                .help(label(option))
                .tag(Optional(option))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Small pictures of marks, drawn by the real renderer in the current colour.
@MainActor
enum StyleSamples {
    static let size = CGSize(width: 30, height: 20)

    static func image(_ mark: Mark, renderer: AnnotationRenderer) -> NSImage? {
        guard let cgImage = renderer.sample(mark, size: size, pixelsPerPoint: 2) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size.width, height: size.height))
    }

    /// A mark in sample space: points times the capture's scale.
    static func mark(_ kind: Mark.Kind, colour: MarkColour, scale: CGFloat, from: CGPoint, to: CGPoint,
                     style: (inout MarkStyle) -> Void) -> Mark {
        var markStyle = StyleBook.defaultStyle(for: kind)
        style(&markStyle)
        let start = CGPoint(x: from.x * scale, y: from.y * scale)
        let end = CGPoint(x: to.x * scale, y: to.y * scale)
        return Mark(kind: kind, colour: colour, style: markStyle, start: start, end: end)
    }
}

private struct ArrowStyleSection: View {
    let model: EditorModel

    var body: some View {
        let style = model.shownStyle
        let colour = model.shownColour
        let scale = model.scale
        SampleChoice(title: "Style", options: ArrowChoice.allCases, selection: ArrowChoice.allCases.first { $0.matches(style) },
                     label: \.title, picture: { choice in
                         var mark = StyleSamples.mark(.arrow, colour: colour, scale: scale, from: CGPoint(x: 6, y: 15),
                                                      to: CGPoint(x: 24, y: 5)) { s in
                             s.weight = 2.6
                             choice.apply(&s)
                         }
                         if choice == .curved {
                             mark.control = MarkGeometry.defaultBend(start: mark.start, end: mark.end)
                         }
                         return StyleSamples.image(mark, renderer: model.renderer)
                     }, choose: { choice in
                         model.updateStyle { choice.apply(&$0) }
                     })
    }
}

private struct FillSection: View {
    let model: EditorModel
    let kind: Mark.Kind

    var body: some View {
        let colour = model.shownColour
        let scale = model.scale
        SampleChoice(title: "Fill", options: ShapeFill.allCases, selection: model.shownStyle.fill, label: \.title,
                     picture: { fill in
                         let mark = StyleSamples.mark(kind, colour: colour, scale: scale, from: CGPoint(x: 7, y: 4),
                                                      to: CGPoint(x: 23, y: 16)) { s in
                             s.weight = 1.6
                             s.fill = fill
                         }
                         return StyleSamples.image(mark, renderer: model.renderer)
                     }, choose: { fill in
                         model.updateStyle { $0.fill = fill }
                     })
    }
}

private struct TextStyleSection: View {
    let model: EditorModel

    var body: some View {
        let colour = model.shownColour
        let shown = model.shownStyle
        let scale = model.scale
        SampleChoice(title: "Style", options: TextStyle.allCases, selection: shown.textStyle, label: \.title,
                     picture: { option in
                         let callout = option == .callout
                         var mark = StyleSamples.mark(.text, colour: colour, scale: scale, from: .zero, to: .zero) { s in
                             s.textStyle = option
                             s.fontSize = callout ? 9 : 11
                             s.font = shown.font
                             s.fontWeight = .bold
                         }
                         mark.text = "Aa"
                         let layout = MarkGeometry.textLayout(mark, scale: scale)
                         let width: CGFloat = StyleSamples.size.width * scale
                         let height: CGFloat = StyleSamples.size.height * scale
                         let x: CGFloat = (width - layout.boxRect.width) / 2
                         // A callout sits high, its pointer reaching to the bottom left.
                         let y: CGFloat = callout ? 0 : (height - layout.boxRect.height) / 2
                         mark.start = CGPoint(x: x.rounded(), y: y.rounded())
                         mark.end = callout ? CGPoint(x: x + 2 * scale, y: height - scale) : mark.start
                         return StyleSamples.image(mark, renderer: model.renderer)
                     }, choose: { option in
                         model.updateStyle { $0.textStyle = option }
                     })
    }
}

private struct FontSection: View {
    let model: EditorModel
    let actions: OptionsBarActions

    var body: some View {
        let style = model.shownStyle
        HStack(spacing: 6) {
            Toggle(isOn: Binding(get: { style.fontWeight == .bold }, set: { _ in model.toggleBold() })) {
                Image(systemName: "bold")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
            }
            .toggleStyle(.button)
            .help("Bold (⌘B)")
            .accessibilityLabel("Bold")
            Menu {
                Picker("Font", selection: Binding(get: { style.font }, set: { font in
                    model.updateStyle("Change Font") { $0.font = font }
                })) {
                    ForEach(fonts(current: style.font), id: \.self) { font in
                        Text(font.title).tag(font)
                    }
                }
                .pickerStyle(.inline)
                Picker("Weight", selection: Binding(get: { style.fontWeight }, set: { weight in
                    model.updateStyle("Change Weight") { $0.fontWeight = weight }
                })) {
                    ForEach(FontWeight.allCases, id: \.self) { weight in
                        Text(weight.title).tag(weight)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Other Fonts…") { actions.showFonts() }
            } label: {
                Text("\(style.font.title) \(style.fontWeight.title)")
                    .font(.system(size: 12))
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Font")
            TextSizeField(model: model, size: style.fontSize, done: actions.focusCanvas)
        }
    }

    private func fonts(current: TextFont) -> [TextFont] {
        var fonts = TextFont.builtIn
        if case .named = current { fonts.append(current) }
        return fonts
    }
}

private struct TextSizeField: View {
    let model: EditorModel
    let size: Double
    /// Return in the field hands the keys back to the canvas.
    let done: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            TextField("Size", value: Binding(get: { size }, set: { value in
                let clamped = min(max(value, 6), 400)
                model.updateStyle("Change Size") { $0.fontSize = clamped }
            }), format: .number.precision(.fractionLength(0...1)))
            .frame(width: 34)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .onSubmit(done)
            .accessibilityLabel("Text size")
            Stepper("Text size", onIncrement: { model.stepSize(up: true) }, onDecrement: { model.stepSize(up: false) })
                .labelsHidden()
            Text("pt").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .help("Text size ([ ] or − +)")
    }
}

private struct RedactSection: View {
    let model: EditorModel
    let actions: OptionsBarActions

    var body: some View {
        let style = model.shownStyle
        HStack(spacing: 14) {
            Picker("Redaction", selection: Binding(get: { style.redact }, set: { option in
                model.updateStyle { $0.redact = option }
            })) {
                ForEach(RedactStyle.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if style.redact == .solid {
                ColourSection(model: model, kind: .redact, actions: actions)
            } else {
                Picker("Strength", selection: Binding(get: { style.strength }, set: { strength in
                    model.updateStyle { $0.strength = strength }
                })) {
                    ForEach(RedactStrength.allCases, id: \.self) { strength in
                        Text(strength.title).tag(strength)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if style.redact != .solid {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help("Blur and pixelate can sometimes be reversed. Use Solid for keys and passwords.")
                        .accessibilityLabel("Blur and pixelate can sometimes be reversed. Use Solid for keys and passwords.")
                }
            }
            PrivateInfoButton(model: model)
        }
    }
}

/// Finds what looks private, when the capture's text has been read.
private struct PrivateInfoButton: View {
    let model: EditorModel

    var body: some View {
        if let insight = model.insight, insight.textWasRead, !insight.text.findings.isEmpty {
            let count = model.privateCount
            Button {
                model.beginReview()
            } label: {
                Label(count > 0 ? "Hide Private Info (\(count))" : "Hide Private Info…", systemImage: "eye.slash")
            }
            .help("Find emails, keys and other private things to hide (⇧B)")
        }
    }
}

/// The pen's steadying: how far the line trails the pointer.
private struct SmoothingSection: View {
    let model: EditorModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Smoothing").font(.system(size: 12)).foregroundStyle(.secondary)
            // How new strokes are drawn: drawings already made keep their shape.
            Picker("Smoothing", selection: Binding(get: { model.styleBook.style(for: .pen).smoothing }, set: { level in
                model.updatePenSmoothing(level)
            })) {
                ForEach(PenSmoothing.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .help("Steadies your hand: the line trails the pointer and smooths out wobbles")
    }
}

private struct SpotlightSection: View {
    let model: EditorModel

    var body: some View {
        let style = model.shownStyle
        HStack(spacing: 14) {
            Picker("Shape", selection: Binding(get: { style.spotlight }, set: { shape in
                model.updateStyle { $0.spotlight = shape }
            })) {
                Image(systemName: "rectangle").accessibilityLabel("Rectangle").tag(SpotlightShape.rectangle)
                Image(systemName: "circle").accessibilityLabel("Ellipse").tag(SpotlightShape.ellipse)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Picker("Around it", selection: Binding(get: { style.spotlightEffect }, set: { effect in
                model.updateStyle { $0.spotlightEffect = effect }
            })) {
                ForEach(SpotlightEffect.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Dim or blur everything around the spotlight")
            HStack(spacing: 6) {
                Text("Dim").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { style.dim }, set: { value in
                    model.updateStyle("Change Dimming") { $0.dim = value }
                }), in: 0.3...0.8) { editing in
                    if editing { model.beginLiveChange() } else { model.endLiveChange("Change Dimming") }
                }
                .frame(width: 110)
                Text("\(Int((style.dim * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }
}

/// A magnifier's shape and how far it zooms. Its ring is always white, so there's no colour.
private struct MagnifierSection: View {
    let model: EditorModel

    var body: some View {
        let style = model.shownStyle
        HStack(spacing: 14) {
            Picker("Shape", selection: Binding(get: { style.spotlight }, set: { shape in
                model.updateStyle { $0.spotlight = shape }
            })) {
                Image(systemName: "circle").accessibilityLabel("Circle").tag(SpotlightShape.ellipse)
                Image(systemName: "rectangle").accessibilityLabel("Rectangle").tag(SpotlightShape.rectangle)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            HStack(spacing: 6) {
                Text("Zoom").font(.system(size: 12)).foregroundStyle(.secondary)
                Picker("Zoom", selection: Binding<Double?>(get: { SizeLadder.zooms.first { abs($0 - style.zoom) < 0.01 } },
                                                           set: { zoom in
                    guard let zoom else { return }
                    model.updateStyle("Change Zoom") { $0.zoom = zoom }
                })) {
                    ForEach(SizeLadder.zooms, id: \.self) { zoom in
                        Text(SizeLadder.zoomTitle(zoom)).tag(Optional(zoom))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .help("Zoom ([ ] or − + step it)")
        }
    }
}

// MARK: More

private struct MoreButton: View {
    let model: EditorModel
    let kind: Mark.Kind
    @State private var shows = false

    var body: some View {
        Button {
            shows.toggle()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("More options")
        .accessibilityLabel("More Options")
        .popover(isPresented: $shows, arrowEdge: .bottom) {
            MoreOptions(model: model, kind: kind)
        }
    }
}

/// Rarer choices: exact size, opacity, dashes, alignment, numbering, and reset.
struct MoreOptions: View {
    let model: EditorModel
    let kind: Mark.Kind

    var body: some View {
        let style = model.shownStyle
        VStack(alignment: .leading, spacing: 12) {
            if let range = weightRange {
                row("Size") {
                    Slider(value: Binding(get: { style.weight }, set: { value in
                        let rounded = (value * 2).rounded() / 2
                        model.updateStyle("Change Size") { $0.weight = rounded }
                    }), in: range) { editing in
                        if editing { model.beginLiveChange() } else { model.endLiveChange("Change Size") }
                    }
                    Text(String(format: "%.1f pt", style.weight))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            row("Opacity") {
                Slider(value: Binding(get: { style.opacity }, set: { value in
                    model.updateStyle("Change Opacity") { $0.opacity = value }
                }), in: 0.1...1) { editing in
                    if editing { model.beginLiveChange() } else { model.endLiveChange("Change Opacity") }
                }
                Text("\(Int((style.opacity * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            if dashes {
                row("Line") {
                    Picker("Line", selection: Binding(get: { style.dash }, set: { dash in
                        model.updateStyle { $0.dash = dash }
                    })) {
                        ForEach(LineDash.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
            if kind == .text {
                row("Align") {
                    Picker("Align", selection: Binding(get: { style.align }, set: { align in
                        model.updateStyle { $0.align = align }
                    })) {
                        Image(systemName: "text.alignleft").accessibilityLabel("Left").tag(TextAlign.left)
                        Image(systemName: "text.aligncenter").accessibilityLabel("Centre").tag(TextAlign.centre)
                        Image(systemName: "text.alignright").accessibilityLabel("Right").tag(TextAlign.right)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
            if kind == .counter {
                row("Style") {
                    Picker("Numbering", selection: Binding(get: { style.counterFormat }, set: { format in
                        model.updateStyle { $0.counterFormat = format }
                    })) {
                        ForEach(CounterFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                row("Start at") {
                    let start = model.document.counterStart
                    Text("\(style.counterFormat.label(start))").monospacedDigit().frame(minWidth: 24)
                    Stepper("Start at", onIncrement: { model.setCounterStart(start + 1) },
                            onDecrement: { model.setCounterStart(start - 1) })
                        .labelsHidden()
                    Spacer()
                }
            }
            Divider()
            Button("Reset \(kind.title) to Default") { model.resetStyle() }
                .buttonStyle(.link)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(14)
        .frame(width: 280)
    }

    private var weightRange: ClosedRange<Double>? {
        switch kind {
        case .arrow: 1.5...24
        case .rectangle, .ellipse, .pen: 1...24
        case .counter: 14...72
        default: nil
        }
    }

    private var dashes: Bool {
        switch kind {
        case .rectangle, .ellipse, .pen: true
        case .arrow: model.shownStyle.heads == .none
        default: false
        }
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            content()
        }
    }
}

// MARK: Crop and review

private struct CropOptions: View {
    let model: EditorModel
    let actions: OptionsBarActions

    var body: some View {
        HStack(spacing: 12) {
            Text("Crop").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Picker("Aspect", selection: Binding(get: { model.cropAspect }, set: { actions.cropAspect($0) })) {
                ForEach(CropAspect.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            if let draft = model.cropDraft {
                Text(verbatim: "\(Int(draft.width)) × \(Int(draft.height)) px")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Reset") { model.resetCropDraft() }
            Divider().frame(height: 16)
            Button("Cancel") { model.cancelCrop() }
                .help("Keep the image as it was (Esc)")
            Button("Crop") { model.applyCrop() }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: EditorCanvas.accentFill))
                .help("Crop to the rectangle (Return)")
        }
    }
}

/// One kind of private thing in the review: on hides them all, off leaves them visible.
private struct ReviewChip: View {
    let model: EditorModel
    let kind: SensitiveTextFinder.Kind
    let count: Int
    let on: Bool

    var body: some View {
        Button {
            model.review?.toggle(kind: kind)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color(nsColor: EditorCanvas.accentFill) : Color.secondary)
                Text(verbatim: "\(kind.title) · \(count)")
            }
        }
        .help(on ? "Leave every \(kind.title.lowercased()) visible" : "Hide every \(kind.title.lowercased()) too")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct ReviewOptions: View {
    let model: EditorModel
    let review: PrivateInfoReview

    var body: some View {
        HStack(spacing: 10) {
            Text("Hide Private Info").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            if review.items.isEmpty {
                let insight = model.insight
                let read = insight?.textWasRead == true
                let looked = insight?.lookedForPrivateInfo != false
                Text(!looked ? "Looking for private info is off in Settings › Capture, so check it yourself."
                     : read ? "Nothing else here looks private." : "The text couldn't be read, so check it yourself.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(review.categories, id: \.kind) { category in
                ReviewChip(model: model, kind: category.kind, count: category.count,
                           on: category.included == category.count)
            }
            Divider().frame(height: 16)
            Button("Cancel") { model.review = nil }
                .help("Hide nothing (Esc)")
            if review.includedCount > 0 {
                Button("Hide \(review.includedCount)") { model.applyReview() }
                    .buttonStyle(AmberButtonStyle())
                    .help("Cover what's striped with solid bars (Return)")
            }
        }
    }
}

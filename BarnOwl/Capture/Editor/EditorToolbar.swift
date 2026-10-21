import SwiftUI

extension Color {
    init(_ colour: MarkColour) {
        self.init(.sRGB, red: colour.red, green: colour.green, blue: colour.blue)
    }
}

/// The editor's toolbar, beside the window buttons: the tools; the colour, size and style for the
/// tool or selection; and on the right, Frame, Copy, Pin and Done.
struct EditorToolbar: View {
    let model: EditorModel

    /// The window buttons' room on the left.
    static let leading: CGFloat = 84
    static let height: CGFloat = 52

    var body: some View {
        HStack(spacing: 10) {
            tools
            if model.tool == .crop {
                cropControls
            } else {
                styleBar
            }
            Spacer(minLength: 8)
            actions
            Button {
                model.perform(.done)
            } label: {
                Text("Done").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.amber)
            .foregroundStyle(Color(hex: 0x2A1604))
            .controlSize(.large)
            .help("Copy, save and close (Return)")
        }
        .padding(.leading, Self.leading)
        .padding(.trailing, 12)
        .frame(height: Self.height)
        .environment(\.colorScheme, .dark)
    }

    private var tools: some View {
        HStack(spacing: 1) {
            ForEach(EditorTool.allCases, id: \.self) { tool in
                Button {
                    model.choose(tool)
                } label: {
                    Image(systemName: tool.symbol).font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(ChipStyle(selected: model.tool == tool))
                .help("\(tool.title) (\(tool.key.uppercased()))")
                .accessibilityLabel(tool.title)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    private var styleBar: some View {
        let kind = model.styleKind
        return HStack(spacing: 2) {
            ForEach(Array(MarkColour.palette.enumerated()), id: \.offset) { index, colour in
                Button {
                    model.setColour(colour)
                } label: {
                    Swatch(colour: colour, selected: model.shownColour == colour && Self.usesColour(kind, model.shownStyle))
                }
                .buttonStyle(.plain)
                .help("\(colour.name) (\(index + 1))")
                .accessibilityLabel(colour.name)
            }
            .disabled(!Self.usesColour(kind, model.shownStyle))
            .opacity(Self.usesColour(kind, model.shownStyle) ? 1 : 0.35)
            Divider().frame(height: 16).padding(.horizontal, 4)
            ForEach(StrokeSize.allCases, id: \.self) { size in
                Button {
                    model.setSize(size)
                } label: {
                    Circle().frame(width: Self.dot(size), height: Self.dot(size))
                }
                .buttonStyle(ChipStyle(selected: model.shownSize == size && Self.usesSize(kind)))
                .help("\(size.title) ([ and ] step the size)")
                .accessibilityLabel(size.title)
            }
            .disabled(!Self.usesSize(kind))
            .opacity(Self.usesSize(kind) ? 1 : 0.35)
            if let kind, StyleChoices.has(kind) {
                Divider().frame(height: 16).padding(.horizontal, 4)
                StyleChoices(kind: kind, style: model.shownStyle) { change in model.setStyle(change) }
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    private var cropControls: some View {
        HStack(spacing: 6) {
            Button("Cancel") { model.cancelCrop() }
                .help("Keep the image as it was (Esc)")
            Button("Crop") { model.applyCrop() }
                .tint(Brand.lavender)
                .help("Crop to the rectangle (Return)")
        }
        .buttonStyle(.glass)
    }

    private var actions: some View {
        HStack(spacing: 1) {
            Button {
                model.showsInspector.toggle()
            } label: {
                Image(systemName: "photo.artframe").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(ChipStyle(selected: model.showsInspector))
            .help("Frame: background, padding and corners")
            .accessibilityLabel("Frame")
            Button {
                model.perform(.copy)
            } label: {
                Image(systemName: model.confirmed == .copy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ChipStyle())
            .help("Copy (⌘C)")
            .accessibilityLabel("Copy")
            Button {
                model.perform(.pin)
            } label: {
                Image(systemName: "pin").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(ChipStyle())
            .help("Pin to the screen")
            .accessibilityLabel("Pin")
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    static func dot(_ size: StrokeSize) -> CGFloat {
        switch size {
        case .small: 4
        case .medium: 6.5
        case .large: 9.5
        }
    }

    /// Spotlights and blurred or pixelated redactions take no colour.
    static func usesColour(_ kind: Mark.Kind?, _ style: MarkStyle) -> Bool {
        switch kind {
        case nil, .spotlight, .image: false
        case .redact: style.redact == .solid
        default: true
        }
    }

    static func usesSize(_ kind: Mark.Kind?) -> Bool {
        switch kind {
        case .arrow, .line, .rectangle, .ellipse, .pen, .text, .counter: true
        default: false
        }
    }
}

/// A toolbar button: a capsule of lavender when it's the one in use.
private struct ChipStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.85))
            .background {
                if selected {
                    Capsule().fill(Brand.lavender)
                } else if configuration.isPressed {
                    Capsule().fill(Color.white.opacity(0.14))
                }
            }
            .contentShape(Capsule())
    }
}

private struct Swatch: View {
    let colour: MarkColour
    let selected: Bool

    var body: some View {
        Circle()
            .fill(Color(colour))
            .overlay(Circle().strokeBorder(Color.white.opacity(colour == .ink ? 0.4 : 0.16), lineWidth: 1))
            .frame(width: 16, height: 16)
            .padding(3)
            .overlay {
                if selected { Circle().strokeBorder(Color.white, lineWidth: 1.75) }
            }
            .frame(width: 24, height: 28)
            .contentShape(Rectangle())
    }
}

/// The style choices for one kind of mark, as small pictures of the result.
private struct StyleChoices: View {
    let kind: Mark.Kind
    let style: MarkStyle
    let change: (@escaping (inout MarkStyle) -> Void) -> Void

    static func has(_ kind: Mark.Kind) -> Bool {
        [.arrow, .text, .redact, .spotlight].contains(kind)
    }

    var body: some View {
        HStack(spacing: 1) {
            switch kind {
            case .arrow:
                ForEach(ArrowStyle.allCases, id: \.self) { option in
                    choice(option.title, selected: style.arrow == option, set: { $0.arrow = option }) {
                        ArrowGlyph(style: option)
                    }
                }
            case .text:
                ForEach(TextStyle.allCases, id: \.self) { option in
                    choice(option.title, selected: style.text == option, set: { $0.text = option }) {
                        TextGlyph(style: option)
                    }
                }
            case .redact:
                ForEach(RedactStyle.allCases, id: \.self) { option in
                    choice(option.title, selected: style.redact == option, set: { $0.redact = option }) {
                        Image(systemName: Self.symbol(option)).font(.system(size: 13, weight: .medium))
                    }
                }
            case .spotlight:
                ForEach(SpotlightShape.allCases, id: \.self) { option in
                    choice(option.title, selected: style.spotlight == option, set: { $0.spotlight = option }) {
                        Image(systemName: option == .rectangle ? "rectangle.dashed" : "circle.dashed")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func choice(_ title: String, selected: Bool, set: @escaping (inout MarkStyle) -> Void,
                        @ViewBuilder label: () -> some View) -> some View {
        Button {
            change(set)
        } label: {
            label()
        }
        .buttonStyle(ChipStyle(selected: selected))
        .help(title)
        .accessibilityLabel(title)
    }

    static func symbol(_ style: RedactStyle) -> String {
        switch style {
        case .pixelate: "squareshape.split.3x3"
        case .blur: "drop.halffull"
        case .solid: "rectangle.fill"
        }
    }
}

/// A little arrow in each style.
private struct ArrowGlyph: View {
    let style: ArrowStyle

    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: 2.5, y: size.height - 2.5)
            let end = CGPoint(x: size.width - 2.5, y: 2.5)
            var line = Path()
            line.move(to: start)
            var endDirection = CGPoint(x: end.x - start.x, y: end.y - start.y)
            if style == .curved {
                let control = CGPoint(x: start.x + 1, y: end.y + 1)
                line.addQuadCurve(to: end, control: control)
                endDirection = CGPoint(x: end.x - control.x, y: end.y - control.y)
            } else {
                line.addLine(to: end)
            }
            context.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            context.fill(Self.head(at: end, direction: endDirection), with: .foreground)
            if style == .double {
                context.fill(Self.head(at: start, direction: CGPoint(x: start.x - end.x, y: start.y - end.y)), with: .foreground)
            }
        }
        .frame(width: 15, height: 15)
    }

    static func head(at tip: CGPoint, direction: CGPoint) -> Path {
        let length: CGFloat = max(hypot(direction.x, direction.y), 0.001)
        let d = CGPoint(x: direction.x / length, y: direction.y / length)
        let n = CGPoint(x: -d.y, y: d.x)
        let size: CGFloat = 5.5
        let base = CGPoint(x: tip.x - d.x * size, y: tip.y - d.y * size)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + n.x * size * 0.6, y: base.y + n.y * size * 0.6))
        path.addLine(to: CGPoint(x: base.x - n.x * size * 0.6, y: base.y - n.y * size * 0.6))
        path.closeSubpath()
        return path
    }
}

/// An "A" in each text style.
private struct TextGlyph: View {
    let style: TextStyle

    var body: some View {
        let letter = Text("A").font(.system(size: 12, weight: .bold, design: .rounded))
        switch style {
        case .halo:
            letter.shadow(color: .white.opacity(0.5), radius: 2)
        case .box:
            letter.foregroundStyle(Color(hex: 0x16151F))
                .frame(width: 16, height: 15)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white))
        case .outline:
            letter.foregroundStyle(Color(hex: 0x16151F))
                .shadow(color: .white, radius: 0, x: 0.8, y: 0)
                .shadow(color: .white, radius: 0, x: -0.8, y: 0)
                .shadow(color: .white, radius: 0, x: 0, y: 0.8)
                .shadow(color: .white, radius: 0, x: 0, y: -0.8)
        }
    }
}

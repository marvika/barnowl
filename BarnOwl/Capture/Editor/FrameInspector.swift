import SwiftUI

/// The Frame panel: a background behind the capture, room around it, rounded corners, a shadow,
/// and an aspect ratio. Everything here is part of what's copied and saved.
struct FrameInspector: View {
    let model: EditorModel
    /// The document before a slider started moving, so the whole slide is one undo step.
    @State private var before: EditorDocument?

    static let width: CGFloat = 256
    /// The window is always dark, so text keeps its night colours whatever the glass shows.
    static let primary = Color(hex: 0xF6F4FF)
    static let secondary = Color(hex: 0xA9A6C6)

    private var frame: FrameSettings { model.document.frame }

    private static let backgrounds: [FrameBackground] = [
        .none, .gradient(.dawn), .gradient(.dusk), .gradient(.meadow), .gradient(.mist),
        .solid(.white), .solid(MarkColour(hex: 0xF7EBD4)), .solid(MarkColour(hex: 0x3D3A8F)), .solid(.ink), .transparent,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Frame").font(.system(size: 15, weight: .semibold))
                Text(frame.isOn ? "Part of what you copy and save." : "Set the capture on a background.")
                    .font(.system(size: 11.5)).foregroundStyle(Self.secondary)
            }
            section("Background") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                    ForEach(Array(Self.backgrounds.enumerated()), id: \.offset) { _, background in
                        Button {
                            model.setFrame("Change Background") { $0.background = background }
                        } label: {
                            BackgroundSwatch(background: background, selected: frame.background == background)
                        }
                        .buttonStyle(.plain)
                        .help(Self.title(background))
                        .accessibilityLabel(Self.title(background))
                    }
                }
            }
            Group {
                slider("Padding", value: \.padding, range: 0...160, undoName: "Change Padding")
                slider("Corners", value: \.cornerRadius, range: 0...40, undoName: "Change Corners")
                Toggle("Shadow", isOn: Binding(get: { frame.shadow }, set: { on in
                    model.setFrame("Change Shadow") { $0.shadow = on }
                }))
                .toggleStyle(.switch).controlSize(.small)
                section("Aspect ratio") {
                    Picker("Aspect ratio", selection: Binding(get: { frame.ratio }, set: { ratio in
                        model.setFrame("Change Aspect Ratio") { $0.ratio = ratio }
                    })) {
                        ForEach(AspectRatio.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
            .disabled(!frame.isOn)
            .opacity(frame.isOn ? 1 : 0.45)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Self.primary)
        .padding(16)
        .frame(width: Self.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .tint(Brand.accent)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.panelRadius))
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .environment(\.colorScheme, .dark)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Self.secondary)
            content()
        }
    }

    /// A slider in points over a length kept in pixels.
    private func slider(_ title: String, value: WritableKeyPath<FrameSettings, CGFloat>, range: ClosedRange<CGFloat>,
                        undoName: String) -> some View {
        let scale = model.scale
        let points = Binding<CGFloat>(get: { frame[keyPath: value] / scale }, set: { newValue in
            model.setFrameLive { $0[keyPath: value] = (newValue * scale).rounded() }
        })
        return section(title) {
            HStack(spacing: 10) {
                Slider(value: points, in: range) { editing in
                    if editing {
                        before = model.document
                    } else if let before {
                        model.commit(from: before, undoName)
                        self.before = nil
                    }
                }
                .controlSize(.small)
                Text("\(Int(points.wrappedValue.rounded()))")
                    .monospacedDigit().foregroundStyle(Self.secondary).frame(width: 28, alignment: .trailing)
            }
        }
    }

    static func title(_ background: FrameBackground) -> String {
        switch background {
        case .none: "No frame"
        case .gradient(let gradient): gradient.title
        case .solid(let colour):
            switch colour {
            case .white: "White"
            case .ink: "Ink"
            case MarkColour(hex: 0xF7EBD4): "Cream"
            default: "Indigo"
            }
        case .transparent: "Transparent"
        }
    }
}

private struct BackgroundSwatch: View {
    let background: FrameBackground
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        fill
            .frame(width: 36, height: 28)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .padding(-3)
                }
            }
            .contentShape(shape)
    }

    @ViewBuilder private var fill: some View {
        switch background {
        case .none:
            ZStack {
                Color.white.opacity(0.06)
                Image(systemName: "nosign").font(.system(size: 12)).foregroundStyle(FrameInspector.secondary)
            }
        case .gradient(let gradient):
            LinearGradient(colors: [Color(gradient.colours.0), Color(gradient.colours.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .solid(let colour):
            Color(colour)
        case .transparent:
            Checkerboard()
        }
    }
}

/// The usual sign for "nothing behind".
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 6
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.85)))
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: 0.6)))
                }
            }
        }
    }
}

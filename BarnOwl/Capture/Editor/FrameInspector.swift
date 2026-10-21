import SwiftUI

/// The Frame inspector: a background behind the capture, room around it, rounded corners, a
/// shadow, and an aspect ratio. Everything here is part of what's copied and saved. With no
/// background chosen, only the backgrounds show; choosing one reveals the rest.
struct FrameInspector: View {
    let model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 260

    private var frame: FrameSettings { model.document.frame }

    static let backgrounds: [FrameBackground] = [
        .none, .gradient(.dawn), .gradient(.dusk), .gradient(.meadow), .gradient(.mist),
        .desktop, .solid(.white), .solid(MarkColour(hex: 0xF7EBD4)), .solid(.ink), .transparent,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Frame").font(.system(size: 13, weight: .semibold))
                    Text(frame.isOn ? "Part of what you copy and save." : "Put the capture on a background.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                section("Background") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 5), alignment: .leading,
                              spacing: 8) {
                        ForEach(Array(Self.backgrounds.enumerated()), id: \.offset) { _, background in
                            Button {
                                choose(background)
                            } label: {
                                BackgroundSwatch(background: background, selected: frame.background == background,
                                                 desktop: model.renderer.desktop)
                            }
                            .buttonStyle(.plain)
                            .help(Self.title(background))
                            .accessibilityLabel(Self.title(background))
                            .accessibilityAddTraits(frame.background == background ? .isSelected : [])
                        }
                    }
                }
                if frame.isOn {
                    VStack(alignment: .leading, spacing: 18) {
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .font(.system(size: 12.5))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .tint(Color(nsColor: EditorCanvas.accent))
    }

    private func choose(_ background: FrameBackground) {
        let change = { model.setFrame("Change Background") { $0.background = background } }
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.25)) { change() }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    /// A slider in points over a length kept in pixels; the whole slide is one undo step.
    private func slider(_ title: String, value: WritableKeyPath<FrameSettings, CGFloat>, range: ClosedRange<CGFloat>,
                        undoName: String) -> some View {
        let scale = model.scale
        let points = Binding<CGFloat>(get: { frame[keyPath: value] / scale }, set: { newValue in
            model.setFrameLive { $0[keyPath: value] = (newValue * scale).rounded() }
        })
        return section(title) {
            HStack(spacing: 10) {
                Slider(value: points, in: range) { editing in
                    if editing { model.beginLiveChange() } else { model.endLiveChange(undoName) }
                }
                .controlSize(.small)
                Text("\(Int(points.wrappedValue.rounded()))")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
            }
        }
    }

    static func title(_ background: FrameBackground) -> String {
        switch background {
        case .none: "No frame"
        case .gradient(let gradient): gradient.title
        case .desktop: "Desktop picture"
        case .solid(let colour):
            switch colour {
            case .white: "White"
            case .ink: "Ink"
            default: "Cream"
            }
        case .transparent: "Transparent"
        }
    }
}

private struct BackgroundSwatch: View {
    let background: FrameBackground
    let selected: Bool
    let desktop: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        fill
            .frame(width: 38, height: 28)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color(nsColor: .labelColor), lineWidth: 2)
                        .padding(-3)
                }
            }
            .contentShape(shape)
    }

    @ViewBuilder private var fill: some View {
        switch background {
        case .none:
            ZStack {
                Color(nsColor: .quaternarySystemFill)
                Image(systemName: "nosign").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .gradient(let gradient):
            LinearGradient(colors: [Color(gradient.colours.0), Color(gradient.colours.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .solid(let colour):
            Color(colour)
        case .desktop:
            if let desktop {
                Image(decorative: desktop, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(nsColor: .quaternarySystemFill)
                    Image(systemName: "menubar.dock.rectangle").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
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

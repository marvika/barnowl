import SwiftUI

/// The Frame inspector: a background behind the capture, room around it, rounded corners, a
/// shadow, an aspect ratio and where the capture sits in it. Everything here is part of what's
/// copied and saved. With no background chosen, only the backgrounds show; choosing one
/// reveals the rest.
struct FrameInspector: View {
    let model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The background being made or changed in the popover.
    @State private var editing: BackgroundEditing?

    static let width: CGFloat = 260
    static let columns: [GridItem] = Array(repeating: GridItem(.fixed(BackgroundSwatch.size.width), spacing: 8), count: 5)

    private var frame: FrameSettings { model.document.frame }

    static let cream = MarkColour(hex: 0xF7EBD4)
    /// No frame, then the ready-made gradients from light to dark.
    static let gradients: [FrameBackground] = [.none] + FrameGradient.allCases.map { .gradient($0) }
    static let plain: [FrameBackground] = [.solid(.white), .solid(cream), .solid(.ink), .desktop, .transparent]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Frame").font(.system(size: 13, weight: .semibold))
                    Text(frame.isOn ? "Part of what you copy and save." : "Put the capture on a background.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                backgrounds
                if frame.isOn {
                    VStack(alignment: .leading, spacing: 18) {
                        slider("Padding", value: \.padding, range: 0...160, undoName: "Change Padding")
                        if !model.renderer.ownShadow {
                            slider("Inset", value: \.inset, range: 0...40, undoName: "Change Inset")
                                .help("Room around the capture, in its own edge colour")
                        }
                        if model.renderer.ownShadow {
                            ownShadowNote
                        } else {
                            slider("Corners", value: \.cornerRadius, range: 0...40, undoName: "Change Corners")
                            shadowSlider
                        }
                        ratios
                        if frame.ratio != .auto { position }
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

    // MARK: Backgrounds

    private var matched: [FrameBackground] {
        (model.harmony?.gradients ?? []).map { .custom($0) }
    }

    private var backgrounds: some View {
        section("Background") {
            VStack(alignment: .leading, spacing: 12) {
                swatches(Self.gradients)
                if !matched.isEmpty {
                    group("Matched to this capture") { swatches(matched) }
                }
                group("Plain") { swatches(Self.plain) }
                group("Yours") { yours }
                if let edit = editAction {
                    Button(edit.title) { editing = edit.editing }
                        .controlSize(.small)
                        .help(edit.help)
                }
            }
            .popover(item: $editing, arrowEdge: .leading) { editing in
                BackgroundEditor(model: model, seed: editing.seed, chips: chips) { final in
                    finish(editing, final: final)
                }
            }
        }
    }

    private func swatches(_ backgrounds: [FrameBackground]) -> some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
            ForEach(backgrounds, id: \.self) { background in
                swatch(background)
            }
        }
    }

    private func swatch(_ background: FrameBackground) -> some View {
        let selected = frame.background == background
        let title = Self.title(background)
        return Button {
            choose(background)
        } label: {
            BackgroundSwatch(background: background, selected: selected, renderer: model.renderer)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// ＋ and the backgrounds you made.
    private var yours: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
            Button {
                editing = BackgroundEditing(seed: newSeed, saved: nil, isNew: true)
            } label: {
                AddSwatch()
            }
            .buttonStyle(.plain)
            .help("New Background…")
            .accessibilityLabel("New Background")
            ForEach(model.styleBook.saved) { saved in
                swatch(saved.background)
                    .contextMenu {
                        Button("Edit…") {
                            editing = BackgroundEditing(seed: saved.background, saved: saved.id, isNew: false)
                        }
                        Button("Delete") { model.deleteSavedBackground(saved.id) }
                    }
            }
        }
    }

    /// What ＋ starts from: the background you have, or one matched to the capture.
    private var newSeed: FrameBackground {
        switch frame.background {
        case .gradient(let gradient): .custom(gradient.custom)
        case .custom, .solid: frame.background
        default: .custom(model.harmony?.gradients.first ?? FrameGradient.dawn.custom)
        }
    }

    /// The capture's own colours, then lavender, white and ink, for the popover's chips.
    private var chips: [MarkColour] {
        var chips: [MarkColour] = []
        for colour in (model.harmony?.colours ?? []) + [.lavender, .white, .ink] where !chips.contains(colour) {
            chips.append(colour)
        }
        return Array(chips.prefix(8))
    }

    private struct EditAction {
        let title: String
        let help: String
        let editing: BackgroundEditing
    }

    /// The link under the backgrounds: change the gradient or colour you have.
    private var editAction: EditAction? {
        let background = frame.background
        let saved = model.styleBook.saved.first { $0.background == background }
        switch background {
        case .gradient(let gradient):
            return EditAction(title: "Customise…", help: "Make a gradient of your own from \(gradient.title)",
                              editing: BackgroundEditing(seed: .custom(gradient.custom), saved: nil, isNew: false))
        case .custom:
            if saved == nil, matched.contains(background) {
                return EditAction(title: "Customise…", help: "Make a gradient of your own from this one",
                                  editing: BackgroundEditing(seed: background, saved: nil, isNew: false))
            }
            return EditAction(title: "Edit Gradient…", help: "Change this gradient",
                              editing: BackgroundEditing(seed: background, saved: saved?.id, isNew: false))
        case .solid:
            guard !Self.plain.contains(background) else { return nil }
            return EditAction(title: "Edit Colour…", help: "Change this colour",
                              editing: BackgroundEditing(seed: background, saved: saved?.id, isNew: false))
        case .none, .desktop, .transparent:
            return nil
        }
    }

    private func choose(_ background: FrameBackground) {
        let change = { model.chooseBackground(background) }
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.25)) { change() }
        }
    }

    /// The popover closed: everything it did is one undo step, and what you made is kept in Yours.
    private func finish(_ editing: BackgroundEditing, final: FrameBackground) {
        model.endLiveChange("Change Background")
        guard editing.isNew || final != editing.seed else { return }
        switch final {
        case .custom, .solid: model.saveBackground(final, replacing: editing.saved)
        default: break
        }
    }

    // MARK: Shape

    private var ownShadowNote: some View {
        Label("Uses the window's own shadow.", systemImage: "macwindow")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .help("This window was captured with its shadow, so the frame keeps it and adds no corners or shadow of its own.")
    }

    private var shadowSlider: some View {
        let amount = Binding<CGFloat>(get: { frame.shadowAmount }, set: { value in
            model.setFrameLive { $0.shadowAmount = (value * 100).rounded() / 100 }
        })
        return section("Shadow") {
            HStack(spacing: 10) {
                Slider(value: amount, in: 0...1) { editing in
                    if editing { model.beginLiveChange() } else { model.endLiveChange("Change Shadow") }
                }
                .controlSize(.small)
                .accessibilityValue("\(Int((amount.wrappedValue * 100).rounded())) percent")
                Text("\(Int((amount.wrappedValue * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
            }
        }
    }

    private var ratios: some View {
        section("Aspect ratio") {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
                ForEach(AspectRatio.allCases, id: \.self) { ratio in
                    let selected = frame.ratio == ratio
                    Button {
                        model.setFrame("Change Aspect Ratio") { $0.ratio = ratio }
                    } label: {
                        RatioCell(ratio: ratio, captureAspect: captureAspect, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .help(ratio.purpose)
                    .accessibilityLabel(ratio.purpose)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    /// Auto's picture follows the capture's own proportions.
    private var captureAspect: CGFloat {
        let crop = model.document.crop
        return crop.height > 0 ? crop.width / crop.height : 1
    }

    private var position: some View {
        let layout = FrameLayout(document: model.document)
        return section("Position") {
            HStack(spacing: 12) {
                PositionPad(canvas: layout.canvasSize, image: layout.imageRect, position: frame.position) { position in
                    model.setFrame("Change Position") { $0.position = position }
                }
                Text(frame.position.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Building blocks

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    /// A row of backgrounds under a small caption.
    private func group(_ caption: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
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
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
            }
        }
    }

    // MARK: Names

    static func title(_ background: FrameBackground) -> String {
        switch background {
        case .none: "No frame"
        case .gradient(let gradient): gradient.title
        case .desktop: "Desktop picture"
        case .solid(let colour):
            switch colour {
            case .white: "White"
            case .ink: "Ink"
            case cream: "Cream"
            default: "Colour, \(colour.plainName)"
            }
        case .transparent: "Transparent"
        case .custom(let gradient): describe(gradient)
        }
    }

    /// "Gradient, blue to violet"; "Radial gradient, shades of teal".
    static func describe(_ gradient: CustomGradient) -> String {
        let kind = gradient.kind == .radial ? "Radial gradient" : "Gradient"
        let names: [String] = gradient.stops.map(\.colour.plainName)
        guard let first = names.first, let last = names.last else { return kind }
        guard first != last else {
            let hue: String = first.replacingOccurrences(of: "light ", with: "").replacingOccurrences(of: "dark ", with: "")
            return "\(kind), shades of \(hue)"
        }
        return "\(kind), \(first) to \(last)"
    }
}

/// The background being made or changed in the popover, and where it came from.
struct BackgroundEditing: Identifiable {
    let id = UUID()
    /// What the popover starts from.
    let seed: FrameBackground
    /// The saved background being changed, which the result replaces in Yours.
    let saved: UUID?
    /// Made with ＋: kept in Yours even if left as it started.
    let isNew: Bool
}

// MARK: Swatches

struct BackgroundSwatch: View {
    static let size = CGSize(width: 38, height: 28)

    let background: FrameBackground
    let selected: Bool
    let renderer: AnnotationRenderer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        fill
            .frame(width: Self.size.width, height: Self.size.height)
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
        case .transparent:
            Checkerboard()
        default:
            if let image = BackgroundSamples.image(background, renderer: renderer) {
                Image(nsImage: image).resizable()
            } else {
                ZStack {
                    Color(nsColor: .quaternarySystemFill)
                    Image(systemName: "menubar.dock.rectangle").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// ＋: make a background of your own.
private struct AddSwatch: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape
            .strokeBorder(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            .overlay(Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary))
            .frame(width: BackgroundSwatch.size.width, height: BackgroundSwatch.size.height)
            .contentShape(shape)
    }
}

/// Swatches drawn by the real renderer, so they look exactly like the frame; made once each.
@MainActor
enum BackgroundSamples {
    private static var cache: [FrameBackground: NSImage] = [:]

    static func image(_ background: FrameBackground, renderer: AnnotationRenderer,
                      size: CGSize = BackgroundSwatch.size) -> NSImage? {
        let cacheable = background != .desktop && size == BackgroundSwatch.size
        if cacheable, let cached = cache[background] { return cached }
        guard let picture = renderer.backgroundSample(background, size: size, pixelsPerPoint: 2) else { return nil }
        let image = NSImage(cgImage: picture, size: NSSize(width: size.width, height: size.height))
        if cacheable {
            if cache.count > 200 { cache.removeAll() }
            cache[background] = image
        }
        return image
    }
}

/// The usual sign for "nothing behind".
struct Checkerboard: View {
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

// MARK: Ratio and position

/// One aspect ratio: a small picture of its shape over its name.
private struct RatioCell: View {
    let ratio: AspectRatio
    let captureAspect: CGFloat
    let selected: Bool

    static let size = CGSize(width: 38, height: 34)
    static let glyph = CGSize(width: 20, height: 14)

    var body: some View {
        let aspect: CGFloat = ratio.value ?? captureAspect
        let size = Self.fitted(aspect)
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        VStack(spacing: 3) {
            ZStack {
                if ratio == .auto {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: 1.25, dash: [2.5, 1.5]))
                } else {
                    shape.strokeBorder(lineWidth: 1.25)
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(width: Self.glyph.width, height: Self.glyph.height)
            Text(ratio.title)
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: EditorCanvas.accent).opacity(0.22))
            }
        }
        .contentShape(Rectangle())
    }

    /// The largest rectangle of `aspect` inside the glyph's box.
    static func fitted(_ aspect: CGFloat) -> CGSize {
        let box = glyph
        guard aspect > 0 else { return box }
        if box.width / box.height > aspect {
            return CGSize(width: (box.height * aspect).rounded(), height: box.height)
        }
        return CGSize(width: box.width, height: (box.width / aspect).rounded())
    }
}

/// Where the capture sits: nine places in a small picture of the frame, with the capture's
/// own place shown faintly. Arrow keys move it; VoiceOver hears a radio group.
struct PositionPad: View {
    let canvas: CGSize
    let image: CGRect
    let position: FramePosition
    let choose: @MainActor (FramePosition) -> Void

    static let box = CGSize(width: 64, height: 44)

    var body: some View {
        let size = fitted
        let factor: CGFloat = canvas.width > 0 ? size.width / canvas.width : 1
        let card = CGRect(x: image.minX * factor, y: image.minY * factor, width: image.width * factor,
                          height: image.height * factor)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.secondary.opacity(0.28))
                .frame(width: max(card.width, 2), height: max(card.height, 2))
                .offset(x: card.minX, y: card.minY)
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { column in
                            spot(FramePosition.grid[row * 3 + column])
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .frame(width: Self.box.width, height: Self.box.height)
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            step(press.key)
            return .handled
        }
        .accessibilityRepresentation {
            Picker("Position", selection: Binding(get: { position }, set: { choose($0) })) {
                ForEach(FramePosition.grid, id: \.self) { place in
                    Text(place.title).tag(place)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    private func spot(_ place: FramePosition) -> some View {
        let selected = place == position
        let alignment = Alignment(horizontal: place.x < 0.25 ? .leading : (place.x > 0.75 ? .trailing : .center),
                                  vertical: place.y < 0.25 ? .top : (place.y > 0.75 ? .bottom : .center))
        return Button {
            choose(place)
        } label: {
            ZStack(alignment: alignment) {
                Color.clear
                Circle()
                    .fill(selected ? Color(nsColor: EditorCanvas.accentFill) : Color.secondary.opacity(0.55))
                    .frame(width: selected ? 7 : 4, height: selected ? 7 : 4)
                    .frame(width: 8, height: 8)
                    .padding(4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(place.title)
    }

    private var fitted: CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return Self.box }
        let aspect: CGFloat = canvas.width / canvas.height
        if Self.box.width / Self.box.height > aspect {
            return CGSize(width: (Self.box.height * aspect).rounded(), height: Self.box.height)
        }
        return CGSize(width: Self.box.width, height: (Self.box.width / aspect).rounded())
    }

    private func step(_ key: KeyEquivalent) {
        var x: Double = position.x
        var y: Double = position.y
        switch key {
        case .leftArrow: x = max(0, x - 0.5)
        case .rightArrow: x = min(1, x + 0.5)
        case .upArrow: y = max(0, y - 0.5)
        case .downArrow: y = min(1, y + 0.5)
        default: return
        }
        let next = FramePosition(x: x, y: y)
        if next != position { choose(next) }
    }
}

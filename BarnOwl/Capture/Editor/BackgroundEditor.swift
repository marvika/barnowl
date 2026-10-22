import AppKit
import SwiftUI

/// What the background popover is making: a colour, or a gradient along a line or out from the
/// capture. The gradient is kept while you try a plain colour, so switching back loses nothing.
struct BackgroundDraft: Equatable {
    enum Fill: String, CaseIterable {
        case colour, gradient, radial

        var title: String {
            switch self {
            case .colour: "Colour"
            case .gradient: "Gradient"
            case .radial: "Radial"
            }
        }
    }

    var fill: Fill
    var colour: MarkColour
    var gradient: CustomGradient

    init(seed: FrameBackground) {
        switch seed {
        case .solid(let colour):
            fill = .colour
            self.colour = colour
            gradient = Self.gradient(around: colour)
        case .custom(let gradient):
            fill = gradient.kind == .radial ? .radial : .gradient
            self.gradient = gradient
            colour = gradient.stops.first?.colour ?? .lavender
        case .gradient(let gradient):
            fill = .gradient
            self.gradient = gradient.custom
            colour = gradient.stops.first ?? .lavender
        case .none, .desktop, .transparent:
            fill = .gradient
            gradient = FrameGradient.dawn.custom
            colour = .lavender
        }
    }

    var background: FrameBackground {
        var shaped = gradient.normalised
        switch fill {
        case .colour:
            return .solid(colour)
        case .gradient:
            shaped.kind = .linear
            return .custom(shaped)
        case .radial:
            shaped.kind = .radial
            return .custom(shaped)
        }
    }

    /// A gentle gradient from one colour: a little lighter one way, a little deeper the other.
    static func gradient(around colour: MarkColour) -> CustomGradient {
        let lab = colour.oklab
        let chroma = lab.chroma
        let lighter = OKLab.lch(min(lab.l + 0.08, 0.97), chroma, lab.hue - 12).colour
        let deeper = OKLab.lch(max(lab.l - 0.1, 0.12), chroma * 1.05, lab.hue + 12).colour
        return CustomGradient(colours: [lighter, deeper])
    }
}

/// The background popover, after Keynote's Fill: the kind of fill, a preview around the
/// capture, the gradient's stops, colours (the capture's own among them), the angle and the
/// soft light. Every change shows on the canvas as you make it; closing it is one undo step,
/// so there's no Save or Cancel: ⌘Z takes the whole thing back.
struct BackgroundEditor: View {
    let model: EditorModel
    let seed: FrameBackground
    let chips: [MarkColour]
    /// Called once, as the popover closes, with what it made.
    let finish: (FrameBackground) -> Void

    @State private var draft: BackgroundDraft
    @State private var selected = 0
    @State private var thumbnail: NSImage?
    @State private var started = false

    static let width: CGFloat = 280

    init(model: EditorModel, seed: FrameBackground, chips: [MarkColour], finish: @escaping (FrameBackground) -> Void) {
        self.model = model
        self.seed = seed
        self.chips = chips
        self.finish = finish
        _draft = State(initialValue: BackgroundDraft(seed: seed))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Fill", selection: $draft.fill) {
                ForEach(BackgroundDraft.Fill.allCases, id: \.self) { fill in
                    Text(fill.title).tag(fill)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            PreviewWell(background: draft.background, renderer: model.renderer, thumbnail: thumbnail)
            if draft.fill != .colour {
                StopBar(gradient: $draft.gradient, selected: $selected)
            }
            colours
            if draft.fill != .colour {
                gradientOptions
            } else {
                HStack {
                    Spacer()
                    shuffleButton
                }
            }
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(16)
        .frame(width: Self.width)
        .onAppear(perform: start)
        .onDisappear { finish(draft.background) }
        .onChange(of: draft.fill) { old, new in
            // From a gradient to a plain colour: the stop you had picked.
            guard new == .colour, old != .colour, draft.gradient.stops.indices.contains(selected) else { return }
            draft.colour = draft.gradient.stops[selected].colour
        }
        .onChange(of: draft) { _, new in
            let background = new.background
            model.setFrameLive { $0.background = background }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        thumbnail = Self.thumbnail(of: model.image)
        model.beginLiveChange()
        let background = draft.background
        let look = model.document.frame.isOn ? nil : model.styleBook.frameLook
        let scale = model.scale
        model.setFrameLive { frame in
            // From no frame, your last frame's padding and corners come with it.
            if let look { frame = look.settings(scale: scale) }
            frame.background = background
        }
    }

    // MARK: Colours

    /// The colour being changed: the plain colour, or the stop you picked.
    private var colour: Binding<MarkColour> {
        Binding(get: {
            if draft.fill == .colour { return draft.colour }
            let stops = draft.gradient.stops
            return stops.indices.contains(selected) ? stops[selected].colour : (stops.first?.colour ?? .lavender)
        }, set: { colour in
            if draft.fill == .colour {
                draft.colour = colour
            } else if draft.gradient.stops.indices.contains(selected) {
                draft.gradient.stops[selected].colour = colour
            }
        })
    }

    private var colours: some View {
        let current = colour.wrappedValue
        return HStack(spacing: 10) {
            ColourWell(colour: colour)
                .frame(width: 40, height: 22)
                .help(draft.fill == .colour ? "Colour" : "This stop's colour")
            HStack(spacing: 5) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    ColourChip(colour: chip, selected: chip == current) { colour.wrappedValue = chip }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour")
    }

    private var gradientOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if draft.fill == .gradient {
                    Text("Angle").foregroundStyle(.secondary)
                    AngleDial(angle: $draft.gradient.angle)
                    HStack(spacing: 1) {
                        TextField("Angle", value: angleField, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 40)
                            .accessibilityLabel("Angle in degrees")
                        Text("°").foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    let count = draft.gradient.stops.count
                    draft.gradient = draft.gradient.reversed
                    selected = max(0, count - 1 - selected)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 18)
                }
                .help(draft.fill == .radial ? "Reverse: swap the inside and outside colours" : "Reverse: run the colours the other way")
                .accessibilityLabel("Reverse")
                shuffleButton
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Soft light")
                    Text("Off keeps the colours exact.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Soft light", isOn: $draft.gradient.softLight)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .help("A soft light from the top left, as through a window")
            HStack {
                Text("Grain")
                Spacer()
                Toggle("Grain", isOn: $draft.gradient.grain)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .help("A fine texture, like paper")
        }
    }

    /// A pleasing gradient round the capture's colours, different each time.
    private var shuffleButton: some View {
        Button {
            shuffle()
        } label: {
            Image(systemName: "die.face.5")
                .frame(width: 18)
        }
        .help("Shuffle: a new gradient around the capture's colours")
        .accessibilityLabel("Shuffle")
    }

    private func shuffle() {
        let harmony = model.harmony
        var generator = SystemRandomNumberGenerator()
        let hue = harmony?.hue ?? BackgroundHarmony.fallbackHue
        var next = BackgroundHarmony.shuffled(around: hue, edgeLightness: harmony?.edgeLightness ?? 0.5, using: &generator)
        next.softLight = draft.gradient.softLight
        next.grain = draft.gradient.grain
        if draft.fill == .colour {
            draft.colour = next.stops.first?.colour ?? draft.colour
        } else {
            draft.gradient = next
            selected = 0
        }
    }

    private var angleField: Binding<Double> {
        Binding(get: { draft.gradient.angle.rounded() }, set: { value in
            let turned: Double = value.truncatingRemainder(dividingBy: 360)
            draft.gradient.angle = turned < 0 ? turned + 360 : turned
        })
    }

    /// The capture, small, for the preview.
    static func thumbnail(of image: CGImage, longest: CGFloat = 320) -> NSImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let factor: CGFloat = min(1, longest / max(width, height, 1))
        let size = CGSize(width: max(1, (width * factor).rounded()), height: max(1, (height * factor).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let small = context.makeImage() else { return nil }
        return NSImage(cgImage: small, size: NSSize(width: size.width / 2, height: size.height / 2))
    }
}

// MARK: Preview

/// The background as it will look around the capture.
private struct PreviewWell: View {
    let background: FrameBackground
    let renderer: AnnotationRenderer
    let thumbnail: NSImage?

    static let size = CGSize(width: 248, height: 96)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            if let picture = renderer.backgroundSample(background, size: Self.size, pixelsPerPoint: 2) {
                Image(decorative: picture, scale: 2)
            }
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 150, maxHeight: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .shadow(color: .black.opacity(renderer.ownShadow ? 0 : 0.3), radius: 4, y: 1.5)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: Colour

/// A colour from the capture or the owl's own, one click away.
private struct ColourChip: View {
    let colour: MarkColour
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(colour))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
                    .frame(width: 16, height: 16)
                if selected {
                    Circle()
                        .strokeBorder(Color(nsColor: .labelColor), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(colour.hex)
        .accessibilityLabel(colour.plainName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The system colour well, without opacity. It lets go of the shared colour panel when the
/// popover closes, so the panel never drives a well that's gone (or the marks, once More
/// Colours… takes the panel back).
private struct ColourWell: NSViewRepresentable {
    @Binding var colour: MarkColour

    func makeCoordinator() -> Coordinator { Coordinator(colour: $colour) }

    func makeNSView(context: Context) -> BackgroundColourWell {
        let well = BackgroundColourWell(style: .default)
        well.supportsAlpha = false
        well.color = NSColor(cgColor: colour.cgColor()) ?? .white
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        well.setAccessibilityLabel("Colour")
        return well
    }

    func updateNSView(_ well: BackgroundColourWell, context: Context) {
        context.coordinator.colour = $colour
        if Coordinator.colour(of: well.color) != colour {
            well.color = NSColor(cgColor: colour.cgColor()) ?? .white
        }
    }

    static func dismantleNSView(_ well: BackgroundColourWell, coordinator: Coordinator) {
        if well.isActive { well.deactivate() }
    }

    @MainActor
    final class Coordinator: NSObject {
        var colour: Binding<MarkColour>

        init(colour: Binding<MarkColour>) {
            self.colour = colour
        }

        @objc func changed(_ sender: NSColorWell) {
            guard let picked = Self.colour(of: sender.color), picked != colour.wrappedValue else { return }
            colour.wrappedValue = picked
        }

        static func colour(of color: NSColor) -> MarkColour? {
            guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
            return MarkColour(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                              blue: Double(srgb.blueComponent))
        }
    }
}

/// A colour well that takes the shared panel from the editor's More Colours…, so picking a
/// background colour never recolours the marks too.
final class BackgroundColourWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.setTarget(nil)
            NSColorPanel.shared.setAction(nil)
        }
        super.activate(exclusive)
    }
}

// MARK: Stops

/// The gradient's stops on a ramp of the gradient itself. Click the ramp to add one (four at
/// most), drag a knob to move it, and drag it off the bar or press Delete to take it away
/// (two at least).
private struct StopBar: View {
    @Binding var gradient: CustomGradient
    @Binding var selected: Int
    /// A knob dragged far enough off the bar to go when it's let go.
    @State private var leaving: Int?
    @State private var lift: CGFloat = 0

    static let height: CGFloat = 22
    static let knob: CGFloat = 14
    static let selectedKnob: CGFloat = 18
    /// How far off the bar a knob goes before letting go of it removes it.
    static let removal: CGFloat = 28
    /// The knobs' centres stay this far in from the ends, so they never hang over.
    static let inset: CGFloat = 9

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ramp(width: width)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { tap in
                        add(at: tap.location.x, width: width)
                    })
                ForEach(gradient.stops.indices, id: \.self) { index in
                    knob(index, width: width)
                }
            }
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: Self.height)
        .focusable()
        .onKeyPress(.delete) {
            remove(selected)
            return .handled
        }
        .onKeyPress(.deleteForward) {
            remove(selected)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let step: Double = press.modifiers.contains(.shift) ? 0.1 : 0.01
            move(selected, by: press.key == .leftArrow ? -step : step)
            return .handled
        }
        .help("Click to add a colour · drag a knob off to remove it")
    }

    private static let space = "stops"

    private func ramp(width: CGFloat) -> some View {
        let expanded = GradientPainter.expanded(gradient.stops)
        let stops: [Gradient.Stop] = zip(expanded.colours, expanded.locations).map { colour, location in
            Gradient.Stop(color: Color(colour), location: location)
        }
        let start: CGFloat = width > 0 ? Self.inset / width : 0
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return shape
            .fill(LinearGradient(stops: stops, startPoint: UnitPoint(x: start, y: 0.5), endPoint: UnitPoint(x: 1 - start, y: 0.5)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .frame(height: Self.height)
    }

    private func knob(_ index: Int, width: CGFloat) -> some View {
        let stop = gradient.stops[index]
        let isSelected = index == selected
        let size: CGFloat = isSelected ? Self.selectedKnob : Self.knob
        let leavingNow = leaving == index
        // White rings read on any gradient; the one you picked also wears the owl's lavender.
        return Circle()
            .fill(Color(stop.colour))
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color(nsColor: EditorCanvas.accentFill), lineWidth: 2).padding(-2)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .frame(width: size, height: size)
            .opacity(leavingNow ? 0.35 : 1)
            // A little more to grab than to see.
            .frame(width: 24, height: 24)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { drag in
                    selected = index
                    gradient.stops[index].location = location(at: drag.location.x, width: width)
                    let off: CGFloat = drag.location.y - Self.height / 2
                    leaving = abs(off) > Self.removal && gradient.stops.count > CustomGradient.stopCount.lowerBound ? index : nil
                    lift = off
                }
                .onEnded { _ in
                    if leaving == index {
                        remove(index)
                    } else {
                        settle(index)
                    }
                    leaving = nil
                    lift = 0
                })
            .accessibilityElement()
            .accessibilityLabel("Stop \(index + 1)")
            .accessibilityValue("\(stop.colour.hex), \(Int((stop.location * 100).rounded()))%")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAdjustableAction { direction in
                selected = index
                move(index, by: direction == .increment ? 0.05 : -0.05)
            }
            .position(x: x(for: stop.location, width: width), y: Self.height / 2 + (leavingNow ? lift : 0))
    }

    private func x(for location: Double, width: CGFloat) -> CGFloat {
        Self.inset + CGFloat(location) * max(width - 2 * Self.inset, 1)
    }

    private func location(at x: CGFloat, width: CGFloat) -> Double {
        let span: CGFloat = max(width - 2 * Self.inset, 1)
        return Double(min(max((x - Self.inset) / span, 0), 1))
    }

    /// A new stop where you clicked, in the colour the gradient already has there.
    private func add(at x: CGFloat, width: CGFloat) {
        guard gradient.stops.count < CustomGradient.stopCount.upperBound else {
            NSSound.beep()
            return
        }
        let place = location(at: x, width: width)
        let stop = GradientStop(colour: gradient.colour(at: place), location: place)
        var stops = gradient.stops
        stops.append(stop)
        stops.sort { $0.location < $1.location }
        gradient.stops = stops
        selected = stops.firstIndex(of: stop) ?? 0
    }

    private func remove(_ index: Int) {
        guard gradient.stops.count > CustomGradient.stopCount.lowerBound, gradient.stops.indices.contains(index) else { return }
        gradient.stops.remove(at: index)
        selected = min(index, gradient.stops.count - 1)
    }

    private func move(_ index: Int, by step: Double) {
        guard gradient.stops.indices.contains(index) else { return }
        gradient.stops[index].location = min(max(gradient.stops[index].location + step, 0), 1)
        settle(index)
    }

    /// Back in order after a move, still holding the stop that moved.
    private func settle(_ index: Int) {
        guard gradient.stops.indices.contains(index) else { return }
        let moved = gradient.stops[index]
        let sorted = gradient.stops.sorted { $0.location < $1.location }
        guard sorted != gradient.stops else { return }
        gradient.stops = sorted
        selected = sorted.firstIndex(of: moved) ?? index
    }
}

// MARK: Angle

/// Keynote's angle dial: drag round it to turn the gradient. It settles on every 45° within 5°
/// with a tap you can feel; hold ⌥ to turn freely. Arrow keys turn it 15°.
private struct AngleDial: View {
    @Binding var angle: Double
    @State private var snappedTo: Double?

    static let size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            DialNeedle(angle: angle)
                .stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle()
                .fill(Color.primary.opacity(0.8))
                .frame(width: 4, height: 4)
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            turn(towards: drag.location)
        })
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let clockwise = press.key == .rightArrow || press.key == .upArrow
            step(clockwise ? 15 : -15)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel("Angle")
        .accessibilityValue("\(Int(angle.rounded())) degrees")
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 15 : -15)
        }
        .help("Drag to turn · ⌥ turns freely · arrow keys step 15°")
    }

    private func turn(towards point: CGPoint) {
        let dx: Double = Double(point.x - Self.size / 2)
        let dy: Double = Double(point.y - Self.size / 2)
        guard hypot(dx, dy) > 2 else { return }
        // CSS degrees: 0 up, 90 right.
        var degrees: Double = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        degrees = degrees.rounded()
        if !NSEvent.modifierFlags.contains(.option) {
            let nearest: Double = (degrees / 45).rounded() * 45
            if abs(degrees - nearest) <= 5 {
                degrees = nearest.truncatingRemainder(dividingBy: 360)
                if snappedTo != degrees {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                snappedTo = degrees
            } else {
                snappedTo = nil
            }
        }
        angle = degrees
    }

    private func step(_ degrees: Double) {
        let next: Double = ((angle / 15).rounded() * 15 + degrees).truncatingRemainder(dividingBy: 360)
        angle = next < 0 ? next + 360 : next
    }
}

/// The dial's hand, from the middle out toward `angle` (CSS degrees: 0 up, 90 right).
private struct DialNeedle: Shape {
    var angle: Double

    func path(in rect: CGRect) -> Path {
        let radians: Double = angle * .pi / 180
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let reach: CGFloat = min(rect.width, rect.height) / 2 - 5
        let tip = CGPoint(x: centre.x + CGFloat(sin(radians)) * reach, y: centre.y - CGFloat(cos(radians)) * reach)
        var path = Path()
        path.move(to: centre)
        path.addLine(to: tip)
        return path
    }
}

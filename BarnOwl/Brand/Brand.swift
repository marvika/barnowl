import SwiftUI

/// Barn Owl's colours: dusk indigo, amber and cream, with a golden owl.
enum Brand {
    static let indigo = Color(hex: 0x3D3A8F)
    static let indigoDeep = Color(hex: 0x1C1A40)
    static let amber = Color(hex: 0xF5A633)
    static let cream = Color(hex: 0xF7EBD4)
    static let golden = Color(hex: 0xF0B04F)
    /// A lighter indigo that reads well on dark backgrounds.
    static let lavender = Color(hex: 0x8C87FF)

    /// The dusk sky behind the owl in setup and About.
    static let dusk = LinearGradient(colors: [indigo, indigoDeep], startPoint: .top, endPoint: .bottom)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// The owl's colours, chosen in Settings → Appearance.
enum OwlPalette: String, CaseIterable, Identifiable {
    case golden, ghost, ember, lilac

    var id: Self { self }

    var title: String {
        switch self {
        case .golden: "Golden Barn"
        case .ghost: "Ghost Owl"
        case .ember: "Ember"
        case .lilac: "Moonlit Lilac"
        }
    }

    struct Colours {
        let bodyTop, bodyBottom, face, rim, belly, speckle, wingTop, wingBottom, eye, blush, beak, feet, outline: Color
    }

    var colours: Colours {
        switch self {
        case .golden:
            Colours(bodyTop: Color(hex: 0xF0B04F), bodyBottom: Color(hex: 0xC8742C), face: Color(hex: 0xFFF9F0),
                    rim: Color(hex: 0xA9572A), belly: Color(hex: 0xFFFDF8), speckle: Color(hex: 0x6E6488),
                    wingTop: Color(hex: 0xE39A3E), wingBottom: Color(hex: 0xB5652A), eye: Color(hex: 0x24182A),
                    blush: Color(hex: 0xFF8A7A), beak: Color(hex: 0xF3C6B4), feet: Color(hex: 0xF5A633),
                    outline: Color(hex: 0x4A2C1E))
        case .ghost:
            Colours(bodyTop: Color(hex: 0xEEEBFA), bodyBottom: Color(hex: 0xB9B3EC), face: .white,
                    rim: Color(hex: 0x8C87FF), belly: .white, speckle: Color(hex: 0x3D3A8F),
                    wingTop: Color(hex: 0xD8D3F6), wingBottom: Color(hex: 0x9C95E8), eye: Color(hex: 0x1C1A40),
                    blush: Color(hex: 0xFF9DBB), beak: Color(hex: 0xF5A633), feet: Color(hex: 0xF5A633),
                    outline: Color(hex: 0x3D3A8F))
        case .ember:
            Colours(bodyTop: Color(hex: 0xFF8A50), bodyBottom: Color(hex: 0xE2552C), face: Color(hex: 0xFFF3E4),
                    rim: Color(hex: 0xB83A1E), belly: Color(hex: 0xFFE6D2), speckle: Color(hex: 0xC24423),
                    wingTop: Color(hex: 0xF06A3C), wingBottom: Color(hex: 0xC2401F), eye: Color(hex: 0x2A1B30),
                    blush: Color(hex: 0xFF5C7A), beak: Color(hex: 0xFFC08A), feet: Color(hex: 0xFFC24D),
                    outline: Color(hex: 0x6E2410))
        case .lilac:
            Colours(bodyTop: Color(hex: 0xA5A1FF), bodyBottom: Color(hex: 0x6E68EA), face: Color(hex: 0xFFF5E4),
                    rim: Color(hex: 0xF5A633), belly: Color(hex: 0xEEEDFF), speckle: Color(hex: 0x6E68EA),
                    wingTop: Color(hex: 0x837DF5), wingBottom: Color(hex: 0x5852D2), eye: Color(hex: 0x1C1A40),
                    blush: Color(hex: 0xFF9FB2), beak: Color(hex: 0xF5A633), feet: Color(hex: 0xF5A633),
                    outline: Color(hex: 0x2E2A86))
        }
    }
}

/// A dusk sky with a few softly twinkling stars.
struct DuskSky: View {
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (0.08, 0.12, 2.5, 0), (0.22, 0.06, 1.8, 0.7), (0.37, 0.18, 1.5, 1.4), (0.61, 0.08, 2.2, 0.3),
        (0.78, 0.15, 1.6, 1.1), (0.91, 0.07, 2.4, 1.8), (0.86, 0.32, 1.4, 0.5), (0.14, 0.34, 1.6, 2.1),
        (0.48, 0.05, 1.3, 1.6), (0.70, 0.26, 1.2, 2.4),
    ]

    var body: some View {
        ZStack {
            Brand.dusk
            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                        Circle()
                            .fill(.white)
                            .frame(width: star.size, height: star.size)
                            .opacity(0.45 + 0.4 * sin(time * 1.3 + star.delay * 2))
                            .position(x: star.x * proxy.size.width, y: star.y * proxy.size.height)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The owl's shapes in a unit square (0…1, y down), shared by the mascot, the
/// menu bar icon and the app icon so they always match. The owl is one
/// pebble, head and body together, with the barn owl's heart-shaped face.
enum OwlGeometry {
    /// The pebble's bounds in the unit square.
    static let pebbleBounds = CGRect(x: 0.17, y: 0.10, width: 0.66, height: 0.82)

    private static func point(_ rect: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    /// Head and body in one egg shape, broad on top and widest low down.
    static func pebble(in rect: CGRect) -> CGPath {
        let p = { point(rect, $0, $1) }
        let (x0, x1, y0, y1, widest, cx): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0.17, 0.83, 0.10, 0.92, 0.6, 0.5)
        let path = CGMutablePath()
        path.move(to: p(cx, y0))
        path.addCurve(to: p(x1, widest), control1: p(cx + (x1 - cx) * 0.9, y0), control2: p(x1, y0 + (widest - y0) * 0.35))
        path.addCurve(to: p(cx, y1), control1: p(x1, widest + (y1 - widest) * 0.6), control2: p(cx + (x1 - cx) * 0.6, y1))
        path.addCurve(to: p(x0, widest), control1: p(cx - (cx - x0) * 0.6, y1), control2: p(x0, widest + (y1 - widest) * 0.6))
        path.addCurve(to: p(cx, y0), control1: p(x0, y0 + (widest - y0) * 0.35), control2: p(cx - (cx - x0) * 0.9, y0))
        path.closeSubpath()
        return path
    }

    /// The heart-shaped facial disc that makes a barn owl a barn owl.
    static func face(in rect: CGRect) -> CGPath {
        let disc = CGRect(x: rect.minX + 0.24 * rect.width, y: rect.minY + 0.17 * rect.height,
                          width: 0.52 * rect.width, height: 0.43 * rect.height)
        let p = { point(disc, $0, $1) }
        let path = CGMutablePath()
        path.move(to: p(0.5, 0.1))
        path.addCurve(to: p(0.03, 0.3), control1: p(0.38, -0.04), control2: p(0.05, 0.0))
        path.addCurve(to: p(0.5, 1), control1: p(0.01, 0.62), control2: p(0.32, 0.9))
        path.addCurve(to: p(0.97, 0.3), control1: p(0.68, 0.9), control2: p(0.99, 0.62))
        path.addCurve(to: p(0.5, 0.1), control1: p(0.95, 0.0), control2: p(0.62, -0.04))
        path.closeSubpath()
        return path
    }

    static func eyeCentres(in rect: CGRect) -> (CGPoint, CGPoint) {
        (point(rect, 0.4, 0.4), point(rect, 0.6, 0.4))
    }

    /// The small beak between and below the eyes.
    static func beak(in rect: CGRect) -> CGPath {
        let p = { point(rect, $0, $1) }
        let path = CGMutablePath()
        path.move(to: p(0.5, 0.445))
        path.addQuadCurve(to: p(0.5, 0.515), control: p(0.53, 0.48))
        path.addQuadCurve(to: p(0.5, 0.445), control: p(0.47, 0.48))
        path.closeSubpath()
        return path
    }

    /// A folded wing on the left (side -1) or right (side 1), hanging from
    /// its shoulder at `shoulder(side:)`.
    static func wing(in rect: CGRect, side: CGFloat) -> CGPath {
        let p = { (x: CGFloat, y: CGFloat) in point(rect, 0.5 + side * x, y) }
        let path = CGMutablePath()
        path.move(to: p(0.31, 0.5))
        path.addCurve(to: p(0.22, 0.85), control1: p(0.36, 0.65), control2: p(0.3, 0.8))
        path.addCurve(to: p(0.31, 0.5), control1: p(0.2, 0.72), control2: p(0.24, 0.58))
        path.closeSubpath()
        return path
    }

    static func shoulder(side: CGFloat) -> UnitPoint { UnitPoint(x: 0.5 + side * 0.3, y: 0.51) }

    /// The little curl of feathers on top of the head.
    static func curl(in rect: CGRect) -> CGPath {
        let p = { point(rect, $0, $1) }
        let path = CGMutablePath()
        path.move(to: p(0.49, 0.12))
        path.addCurve(to: p(0.55, 0.03), control1: p(0.47, 0.06), control2: p(0.5, 0.03))
        path.addQuadCurve(to: p(0.53, 0.08), control: p(0.58, 0.06))
        return path
    }
}

/// What the owl is wearing.
enum OwlAccessory: Equatable {
    case none, sunglasses, partyHat, nightcap, santaHat

    /// A seasonal surprise when nothing else is worn.
    static var seasonal: OwlAccessory {
        Calendar.current.component(.month, from: .now) == 12 ? .santaHat : .none
    }
}

/// The owl: a golden pebble with a heart-shaped face. Everything that moves
/// is a parameter, so `WatchingOwl` can animate it.
struct OwlView: View {
    var eyesOpen = true
    var look: CGVector = .zero
    var blinks = true
    /// Wide eyes, for excitement.
    var surprised = false
    /// Smiling eyes (upward arcs), for a job well done.
    var happy = false
    var hearts = false
    var dizzy = false
    /// How far the lids are down over open eyes: 0 wide awake, 1 shut.
    var lids: CGFloat = 0
    /// 0 folded, 1 spread; more is a big stretch.
    var wingLift: CGFloat = 0
    /// The face turning round: 0 facing you, 2π all the way round.
    var turn: Double = 0
    /// Head tilt in degrees.
    var tilt: Double = 0
    /// 0 to 1, how wide it yawns.
    var yawn: CGFloat = 0
    var accessory: OwlAccessory = .none
    /// nil uses the colours chosen in Settings.
    var palette: OwlPalette?

    @AppStorage(PrefKey.owlPalette) private var chosen = OwlPalette.golden
    @State private var blink = false

    var body: some View {
        let colours = (palette ?? chosen).colours
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lookTilt = Double(max(-1, min(1, look.dx))) * 8
            ZStack {
                OwlBodyLayer(colours: colours, curl: accessory == .none || accessory == .sunglasses)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    WingLayer(colours: colours, side: side)
                        .rotationEffect(.degrees(Double(wingLift) * 95 * -side), anchor: OwlGeometry.shoulder(side: side))
                }
                Group {
                    OwlFaceLayer(colours: colours, eyes: eyeState, lids: lids, look: look, surprised: surprised,
                                 yawn: yawn, sunglasses: accessory == .sunglasses)
                        .modifier(HeadTurn(angle: turn, reach: side * 0.22))
                        .offset(x: max(-1, min(1, look.dx)) * side * 0.03, y: max(-1, min(1, look.dy)) * side * 0.015)
                    HatLayer(accessory: accessory)
                }
                .rotationEffect(.degrees(lookTilt), anchor: UnitPoint(x: 0.5, y: 0.62))
                .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 0.62))
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(duration: 0.25), value: look)
        .animation(.easeInOut(duration: 0.12), value: blink)
        .animation(.spring(duration: 0.3), value: eyesOpen)
        .task(id: blinks && eyesOpen) {
            guard blinks && eyesOpen else { return }
            // A blink every few seconds, at slightly random times, and now
            // and then a double blink.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3...7)))
                for _ in 0..<(Int.random(in: 0...4) == 0 ? 2 : 1) {
                    blink = true
                    try? await Task.sleep(for: .milliseconds(130))
                    blink = false
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var eyeState: OwlFaceLayer.Eyes {
        if dizzy { return .dizzy }
        if hearts { return .hearts }
        if happy { return .happy }
        return eyesOpen && !blink ? .open : .closed
    }
}

/// Turns the face round: it slides to one side and narrows, is hidden while
/// the owl looks behind itself, and comes back from the other side.
private struct HeadTurn: ViewModifier, @preconcurrency Animatable {
    var angle: Double
    var reach: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let facing = cos(angle)
        content
            .scaleEffect(x: max(0.01, abs(facing)), y: 1)
            .offset(x: sin(angle) * reach)
            .opacity(facing > 0.02 ? 1 : 0)
    }
}

private struct OwlBodyLayer: View {
    let colours: OwlPalette.Colours
    let curl: Bool

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let detailed = size.width >= 30
            let outline = max(1, size.width * 0.025)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
            func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (x - w / 2) * size.width, y: (y - h / 2) * size.height,
                                       width: w * size.width, height: h * size.height))
            }

            // Feet: three toes each, peeking out below.
            for x in [0.42, 0.58] as [CGFloat] {
                for t in [-1, 0, 1] as [CGFloat] {
                    context.fill(oval(x + t * 0.03, 0.93, 0.032, 0.055), with: .color(colours.feet))
                }
            }
            if curl && detailed {
                let tuft = Path(OwlGeometry.curl(in: rect))
                context.stroke(tuft, with: .color(colours.outline),
                               style: StrokeStyle(lineWidth: size.width * 0.035 + outline * 2, lineCap: .round))
                context.stroke(tuft, with: .color(colours.bodyTop), style: StrokeStyle(lineWidth: size.width * 0.035, lineCap: .round))
            }
            let pebble = Path(OwlGeometry.pebble(in: rect))
            context.stroke(pebble, with: .color(colours.outline), lineWidth: outline * 2)
            context.fill(pebble, with: .linearGradient(Gradient(colors: [colours.bodyTop, colours.bodyBottom]),
                                                       startPoint: p(0.5, 0.1), endPoint: p(0.5, 0.92)))
            context.fill(oval(0.5, 0.75, 0.36, 0.3), with: .color(colours.belly))
            if detailed {
                // A few chevron speckles on the chest, and pale ones on the crown.
                for (x, y) in [(0.45, 0.69), (0.56, 0.71), (0.5, 0.78), (0.43, 0.83), (0.58, 0.84)] as [(CGFloat, CGFloat)] {
                    var v = Path()
                    v.move(to: p(x - 0.022, y - 0.012))
                    v.addLine(to: p(x, y))
                    v.addLine(to: p(x + 0.022, y - 0.012))
                    context.stroke(v, with: .color(colours.speckle.opacity(0.6)),
                                   style: StrokeStyle(lineWidth: size.width * 0.012, lineCap: .round, lineJoin: .round))
                }
                for (x, y) in [(0.38, 0.15), (0.5, 0.125), (0.62, 0.15)] as [(CGFloat, CGFloat)] {
                    context.fill(oval(x, y, 0.022, 0.022), with: .color(.white.opacity(0.55)))
                }
            }
        }
    }
}

private struct WingLayer: View {
    let colours: OwlPalette.Colours
    let side: CGFloat

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let wing = Path(OwlGeometry.wing(in: rect, side: side))
            context.stroke(wing, with: .color(colours.outline.opacity(0.6)), lineWidth: max(0.5, size.width * 0.012))
            context.fill(wing, with: .linearGradient(Gradient(colors: [colours.wingTop, colours.wingBottom]),
                                                     startPoint: CGPoint(x: 0, y: size.height * 0.5),
                                                     endPoint: CGPoint(x: 0, y: size.height * 0.85)))
            if size.width >= 30 {
                // Three feather tips.
                for (index, y) in [0.62, 0.7, 0.78].enumerated() {
                    let x = 0.5 + side * (0.31 - CGFloat(index) * 0.022)
                    var tip = Path()
                    tip.move(to: CGPoint(x: x * size.width, y: CGFloat(y) * size.height))
                    tip.addLine(to: CGPoint(x: (x - side * 0.045) * size.width, y: (CGFloat(y) + 0.03) * size.height))
                    context.stroke(tip, with: .color(colours.wingBottom.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: size.width * 0.012, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct OwlFaceLayer: View {
    enum Eyes { case open, closed, happy, hearts, dizzy }

    let colours: OwlPalette.Colours
    let eyes: Eyes
    let lids: CGFloat
    let look: CGVector
    let surprised: Bool
    let yawn: CGFloat
    let sunglasses: Bool

    var body: some View {
        if eyes == .dizzy {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                face(spin: context.date.timeIntervalSinceReferenceDate * 6)
            }
        } else {
            face(spin: 0)
        }
    }

    private func face(spin: Double) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let detailed = size.width >= 30
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
            func oval(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            }

            // The heart-shaped disc: brightest in the middle, a russet rim and
            // a soft ruff just inside it.
            let disc = Path(OwlGeometry.face(in: rect))
            context.fill(disc, with: .radialGradient(Gradient(colors: [.white, colours.face]), center: p(0.5, 0.45),
                                                     startRadius: 0, endRadius: size.width * 0.3))
            context.stroke(disc, with: .color(colours.rim), lineWidth: max(1, size.width * 0.025))
            if detailed {
                var ruff = context
                ruff.clip(to: disc)
                ruff.stroke(disc, with: .color(colours.rim.opacity(0.22)), lineWidth: size.width * 0.06)
            }
            for x in [0.325, 0.675] as [CGFloat] {
                context.fill(oval(p(x, 0.485), size.width * 0.09, size.height * 0.04), with: .color(colours.blush.opacity(0.4)))
            }

            let (left, right) = OwlGeometry.eyeCentres(in: rect)
            let ink = colours.eye
            let width = size.width
            for (index, centre) in [left, right].enumerated() {
                switch eyes {
                case .open:
                    let d = width * 0.1 * (surprised ? 1.2 : 1)
                    let shift = CGPoint(x: max(-1, min(1, look.dx)) * width * 0.012,
                                        y: max(-1, min(1, look.dy)) * width * 0.01)
                    let iris = CGPoint(x: centre.x + shift.x, y: centre.y + shift.y)
                    context.fill(oval(iris, d, d * 1.08), with: .color(ink))
                    context.fill(oval(CGPoint(x: iris.x - d * 0.2, y: iris.y - d * 0.22), d * 0.34, d * 0.34), with: .color(.white))
                    if detailed {
                        context.fill(oval(CGPoint(x: iris.x + d * 0.2, y: iris.y + d * 0.2), d * 0.14, d * 0.14),
                                     with: .color(.white.opacity(0.7)))
                    }
                    if lids > 0.01 {
                        // Drowsy: the lid slides down over the eye.
                        let box = CGRect(x: centre.x - d * 0.75, y: centre.y - d * 0.75, width: d * 1.5, height: d * 1.5 * min(1, lids))
                        context.fill(Path(box), with: .color(colours.face))
                        var lash = Path()
                        lash.move(to: CGPoint(x: box.minX + d * 0.2, y: box.maxY))
                        lash.addLine(to: CGPoint(x: box.maxX - d * 0.2, y: box.maxY))
                        context.stroke(lash, with: .color(ink), style: StrokeStyle(lineWidth: max(1, width * 0.02), lineCap: .round))
                    }
                case .closed:
                    var lid = Path()
                    lid.move(to: CGPoint(x: centre.x - width * 0.05, y: centre.y))
                    lid.addQuadCurve(to: CGPoint(x: centre.x + width * 0.05, y: centre.y),
                                     control: CGPoint(x: centre.x, y: centre.y + width * 0.045))
                    context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: max(1.2, width * 0.022), lineCap: .round))
                case .happy:
                    var arc = Path()
                    arc.move(to: CGPoint(x: centre.x - width * 0.05, y: centre.y + width * 0.015))
                    arc.addQuadCurve(to: CGPoint(x: centre.x + width * 0.05, y: centre.y + width * 0.015),
                                     control: CGPoint(x: centre.x, y: centre.y - width * 0.055))
                    context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, width * 0.025), lineCap: .round))
                case .hearts:
                    context.fill(Path(heartPath(centre: centre, size: width * 0.12)), with: .color(Color(hex: 0xFF4D6D)))
                case .dizzy:
                    // Spinning spirals, each eye the other way round.
                    var spiral = Path()
                    let turns = 2.3
                    for step in 0...40 {
                        let t = Double(step) / 40
                        let angle = t * turns * 2 * .pi + spin * (index == 0 ? 1 : -1)
                        let radius = width * 0.055 * t
                        let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
                        step == 0 ? spiral.move(to: point) : spiral.addLine(to: point)
                    }
                    context.stroke(spiral, with: .color(ink), style: StrokeStyle(lineWidth: max(1, width * 0.015), lineCap: .round))
                }
            }
            if sunglasses {
                // Cool shades for presenting.
                for centre in [left, right] {
                    let lens = Path(roundedRect: CGRect(x: centre.x - width * 0.08, y: centre.y - width * 0.055,
                                                        width: width * 0.16, height: width * 0.11), cornerRadius: width * 0.035)
                    context.fill(lens, with: .linearGradient(Gradient(colors: [Color(hex: 0x2A2A35), Color(hex: 0x0E0E14)]),
                                                             startPoint: CGPoint(x: centre.x, y: centre.y - width * 0.05),
                                                             endPoint: CGPoint(x: centre.x, y: centre.y + width * 0.05)))
                    var glint = Path()
                    glint.move(to: CGPoint(x: centre.x - width * 0.05, y: centre.y - width * 0.02))
                    glint.addLine(to: CGPoint(x: centre.x - width * 0.02, y: centre.y - width * 0.04))
                    context.stroke(glint, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: max(1, width * 0.012), lineCap: .round))
                }
                var bridge = Path()
                bridge.move(to: CGPoint(x: left.x + width * 0.08, y: left.y - width * 0.02))
                bridge.addQuadCurve(to: CGPoint(x: right.x - width * 0.08, y: right.y - width * 0.02),
                                    control: CGPoint(x: (left.x + right.x) / 2, y: left.y - width * 0.045))
                context.stroke(bridge, with: .color(Color(hex: 0x0E0E14)), lineWidth: max(1, width * 0.015))
            }
            // A yawn opens below the beak.
            if yawn > 0.01 {
                let mouth = CGRect(x: p(0.5, 0).x - width * 0.035, y: p(0, 0.5).y,
                                   width: width * 0.07, height: size.height * 0.085 * yawn)
                context.fill(Path(ellipseIn: mouth), with: .color(Color(hex: 0x5A2230)))
                context.fill(Path(ellipseIn: CGRect(x: mouth.minX + mouth.width * 0.2, y: mouth.midY,
                                                    width: mouth.width * 0.6, height: mouth.height * 0.45)),
                             with: .color(Color(hex: 0xFF8FA3)))
            }
            context.fill(Path(OwlGeometry.beak(in: rect).copy(using: [CGAffineTransform(translationX: 0, y: -size.height * 0.02 * yawn)])!),
                         with: .linearGradient(Gradient(colors: [colours.beak, colours.beak.mix(with: colours.rim, by: 0.3)]),
                                               startPoint: p(0.5, 0.445), endPoint: p(0.5, 0.515)))
        }
    }

    private func heartPath(centre: CGPoint, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let s = size / 2
        path.move(to: CGPoint(x: centre.x, y: centre.y + s * 0.9))
        path.addCurve(to: CGPoint(x: centre.x - s, y: centre.y - s * 0.2),
                      control1: CGPoint(x: centre.x - s * 0.4, y: centre.y + s * 0.5),
                      control2: CGPoint(x: centre.x - s, y: centre.y + s * 0.2))
        path.addArc(center: CGPoint(x: centre.x - s * 0.5, y: centre.y - s * 0.3), radius: s * 0.52,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        path.addArc(center: CGPoint(x: centre.x + s * 0.5, y: centre.y - s * 0.3), radius: s * 0.52,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        path.addCurve(to: CGPoint(x: centre.x, y: centre.y + s * 0.9),
                      control1: CGPoint(x: centre.x + s, y: centre.y + s * 0.2),
                      control2: CGPoint(x: centre.x + s * 0.4, y: centre.y + s * 0.5))
        path.closeSubpath()
        return path
    }
}

/// Hats, drawn on top of the head. The canvas reaches above the owl, so a
/// tall hat isn't cut off.
private struct HatLayer: View {
    let accessory: OwlAccessory

    /// How far above the owl's frame the hat may reach, as a fraction of it.
    private static let headroom: CGFloat = 0.3

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            Canvas { context, _ in
                // Owl coordinates: 0…1 across the owl, y may go below 0.
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * side, y: (y + Self.headroom) * side) }
                func pompom(_ x: CGFloat, _ y: CGFloat, _ colour: Color) {
                    let r = side * 0.045
                    context.fill(Path(ellipseIn: CGRect(x: p(x, y).x - r, y: p(x, y).y - r, width: r * 2, height: r * 2)),
                                 with: .color(colour))
                }
                let outline = Color.black.opacity(0.35)
                switch accessory {
                case .partyHat:
                    var cone = Path()
                    cone.move(to: p(0.35, 0.165))
                    cone.addLine(to: p(0.57, -0.13))
                    cone.addLine(to: p(0.65, 0.14))
                    cone.addQuadCurve(to: p(0.35, 0.165), control: p(0.5, 0.2))
                    cone.closeSubpath()
                    context.stroke(cone, with: .color(outline), lineWidth: side * 0.02)
                    context.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: 0xFF5C8A), Color(hex: 0x8C87FF)]),
                                                             startPoint: p(0.57, -0.13), endPoint: p(0.5, 0.17)))
                    var stripes = context
                    stripes.clip(to: cone)
                    for (y, colour) in [(-0.04, 0xFFE27A), (0.05, 0x5ED3B5)] as [(CGFloat, UInt32)] {
                        var band = Path()
                        band.move(to: p(0.3, y + 0.03))
                        band.addLine(to: p(0.7, y - 0.03))
                        stripes.stroke(band, with: .color(Color(hex: colour)), lineWidth: side * 0.035)
                    }
                    pompom(0.57, -0.13, Color(hex: 0xFFE27A))
                case .nightcap, .santaHat:
                    let santa = accessory == .santaHat
                    let main = santa ? Color(hex: 0xE23B3B) : Color(hex: 0x6E68EA)
                    let trim = santa ? Color.white : Color(hex: 0xF7EBD4)
                    var cap = Path()
                    cap.move(to: p(0.29, 0.14))
                    cap.addCurve(to: p(0.86, 0.22), control1: p(0.3, -0.12), control2: p(0.7, -0.14))
                    cap.addCurve(to: p(0.71, 0.13), control1: p(0.8, 0.1), control2: p(0.76, 0.1))
                    cap.closeSubpath()
                    context.stroke(cap, with: .color(outline), lineWidth: side * 0.02)
                    context.fill(cap, with: .linearGradient(Gradient(colors: [main, main.mix(with: .black, by: 0.18)]),
                                                            startPoint: p(0.4, -0.1), endPoint: p(0.8, 0.2)))
                    if !santa {
                        var stripes = context
                        stripes.clip(to: cap)
                        for x in [0.44, 0.6, 0.76] as [CGFloat] {
                            var band = Path()
                            band.move(to: p(x - 0.06, -0.2))
                            band.addLine(to: p(x + 0.06, 0.3))
                            stripes.stroke(band, with: .color(Color(hex: 0x8C87FF)), lineWidth: side * 0.045)
                        }
                    }
                    let brim = Path(roundedRect: CGRect(x: p(0.26, 0).x, y: p(0, 0.1).y, width: side * 0.48, height: side * 0.075),
                                    cornerRadius: side * 0.0375)
                    context.stroke(brim, with: .color(outline), lineWidth: side * 0.015)
                    context.fill(brim, with: .color(trim))
                    pompom(0.86, 0.22, trim)
                case .none, .sunglasses:
                    break
                }
            }
            .frame(width: side, height: side * (1 + Self.headroom))
            .offset(y: -side * Self.headroom)
        }
        .allowsHitTesting(false)
    }
}

/// Knows where a SwiftUI view is on screen, through a plain NSView behind it.
@MainActor
final class ScreenAnchor {
    weak var view: NSView?

    var screenCentre: CGPoint? {
        guard let view, let window = view.window else { return nil }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}

struct ScreenAnchorView: NSViewRepresentable {
    let anchor: ScreenAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

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
    /// Selections, switches and buttons everywhere: always the owl's
    /// lavender, whatever accent colour macOS is set to.
    static let accent = lavender
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

/// Shared measurements, so every surface has the same shape.
enum Theme {
    /// Floating panels: the Perch, quick panel, search, clipboard, the Nest.
    static let panelRadius: CGFloat = 20
    /// Groups inside a panel or window: cards, tiles.
    static let cardRadius: CGFloat = 14
    /// Rows, chips and small controls.
    static let rowRadius: CGFloat = 9
}

extension View {
    /// What every floating panel wears: Liquid Glass with a breath of dusk,
    /// the owl's accent, and a soft shadow (the window draws none, as it's
    /// larger than the glass).
    func owlPanel() -> some View {
        self
            .tint(Brand.accent)
            .glassEffect(.regular.tint(Brand.indigo.opacity(0.10)), in: .rect(cornerRadius: Theme.panelRadius))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

/// A dusk sky with a few softly twinkling stars.
struct DuskSky: View {
    /// Tonight's moon in the corner; off where it would look like a button.
    var showsMoon = true

    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (0.08, 0.12, 2.5, 0), (0.22, 0.06, 1.8, 0.7), (0.37, 0.18, 1.5, 1.4), (0.61, 0.08, 2.2, 0.3),
        (0.78, 0.15, 1.6, 1.1), (0.91, 0.07, 2.4, 1.8), (0.86, 0.32, 1.4, 0.5), (0.14, 0.34, 1.6, 2.1),
        (0.48, 0.05, 1.3, 1.6), (0.70, 0.26, 1.2, 2.4),
    ]

    @State private var visible = false

    var body: some View {
        ZStack {
            Brand.dusk
            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: 1 / 10, paused: !visible)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                        Circle()
                            .fill(.white)
                            .frame(width: star.size, height: star.size)
                            .opacity(0.45 + 0.4 * sin(time * 1.3 + star.delay * 2))
                            .position(x: star.x * proxy.size.width, y: star.y * proxy.size.height)
                    }
                }
                // Tonight's moon, as it really is.
                if showsMoon {
                    Moon(phase: Moon.phase(on: .now))
                        .frame(width: max(14, min(26, proxy.size.width * 0.04)))
                        .position(x: proxy.size.width * 0.88, y: proxy.size.height * 0.16)
                }
            }
        }
        .ignoresSafeArea()
        .background(VisibilityReader { visible = $0 })
        .accessibilityHidden(true)
    }
}

/// The moon in a given phase: 0 new, 0.25 first quarter, 0.5 full, 0.75 last
/// quarter. Worked out from the date alone, no internet needed.
struct Moon: View {
    let phase: Double

    /// The phase on a date, from a known new moon (6 January 2000, 18:14 UTC)
    /// and the length of a lunar month.
    static func phase(on date: Date) -> Double {
        let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)
        let synodicMonth = 29.530588853 * 86_400
        let cycles = date.timeIntervalSince(knownNewMoon) / synodicMonth
        return cycles - floor(cycles)
    }

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            // The dark part, faintly.
            context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.08)))
            // The lit part: half a disc on the sunny side, closed by the
            // terminator, a half ellipse whose width follows the phase.
            let waxing = phase < 0.5
            let k = cos(phase * 2 * .pi)
            var lit = Path()
            let steps = 48
            for step in 0...steps {
                let angle = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
                let x = centre.x + (waxing ? 1 : -1) * r * cos(angle)
                let y = centre.y + r * sin(angle)
                step == 0 ? lit.move(to: CGPoint(x: x, y: y)) : lit.addLine(to: CGPoint(x: x, y: y))
            }
            for step in 0...steps {
                let angle = Double.pi / 2 - Double.pi * Double(step) / Double(steps)
                let x = centre.x + (waxing ? 1 : -1) * k * r * cos(angle)
                let y = centre.y + r * sin(angle)
                lit.addLine(to: CGPoint(x: x, y: y))
            }
            lit.closeSubpath()
            context.addFilter(.shadow(color: Brand.amber.opacity(0.6), radius: r * 0.6))
            context.fill(lit, with: .color(Color(hex: 0xFFE2A8)))
        }
        .aspectRatio(1, contentMode: .fit)
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

/// What the owl is wearing: something on its head, something on its eyes,
/// and something it holds.
struct OwlOutfit: Equatable {
    enum Hat { case none, party, nightcap, santa, witch, headset }
    enum Eyewear { case none, shades, glasses }
    enum Prop { case none, coffee, twoCoffees, thermos, blanket }

    var hat = Hat.none
    var eyewear = Eyewear.none
    var prop = Prop.none

    static let none = OwlOutfit()
    static let sunglasses = OwlOutfit(eyewear: .shades)
    static let glasses = OwlOutfit(eyewear: .glasses)
    static let partyHat = OwlOutfit(hat: .party)
    static let nightcap = OwlOutfit(hat: .nightcap)
    static let santaHat = OwlOutfit(hat: .santa)
    static let witchHat = OwlOutfit(hat: .witch)
    static let headset = OwlOutfit(hat: .headset)
    static let coffee = OwlOutfit(prop: .coffee)
    static let twoCoffees = OwlOutfit(prop: .twoCoffees)
    static let thermos = OwlOutfit(prop: .thermos)
    static let blanket = OwlOutfit(prop: .blanket)

    /// Both outfits together; the right-hand one wins where they clash.
    static func + (lhs: OwlOutfit, rhs: OwlOutfit) -> OwlOutfit {
        OwlOutfit(hat: rhs.hat == .none ? lhs.hat : rhs.hat,
                  eyewear: rhs.eyewear == .none ? lhs.eyewear : rhs.eyewear,
                  prop: rhs.prop == .none ? lhs.prop : rhs.prop)
    }

    /// A surprise for the day: a witch hat at Halloween, a Santa hat in
    /// December, a party hat at New Year and on Barn Owl's birthday.
    static var seasonal: OwlOutfit {
        let day = Calendar.current.dateComponents([.month, .day], from: .now)
        switch (day.month ?? 0, day.day ?? 0) {
        case (10, 31): return .witchHat
        case (12, _): return .santaHat
        case (1, 1...3): return .partyHat
        case (OwlOutfit.birthday.month, OwlOutfit.birthday.day): return .partyHat
        default: return .none
        }
    }

    /// Barn Owl 0.7.0, the first owl, came out on 17 October 2026.
    static let birthday = (month: 10, day: 17)
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
    /// 0 to 1, how wide it yawns (or opens its beak for a snack).
    var yawn: CGFloat = 0
    var accessory: OwlOutfit = .none
    /// Wings over the eyes: "I didn't see that!"
    var coverEyes = false
    /// A wing over the beak: "Shh!"
    var shush = false
    /// Eyes that glow in the dark.
    var glowEyes = false
    /// Bags under the eyes.
    var tired = false
    /// A colour shown on the chest for a moment.
    var bellyTint: Color?
    /// Ducks the head down, 0 to 1, for nods and peekaboo.
    var faceDip: CGFloat = 0
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
                OwlBodyLayer(colours: colours, curl: accessory.hat == .none)
                Ellipse()
                    .fill(bellyTint ?? .clear)
                    .frame(width: side * 0.36, height: side * 0.3)
                    .position(x: side * 0.5, y: side * 0.75)
                    .opacity(bellyTint == nil ? 0 : 0.92)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    WingLayer(colours: colours, side: side)
                        .rotationEffect(.degrees(Double(wingLift) * 95 * -side), anchor: OwlGeometry.shoulder(side: side))
                }
                if accessory.prop != .none { PropLayer(prop: accessory.prop, colours: colours) }
                Group {
                    OwlFaceLayer(colours: colours, eyes: eyeState, lids: lids, look: look, surprised: surprised,
                                 yawn: yawn, eyewear: accessory.eyewear, coverEyes: coverEyes, shush: shush,
                                 glowEyes: glowEyes, tired: tired)
                        .modifier(HeadTurn(angle: turn, reach: side * 0.22))
                        .offset(x: max(-1, min(1, look.dx)) * side * 0.018, y: max(-1, min(1, look.dy)) * side * 0.012)
                    HatLayer(hat: accessory.hat)
                }
                .offset(y: faceDip * side * 0.06)
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
        .animation(.easeInOut(duration: 0.4), value: bellyTint)
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
    let eyewear: OwlOutfit.Eyewear
    let coverEyes: Bool
    let shush: Bool
    let glowEyes: Bool
    let tired: Bool

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
                    if glowEyes {
                        // Eyes that glow in the dark.
                        context.fill(oval(centre, d * 2.1, d * 2.1),
                                     with: .radialGradient(Gradient(colors: [Brand.amber.opacity(0.85), Brand.amber.opacity(0)]),
                                                           center: centre, startRadius: d * 0.3, endRadius: d * 1.05))
                    }
                    let shift = CGPoint(x: max(-1, min(1, look.dx)) * width * 0.012,
                                        y: max(-1, min(1, look.dy)) * width * 0.01)
                    let iris = CGPoint(x: centre.x + shift.x, y: centre.y + shift.y)
                    context.fill(oval(iris, d, d * 1.08), with: .color(glowEyes ? Color(hex: 0x3A2410) : ink))
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
            if tired {
                // Bags under the eyes.
                for centre in [left, right] {
                    var bag = Path()
                    bag.move(to: CGPoint(x: centre.x - width * 0.05, y: centre.y + width * 0.068))
                    bag.addQuadCurve(to: CGPoint(x: centre.x + width * 0.05, y: centre.y + width * 0.068),
                                     control: CGPoint(x: centre.x, y: centre.y + width * 0.1))
                    context.stroke(bag, with: .color(colours.rim.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: max(0.8, width * 0.012), lineCap: .round))
                }
            }
            if eyewear == .glasses {
                // Round reading glasses, for the big screen.
                let frame = Color(hex: 0x2A2140)
                for centre in [left, right] {
                    context.stroke(oval(centre, width * 0.15, width * 0.15), with: .color(frame),
                                   lineWidth: max(1, width * 0.016))
                }
                var bridge = Path()
                bridge.move(to: CGPoint(x: left.x + width * 0.075, y: left.y - width * 0.01))
                bridge.addQuadCurve(to: CGPoint(x: right.x - width * 0.075, y: right.y - width * 0.01),
                                    control: CGPoint(x: (left.x + right.x) / 2, y: left.y - width * 0.035))
                context.stroke(bridge, with: .color(frame), lineWidth: max(1, width * 0.014))
            }
            if coverEyes {
                // Wing tips over both eyes.
                for (index, centre) in [left, right].enumerated() {
                    let lean: CGFloat = index == 0 ? -0.35 : 0.35
                    let tip = Path(ellipseIn: CGRect(x: -width * 0.1, y: -width * 0.075, width: width * 0.2, height: width * 0.15))
                        .applying(CGAffineTransform(rotationAngle: lean).concatenating(
                            CGAffineTransform(translationX: centre.x, y: centre.y + width * 0.005)))
                    context.fill(tip, with: .linearGradient(Gradient(colors: [colours.wingTop, colours.wingBottom]),
                                                            startPoint: CGPoint(x: centre.x, y: centre.y - width * 0.07),
                                                            endPoint: CGPoint(x: centre.x, y: centre.y + width * 0.07)))
                    context.stroke(tip, with: .color(colours.outline.opacity(0.6)), lineWidth: max(0.5, width * 0.01))
                }
            }
            if eyewear == .shades {
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
            if shush {
                // A wing over the beak.
                let wing = Path(ellipseIn: CGRect(x: -width * 0.09, y: -width * 0.055, width: width * 0.18, height: width * 0.11))
                    .applying(CGAffineTransform(rotationAngle: -0.5).concatenating(
                        CGAffineTransform(translationX: width * 0.52, y: size.height * 0.49)))
                context.fill(wing, with: .linearGradient(Gradient(colors: [colours.wingTop, colours.wingBottom]),
                                                         startPoint: p(0.5, 0.44), endPoint: p(0.5, 0.55)))
                context.stroke(wing, with: .color(colours.outline.opacity(0.6)), lineWidth: max(0.5, width * 0.01))
            }
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
    let hat: OwlOutfit.Hat

    /// How far above the owl's frame the hat may reach, as a fraction of it.
    private nonisolated static let headroom: CGFloat = 0.3

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
                switch hat {
                case .party:
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
                case .nightcap, .santa:
                    let santa = hat == .santa
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
                case .witch:
                    let felt = Color(hex: 0x2B2140)
                    var cone = Path()
                    cone.move(to: p(0.34, 0.13))
                    cone.addCurve(to: p(0.64, -0.2), control1: p(0.42, 0.0), control2: p(0.5, -0.12))
                    cone.addQuadCurve(to: p(0.57, -0.05), control: p(0.6, -0.1))
                    cone.addQuadCurve(to: p(0.66, 0.13), control: p(0.6, 0.04))
                    cone.closeSubpath()
                    let brim = Path(ellipseIn: CGRect(x: p(0.17, 0).x, y: p(0, 0.095).y, width: side * 0.66, height: side * 0.085))
                    for shape in [brim, cone] {
                        context.stroke(shape, with: .color(outline), lineWidth: side * 0.02)
                        context.fill(shape, with: .linearGradient(Gradient(colors: [Color(hex: 0x4A3A6E), felt]),
                                                                  startPoint: p(0.6, -0.2), endPoint: p(0.5, 0.15)))
                    }
                    var band = context
                    band.clip(to: cone)
                    band.fill(Path(CGRect(x: 0, y: p(0, 0.06).y, width: side, height: side * 0.045)), with: .color(Brand.amber))
                    context.stroke(Path(CGRect(x: p(0.47, 0).x, y: p(0, 0.062).y, width: side * 0.06, height: side * 0.04)),
                                   with: .color(Color(hex: 0xFFE27A)), lineWidth: side * 0.012)
                case .headset:
                    let dark = Color(hex: 0x2A2A35)
                    var band = Path()
                    band.move(to: p(0.17, 0.4))
                    band.addQuadCurve(to: p(0.83, 0.4), control: p(0.5, -0.14))
                    context.stroke(band, with: .color(dark), style: StrokeStyle(lineWidth: side * 0.04, lineCap: .round))
                    for x in [0.135, 0.795] as [CGFloat] {
                        let cup = Path(roundedRect: CGRect(x: p(x, 0).x, y: p(0, 0.33).y, width: side * 0.07, height: side * 0.15),
                                       cornerRadius: side * 0.03)
                        context.fill(cup, with: .color(dark))
                        context.fill(Path(roundedRect: CGRect(x: p(x + 0.015, 0).x, y: p(0, 0.35).y, width: side * 0.04,
                                                              height: side * 0.11), cornerRadius: side * 0.02),
                                     with: .color(Brand.lavender))
                    }
                    var boom = Path()
                    boom.move(to: p(0.19, 0.47))
                    boom.addQuadCurve(to: p(0.39, 0.58), control: p(0.22, 0.6))
                    context.stroke(boom, with: .color(dark), style: StrokeStyle(lineWidth: side * 0.018, lineCap: .round))
                    pompom(0.4, 0.58, dark)
                case .none:
                    break
                }
            }
            .frame(width: side, height: side * (1 + Self.headroom))
            .offset(y: -side * Self.headroom)
        }
        .allowsHitTesting(false)
    }
}

/// What the owl holds: coffee, a thermos, or a blanket over its knees.
private struct PropLayer: View {
    let prop: OwlOutfit.Prop
    let colours: OwlPalette.Colours

    var body: some View {
        Canvas { context, size in
            let w = size.width
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * size.height) }
            let outline = colours.outline.opacity(0.7)
            func mug(at x: CGFloat, flip: Bool) {
                let body = Path(roundedRect: CGRect(x: p(x, 0).x, y: p(0, 0.7).y, width: w * 0.15, height: w * 0.15),
                                cornerRadius: w * 0.03)
                var handle = Path()
                let hx = flip ? p(x, 0).x : p(x + 0.15, 0).x
                handle.addArc(center: CGPoint(x: hx, y: p(0, 0.775).y), radius: w * 0.04,
                              startAngle: .degrees(flip ? 90 : -90), endAngle: .degrees(flip ? 270 : 90), clockwise: false)
                context.stroke(handle, with: .color(outline), lineWidth: w * 0.03)
                context.stroke(handle, with: .color(Color(hex: 0xFFF7E8)), lineWidth: w * 0.017)
                context.stroke(body, with: .color(outline), lineWidth: max(0.8, w * 0.014))
                context.fill(body, with: .color(Color(hex: 0xFFF7E8)))
                context.fill(Path(CGRect(x: p(x, 0).x, y: p(0, 0.755).y, width: w * 0.15, height: w * 0.03)), with: .color(Brand.amber))
                context.fill(Path(ellipseIn: CGRect(x: p(x + 0.015, 0).x, y: p(0, 0.695).y, width: w * 0.12, height: w * 0.03)),
                             with: .color(Color(hex: 0x6B3E1F)))
                // Steam.
                for dx in [0.045, 0.095] as [CGFloat] {
                    var steam = Path()
                    steam.move(to: p(x + dx, 0.685))
                    steam.addCurve(to: p(x + dx, 0.6), control1: p(x + dx - 0.03, 0.66), control2: p(x + dx + 0.03, 0.63))
                    context.stroke(steam, with: .color(.white.opacity(0.7)),
                                   style: StrokeStyle(lineWidth: max(0.8, w * 0.012), lineCap: .round))
                }
            }
            switch prop {
            case .coffee:
                mug(at: 0.62, flip: false)
            case .twoCoffees:
                mug(at: 0.62, flip: false)
                mug(at: 0.23, flip: true)
            case .thermos:
                let flask = Path(roundedRect: CGRect(x: p(0.63, 0).x, y: p(0, 0.62).y, width: w * 0.14, height: w * 0.26),
                                 cornerRadius: w * 0.04)
                context.stroke(flask, with: .color(outline), lineWidth: max(0.8, w * 0.014))
                context.fill(flask, with: .linearGradient(Gradient(colors: [Brand.indigo, Brand.indigoDeep]),
                                                          startPoint: p(0.63, 0.62), endPoint: p(0.77, 0.88)))
                context.fill(Path(CGRect(x: p(0.63, 0).x, y: p(0, 0.72).y, width: w * 0.14, height: w * 0.035)),
                             with: .color(Brand.lavender))
                context.fill(Path(roundedRect: CGRect(x: p(0.645, 0).x, y: p(0, 0.585).y, width: w * 0.11, height: w * 0.05),
                                  cornerRadius: w * 0.015), with: .color(Color(hex: 0x9A92B0)))
            case .blanket:
                let quilt = Path(roundedRect: CGRect(x: p(0.12, 0).x, y: p(0, 0.66).y, width: w * 0.76, height: w * 0.31),
                                 cornerRadius: w * 0.08)
                context.stroke(quilt, with: .color(outline), lineWidth: max(0.8, w * 0.014))
                context.fill(quilt, with: .color(Brand.lavender))
                var stripes = context
                stripes.clip(to: quilt)
                for x in stride(from: 0.16, to: 0.9, by: 0.12) {
                    stripes.fill(Path(CGRect(x: p(x, 0).x, y: 0, width: w * 0.05, height: size.height)),
                                 with: .color(Color(hex: 0x6E68EA).opacity(0.6)))
                }
                stripes.fill(Path(CGRect(x: 0, y: p(0, 0.66).y, width: w, height: w * 0.06)), with: .color(Brand.cream))
            case .none:
                break
            }
        }
        .allowsHitTesting(false)
    }
}

/// Knows where a SwiftUI view is on screen, and whether its window is
/// visible, through a plain NSView behind it.
@MainActor
@Observable
final class ScreenAnchor {
    @ObservationIgnored weak var view: NSView?
    /// The window is on screen and not completely covered.
    var isVisible = false

    var screenCentre: CGPoint? {
        guard let view, let window = view.window else { return nil }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Space between the view and the edges of its window.
    var roomInWindow: EdgeInsets? {
        guard let view, let content = view.window?.contentView else { return nil }
        let frame = view.convert(view.bounds, to: content)
        let bounds = content.bounds
        let top = content.isFlipped ? frame.minY - bounds.minY : bounds.maxY - frame.maxY
        let bottom = content.isFlipped ? bounds.maxY - frame.maxY : frame.minY - bounds.minY
        return EdgeInsets(top: top, leading: frame.minX - bounds.minX, bottom: bottom,
                          trailing: bounds.maxX - frame.maxX)
    }
}

struct ScreenAnchorView: NSViewRepresentable {
    let anchor: ScreenAnchor

    func makeNSView(context: Context) -> NSView {
        let view = VisibilityTrackingView { [weak anchor] visible in anchor?.isVisible = visible }
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// Calls back with whether a view's window is visible, so animations can
/// stop when nobody can see them.
struct VisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityTrackingView { VisibilityTrackingView(onChange: onChange) }
    func updateNSView(_ nsView: VisibilityTrackingView, context: Context) {}
}

/// A view that's only there to be measured and to watch its window; clicks
/// go to whatever is around it.
final class VisibilityTrackingView: NSView {
    private let onChange: (Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var reported: Bool?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return report(false) }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
            let closing = name == NSWindow.willCloseNotification
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(closing: closing) }
            })
        }
        update(closing: false)
    }

    private func update(closing: Bool) {
        report(!closing && (window?.occlusionState.contains(.visible) ?? false))
    }

    private func report(_ visible: Bool) {
        guard visible != reported else { return }
        reported = visible
        // Not in the middle of a SwiftUI update.
        DispatchQueue.main.async { [onChange] in onChange(visible) }
    }
}

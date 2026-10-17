import SwiftUI

/// The owl with some personality. It watches the pointer, breathes and
/// blinks, and reacts to what happens:
///
/// - click: a hoot and a hop; three quick clicks: it turns its head all the
///   way round; keep clicking and it gets dizzy;
/// - press and hold: it loves being petted;
/// - eyes opening (keep awake starts): a big wide-awake stretch; eyes
///   closing: a yawn, then it nods off and snores;
/// - left alone for a while it gets drowsy, and startles when you're back;
///   now and then it dances or stretches.
struct WatchingOwl: View {
    enum Entrance {
        case none
        /// Flaps hello and hoots.
        case greet
        /// Hops for joy, flapping, turns round, feathers and confetti fly.
        case celebrate
        /// Tilts its head: "?"
        case puzzled
    }

    var eyesOpen = true
    var surprised = false
    var happy = false
    /// How far (in points) the pointer must be for the eyes to look all the way.
    var reach: CGFloat = 220
    /// Follows the pointer with its eyes and head.
    var watches = true
    /// Reacts to clicks, gets drowsy and does things by itself.
    var playful = true
    /// Shows drifting z's while the eyes are shut.
    var snores = true
    /// Says things in a speech bubble. Off where the text around it already
    /// says it.
    var talks = true
    var accessory: OwlAccessory?
    /// nil uses the colours chosen in Settings.
    var palette: OwlPalette?
    var entrance: Entrance = .none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = ScreenAnchor()
    @State private var tilt: Double = 0
    @State private var turn: Double = 0
    @State private var hop: CGFloat = 0
    @State private var squash: CGFloat = 1
    @State private var sway: Double = 0
    @State private var wingLift: CGFloat = 0
    @State private var yawn: CGFloat = 0
    @State private var lids: CGFloat = 0
    @State private var bubble: String?
    @State private var bubbleID = 0
    @State private var cheering = false
    @State private var loving = false
    @State private var dizzy = false
    @State private var roused = false
    @State private var dozing = false
    @State private var stunned = false
    @State private var clicks: [Date] = []
    @State private var bursts: [Burst] = []
    @State private var pressing = false

    /// Eyes open as far as the owl itself is concerned: it stays awake a
    /// moment longer to yawn first.
    private var awake: Bool { eyesOpen || roused || dozing }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion && !watches)) { context in
                let look = watches && awake && lids < 0.5 ? direction() : .zero
                let breath = reduceMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate * (awake ? 1.9 : 1.1))
                let depth: CGFloat = awake ? 0.012 : 0.024
                OwlView(eyesOpen: awake, look: look, surprised: surprised || roused || stunned, happy: happy || cheering,
                        hearts: loving, dizzy: dizzy, lids: lids, wingLift: wingLift, turn: turn, tilt: tilt, yawn: yawn,
                        accessory: accessory ?? (side >= 40 ? .seasonal : .none), palette: palette)
                    .scaleEffect(x: 1 + depth * 0.7 * breath, y: 1 - depth * breath, anchor: .bottom)
            }
            .rotationEffect(.degrees(sway), anchor: .bottom)
            .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
            .offset(y: hop)
            .frame(width: side, height: side)
            .overlay {
                if snores && !awake && !reduceMotion && side >= 30 { Snore() }
            }
            .overlay {
                if dizzy { OrbitingStars(side: side) }
            }
            .overlay {
                BurstsView(bursts: bursts, side: side)
            }
            .overlay(alignment: .topLeading) {
                if talks, let bubble {
                    // Grows to the right from just above the owl's shoulder.
                    let fontSize = max(10, min(22, side * 0.14))
                    SpeechBubble(text: bubble, fontSize: fontSize)
                        .fixedSize()
                        .offset(x: side * 0.7, y: side * 0.1 - fontSize * 1.9)
                        .transition(.scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(ScreenAnchorView(anchor: anchor))
        // Only a playful owl takes clicks; otherwise they pass through to
        // whatever it sits in, such as a button.
        .modifier(OwlGestures(enabled: playful, tap: poke, hold: pet))
        .onChange(of: surprised) { _, now in if now { notice() } }
        .onChange(of: eyesOpen) { _, now in now ? wakeUp() : doze() }
        .onChange(of: happy) { _, now in if now { catchIt() } }
        .task(id: playful && awake && !reduceMotion) { await liveALittle() }
        .task { await perform(entrance) }
        .accessibilityHidden(true)
    }

    private func direction() -> CGVector {
        guard let centre = anchor.screenCentre else { return .zero }
        let mouse = NSEvent.mouseLocation
        // Screen y grows upwards; the owl's eyes look down for positive dy.
        return CGVector(dx: max(-1, min(1, (mouse.x - centre.x) / reach)),
                        dy: max(-1, min(1, (centre.y - mouse.y) / reach)))
    }

    // MARK: Reactions

    private func poke() {
        let now = Date()
        clicks = clicks.filter { now.timeIntervalSince($0) < 2.5 } + [now]
        if dizzy { return }
        if !awake {
            // Woken up: a startled look, then back to sleep.
            roused = true
            say("Hm?", for: 1.6)
            bounce(height: 4)
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                roused = false
            }
        } else if clicks.count >= 6 {
            clicks = []
            getDizzy()
        } else if clicks.count == 3 {
            say("Whoa!", for: 1.4)
            turnRound()
        } else if clicks.count < 3 {
            say(["Hoo!", "Hoo hoo!", "Hoot!", "Hi there!", "Who? Me?"].randomElement()!, for: 1.1)
            cheer(for: 0.9)
            bounce(height: 9)
            flap(times: 2)
        } else {
            bounce(height: 5)
        }
    }

    private func pet() {
        guard awake, !dizzy else { return }
        loving = true
        say("♥", for: 1.4)
        burst(.hearts)
        wiggle()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            loving = false
        }
    }

    /// Keep awake started: eyes pop, a big stretch, sparkles.
    private func wakeUp() {
        guard !reduceMotion else { return }
        dozing = false
        stunned = true
        say("Wide awake!", for: 1.4)
        burst(.sparkles)
        Task {
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { wingLift = 1.3; squash = 1.08 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(duration: 0.5, bounce: 0.45)) { wingLift = 0; squash = 1 }
            try? await Task.sleep(for: .milliseconds(500))
            stunned = false
        }
    }

    /// Keep awake stopped: a big yawn, a stretch, then off to sleep.
    private func doze() {
        guard !reduceMotion else { return }
        dozing = true
        Task {
            withAnimation(.easeOut(duration: 0.5)) { yawn = 1; lids = 0.55; wingLift = 0.5; squash = 1.05 }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeIn(duration: 0.4)) { yawn = 0; wingLift = 0; squash = 1 }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeInOut(duration: 0.5)) { lids = 0.9 }
            try? await Task.sleep(for: .milliseconds(500))
            lids = 0
            dozing = false
        }
    }

    /// Something to look at: wide eyes, a lean, "Ooh!".
    private func notice() {
        say("Ooh!", for: 1.2)
        bounce(height: 7)
        flap(times: 1)
    }

    /// Something landed: a happy hop with sparkles.
    private func catchIt() {
        burst(.sparkles)
        bounce(height: 10)
        flap(times: 2)
    }

    private func getDizzy() {
        dizzy = true
        say("@_@", for: 2.2)
        Task {
            for _ in 0..<4 {
                withAnimation(.easeInOut(duration: 0.28)) { sway = 9 }
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(.easeInOut(duration: 0.28)) { sway = -9 }
                try? await Task.sleep(for: .milliseconds(280))
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { sway = 0 }
            dizzy = false
        }
    }

    private func wiggle() {
        guard !reduceMotion else { return }
        Task {
            for angle in [6.0, -6, 4, -3, 0] {
                withAnimation(.easeInOut(duration: 0.12)) { sway = angle }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func say(_ text: String, for seconds: Double) {
        bubbleID += 1
        let id = bubbleID
        withAnimation(.spring(duration: 0.35, bounce: 0.55)) { bubble = text }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if bubbleID == id { withAnimation(.easeOut(duration: 0.2)) { bubble = nil } }
        }
    }

    private func cheer(for seconds: Double) {
        cheering = true
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            cheering = false
        }
    }

    private func burst(_ kind: Burst.Kind) {
        guard !reduceMotion else { return }
        let new = Burst(kind: kind)
        bursts.append(new)
        Task {
            try? await Task.sleep(for: .seconds(new.duration))
            bursts.removeAll { $0.id == new.id }
        }
    }

    /// A squash, a hop and a bouncy landing.
    private func bounce(height: CGFloat) {
        guard !reduceMotion else { return }
        Task { await hopOnce(height: height) }
    }

    private func hopOnce(height: CGFloat) async {
        withAnimation(.easeOut(duration: 0.08)) { squash = 0.88 }
        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(.spring(duration: 0.22, bounce: 0.2)) { squash = 1.06; hop = -height }
        try? await Task.sleep(for: .milliseconds(190))
        withAnimation(.spring(duration: 0.4, bounce: 0.55)) { squash = 1; hop = 0 }
        try? await Task.sleep(for: .milliseconds(220))
    }

    private func flap(times: Int) {
        guard !reduceMotion else { return }
        Task { await flapWings(times: times) }
    }

    private func flapWings(times: Int) async {
        for _ in 0..<times {
            withAnimation(.easeOut(duration: 0.11)) { wingLift = 1 }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeIn(duration: 0.13)) { wingLift = 0 }
            try? await Task.sleep(for: .milliseconds(140))
        }
    }

    private func turnRound() {
        guard !reduceMotion else { return }
        withAnimation(.spring(duration: 1.2, bounce: 0.25)) { turn += 2 * .pi }
    }

    // MARK: Living

    /// The owl's own life: a curious tilt, a stretch or a little dance now
    /// and then. Left alone it gets drowsy, and startles when you're back.
    private func liveALittle() async {
        guard playful, awake, !reduceMotion else { return }
        defer { tilt = 0; lids = 0 }
        var lastMouse = NSEvent.mouseLocation
        var still: TimeInterval = 0
        var nextTrick = Date.now.addingTimeInterval(.random(in: 12...25))
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let mouse = NSEvent.mouseLocation
            if mouse != lastMouse {
                lastMouse = mouse
                if lids > 0.3 {
                    // Caught napping!
                    withAnimation(.spring(duration: 0.25)) { lids = 0 }
                    stunned = true
                    say("!", for: 0.9)
                    bounce(height: 8)
                    flap(times: 1)
                    try? await Task.sleep(for: .milliseconds(700))
                    stunned = false
                }
                still = 0
            } else {
                still += 1
            }
            if still >= 40 {
                // Nodding off: lids droop, the head dips, jerks back up.
                let droop = min(0.85, 0.35 + (still - 40) * 0.03)
                withAnimation(.easeInOut(duration: 0.9)) { lids = droop; tilt = droop > 0.7 ? 7 : 3 }
                if droop > 0.7, Int(still) % 6 == 0 {
                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) { lids = 0.3; tilt = 0 }
                }
                continue
            }
            guard Date.now >= nextTrick else { continue }
            nextTrick = Date.now.addingTimeInterval(.random(in: 20...40))
            switch Int.random(in: 0..<5) {
            case 0, 1:
                withAnimation(.spring(duration: 0.5, bounce: 0.35)) { tilt = .random(in: 10...16) * (Bool.random() ? 1 : -1) }
                try? await Task.sleep(for: .seconds(.random(in: 0.9...1.6)))
                withAnimation(.spring(duration: 0.6, bounce: 0.3)) { tilt = 0 }
            case 2:
                await flapWings(times: 1)
            case 3:
                // A stretch.
                withAnimation(.easeOut(duration: 0.4)) { wingLift = 1.2; squash = 1.06 }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) { wingLift = 0; squash = 1 }
            default:
                // A little dance.
                cheering = true
                for angle in [8.0, -8, 8, -8, 0] {
                    withAnimation(.easeInOut(duration: 0.2)) { sway = angle; hop = angle == 0 ? 0 : -3 }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                cheering = false
            }
        }
    }

    private func perform(_ entrance: Entrance) async {
        guard !reduceMotion else { return }
        switch entrance {
        case .none:
            return
        case .greet:
            try? await Task.sleep(for: .milliseconds(550))
            say("Hoo!", for: 1.3)
            async let wings: Void = flapWings(times: 3)
            await hopOnce(height: 10)
            await wings
        case .celebrate:
            try? await Task.sleep(for: .milliseconds(300))
            burst(.confetti)
            for _ in 0..<3 {
                async let wings: Void = flapWings(times: 2)
                await hopOnce(height: 16)
                await wings
            }
            say("Hoo-ray!", for: 1.8)
            burst(.feathers)
            turnRound()
        case .puzzled:
            try? await Task.sleep(for: .milliseconds(250))
            say("?", for: 1.6)
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { tilt = 14 }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { tilt = 0 }
        }
    }
}

private struct OwlGestures: ViewModifier {
    let enabled: Bool
    let tap: () -> Void
    let hold: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: tap)
                .onLongPressGesture(minimumDuration: 0.5, perform: hold)
        } else {
            content
        }
    }
}

// MARK: - Effects

/// A one-off shower of little things: hearts, sparkles, feathers or confetti.
struct Burst: Identifiable, Equatable {
    enum Kind { case hearts, sparkles, feathers, confetti }
    let kind: Kind
    let id = UUID()
    let start = Date()

    var duration: Double {
        switch kind {
        case .hearts, .sparkles: 1.4
        case .feathers, .confetti: 2.6
        }
    }
}

private struct BurstsView: View {
    let bursts: [Burst]
    let side: CGFloat

    var body: some View {
        if !bursts.isEmpty {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                Canvas { canvas, size in
                    for burst in bursts {
                        let t = context.date.timeIntervalSince(burst.start) / burst.duration
                        guard t >= 0, t <= 1 else { continue }
                        draw(burst, at: t, in: canvas, size: size)
                    }
                }
            }
            .frame(width: side * 2.2, height: side * 2.2)
            .allowsHitTesting(false)
        }
    }

    private func draw(_ burst: Burst, at t: Double, in canvas: GraphicsContext, size: CGSize) {
        var random = SeededRandom(seed: UInt64(truncatingIfNeeded: burst.id.hashValue))
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = burst.kind == .hearts ? 7 : burst.kind == .sparkles ? 10 : 16
        for _ in 0..<count {
            let angle = random.next(in: -Double.pi...0) // upwards
            let speed = random.next(in: 0.35...0.85)
            let delay = random.next(in: 0...0.25)
            let local = max(0, min(1, (t - delay) / (1 - delay)))
            guard local > 0 else { continue }
            let fade = local > 0.7 ? (1 - local) / 0.3 : 1
            let spin = random.next(in: -4...4)
            var point: CGPoint
            switch burst.kind {
            case .hearts:
                point = CGPoint(x: centre.x + cos(angle) * side * 0.25 * speed + sin(local * 9 + speed * 7) * side * 0.04,
                                y: centre.y - side * 0.1 - local * side * 0.6 * speed)
            case .sparkles:
                let distance = side * (0.3 + 0.45 * speed) * (1 - pow(1 - local, 3))
                point = CGPoint(x: centre.x + cos(angle * 2) * distance, y: centre.y - side * 0.05 + sin(angle * 2) * distance)
            case .feathers, .confetti:
                let x0 = centre.x + random.next(in: -1...1) * side * 0.9
                point = CGPoint(x: x0 + sin(local * 6 + spin) * side * 0.08, y: centre.y - side * 0.9 + local * side * 1.6 * speed + side * 0.2)
            }
            var context = canvas
            context.opacity = fade
            context.translateBy(x: point.x, y: point.y)
            context.rotate(by: .radians(spin * local * 2))
            let s = side * 0.07
            switch burst.kind {
            case .hearts:
                context.fill(Path(Self.heart(size: s * (0.8 + speed * 0.5))), with: .color(Color(hex: 0xFF5C7A)))
            case .sparkles:
                let k = s * 0.55 * (1 - local * 0.5)
                var star = Path()
                for i in 0..<8 {
                    let a = Double(i) * .pi / 4
                    let r = i % 2 == 0 ? k : k * 0.3
                    let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
                    i == 0 ? star.move(to: p) : star.addLine(to: p)
                }
                star.closeSubpath()
                context.fill(star, with: .color([Brand.amber, .white, Brand.lavender].randomElement(using: &random)!))
            case .feathers:
                var feather = Path()
                feather.move(to: CGPoint(x: 0, y: -s * 0.9))
                feather.addQuadCurve(to: CGPoint(x: 0, y: s * 0.9), control: CGPoint(x: s * 0.6, y: 0))
                feather.addQuadCurve(to: CGPoint(x: 0, y: -s * 0.9), control: CGPoint(x: -s * 0.6, y: 0))
                context.fill(feather, with: .color([Brand.golden, Brand.cream, Color(hex: 0xC8742C)].randomElement(using: &random)!))
                var quill = Path()
                quill.move(to: CGPoint(x: 0, y: -s * 0.9))
                quill.addLine(to: CGPoint(x: 0, y: s * 1.1))
                context.stroke(quill, with: .color(.white.opacity(0.6)), lineWidth: max(0.5, s * 0.08))
            case .confetti:
                let colour = [Brand.amber, Brand.lavender, Color(hex: 0xFF5C8A), Color(hex: 0x5ED3B5), .white].randomElement(using: &random)!
                context.fill(Path(roundedRect: CGRect(x: -s * 0.3, y: -s * 0.15, width: s * 0.6, height: s * 0.3), cornerRadius: s * 0.05),
                             with: .color(colour))
            }
        }
    }

    private static func heart(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let s = size / 2
        path.move(to: CGPoint(x: 0, y: s * 0.9))
        path.addCurve(to: CGPoint(x: -s, y: -s * 0.2), control1: CGPoint(x: -s * 0.4, y: s * 0.5), control2: CGPoint(x: -s, y: s * 0.2))
        path.addArc(center: CGPoint(x: -s * 0.5, y: -s * 0.3), radius: s * 0.52, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addArc(center: CGPoint(x: s * 0.5, y: -s * 0.3), radius: s * 0.52, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addCurve(to: CGPoint(x: 0, y: s * 0.9), control1: CGPoint(x: s, y: s * 0.2), control2: CGPoint(x: s * 0.4, y: s * 0.5))
        path.closeSubpath()
        return path
    }
}

/// A tiny, repeatable random number generator, so each burst's particles
/// keep their paths from frame to frame.
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
    }
}

/// Little stars circling a dizzy owl's head.
private struct OrbitingStars: View {
    let side: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate * 3
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let angle = time + Double(index) * 2 * .pi / 3
                    Image(systemName: "star.fill")
                        .font(.system(size: max(6, side * 0.09)))
                        .foregroundStyle(Brand.amber)
                        .offset(x: cos(angle) * side * 0.3, y: -side * 0.38 + sin(angle) * side * 0.07)
                        .scaleEffect(sin(angle) > 0 ? 1.1 : 0.8)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A small speech bubble with a tail pointing back at the owl.
private struct SpeechBubble: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(Brand.indigoDeep)
            .padding(.horizontal, fontSize * 0.6)
            .padding(.vertical, fontSize * 0.32)
            .background(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: fontSize * 0.6, style: .continuous).fill(Brand.cream)
                    BubbleTail()
                        .fill(Brand.cream)
                        .frame(width: fontSize * 0.7, height: fontSize * 0.6)
                        .offset(x: fontSize * 0.25, y: fontSize * 0.45)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .rotationEffect(.degrees(-5))
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Little z's drifting up from a sleeping owl.
private struct Snore: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        SnoreZ(phase: (time / 2.8 + Double(index) / 3).truncatingRemainder(dividingBy: 1),
                               size: proxy.size)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One z, `phase` (0…1) of the way through its drift up and away.
private struct SnoreZ: View {
    let phase: Double
    let size: CGSize

    var body: some View {
        let w: CGFloat = size.width, h: CGFloat = size.height
        let p = CGFloat(phase)
        let fontSize: CGFloat = max(7, w * (0.13 + 0.09 * p))
        let opacity: Double = phase < 0.15 ? phase / 0.15 : (1 - phase) * 1.15
        let x: CGFloat = w * (0.78 + 0.22 * p) + CGFloat(sin(phase * 8)) * w * 0.03
        let y: CGFloat = h * (0.2 - 0.38 * p)
        return Text("z")
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(Brand.lavender)
            .opacity(opacity)
            .position(x: x, y: y)
    }
}

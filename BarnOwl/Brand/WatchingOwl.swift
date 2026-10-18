import SwiftUI

/// The owl with some personality. It watches the pointer, breathes and
/// blinks, and reacts to what happens:
///
/// - click: a hoot and a hop; three quick clicks: it turns its head all the
///   way round; keep clicking and it gets dizzy;
/// - press and hold: it loves being petted;
/// - eyes opening (keep awake starts): a big wide-awake stretch; eyes
///   closing: a yawn, then it nods off and snores;
/// - cues from the rest of the app (`OwlCue`): toggles, the Nest, search,
///   the clipboard;
/// - left alone for a while it gets drowsy, and startles when you're back;
///   now and then it dances or stretches, more so after midnight.
///
/// Settings → Appearance → Owl personality, and Reduce Motion, tone it down.
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
    /// Looks this way instead of at the pointer.
    var lookAt: CGVector?
    /// Reacts to clicks, gets drowsy and does things by itself.
    var playful = true
    /// Shows drifting z's while the eyes are shut.
    var snores = true
    /// Says things in a speech bubble. Off where the text around it already
    /// says it.
    var talks = true
    /// Bags under the eyes.
    var tired = false
    /// Opens its beak, hoping for a snack.
    var hungry = false
    var accessory: OwlOutfit?
    /// nil uses the colours chosen in Settings.
    var palette: OwlPalette?
    var entrance: Entrance = .none
    /// Plays a reaction whenever a new cue arrives.
    var cue: OwlCue?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PrefKey.owlPersonality) private var personality = OwlPersonality.lively
    @State private var anchor = ScreenAnchor()
    @State private var tilt: Double = 0
    @State private var turn: Double = 0
    @State private var hop: CGFloat = 0
    @State private var squash: CGFloat = 1
    @State private var sway: Double = 0
    @State private var wingLift: CGFloat = 0
    @State private var yawn: CGFloat = 0
    @State private var lids: CGFloat = 0
    @State private var faceDip: CGFloat = 0
    @State private var bubble: String?
    @State private var bubblePlacement = BubblePlacement.aboveTrailing
    @State private var bubbleID = 0
    @State private var cheering = false
    @State private var loving = false
    @State private var dizzy = false
    @State private var roused = false
    @State private var dozing = false
    @State private var stunned = false
    @State private var coverEyes = false
    @State private var shush = false
    @State private var glow = false
    @State private var bellyTint: Color?
    @State private var clicks: [Date] = []
    @State private var bursts: [Burst] = []
    @State private var side: CGFloat = 0

    /// Eyes open as far as the owl itself is concerned: it stays awake a
    /// moment longer to yawn first.
    private var awake: Bool { eyesOpen || roused || dozing }
    /// Whether it may move at all.
    private var moves: Bool { !reduceMotion && personality != .still }
    /// Whether it may do things nobody asked for.
    private var idles: Bool { moves && personality == .lively }
    private var bubbleFontSize: CGFloat { max(10, min(22, side * 0.14)) }
    private var outfit: OwlOutfit { accessory ?? (side >= 40 ? .seasonal : .none) }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !moves && !watches)) { context in
                let look = currentLook
                let breath = moves ? sin(context.date.timeIntervalSinceReferenceDate * (awake ? 1.9 : 1.1)) : 0
                let depth: CGFloat = awake ? 0.012 : 0.024
                OwlView(eyesOpen: awake, look: look, surprised: surprised || roused || stunned, happy: happy || cheering,
                        hearts: loving, dizzy: dizzy, lids: lids, wingLift: wingLift, turn: turn, tilt: tilt, yawn: yawn,
                        accessory: outfit, coverEyes: coverEyes, shush: shush, glowEyes: glow, tired: tired,
                        bellyTint: bellyTint, faceDip: faceDip, palette: palette)
                    .scaleEffect(x: 1 + depth * 0.7 * breath, y: 1 - depth * breath, anchor: .bottom)
            }
            .rotationEffect(.degrees(sway), anchor: .bottom)
            .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
            .offset(y: hop)
            .frame(width: side, height: side)
            .overlay {
                if snores && !awake && moves && side >= 30 { Snore() }
            }
            .overlay {
                if dizzy { OrbitingStars(side: side) }
            }
            .overlay {
                BurstsView(bursts: bursts, side: side)
            }
            .overlay(alignment: .topLeading) {
                if talks, let bubble {
                    let size = SpeechBubble.size(of: bubble, fontSize: bubbleFontSize)
                    let origin = bubblePlacement.origin(for: size, owlSide: side)
                    SpeechBubble(text: bubble, fontSize: bubbleFontSize, placement: bubblePlacement)
                        .offset(x: origin.x, y: origin.y)
                        .transition(moves ? .scale(scale: 0.5, anchor: bubblePlacement.growsFrom).combined(with: .opacity)
                                          : .opacity)
                        .zIndex(1)
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .onAppear { self.side = side }
            .onChange(of: side) { _, new in self.side = new }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(ScreenAnchorView(anchor: anchor))
        // Only a playful owl takes clicks; otherwise they pass through to
        // whatever it sits in, such as a button.
        .modifier(OwlGestures(enabled: playful && moves, tap: poke, hold: pet))
        .onChange(of: surprised) { _, now in if now { notice() } }
        .onChange(of: eyesOpen) { _, now in now ? wakeUp() : doze() }
        .onChange(of: happy) { _, now in if now { catchIt() } }
        .onChange(of: hungry) { _, now in
            guard moves else { return }
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { yawn = now ? 0.6 : 0 }
        }
        .onChange(of: cue) { _, new in if let new { react(to: new.kind) } }
        .onChange(of: outfit, initial: true) { _, new in meetOutfit(new) }
        .task(id: idles && awake) { await liveALittle() }
        .task {
            await perform(entrance)
            await greetTheDay()
        }
        .accessibilityHidden(true)
    }

    private var currentLook: CGVector {
        guard awake, lids < 0.5 else { return .zero }
        if let lookAt { return lookAt }
        return watches ? direction() : .zero
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
            OwlMoment.turnaround.meet()
        } else if clicks.count < 3 {
            hoot()
        } else {
            bounce(height: 5)
        }
    }

    private func hoot() {
        say(["Hoo!", "Hoo hoo!", "Hoot!", "Hi there!", "Who? Me?"].randomElement()!, for: 1.1)
        cheer(for: 0.9)
        bounce(height: 9)
        flap(times: 2)
        OwlMoment.hoot.meet()
    }

    private func pet() {
        guard awake, !dizzy else { return }
        loving = true
        say("♥", for: 1.4)
        burst(.hearts)
        wiggle()
        OwlMoment.petted.meet()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            loving = false
        }
    }

    /// Keep awake started: eyes pop, a big stretch, sparkles.
    private func wakeUp() {
        guard moves else { return }
        dozing = false
        stunned = true
        // Presenting keeps the Mac awake too, but then it's the shades that matter.
        if outfit.eyewear == .shades {
            say("Incognito!", for: 1.4)
        } else {
            say("Wide awake!", for: 1.4)
            burst(.sparkles)
            OwlMoment.wideAwake.meet()
        }
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
        guard moves else { return }
        dozing = true
        OwlMoment.yawn.meet()
        Task {
            await yawnAndStretch()
            withAnimation(.easeInOut(duration: 0.5)) { lids = 0.9 }
            try? await Task.sleep(for: .milliseconds(500))
            lids = 0
            dozing = false
        }
    }

    private func yawnAndStretch() async {
        withAnimation(.easeOut(duration: 0.5)) { yawn = 1; lids = 0.55; wingLift = 0.5; squash = 1.05 }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.easeIn(duration: 0.4)) { yawn = 0; wingLift = 0; squash = 1 }
        try? await Task.sleep(for: .milliseconds(350))
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

    private func react(to kind: OwlCue.Kind) {
        guard moves else { return }
        switch kind {
        case .hoot:
            hoot()
        case .dance:
            say("♪", for: 1.4)
            Task { await dance() }
        case .found:
            say("Found it!", for: 1.2)
            catchIt()
            OwlMoment.found.meet()
        case .lightsOut:
            say("Lights out!", for: 1.5)
            OwlMoment.lightsOut.meet()
            hold(.glow, for: 2.6)
        case .lightsOn:
            say("Bright!", for: 1.2)
            cheer(for: 1)
        case .shush:
            say("Shh!", for: 1.5)
            OwlMoment.shush.meet()
            hold(.shush, for: 2)
        case .listening:
            say("I'm all ears!", for: 1.3)
            bounce(height: 6)
        case .peekaboo:
            OwlMoment.peekaboo.meet()
            Task {
                withAnimation(.easeIn(duration: 0.25)) { faceDip = 1; hop = side * 0.12 }
                try? await Task.sleep(for: .milliseconds(700))
                say("Peekaboo!", for: 1.2)
                withAnimation(.spring(duration: 0.4, bounce: 0.5)) { faceDip = 0; hop = 0 }
            }
        case .backAgain:
            say("There you are!", for: 1.2)
            bounce(height: 6)
        case .secrets:
            say("Ooh, secrets!", for: 1.4)
            OwlMoment.secrets.meet()
            hold(.stunned, for: 1.4)
            bounce(height: 6)
        case .unseen:
            say("I saw nothing.", for: 1.4)
            hold(.coverEyes, for: 1.6)
        case .nightNight:
            say("Night night", for: 1.2)
            Task { await yawnAndStretch() }
        case .caught:
            catchIt()
        case .bye:
            say("Bye!", for: 1.1)
            OwlMoment.bye.meet()
            Task {
                for _ in 0..<3 {
                    withAnimation(.easeOut(duration: 0.12)) { wingLift = 0.7 }
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.easeIn(duration: 0.12)) { wingLift = 0.35 }
                    try? await Task.sleep(for: .milliseconds(140))
                }
                withAnimation(.easeIn(duration: 0.15)) { wingLift = 0 }
            }
        case .sweep:
            say("All clear!", for: 1.2)
            OwlMoment.sweep.meet()
            Task {
                for angle in [-12.0, 12, -12, 0] {
                    withAnimation(.easeInOut(duration: 0.15)) { tilt = angle; wingLift = angle == 0 ? 0 : 0.8 }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        case .nom:
            say("Nom!", for: 1.2)
            OwlMoment.nom.meet()
            Task {
                for _ in 0..<2 {
                    withAnimation(.easeOut(duration: 0.1)) { yawn = 0.7 }
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeIn(duration: 0.1)) { yawn = 0 }
                    try? await Task.sleep(for: .milliseconds(120))
                }
                cheer(for: 0.8)
            }
            bounce(height: 6)
        case .didntSee:
            say("I didn't see that!", for: 1.8)
            OwlMoment.didntSee.meet()
            hold(.coverEyes, for: 2)
        case .colour(let colour):
            say("Pretty!", for: 1.4)
            OwlMoment.pretty.meet()
            withAnimation(.easeInOut(duration: 0.4)) { bellyTint = colour }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeInOut(duration: 0.6)) { bellyTint = nil }
            }
        case .charged:
            say("⚡", for: 1.2)
            OwlMoment.chargedUp.meet()
            burst(.sparkles)
            bounce(height: 9)
        case .thrown:
            say("Whee!", for: 1.2)
            OwlMoment.thrown.meet()
            flap(times: 3)
            cheer(for: 1)
        }
    }

    private enum Pose { case glow, shush, coverEyes, stunned }

    /// Strikes a pose for a while.
    private func hold(_ pose: Pose, for seconds: Double) {
        set(pose, true)
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            set(pose, false)
        }
    }

    private func set(_ pose: Pose, _ value: Bool) {
        withAnimation(.spring(duration: 0.3)) {
            switch pose {
            case .glow: glow = value
            case .shush: shush = value
            case .coverEyes: coverEyes = value
            case .stunned: stunned = value
            }
        }
    }

    /// Meets the moments an outfit stands for.
    private func meetOutfit(_ outfit: OwlOutfit) {
        switch outfit.hat {
        case .headset: OwlMoment.onCall.meet()
        case .nightcap where !eyesOpen: OwlMoment.sweetDreams.meet()
        case .santa: OwlMoment.santa.meet()
        case .witch: OwlMoment.witch.meet()
        default: break
        }
        if outfit.eyewear == .shades { OwlMoment.presenting.meet() }
        if outfit.eyewear == .glasses { OwlMoment.atTheDesk.meet() }
        switch outfit.prop {
        case .coffee: OwlMoment.coffee.meet()
        case .twoCoffees: OwlMoment.doubleShot.meet()
        case .thermos: OwlMoment.allNighter.meet()
        case .blanket: OwlMoment.lidClosed.meet()
        case .none: break
        }
    }

    private func getDizzy() {
        dizzy = true
        say("@_@", for: 2.2)
        OwlMoment.dizzy.meet()
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
        guard moves else { return }
        Task {
            for angle in [6.0, -6, 4, -3, 0] {
                withAnimation(.easeInOut(duration: 0.12)) { sway = angle }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func dance() async {
        cheering = true
        OwlMoment.dance.meet()
        for angle in [8.0, -8, 8, -8, 0] {
            withAnimation(.easeInOut(duration: 0.2)) { sway = angle; hop = angle == 0 ? 0 : -3 }
            try? await Task.sleep(for: .milliseconds(200))
        }
        cheering = false
    }

    private func say(_ text: String, for seconds: Double) {
        bubbleID += 1
        let id = bubbleID
        // Chosen as it appears, so it fits wherever the owl is right now.
        bubblePlacement = .best(for: SpeechBubble.size(of: text, fontSize: bubbleFontSize), owlSide: side,
                                room: anchor.roomInWindow)
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
        guard moves else { return }
        let new = Burst(kind: kind)
        bursts.append(new)
        Task {
            try? await Task.sleep(for: .seconds(new.duration))
            bursts.removeAll { $0.id == new.id }
        }
    }

    /// A squash, a hop and a bouncy landing.
    private func bounce(height: CGFloat) {
        guard moves else { return }
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
        guard moves else { return }
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
        guard moves else { return }
        withAnimation(.spring(duration: 1.2, bounce: 0.25)) { turn += 2 * .pi }
    }

    // MARK: Living

    /// The owl's own life: a curious tilt, a stretch or a little dance now
    /// and then, more often after midnight. Left alone it gets drowsy, and
    /// startles when you're back.
    private func liveALittle() async {
        guard playful, idles, awake else { return }
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
                    withAnimation(.spring(duration: 0.25)) { lids = 0; tilt = 0 }
                    stunned = true
                    say("!", for: 0.9)
                    bounce(height: 8)
                    flap(times: 1)
                    OwlMoment.caughtNapping.meet()
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
            // A night owl: livelier between midnight and four.
            let night = (0..<4).contains(Calendar.current.component(.hour, from: .now))
            nextTrick = Date.now.addingTimeInterval(night ? .random(in: 6...12) : .random(in: 20...40))
            if night {
                OwlMoment.nightOwl.meet()
                if Bool.random() {
                    withAnimation(.easeInOut(duration: 0.3)) { glow = true }
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.easeInOut(duration: 0.5)) { glow = false }
                    continue
                }
            }
            switch Int.random(in: 0..<5) {
            case 0, 1:
                withAnimation(.spring(duration: 0.5, bounce: 0.35)) { tilt = .random(in: 10...16) * (Bool.random() ? 1 : -1) }
                try? await Task.sleep(for: .seconds(.random(in: 0.9...1.6)))
                withAnimation(.spring(duration: 0.6, bounce: 0.3)) { tilt = 0 }
            case 2:
                await flapWings(times: 1)
            case 3:
                // A stretch.
                OwlMoment.stretch.meet()
                withAnimation(.easeOut(duration: 0.4)) { wingLift = 1.2; squash = 1.06 }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) { wingLift = 0; squash = 1 }
            default:
                await dance()
            }
        }
    }

    /// Once a day, the first owl you see says good morning; once a year it
    /// celebrates New Year and its birthday.
    private func greetTheDay() async {
        guard moves, side >= 28, awake else { return }
        let now = Calendar.current.dateComponents([.month, .day, .hour], from: .now)
        try? await Task.sleep(for: .milliseconds(400))
        if now.month == 1, (now.day ?? 99) <= 7, OwlOccasions.firstTime("newYear", period: OwlOccasions.thisYear) {
            say("Happy New Year!", for: 2)
            burst(.confetti)
            OwlMoment.newYear.meet()
        } else if now.month == OwlOutfit.birthday.month, now.day == OwlOutfit.birthday.day,
                  OwlOccasions.firstTime("birthday", period: OwlOccasions.thisYear) {
            say("It's my birthday!", for: 2)
            burst(.confetti)
            OwlMoment.birthday.meet()
        } else if (5..<11).contains(now.hour ?? 0), OwlOccasions.firstTime("morning", period: OwlOccasions.today) {
            OwlMoment.morning.meet()
            await yawnAndStretch()
            say("Morning!", for: 1.6)
        }
    }

    private func perform(_ entrance: Entrance) async {
        guard moves else { return }
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
            OwlMoment.hooray.meet()
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
            OwlMoment.puzzled.meet()
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

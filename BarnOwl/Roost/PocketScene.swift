import CoreGraphics
import SwiftUI

/// The small night scenes the quick panel and the desktop widget share: a
/// strip with one branch for the quick panel, and the Roost under a glass
/// dome for the widget. Each is painted once, cell by cell, into a cached
/// image keyed by its size and what's on it, so nothing redraws per frame.
@MainActor
enum PocketScene {
    // MARK: The quick panel's strip

    /// Something the strip paints beside an owlet, at the owlet's centre `x`.
    enum Mark: Hashable, Sendable {
        /// A lantern hanging from the branch, for the owlet that needs you.
        case lantern(x: Int)
        /// A rain cloud over a stuck owlet.
        case rain(x: Int)
        /// Fireflies around an owlet whose helpers are at work.
        case fireflies(x: Int)
        /// Sleep marks over a napping owlet.
        case sleep(x: Int)
    }

    /// Owlets in the strip stand with their feet on this row.
    static func branchTop(x: Int, height: Int) -> Int {
        let base = Double(height) * 0.73
        return Int((base + 1.1 * sin(Double(x) / 47 + 0.6) + 0.7 * sin(Double(x) / 19)).rounded())
    }

    /// Where the strip's lantern hangs for an owlet at `x`: the centre of its glass, in cells.
    static func lanternGlass(x: Int, height: Int) -> (x: Int, y: Int) {
        (x + 24, branchTop(x: x + 24, height: height) + 10)
    }

    /// Owlet sprites are this tall, in cells.
    static let owletHeight = OwletArt.height

    /// The strip's sky, stars, branch and marks, one cell per point.
    static func strip(width: Int, height: Int, marks: [Mark]) -> CGImage? {
        let key = "strip|\(width)x\(height)|\(marks)"
        return cached(key) {
            var canvas = PocketPixels(width: width, height: height, fill: 0)
            PocketPaint.sky(&canvas, stops: [0x0E0C2A, 0x1E1A48, 0x3A2F6E], bands: 9)
            PocketPaint.stars(&canvas, count: width * height / 520, top: Double(height) * 0.62, seed: 3)
            PocketPaint.branch(&canvas, top: { branchTop(x: $0, height: height) })
            for mark in marks {
                switch mark {
                case .lantern(let x):
                    let lx = x + 24, top = branchTop(x: lx, height: height) + 5
                    for y in top..<(top + 2) { canvas.put(lx, y, 0x6B5A52) }
                    PocketPaint.lantern(&canvas, cx: lx, top: top + 2)
                case .rain(let x):
                    PocketPaint.rain(&canvas, cx: x, base: branchTop(x: x, height: height) - owletHeight + 3)
                case .fireflies(let x):
                    let top = branchTop(x: x, height: height) - owletHeight
                    PocketPaint.fireflies(&canvas, [(x - 21, top + 17), (x + 20, top + 21), (x - 15, top + 7)])
                case .sleep(let x):
                    PocketPaint.sleep(&canvas, x: x + 9, top: branchTop(x: x, height: height) - owletHeight + 4)
                }
            }
            return canvas.image()
        }
    }

    // MARK: The widget's dome

    /// An owlet on a branch in the dome, by what it shows.
    struct Perched: Hashable, Sendable {
        var sprite: String
        var palette: String
        var needsYou = false
        var stuck = false
        var helpers = false
    }

    /// Everything the dome shows: the light, who's on the branches, who's
    /// curled up in the hollow and who's home in the nest.
    struct Dome: Hashable, Sendable {
        var light: PocketLight
        /// The moon's phase in sixteenths, 0 new, 8 full.
        var moon = 4
        var perched: [Perched] = []
        /// Up to three napping owlets' colours.
        var nappers: [String] = []
        /// Up to three colours of owlets home today.
        var home: [String] = []
    }

    /// The Roost under a glass dome, one cell per point, owlets one point per
    /// sprite pixel, so the tree and its owlets share one grid.
    static func dome(diameter: Int, _ dome: Dome) -> CGImage? {
        cached("dome|\(diameter)|\(dome)") {
            let layout = DomeLayout(diameter: diameter)
            let p = DomePalette.of(dome.light)
            var canvas = PocketPixels(width: diameter, height: diameter, fill: 0)
            DomeTree.paint(&canvas, layout, p, moon: dome.moon, light: dome.light, nappers: dome.nappers, home: dome.home)
            for (owlet, spot) in zip(dome.perched, layout.perches) {
                let cx = Int(spot.x), feet = Int(spot.y)
                if owlet.needsYou {
                    let glass = layout.lantern(beside: spot)
                    for y in (feet + 5)..<(Int(glass.y) - 3) { canvas.put(Int(glass.x), y, 0x6B5A52) }
                    PocketPaint.lantern(&canvas, cx: Int(glass.x), top: Int(glass.y) - 3)
                }
                if owlet.helpers {
                    canvas.firefly(cx - 21, feet - 14)
                    canvas.firefly(cx + 19, feet - 9)
                }
                canvas.stamp(sprite: owlet.sprite, palette: owlet.palette, left: cx - OwletArt.width / 2,
                             top: feet - OwletArt.height)
                if owlet.stuck {
                    PocketPaint.rain(&canvas, cx: cx, base: feet - OwletArt.height + 3, day: dome.light == .day)
                }
            }
            return canvas.image()
        }
    }

    // MARK: Cache

    private static var cache: [String: CGImage] = [:]
    private static var recent: [String] = []

    private static func cached(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        if let image = cache[key] { return image }
        guard let image = make() else { return nil }
        cache[key] = image
        recent.append(key)
        while recent.count > 8 { cache[recent.removeFirst()] = nil }
        return image
    }
}

// MARK: - The dome's light

/// The light in the dome, by the time of day, as the Roost's tree has it.
enum PocketLight: String, Hashable, Sendable {
    case day, golden, dusk, night, plain

    /// `sky` is the Roost's sky setting: "follow" (or nil), "dusk", "night" or "plain".
    static func at(_ date: Date, sky: String?) -> PocketLight {
        switch sky {
        case "dusk": return .dusk
        case "night": return .night
        case "plain": return .plain
        default:
            switch Calendar.current.component(.hour, from: date) {
            case 8..<17: return .day
            case 6..<8, 17..<19: return .golden
            case 19..<21: return .dusk
            default: return .night
            }
        }
    }

    /// When the light next changes after `date`, if it follows the time of day.
    static func nextChange(after date: Date, sky: String?) -> Date? {
        guard sky == nil || sky == "follow" else { return nil }
        let calendar = Calendar.current
        return [6, 8, 17, 19, 21].compactMap { hour in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, second: 0),
                              matchingPolicy: .nextTime)
        }.min()
    }

    /// The moon's phase in sixteenths, from a known new moon: 0 new, 8 full.
    static func moon(at date: Date) -> Int {
        let knownNew = Date(timeIntervalSince1970: 947_182_440)
        let synodic = 29.530588853 * 86_400
        var elapsed = date.timeIntervalSince(knownNew).truncatingRemainder(dividingBy: synodic)
        if elapsed < 0 { elapsed += synodic }
        return Int((elapsed / synodic * 16).rounded()) % 16
    }
}

/// The dome's colours for one light: the Roost tree's values.
struct DomePalette {
    var sky: [UInt32]
    var stars: Double
    var ridge: UInt32
    var hill: UInt32
    var meadow: UInt32
    var meadowHigh: UInt32
    var foreground: UInt32
    var bark: UInt32
    var barkDark: UInt32
    var barkLight: UInt32
    var leaves: [UInt32]

    static func of(_ light: PocketLight) -> DomePalette {
        switch light {
        case .day:
            DomePalette(sky: [0x3F7CC0, 0x5B93CF, 0x7EAAD8, 0xA6C3DF, 0xCFDCE2], stars: 0, ridge: 0xA9BFD0, hill: 0x73986A,
                        meadow: 0x5F8F4F, meadowHigh: 0x7EAB5B, foreground: 0x3F6A40, bark: 0x6E4D37, barkDark: 0x4D3527,
                        barkLight: 0x8E6B4D, leaves: [0x3C6A3F, 0x56904A, 0x86B956])
        case .golden:
            DomePalette(sky: [0x36457F, 0x6A64A0, 0xB77796, 0xEC9A7A, 0xFFC677], stars: 0, ridge: 0xB77B8B, hill: 0x5D3E63,
                        meadow: 0x4A3654, meadowHigh: 0x6A4A62, foreground: 0x2C2139, bark: 0x573640, barkDark: 0x3A232E,
                        barkLight: 0x77494C, leaves: [0x7D3540, 0xBC5338, 0xE58D3F])
        case .dusk:
            DomePalette(sky: [0x1D2050, 0x363470, 0x664E87, 0xAC6B8C, 0xE8A28C], stars: 0.45, ridge: 0x5E4F86, hill: 0x3A2F58,
                        meadow: 0x33294F, meadowHigh: 0x44375F, foreground: 0x211A38, bark: 0x4A3550, barkDark: 0x33243C,
                        barkLight: 0x634866, leaves: [0x1F2E46, 0x2C4458, 0x48667A])
        case .night:
            DomePalette(sky: [0x090B22, 0x0F1233, 0x161A44, 0x1F2453, 0x2C3264], stars: 1, ridge: 0x252A59, hill: 0x161A3D,
                        meadow: 0x131735, meadowHigh: 0x1B2044, foreground: 0x0A0B20, bark: 0x352A45, barkDark: 0x231B32,
                        barkLight: 0x4A3D5E, leaves: [0x12273A, 0x1A3848, 0x2A5868])
        case .plain:
            DomePalette(sky: [0x1A1936], stars: 0, ridge: 0x1F1D3F, hill: 0x1F1D3F, meadow: 0x191834, meadowHigh: 0x232147,
                        foreground: 0x100F26, bark: 0x3A2E4C, barkDark: 0x261E35, barkLight: 0x52446A,
                        leaves: [0x27284C, 0x353863, 0x4A5085])
        }
    }
}

// MARK: - The dome's tree

/// Where things are in a dome of a given size, in points from its top-left:
/// a trunk a little left of centre with a nest in its fork and a hollow
/// below, a long branch to the right and a shorter one to the left.
struct DomeLayout {
    let d: Double

    init(diameter: Int) { d = Double(diameter) }

    var trunkX: Double { (d * 0.38).rounded() }
    var forkY: Double { (d * 0.37).rounded() }
    var groundY: Double { (d * 0.84).rounded() }
    var hollow: CGPoint { CGPoint(x: trunkX, y: (d * 0.7).rounded()) }
    var nest: CGPoint { CGPoint(x: trunkX, y: forkY - 2) }

    /// The right branch's top at `x`, and the left's.
    func rightTop(_ x: Double) -> Double { (d * 0.56 - (x - trunkX) * 0.07).rounded() }
    func leftTop(_ x: Double) -> Double { (d * 0.62 - (trunkX - x) * 0.08).rounded() }

    /// Feet positions for perched owlets, the best first.
    var perches: [CGPoint] {
        let inner = (d * 0.67).rounded(), outer = (d * 0.89).rounded(), left = (d * 0.15).rounded()
        return [CGPoint(x: inner, y: rightTop(inner)), CGPoint(x: left, y: leftTop(left)), CGPoint(x: outer, y: rightTop(outer))]
    }

    /// The centre of the lantern's glass, hanging under the branch beside an owlet.
    func lantern(beside spot: CGPoint) -> CGPoint {
        let x = spot.x + 19
        return CGPoint(x: x, y: rightTop(x) + 12)
    }

    /// Where a "+N" for owlets that didn't fit goes: against the trunk, under the right branch.
    var more: CGPoint { CGPoint(x: trunkX + 24, y: rightTop(trunkX + 24) + 15) }
}

@MainActor
enum DomeTree {
    static func paint(_ canvas: inout PocketPixels, _ layout: DomeLayout, _ p: DomePalette, moon: Int, light: PocketLight,
                      nappers: [String], home: [String]) {
        let d = layout.d
        PocketPaint.sky(&canvas, stops: p.sky, bands: 12)
        if p.stars > 0 {
            var random = PocketRandom(11)
            for _ in 0..<Int(d * d / 260 * p.stars) {
                let x = random.int(0..<canvas.width), y = Int(pow(random.next(), 1.3) * d * 0.6)
                canvas.blend(x, y, 0xF1EEFF, (0.3 + 0.55 * random.next()) * p.stars)
            }
        }
        switch light {
        case .day:
            sun(&canvas, d * 0.8, d * 0.17, d * 0.05, core: 0xFFFBEA, ring: 0xFFF1C2)
        case .golden:
            canvas.glow(d * 0.82, d * 0.66, [(d * 0.12, 0.2), (d * 0.2, 0.1), (d * 0.3, 0.05)], 0xFFD98C)
            sun(&canvas, d * 0.82, d * 0.66, d * 0.07, core: 0xFFF4CF, ring: 0xFFD98C)
        case .dusk:
            canvas.glow(d * 0.75, d * 0.72, [(d * 0.15, 0.08), (d * 0.28, 0.05)], 0xFFC9A8)
        case .night:
            moonDisc(&canvas, d * 0.79, d * 0.19, max(3.5, d * 0.045), phase: Double(moon) / 16)
        case .plain:
            break
        }
        PocketPaint.ridge(&canvas, base: d * 0.76, amps: [(d * 0.025, d * 0.14), (d * 0.012, d * 0.06)], colour: p.ridge,
                          seed: 1.2)
        PocketPaint.ridge(&canvas, base: d * 0.81, amps: [(d * 0.02, d * 0.2), (d * 0.01, d * 0.08)], colour: p.hill, seed: 4.1)
        // Canopy behind the fork.
        let back = p.leaves.map { PocketColour.mix($0, p.sky[0], 0.28) }
        let tx = layout.trunkX
        for (x, y, r, seed) in [(tx - 0.2 * d, 0.24 * d, 0.15 * d, 1), (tx + 0.14 * d, 0.13 * d, 0.16 * d, 2),
                                (tx + 0.33 * d, 0.27 * d, 0.12 * d, 3)] {
            PocketPaint.clump(&canvas, x, y, r, back, seed: seed)
        }
        // Trunk, from the ground up into the fork.
        for yi in Int(layout.forkY)..<canvas.height {
            let y = Double(yi)
            let flare = pow(max(0, y - (layout.groundY - 14)), 1.4) * 0.35
            let w = 24 + (y - layout.forkY) * 0.03 + flare
            let x0 = tx - w / 2 + 1.2 * sin((y - layout.forkY) / 22)
            for xi in Int(x0)..<Int(x0 + w) { canvas.put(xi, yi, p.bark, tag: .bark) }
        }
        // The fork's two limbs, cradling the nest.
        thick(&canvas, p, tx - 6, layout.forkY + 6, tx - 0.17 * d, layout.forkY - 0.2 * d, 8, 3)
        thick(&canvas, p, tx + 6, layout.forkY + 6, tx + 0.17 * d, layout.forkY - 0.22 * d, 8, 3)
        // The branches owlets sit on.
        let right0 = tx + 8, right1 = d * 1.02, left0 = tx - 8, left1 = -2.0
        thick(&canvas, p, right0, layout.rightTop(right0) + 4, right1, layout.rightTop(right1) + 2, 8, 3.5)
        thick(&canvas, p, left0, layout.leftTop(left0) + 4, left1, layout.leftTop(left1) + 2, 7, 3)
        // A twig on each, for a branch that grew rather than was drawn.
        let twig = d * 0.74
        thick(&canvas, p, twig, layout.rightTop(twig) + 1, twig + 4, layout.rightTop(twig) - 6, 2, 1)
        shade(&canvas, p)
        // Front canopy.
        for (x, y, r, seed) in [(tx - 0.24 * d, 0.27 * d, 0.12 * d, 11), (tx + 0.02 * d, 0.12 * d, 0.14 * d, 12),
                                (tx + 0.26 * d, 0.2 * d, 0.13 * d, 13), (tx - 0.08 * d, 0.3 * d, 0.07 * d, 14),
                                (tx + 0.4 * d, 0.33 * d, 0.07 * d, 15)] {
            PocketPaint.clump(&canvas, x, y, r, p.leaves, seed: seed)
        }
        // A tuft at the end of the left branch.
        PocketPaint.clump(&canvas, 2, layout.leftTop(0) - 1, max(4, d * 0.04), p.leaves, seed: 21, squash: 0.8)
        hollow(&canvas, layout, p, nappers: nappers)
        nest(&canvas, layout, p, sleepers: home, light: light)
        // Ground.
        for xi in 0..<canvas.width {
            let x = Double(xi)
            let top = Int((layout.groundY + 1.5 * sin(x / 17) - 3 * max(0, cos((x - tx) / (d * 0.22)))).rounded())
            for yi in max(0, top)..<canvas.height {
                let depth = yi - top
                let c = depth == 0 ? p.meadowHigh : depth < 7 ? p.meadow
                    : (depth < 9 && (xi + yi) % 2 == 0 ? p.meadow : p.foreground)
                canvas.put(xi, yi, c, tag: .ground)
            }
        }
    }

    private static func sun(_ canvas: inout PocketPixels, _ cx: Double, _ cy: Double, _ r: Double, core: UInt32, ring: UInt32) {
        canvas.glow(cx, cy, [(r * 1.6, 0.2), (r * 2.4, 0.08)], ring)
        for (x, y) in PocketPixels.disc(cx, cy, r) {
            canvas.put(x, y, hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy) < r - 1.4 ? core : ring)
        }
    }

    /// Tonight's moon in its real phase: lit on the right while it waxes.
    private static func moonDisc(_ canvas: inout PocketPixels, _ cx: Double, _ cy: Double, _ r: Double, phase: Double) {
        canvas.glow(cx, cy, [(r + 3, 0.08), (r + 7, 0.05)], 0xC9C6FF)
        let turn = cos(phase * 2 * .pi)
        for (x, y) in PocketPixels.disc(cx, cy, r) {
            let dy = Double(y) + 0.5 - cy, mx = Double(x) + 0.5 - cx
            let half = max(0, r * r - dy * dy).squareRoot()
            let lit = phase < 0.5 ? mx > half * turn : mx < -half * turn
            canvas.put(x, y, lit ? 0xF4EAD6 : 0x262B5A)
        }
    }

    private static func thick(_ canvas: inout PocketPixels, _ p: DomePalette, _ x0: Double, _ y0: Double, _ x1: Double,
                              _ y1: Double, _ t0: Double, _ t1: Double) {
        let n = Int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in 0...n {
            let u = Double(i) / Double(n)
            let x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * u, t = t0 + (t1 - t0) * u
            for (px, py) in PocketPixels.disc(x, y, max(0.6, t / 2)) { canvas.put(px, py, p.bark, tag: .bark) }
        }
    }

    /// Lit tops and left edges, shadowed undersides, light from the upper left.
    private static func shade(_ canvas: inout PocketPixels, _ p: DomePalette) {
        var changes: [(Int, UInt32)] = []
        for y in 0..<canvas.height {
            for x in 0..<canvas.width where canvas.tag(x, y) == .bark {
                let up = canvas.tag(x, y - 1) != .bark, down = canvas.tag(x, y + 1) != .bark
                let left = canvas.tag(x - 1, y) != .bark, right = canvas.tag(x + 1, y) != .bark
                var c = p.bark
                if down || right {
                    c = p.barkDark
                } else if up || left {
                    c = p.barkLight
                } else if PocketPixels.noise(x, y / 5, 4) > 0.9 {
                    c = PocketColour.mix(p.bark, p.barkDark, 0.6)
                }
                changes.append((y * canvas.width + x, c))
            }
        }
        for (index, c) in changes { canvas.colour[index] = c }
    }

    /// An owlet curled up asleep in its nightcap, small enough for three to share the hollow.
    static let curled = ["....mlL...", "...mllLL..", "..oLLLLLo.", ".ohhggggdo", "ohwwgwwgdo", "oweewweedo", "ogwwawwgdo",
                         ".ogddddgo.", "..oooooo.."]

    /// The hollow in the trunk: a dark arch with a lit lip, and napping owlets curled up inside.
    private static func hollow(_ canvas: inout PocketPixels, _ layout: DomeLayout, _ p: DomePalette, nappers: [String]) {
        let hx = Double(layout.hollow.x) + 0.5, hy = Double(layout.hollow.y)
        let rx = 9.5, ry = 6.5
        func inside(_ x: Int, _ y: Int, grow: Double) -> Bool {
            let dx = (Double(x) + 0.5 - hx) / (rx + grow), dy = (Double(y) + 0.5 - hy) / (ry + grow)
            return dy < 0 ? dx * dx + dy * dy <= 1 : abs(dx) <= 1 && dy <= 1 - dx * dx * 0.25
        }
        let core: UInt32 = 0x140D1A, depth = PocketColour.mix(core, p.barkDark, 0.45)
        for y in Int(hy - ry - 2)...Int(hy + ry + 2) {
            for x in Int(hx - rx - 2)...Int(hx + rx + 2) {
                if inside(x, y, grow: 0) {
                    canvas.put(x, y, inside(x, y, grow: -2.5) ? core : depth)
                } else if inside(x, y, grow: 1.2) {
                    canvas.put(x, y, Double(y) + 0.5 > hy + ry - 1 ? p.barkLight : p.barkDark)
                }
            }
        }
        let offsets: [Int] = switch nappers.count {
        case 0: []
        case 1: [0]
        case 2: [-4, 4]
        default: [-6, 6, 0]
        }
        let order = nappers.count >= 3 ? [1, 2, 0] : Array(nappers.indices)
        for (slot, index) in order.enumerated() where slot < offsets.count {
            let colours = OwletArt.palettes[nappers[index]] ?? OwletArt.palettes["golden"] ?? [:]
            let behind = nappers.count > 1 && slot < offsets.count - 1
            let ox = Int(hx) - 5 + offsets[slot], oy = Int(hy + ry) - curled.count + 1 + (behind ? 0 : 1)
            for (y, row) in curled.enumerated() {
                for (x, key) in row.enumerated() where key != "." {
                    guard let c = colours[key], inside(ox + x, oy + y, grow: 0) else { continue }
                    canvas.put(ox + x, oy + y, behind ? PocketColour.mix(c, core, 0.35) : c)
                }
            }
        }
    }

    /// A woven nest in the fork; owlets home today in it, only their heads showing:
    /// party hats by day, nightcaps after dark.
    private static func nest(_ canvas: inout PocketPixels, _ layout: DomeLayout, _ p: DomePalette, sleepers: [String],
                             light: PocketLight) {
        let cx = Double(layout.nest.x), top = Int(layout.nest.y)
        let sprite = light == .day || light == .golden ? "done" : "nap"
        if let frame = OwletArt.states[sprite]?.frames.first {
            let cells = Array(frame)
            // The top rows with a face in them: the hat, the head, the eyes.
            let rows = sprite == "nap" ? 2..<20 : 0..<19
            for (index, palette) in sleepers.prefix(3).enumerated() {
                let colours = OwletArt.palettes[palette] ?? OwletArt.palettes["golden"] ?? [:]
                let ox = Int(cx) - 16 + Int((Double(index) - Double(min(sleepers.count, 3) - 1) / 2) * 9)
                for y in rows {
                    for x in 3..<29 {
                        let key = cells[y * OwletArt.width + x]
                        guard key != ".", let c = colours[key] else { continue }
                        canvas.put(ox + x, top - rows.count + 2 + y - rows.lowerBound, c)
                    }
                }
            }
        }
        let c1: UInt32 = 0x6B4433, c2: UInt32 = 0x8E5E3E, c3: UInt32 = 0x4A2E25
        let insets = [2, 0, 0, 0, 1, 3]
        for y in top..<(top + insets.count) {
            let inset = Double(insets[y - top])
            for x in Int(cx - 15 + inset)..<Int(cx + 15 - inset) {
                var c = (x + 2 * (y - top)) % 5 < 2 ? c2 : c1
                if y == top { c = x % 3 != 0 ? c2 : c3 }
                if y >= top + 4 { c = c3 }
                canvas.put(x, y, c)
            }
        }
    }
}

// MARK: - Painting

enum PocketPaint {
    /// Flat bands with a two-row checker between them: calm, and free of gradient noise.
    static func sky(_ canvas: inout PocketPixels, stops: [UInt32], bands: Int) {
        let height = Double(canvas.height) / Double(bands)
        let colours = (0..<bands).map { PocketColour.ramp(stops, Double($0) / Double(bands - 1)) }
        for y in 0..<canvas.height {
            let band = min(Int(Double(y) / height), bands - 1)
            let inBand = y - Int(Double(band) * height)
            let colour = colours[band], previous = band > 0 ? colours[band - 1] : colour
            for x in 0..<canvas.width {
                canvas.put(x, y, inBand < 2 && (x + y) % 2 == 0 ? previous : colour, tag: .sky)
            }
        }
    }

    static func stars(_ canvas: inout PocketPixels, count: Int, top: Double, seed: Int) {
        var random = PocketRandom(seed)
        for _ in 0..<count {
            let x = random.int(0..<max(1, canvas.width)), y = Int(pow(random.next(), 1.3) * top)
            let bright = random.next()
            canvas.blend(x, y, 0xF1EEFF, 0.3 + 0.55 * bright)
        }
    }

    /// The strip's branch: a lit top, the bark, a shadowed underside.
    static func branch(_ canvas: inout PocketPixels, top: (Int) -> Int) {
        for x in 0..<canvas.width {
            let t = top(x)
            let lit = PocketPixels.noise(x / 3, 0, 5) > 0.8 ? 0x64506E as UInt32 : 0x54425E
            canvas.put(x, t, lit)
            for y in (t + 1)...(t + 2) { canvas.put(x, y, 0x3C2D47) }
            canvas.put(x, t + 3, 0x2A1F33)
            canvas.put(x, t + 4, 0x211829)
            if PocketPixels.noise(x / 2, 1, 7) > 0.8 { canvas.put(x, t + 2, 0x33263D) }
        }
    }

    /// A small lantern: handle, cap, warm glass, base.
    static func lantern(_ canvas: inout PocketPixels, cx: Int, top: Int) {
        let rows = ["..f..", ".fff.", "fgggf", "fghgf", "fghgf", "fgggf", ".fff."]
        let colours: [Character: UInt32] = ["f": 0x3A2C2A, "g": 0xFFC861, "h": 0xFFF4C8]
        for (y, row) in rows.enumerated() {
            for (x, key) in row.enumerated() where key != "." {
                if let c = colours[key] { canvas.put(cx - 2 + x, top + y, c) }
            }
        }
    }

    /// A rain cloud in cool grey, never amber: the lantern is the only warm light.
    static func rain(_ canvas: inout PocketPixels, cx: Int, base: Int, small: Bool = false, day: Bool = false) {
        let (light, shade, drop): (UInt32, UInt32, UInt32) = day ? (0x9AA3B8, 0x7C859C, 0x5B86C6) : (0x9B97C4, 0x6F6B9C, 0xA9CCFF)
        let lumps: [(Double, Double, Double)] = small ? [(-5, -1, 3), (1, -3, 4.4), (6, -1, 3)]
            : [(-6, -2, 4.2), (1, -4, 6), (7, -2, 4.2)]
        var cells: Set<[Int]> = []
        for (lx, ly, r) in lumps {
            for (x, y) in PocketPixels.disc(lx, ly, r) where y <= 0 { cells.insert([x, y]) }
        }
        for cell in cells {
            canvas.put(cell[0] + cx, cell[1] + base, cells.contains([cell[0], cell[1] + 2]) ? light : shade)
        }
        for (index, dx) in (small ? [-4, 0, 4, 8] : [-6, -2, 2, 6, 10]).enumerated() {
            let dy = 2 + (index % 2) * 2
            canvas.put(dx + cx, base + dy, drop)
            canvas.put(dx + cx, base + dy + 1, drop)
        }
    }

    static func fireflies(_ canvas: inout PocketPixels, _ spots: [(Int, Int)]) {
        for (x, y) in spots { canvas.firefly(x, y) }
    }

    /// Two small Zs drifting up and to the right.
    static func sleep(_ canvas: inout PocketPixels, x: Int, top: Int, small: Bool = false) {
        let big = ["oooo", "..o.", ".o..", "oooo"], little = ["ooo", ".o.", "ooo"]
        for (glyph, ox, oy) in small ? [(little, 0, 1), (little, 4, -3)] : [(big, 0, 0), (little, 6, -5)] {
            for (dy, row) in glyph.enumerated() {
                for (dx, key) in row.enumerated() where key == "o" { canvas.put(x + ox + dx, top + oy + dy, 0xB9B3EC) }
            }
        }
    }

    static func ridge(_ canvas: inout PocketPixels, base: Double, amps: [(Double, Double)], colour: UInt32, seed: Double) {
        for x in 0..<canvas.width {
            var h = base
            for (index, (a, f)) in amps.enumerated() { h += a * sin(Double(x) / f + seed * (Double(index) + 1.7)) }
            for y in max(0, Int(h.rounded()))..<canvas.height { canvas.put(x, y, colour, tag: .ground) }
        }
    }

    /// A leafy clump lit from the upper left, with small two-pixel leaf marks.
    static func clump(_ canvas: inout PocketPixels, _ cx: Double, _ cy: Double, _ r: Double, _ tones: [UInt32], seed: Int,
                      squash: Double = 1) {
        var random = PocketRandom(seed)
        let phase = random.next() * 6.28, phase2 = random.next() * 6.28
        let light = (x: -0.6, y: -0.8)
        for y in (Int(cy - r * 1.2) - 1)...(Int(cy + r * 1.2) + 1) {
            for x in (Int(cx - r * 1.2) - 1)...(Int(cx + r * 1.2) + 1) {
                let dx = Double(x) + 0.5 - cx, dy = (Double(y) + 0.5 - cy) / squash
                let d = hypot(dx, dy)
                let angle = atan2(dy, dx)
                let reach = r * (1 + 0.1 * sin(6 * angle + phase) + 0.06 * sin(13 * angle + phase2))
                guard d <= reach else { continue }
                // A ragged, dithered rim.
                if d > reach - 1.2 && PocketPixels.noise(x, y, seed) < 0.3 { continue }
                let lit = (dx * light.x + dy * light.y) / max(reach, 1) + (PocketPixels.noise(x / 2, y / 2, seed) - 0.5) * 0.3
                var c = lit > 0.3 ? tones[2] : lit > -0.3 ? tones[1] : tones[0]
                let speckle = PocketPixels.noise(x / 2, y, seed + 7)
                if speckle > 0.94 && c == tones[1] { c = lit > 0 ? tones[2] : tones[0] }
                canvas.put(x, y, c, tag: .leaf)
            }
        }
    }
}

// MARK: - Pixels

/// A pixel buffer: one 0xRRGGBB colour, and what's there, per cell.
struct PocketPixels {
    enum Tag: UInt8 { case clear, sky, bark, leaf, ground, other }

    let width: Int
    let height: Int
    var colour: [UInt32]
    var tags: [Tag]

    init(width: Int, height: Int, fill: UInt32, clear: Bool = false) {
        self.width = width
        self.height = height
        colour = Array(repeating: fill, count: width * height)
        tags = Array(repeating: clear ? .clear : .other, count: width * height)
    }

    func tag(_ x: Int, _ y: Int) -> Tag { x >= 0 && x < width && y >= 0 && y < height ? tags[y * width + x] : .clear }

    mutating func put(_ x: Int, _ y: Int, _ c: UInt32, tag: Tag = .other) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        colour[y * width + x] = c
        tags[y * width + x] = tag
    }

    mutating func blend(_ x: Int, _ y: Int, _ c: UInt32, _ amount: Double) {
        guard x >= 0, x < width, y >= 0, y < height, tags[y * width + x] != .clear else { return }
        colour[y * width + x] = PocketColour.mix(colour[y * width + x], c, amount)
    }

    /// Stepped radial light: each ring adds its amount inside its radius, with a checkerboard edge.
    mutating func glow(_ cx: Double, _ cy: Double, _ rings: [(Double, Double)], _ c: UInt32) {
        let radius = rings.map(\.0).max() ?? 0
        for y in Int(cy - radius)...Int(cy + radius) {
            for x in Int(cx - radius)...Int(cx + radius) {
                let d = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
                var amount = 0.0
                for (r, a) in rings where d <= r - 1 || (d <= r && (x + y) % 2 == 0) { amount += a }
                if amount > 0 { blend(x, y, c, min(amount, 0.85)) }
            }
        }
    }

    /// A firefly: a pale core with a soft green halo, each of its pixels `size` cells square.
    mutating func firefly(_ x: Int, _ y: Int, size: Int = 1) {
        func block(_ dx: Int, _ dy: Int, _ paint: (inout PocketPixels, Int, Int) -> Void) {
            for by in 0..<size { for bx in 0..<size { paint(&self, x + dx * size + bx, y + dy * size + by) } }
        }
        for (dx, dy) in [(-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
            block(dx, dy) { $0.blend($1, $2, 0xE9FF9C, 0.22) }
        }
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { block(dx, dy) { $0.blend($1, $2, 0xE9FF9C, 0.55) } }
        block(0, 0) { $0.put($1, $2, 0xF2FFC2) }
    }

    /// An owlet's first frame, one pixel per sprite pixel.
    mutating func stamp(sprite: String, palette: String, left: Int, top: Int) {
        guard let frame = OwletArt.states[sprite]?.frames.first ?? OwletArt.states["idle"]?.frames.first else { return }
        let colours = OwletArt.palettes[palette] ?? OwletArt.palettes["golden"] ?? [:]
        for (index, key) in frame.enumerated() where key != "." && index < OwletArt.width * OwletArt.height {
            if let c = colours[key] { put(left + index % OwletArt.width, top + index / OwletArt.width, c) }
        }
    }

    func image() -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) where tags[index] != .clear {
            let c = colour[index]
            bytes[index * 4] = UInt8((c >> 16) & 0xFF)
            bytes[index * 4 + 1] = UInt8((c >> 8) & 0xFF)
            bytes[index * 4 + 2] = UInt8(c & 0xFF)
            bytes[index * 4 + 3] = 0xFF
        }
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The cells of a disc, as the pixel-art circle rule has it.
    static func disc(_ cx: Double, _ cy: Double, _ r: Double) -> [(Int, Int)] {
        var cells: [(Int, Int)] = []
        for y in (Int(cy - r) - 1)...(Int(cy + r) + 1) {
            for x in (Int(cx - r) - 1)...(Int(cx + r) + 1) where hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy) <= r {
                cells.append((x, y))
            }
        }
        return cells
    }

    /// A noise value in 0…1 for a cell, the same every time.
    static func noise(_ x: Int, _ y: Int, _ seed: Int = 0) -> Double {
        var n = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647)
        n = (n ^ (n >> 13)) &* 1_274_126_177
        return Double((n ^ (n >> 16)) & 0xFFFF) / 65535
    }
}

enum PocketColour {
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let from = Double((a >> shift) & 0xFF), to = Double((b >> shift) & 0xFF)
            return UInt32(max(0, min(255, (from + (to - from) * t).rounded())))
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    static func ramp(_ stops: [UInt32], _ t: Double) -> UInt32 {
        guard stops.count > 1 else { return stops.first ?? 0 }
        let position = max(0, min(1, t)) * Double(stops.count - 1)
        let index = min(Int(position), stops.count - 2)
        return mix(stops[index], stops[index + 1], position - Double(index))
    }
}

/// A deterministic random sequence (SplitMix64), so a scene paints the same every time.
struct PocketRandom {
    private var state: UInt64

    init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 &+ 0x6A09_E667_F3BC_C909 }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    mutating func int(_ range: Range<Int>) -> Int {
        min(range.upperBound - 1, range.lowerBound + Int(next() * Double(range.count)))
    }
}

// MARK: - Views

/// A baked scene shown one cell per point, every cell a crisp square.
struct PocketImage: View {
    let image: CGImage?
    /// Device pixels per point the image was painted at.
    var pixelsPerPoint: CGFloat = 1

    var body: some View {
        if let image {
            Image(decorative: image, scale: pixelsPerPoint)
                .interpolation(.none)
                .accessibilityHidden(true)
        }
    }
}

/// The plan as a moon that waxes as it's used, lit from the right. An old
/// reading is faded, with a dashed ring around it.
struct PocketMoon: View {
    let fraction: Double
    var stale = false
    var lit = Color(red: 0.97, green: 0.92, blue: 0.83)
    var dark = Color.white.opacity(0.12)

    var body: some View {
        Canvas { context, size in
            let ring: CGFloat = stale ? 2.5 : 0
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: ring, dy: ring)
            var moon = context
            moon.opacity = stale ? 0.55 : 1
            moon.fill(Path(ellipseIn: rect), with: .color(dark))
            moon.fill(Self.litPath(in: rect, fraction: fraction), with: .color(lit))
            if stale {
                context.stroke(Path(ellipseIn: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)),
                               with: .color(lit.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
            }
        }
        .accessibilityHidden(true)
    }

    /// The lit part, growing from the right as `fraction` goes from 0 to 1.
    static func litPath(in rect: CGRect, fraction: Double) -> Path {
        let lit = min(1, max(0, fraction)), r = rect.width / 2, centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let steps = 40
        for i in 0...steps {
            let angle = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            let point = CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        let bulge = r * (1 - 2 * lit)
        for i in stride(from: steps, through: 0, by: -1) {
            let angle = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: centre.x + bulge * cos(angle), y: centre.y + r * sin(angle)))
        }
        path.closeSubpath()
        return path
    }
}

/// The lantern's warm light, soft as the glass it shines through.
struct LanternGlow: View {
    let radius: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(red: 1, green: 0.71, blue: 0.28).opacity(0.6),
                                          Color(red: 1, green: 0.71, blue: 0.28).opacity(0)],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A count of helpers at work, in firefly green, worn at an owlet's shoulder.
struct BroodBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(Color(red: 0.94, green: 1, blue: 0.77))
            .padding(.horizontal, 5).frame(height: 13)
            .background(Color(red: 0.91, green: 1, blue: 0.61).opacity(0.18), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(red: 0.91, green: 1, blue: 0.61).opacity(0.45), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

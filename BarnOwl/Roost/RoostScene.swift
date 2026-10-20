import AppKit
import SwiftUI

/// The sky behind the Roost's tree. It follows the time of day and the real
/// moon, unless Settings say otherwise.
enum RoostSky: String, CaseIterable, Identifiable, Sendable {
    case follow, dusk, night, plain
    var id: Self { self }

    var title: String {
        switch self {
        case .follow: "Follow the Time of Day"
        case .dusk: "Always Dusk"
        case .night: "Always Night"
        case .plain: "Plain"
        }
    }

    enum Light: Sendable { case day, golden, dusk, night }

    func light(at date: Date) -> Light? {
        switch self {
        case .plain: return nil
        case .dusk: return .dusk
        case .night: return .night
        case .follow:
            let hour = Calendar.current.component(.hour, from: date)
            switch hour {
            case 8..<17: return .day
            case 6..<8, 17..<19: return .golden
            case 19..<21: return .dusk
            default: return .night
            }
        }
    }
}

/// The moon's phase, from a known new moon: 0 is new, 0.5 full.
enum MoonPhase {
    static func fraction(at date: Date) -> Double {
        let knownNew = Date(timeIntervalSince1970: 947_182_440) // 6 Jan 2000, 18:14 UTC
        let synodic = 29.530588853 * 86_400
        let elapsed = date.timeIntervalSince(knownNew).truncatingRemainder(dividingBy: synodic)
        return (elapsed < 0 ? elapsed + synodic : elapsed) / synodic
    }
}

// MARK: - The tree

/// The Roost as a place: one tree on one pixel grid. A branch per repository
/// with owlets doing something (the one that needs you on top), a lantern for
/// "needs you", a small rain cloud for "stuck"; owlets napping curl up in the
/// trunk's hollow, and the ones that finished today sleep in the nest.
///
/// The whole scene sits on one grid of 1.5 points per pixel (1 when space is
/// short, or on a 1x display), so the owlets and the tree always agree. The
/// sky and the tree are baked into two images, once per size, light and set of
/// branches; only the owlets (and the flock and the rain) move, and only while
/// `owletsMove` allows it.
struct RoostTreeView: View {
    /// For the right-click menu; nil in previews.
    let model: AppModel?
    let sessions: [AgentSession]
    let cameHome: [AgentSession]
    let sky: RoostSky
    @Binding var selected: String?
    /// Whether the tree may grow taller than the view and scroll. Without it
    /// (the pop-out window, previews) the tree always fits: the grid steps down,
    /// crowded branches end in "+N", and repositories that still don't fit are
    /// named at the foot of the tree.
    var scrolls: Bool = true
    /// The moment to paint, for previews; otherwise now, refreshed every minute.
    var date: Date? = nil

    @Environment(\.owletsMove) private var moves
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.everyMinute) { context in
            GeometryReader { proxy in
                let now = date ?? context.date
                let plan = TreePlan.fitting(sessions: sessions, cameHome: cameHome, size: proxy.size, now: now,
                                            units: displayScale >= 2 ? [1.5, 1] : [1], scrolls: scrolls)
                let style = TreeStyle(light: sky.light(at: now), moon: MoonPhase.fraction(at: now),
                                      contrast: contrast == .increased)
                TreeScroller(plan: plan, style: style, size: proxy.size, model: model, selected: $selected,
                             scrolls: scrolls, moves: moves)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Roost")
    }
}

/// The light the scene is painted in, and how strongly.
struct TreeStyle: Equatable {
    var light: RoostSky.Light?
    /// The moon's phase in 64ths, so the sky is re-painted a few times a day at most.
    var moon: Int
    var contrast: Bool

    init(light: RoostSky.Light?, moon: Double, contrast: Bool) {
        self.light = light
        self.moon = Int((moon * 64).rounded()) % 64
        self.contrast = contrast
    }

    var palette: TreePalette { TreePalette.of(light, contrast: contrast) }
    var ink: Color { Color(hex: palette.ink) }
    var halo: Double { contrast ? 0.85 : 0.62 }
    /// The lantern's light, scaled with the ambient light so it reads the same at every hour.
    var lantern: Double {
        switch light {
        case .day: 0.55
        case .golden: 0.85
        default: 1
        }
    }
}

// MARK: Layout

/// Where everything sits, in cells of the scene's grid, worked out once per
/// size and set of sessions so the painting and the owlets agree.
struct TreePlan: Equatable {
    static let trunkX = 60
    static let trunkTop = 80
    /// Where branches leave the trunk.
    static let branchRoot = 68
    /// Where repository names start, clear of the bark.
    static let labelX = 80
    static let firstBranch = 96
    static let nest = (x: 61, y: 68)
    /// The hollow in the trunk where napping owlets curl up.
    static let hollow = (x: 62, y: 120)
    /// From the meadow's top to the bottom of the scene.
    static let ground = 42

    struct Branch: Hashable {
        var repository: String
        /// The branch's top surface where it leaves the trunk's lean.
        var y: Int
        var end: Int
        /// 0.25…1: how much work this repository saw today.
        var leafy: Double
        var labelled: Bool
        /// Where owlets and hatchlings sit, so no leaves grow there.
        var avoid: [Int]
        /// A bare twig: a repository with nobody doing anything, or an empty tree.
        var bare: Bool
        var seed: Int
    }

    struct Perch: Equatable, Identifiable {
        var session: AgentSession
        var name: String
        /// Tells it apart from a twin of the same name: its worktree, or when it started.
        var suffix: String?
        var x: Int
        /// The branch's top row under the owlet's feet.
        var top: Int
        /// Working helpers beside it, at most five: true for one just hatched.
        var kids: [Bool]
        /// All working helpers, when there are more than five: they fly as a flock.
        var flock: Int
        var flockX: Int
        var animated: Bool
        /// Room for its labels, in points.
        var labelWidth: CGFloat
        var id: String { session.id }
    }

    /// A twig grown out of a caller's branch for the agents it asked to help:
    /// it falls away below the caller's labels, then runs on nearly level.
    struct Twig: Hashable {
        /// Where it leaves the branch, and the branch's top there.
        var x: Int
        var from: Int
        /// Its top once level, and its tip.
        var y: Int
        var end: Int
        var seed: Int
        /// Cells it takes to fall to its level.
        static let fall = 28

        func top(at column: Int) -> Int {
            let t = min(1, max(0, Double(column - x) / Double(Self.fall)))
            let fallen = Double(from) + Double(y - from) * t * t * (3 - 2 * t)
            let past = Double(max(0, column - (end - 24)))
            return Int((fallen + past * past / (24 * 24) * 2).rounded())
        }
    }

    /// The helpers on one caller's twig: one label for them all, and a flock
    /// for those past the first few.
    struct Helpers: Equatable {
        var caller: String
        var callerName: String
        var working: Int
        /// Out but idle, at their prompt.
        var idle: Int
        var back: Int
        /// Where they work, when it isn't the caller's repository.
        var place: String?
        /// The label's top-left, in cells.
        var labelX: Int
        var labelY: Int
        /// The rest, huddled at the twig's end.
        var flock: [AgentSession]
        var flockX: Int
        var flockTop: Int
    }

    /// Owlets that didn't fit on their branch: "+N" at its end.
    struct Overflow: Equatable {
        var repository: String
        var x: Int
        var y: Int
        var sessions: [AgentSession]
    }

    /// The owlets curled up in the hollow, or asleep in the nest.
    struct Group: Equatable {
        /// The live sessions in it, which you can pick.
        var ids: [String] = []
        var names: [String] = []
        /// The first few, to draw.
        var palettes: [String] = []
        var count = 0
    }

    var unit: CGFloat
    var cols: Int
    var rows = 0
    var viewRows: Int
    var firstPerch: Int
    /// Cells from a branch's top to the bottom of its owlets' labels.
    var labelBottom: Int
    var branches: [Branch] = []
    var perches: [Perch] = []
    var twigs: [Twig] = []
    var helpers: [Helpers] = []
    var overflows: [Overflow] = []
    var hollow = Group()
    var nest = Group()
    /// Repositories that didn't fit at all.
    var hidden: [String] = []
    var isEmpty: Bool
    /// Owlets out, but none doing anything.
    var allQuiet: Bool
    var fits = true

    /// Picks the largest grid that fits everything; failing that, the smallest,
    /// trimmed to fit unless the tree may scroll.
    static func fitting(sessions: [AgentSession], cameHome: [AgentSession], size: CGSize, now: Date, units: [CGFloat],
                        scrolls: Bool) -> TreePlan {
        for unit in units.dropLast() {
            let plan = TreePlan(sessions: sessions, cameHome: cameHome, size: size, now: now, unit: unit, trim: false)
            if plan.fits { return plan }
        }
        let smallest = TreePlan(sessions: sessions, cameHome: cameHome, size: size, now: now, unit: units.last ?? 1,
                                trim: !scrolls)
        // A tree that may scroll keeps its first grid rather than shrinking to a size that still won't fit.
        if scrolls, !smallest.fits, let first = units.first, first != units.last {
            return TreePlan(sessions: sessions, cameHome: cameHome, size: size, now: now, unit: first, trim: false)
        }
        return smallest
    }

    /// Doing something, so it sits on a branch rather than in the hollow or the nest.
    static func isOnBranch(_ state: OwletState) -> Bool {
        switch state {
        case .napping, .resting, .done, .shipped: false
        default: true
        }
    }

    static func isNapping(_ state: OwletState) -> Bool { state == .napping || state == .resting }

    /// `withTwigs`: the callers that may grow a twig. Left out, every caller out on a branch
    /// may; callers that turn out to have no room are left out on a second pass, so their
    /// helpers perch on their own branches instead of going missing.
    init(sessions: [AgentSession], cameHome: [AgentSession], size: CGSize, now: Date, unit: CGFloat, trim: Bool,
         withTwigs: Set<String>? = nil) {
        self.unit = unit
        cols = max(150, Int((size.width / unit).rounded(.up)))
        viewRows = max(100, Int((size.height / unit).rounded(.up)))
        labelBottom = 6 + Int((31 / unit).rounded(.up))
        firstPerch = Self.labelX + Int((104 / unit).rounded(.up)) + 20
        let everyone = sessions.sorted(by: AgentWatcher.order)
        // Helpers perch with a caller that's out on a branch; otherwise they're owlets like any other.
        let callers = withTwigs ?? Set(everyone.filter { Self.isOnBranch($0.state) && !$0.isHelper }.map(\.id))
        let helping = Dictionary(grouping: everyone.filter { $0.calledBy.map(callers.contains) ?? false },
                                 by: { $0.calledBy ?? "" })
        let ordered = everyone.filter { !($0.calledBy.map(callers.contains) ?? false) }
        let active = ordered.filter { Self.isOnBranch($0.state) }
        let nappers = ordered.filter { Self.isNapping($0.state) }
        let finished = ordered.filter { $0.state == .done || $0.state == .shipped }
        hollow = Group(ids: nappers.map(\.id), names: nappers.map(Self.baseName), palettes: nappers.prefix(3).map(\.agent.palette),
                       count: nappers.count)
        // Helpers that finished went back to a caller that's out, not to the nest.
        let home = cameHome.filter { !($0.calledBy.map(callers.contains) ?? false) } + finished
        nest = Group(ids: finished.map(\.id), names: home.map(Self.baseName), palettes: home.suffix(3).map(\.agent.palette),
                     count: home.count)
        isEmpty = everyone.isEmpty && cameHome.isEmpty
        allQuiet = active.isEmpty && !isEmpty

        let names = Self.tellApart(active)
        let lively = Set(active.prefix(6).map(\.id))
        var repositories: [String] = []
        var groups: [String: [AgentSession]] = [:]
        for session in active {
            if groups[session.place.repository] == nil { repositories.append(session.place.repository) }
            groups[session.place.repository, default: []].append(session)
        }

        // Each placed branch, and the row below its labels.
        var placed: [(branch: Branch, perches: [Perch], overflow: Overflow?, bottom: Int)] = []
        var grown: [String: (twigs: [Twig], helpers: [Helpers], perches: [Perch])] = [:]
        let labelHalf = Int((70 / unit).rounded(.up))
        let limit = cols - 4
        for repository in repositories {
            let members = groups[repository] ?? []
            let leafy = Self.leafiness(repository, live: members, home: cameHome, now: now)
            struct Spec { var session: AgentSession; var kids: [Bool]; var flock: Int; var right: Int; var advance: Int }
            let specs = members.map { session -> Spec in
                let working = session.helpersByActivity.filter(\.isWorking)
                let kids = working.prefix(5).map { now.timeIntervalSince($0.started) < 20 }
                let flock = working.count > 5 ? working.count : 0
                let right = kids.isEmpty ? 12 : 20 + 8 * (kids.count - 1)
                var advance = max(Int((116 / unit).rounded(.up)), right + 34)
                if flock > 0 { advance = max(advance, 62 + max(17, Int((52 / unit).rounded(.up))) + 22) }
                return Spec(session: session, kids: kids, flock: flock, right: right, advance: advance)
            }
            func centre(_ index: Int) -> Int { firstPerch + specs.prefix(index).reduce(0) { $0 + $1.advance } }
            func edge(_ count: Int) -> Int { centre(count - 1) + max(specs[count - 1].right, labelHalf) }
            // As many as fit, the rest summed up as "+N" at the branch's end.
            var shown = specs.count
            if edge(shown) > limit {
                let room = Int((30 / unit).rounded(.up))
                while shown > 1 && edge(shown) + room > limit { shown -= 1 }
            }
            let headroom = specs.prefix(shown).map { $0.flock > 0 ? 47 : $0.session.state == .stuck ? 41 : 28 }.max() ?? 28
            let y = placed.last.map { $0.bottom + headroom + 3 } ?? Self.firstBranch + max(0, headroom - 36)

            let last = specs[shown - 1]
            let natural = centre(shown - 1) - firstPerch
            let tail = Int(((40 + 150 * leafy) / unit).rounded()) + (shown - 1) * Int((24 / unit).rounded())
            var end = min(cols - 8, firstPerch + natural + last.right + tail)
            if shown < specs.count { end = cols - 8 }
            end = max(end, firstPerch + natural + last.right + 12)
            // Spread the owlets along the branch rather than piling them by the trunk.
            let furthest = min(end - last.right - 14, limit - labelHalf)
            let stretch = shown > 1 && natural > 0 ? min(1.9, max(1, Double(furthest - firstPerch) / Double(natural))) : 1
            var xs: [Int] = []
            for index in 0..<shown { xs.append(firstPerch + Int((Double(centre(index) - firstPerch) * stretch).rounded())) }

            var avoid = [Self.branchRoot + 14]
            for (index, spec) in specs.prefix(shown).enumerated() {
                avoid.append(xs[index])
                avoid += spec.kids.indices.map { xs[index] + 16 + 8 * $0 }
            }
            let branch = Branch(repository: repository, y: y, end: end, leafy: leafy, labelled: true, avoid: avoid, bare: false,
                                seed: Self.stableHash(repository) % 997)
            var perches: [Perch] = []
            for (index, spec) in specs.prefix(shown).enumerated() {
                let before = index == 0 ? 2 * (xs[0] - Self.branchRoot) : xs[index] - xs[index - 1]
                let after = index == shown - 1 ? 2 * (limit - xs[index]) : xs[index + 1] - xs[index]
                let width = min(190, CGFloat(min(before, after)) * unit - 10)
                perches.append(Perch(session: spec.session, name: Self.baseName(spec.session), suffix: names[spec.session.id],
                                     x: xs[index],
                                     top: Self.top(of: branch, at: xs[index]), kids: spec.kids, flock: spec.flock,
                                     flockX: min(xs[index] + 62, cols - max(22, Int((54 / unit).rounded(.up)))),
                                     animated: lively.contains(spec.session.id),
                                     labelWidth: max(70, width)))
            }
            // Each caller's helpers, on a twig of its own below the caller's labels. Twigs on one
            // branch stack: the rightmost caller's highest, so no twig falls across another.
            var bottom = y + labelBottom
            var twigsHere: [Twig] = [], groupsHere: [Helpers] = [], helperPerches: [Perch] = []
            let lane = labelBottom + 30 + Int((20 / unit).rounded(.up))
            let recent = { (caller: String) in
                cameHome.filter { $0.calledBy == caller && now.timeIntervalSince($0.stateSince) < 10 * 60 }
            }
            let withHelpers = specs.prefix(shown).indices.filter { index in
                let id = specs[index].session.id
                return callers.contains(id) && (!(helping[id] ?? []).isEmpty || !recent(id).isEmpty)
            }
            var stack = 0
            for index in withHelpers.sorted(by: { xs[$0] > xs[$1] }) {
                let spec = specs[index]
                let team = helping[spec.session.id] ?? []
                let x0 = xs[index] + max(spec.right, 12) + 4
                let level = y + lane * (stack + 1)
                let step = Int((116 / unit).rounded(.up))
                let first = x0 + Twig.fall + 12
                var room = 0
                while room < team.count, first + room * step + labelHalf <= limit { room += 1 }
                // No room at all: no twig; its helpers perch on their own branch instead.
                guard team.isEmpty ? first + 30 <= limit : room > 0 else { continue }
                // Up to five sit in a row; past that, four do and the rest huddle as a flock.
                let perched = team.count <= 5 ? min(team.count, room) : min(4, max(room - 1, 0))
                let rest = Array(team.dropFirst(perched))
                let flockX = min(first + max(perched, 0) * step - (perched > 0 ? step / 4 : 0), cols - 46)
                let tip = min(cols - 8, max(x0 + Twig.fall + 30,
                                            (rest.isEmpty ? first + max(perched - 1, 0) * step + 22 : flockX + 30) + 8))
                let twig = Twig(x: x0, from: Self.top(of: branch, at: x0) + 1, y: level, end: tip,
                                seed: Self.stableHash(spec.session.id) % 997)
                for (place, helper) in team.prefix(perched).enumerated() {
                    let hx = first + place * step
                    helperPerches.append(Perch(session: helper, name: Self.baseName(helper), suffix: nil, x: hx,
                                               top: twig.top(at: hx), kids: [], flock: 0, flockX: hx,
                                               animated: lively.contains(helper.id) || place < 2,
                                               labelWidth: max(70, min(190, CGFloat(step) * unit - 10))))
                }
                let places = Set(team.map(\.place.repository))
                let elsewhere = places.count == 1 && places.first != repository ? places.first : nil
                let idle = team.filter { Self.isNapping($0.state) }.count
                groupsHere.append(Helpers(caller: spec.session.id, callerName: Self.baseName(spec.session),
                                          working: team.count - idle, idle: idle,
                                          back: cameHome.filter { $0.calledBy == spec.session.id }.count,
                                          place: elsewhere, labelX: min(first - 14, cols - 8 - Int((150 / unit).rounded())),
                                          labelY: level - 30 - Int((18 / unit).rounded(.up)),
                                          flock: rest, flockX: flockX, flockTop: twig.top(at: flockX)))
                twigsHere.append(twig)
                bottom = max(bottom, level + labelBottom)
                stack += 1
            }
            grown[repository] = (twigsHere, groupsHere, helperPerches)

            var overflow: Overflow?
            if shown < specs.count {
                let x = min(xs[shown - 1] + last.right + 6, limit - Int((26 / unit).rounded(.up)))
                overflow = Overflow(repository: repository, x: x, y: Self.top(of: branch, at: min(x, end)),
                                    sessions: specs.dropFirst(shown).map(\.session))
            }
            placed.append((branch, perches, overflow, bottom))
        }

        // Repositories with nobody doing anything keep a short bare twig, their names dimmed.
        let live = Set(repositories)
        var quiet: [String] = []
        for session in ordered + cameHome.filter({ !$0.isHelper }).reversed() where !live.contains(session.place.repository)
            && !quiet.contains(session.place.repository) {
            quiet.append(session.place.repository)
        }
        let quietStep = 6 + Int((17 / unit).rounded(.up))
        let floor = { (bottom: Int) in max(bottom, Self.hollow.y + 12, 150) + 6 + Self.ground }
        let busyBottom = placed.last?.bottom
        func twigs(_ names: [String]) -> [(branch: Branch, perches: [Perch], overflow: Overflow?, bottom: Int)] {
            var list: [(branch: Branch, perches: [Perch], overflow: Overflow?, bottom: Int)] = []
            for (index, name) in names.enumerated() {
                let y = (list.last?.bottom ?? busyBottom.map { $0 + 4 }).map { $0 + quietStep } ?? Self.firstBranch + 4
                list.append((Branch(repository: name, y: y, end: Self.branchRoot + 34 + 12 * (index % 2), leafy: 0,
                                    labelled: true, avoid: [], bare: true, seed: Self.stableHash(name) % 997), [], nil, y + 4))
            }
            return list
        }
        var quietTwigs = twigs(Array(quiet.prefix(8)))
        // Short of room: the quiet ones share one twig ("infra · dotfiles") before anything shrinks.
        if quiet.count > 1, floor(quietTwigs.last?.bottom ?? 0) > viewRows {
            quietTwigs = twigs([quiet.joined(separator: " · ")])
        }
        placed += quietTwigs

        // Fit: everything above the meadow, or trimmed from the bottom when it may not scroll.
        var needed = floor(placed.last?.bottom ?? 0)
        if trim {
            while needed > viewRows, placed.count > 1 {
                let dropped = placed.removeLast().branch
                hidden.insert(contentsOf: dropped.bare ? dropped.repository.components(separatedBy: " · ")
                              : [dropped.repository], at: 0)
                needed = floor(placed.last?.bottom ?? 0)
            }
        }
        rows = trim ? viewRows : max(viewRows, needed)
        for entry in placed {
            branches.append(entry.branch)
            perches += entry.perches
            if let overflow = entry.overflow { overflows.append(overflow) }
            if !entry.branch.bare, let extra = grown[entry.branch.repository] {
                self.twigs += extra.twigs
                self.helpers += extra.helpers
                perches += extra.perches
            }
        }
        if isEmpty {
            // Nobody out: two waiting branches.
            for (twigY, end) in [(112, 196), (176, 164)] {
                branches.append(Branch(repository: "", y: twigY, end: end, leafy: 0, labelled: false, avoid: [], bare: true,
                                       seed: twigY))
            }
        }
        // Crowded branches end in "+N" rather than shrinking the whole tree; only height steps the grid down.
        fits = needed <= viewRows && hidden.isEmpty

        // A caller that ended up in a branch's "+N", was trimmed, or had no room grew no twig:
        // lay the tree out again with its helpers on their own branches.
        let grew = Set(self.helpers.map(\.caller))
        if withTwigs == nil, !Set(helping.keys).isSubset(of: grew) {
            self = TreePlan(sessions: sessions, cameHome: cameHome, size: size, now: now, unit: unit, trim: trim,
                            withTwigs: grew)
        }
    }

    /// The branch's top row at x: it rises out of the trunk and droops at the tip.
    static func top(of branch: Branch, at x: Int) -> Int {
        let u = Double(x - branchRoot)
        let rise = 9 * exp(-u / 13)
        let past = Double(max(0, x - (branch.end - 34)))
        let droop = past * past / (34 * 34) * 5
        return Int((Double(branch.y) + rise + droop).rounded())
    }

    /// "2 Codex · 1 Vibe, working"
    static func makeUp(_ helpers: [AgentSession]) -> String {
        var counts: [(String, Int)] = []
        for helper in helpers {
            let name = helper.agent == .vibe ? "Vibe" : helper.agent.name
            if let index = counts.firstIndex(where: { $0.0 == name }) { counts[index].1 += 1 } else { counts.append((name, 1)) }
        }
        let waiting = helpers.contains { $0.state.needsYou }
        return counts.map { "\($0.1) \($0.0)" }.joined(separator: " · ") + (waiting ? ", one needs you" : ", working")
    }

    static func baseName(_ session: AgentSession) -> String {
        session.name == session.place.repository ? session.agent.name : session.name
    }

    /// What tells twins of the same name apart: their worktrees, or else when they started ("21:04").
    static func tellApart(_ sessions: [AgentSession]) -> [String: String] {
        let byName = Dictionary(grouping: sessions, by: baseName)
        var suffixes: [String: String] = [:]
        for twins in byName.values where twins.count > 1 {
            let distinct = Set(twins.compactMap(\.place.worktree)).count == twins.count
            for session in twins {
                suffixes[session.id] = distinct ? session.place.worktree
                    : session.started.formatted(date: .omitted, time: .shortened)
            }
        }
        return suffixes
    }

    /// How leafy a repository's branch is: it grows with the day's work, in
    /// four steps so the tree is re-painted only a few times a day.
    static func leafiness(_ repository: String, live: [AgentSession], home: [AgentSession], now: Date) -> Double {
        var minutes = 0.0
        for session in live {
            minutes += min(max(0, now.timeIntervalSince(session.started)), 3 * 3600) / 60 + Double(session.helpers.count) * 4
        }
        for session in home where session.place.repository == repository {
            let turn = session.lastTurn ?? session.stateSince.timeIntervalSince(session.started)
            minutes += min(max(0, turn), 3 * 3600) / 60
        }
        let raw = 0.25 + 0.75 * min(1, minutes / 240)
        return min(1, max(0.25, (raw * 4).rounded() / 4))
    }

    /// A hash that stays the same from launch to launch, unlike `hashValue`.
    static func stableHash(_ text: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash & 0x7FFF_FFFF)
    }

    /// Changes whenever an owlet moves, arrives, leaves or changes pose.
    var motion: [String] {
        perches.map { "\($0.id)@\($0.x),\($0.top),\($0.session.state.rawValue)" }
            + helpers.map { "\($0.caller)+\($0.flock.count)" } + ["\(unit)", "\(hollow.count)", "\(nest.count)"]
    }
}

// MARK: Scrolling and parallax

private struct TreeScroller: View {
    let plan: TreePlan
    let style: TreeStyle
    let size: CGSize
    let model: AppModel?
    @Binding var selected: String?
    let scrolls: Bool
    let moves: Bool
    @State private var offset: CGFloat = 0

    /// The backdrop scrolls at 0.3x behind the tree, which is what tells the eye there's depth.
    private static let parallax = 0.3

    var body: some View {
        let tall = plan.rows > plan.viewRows
        let parallax = scrolls && moves && tall
        let skyRows = parallax ? plan.viewRows + Int((Double(plan.rows - plan.viewRows) * Self.parallax).rounded(.up))
            : plan.rows
        let images = TreeScenery.images(for: TreeScenery.Key(plan: plan, style: style, skyRows: skyRows))
        let height = tall ? CGFloat(plan.rows) * plan.unit : size.height
        let stage = TreeStage(plan: plan, style: style, model: model, selected: selected, select: { selected = $0 },
                              moves: moves, tree: images.tree, sky: parallax ? nil : images.sky, width: size.width,
                              height: height)
            .equatable()
        if scrolls && tall {
            ScrollView(.vertical) { stage }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in
                    offset = new
                }
                .background(alignment: .topLeading) {
                    if parallax, let sky = images.sky {
                        TreePixelImage(image: sky, unit: plan.unit)
                            .offset(y: -min(max(0, offset), height - size.height) * Self.parallax)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let hint { hint.padding(.leading, 12).padding(.bottom, 10).allowsHitTesting(false) }
                }
        } else {
            stage
        }
    }

    /// "dotfiles, docs further down the trunk ↓", for branches below the window, by the trunk's foot.
    private var hint: TreeHaloText? {
        let bottom = offset + size.height - 8
        let names = plan.branches.filter { $0.labelled && CGFloat($0.y) * plan.unit > bottom }.map(\.repository)
        guard !names.isEmpty else { return nil }
        let list = names.count > 2 ? "\(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
            : names.joined(separator: ", ")
        return TreeHaloText(text: "\(list) further down the trunk ↓", size: 9.5, weight: .semibold,
                            colour: .white.opacity(0.82), ink: style.ink, halo: style.halo)
    }
}

// MARK: The stage

private struct TreeStage: View, Equatable {
    let plan: TreePlan
    let style: TreeStyle
    let model: AppModel?
    let selected: String?
    let select: (String?) -> Void
    let moves: Bool
    let tree: CGImage?
    let sky: CGImage?
    let width: CGFloat
    let height: CGFloat

    nonisolated static func == (a: TreeStage, b: TreeStage) -> Bool {
        a.plan == b.plan && a.style == b.style && a.model === b.model && a.selected == b.selected
            && a.moves == b.moves && a.tree === b.tree && a.sky === b.sky && a.width == b.width && a.height == b.height
    }

    private var u: CGFloat { plan.unit }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let sky { TreePixelImage(image: sky, unit: u) }
            if let tree { TreePixelImage(image: tree, unit: u) }
            ForEach(plan.branches.filter(\.labelled), id: \.self) { branch in repositoryName(branch) }
            hollow
            nest
            ForEach(plan.perches) { perch in
                TreePerch(perch: perch, unit: u, labelBottom: plan.labelBottom, style: style, selected: selected == perch.id,
                          moves: moves, model: model, select: select)
                    .id(moves ? perch.id : "\(perch.id)@\(perch.x),\(perch.top)")
                    .position(x: CGFloat(perch.x) * u,
                              y: (CGFloat(perch.top - TreePerch.above) + CGFloat(TreePerch.above + plan.labelBottom + 2) / 2) * u)
                    .transition(transition(for: perch))
            }
            ForEach(plan.helpers, id: \.caller) { group in helpers(group) }
            ForEach(plan.overflows, id: \.repository) { overflow in more(overflow) }
            if !plan.hidden.isEmpty { hiddenNote }
            if plan.isEmpty {
                message("No owlets out", "Start Claude Code, Codex or another agent, and an owlet will perch here.")
            } else if plan.allQuiet {
                message("All quiet", quietLine)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .animation(moves ? .spring(response: 0.32, dampingFraction: 0.82) : .easeInOut(duration: 0.2), value: plan.motion)
    }

    /// The repository's name above its branch, clear of the joint and the bark; long names wrap.
    @ViewBuilder
    private func repositoryName(_ branch: TreePlan.Branch) -> some View {
        let x = CGFloat(TreePlan.labelX) * u
        let base = CGFloat(branch.y - 3) * u + 2
        if branch.bare {
            TreeHaloText(text: branch.repository, size: 10, weight: .semibold, tracking: 0.3, colour: .white.opacity(0.56),
                         ink: style.ink, halo: style.halo, alignment: .leading)
                .frame(width: CGFloat(plan.cols - TreePlan.labelX - 6) * u, height: 14, alignment: .bottomLeading)
                .offset(x: x, y: base - 14)
                .help("Nobody's working in \(branch.repository) right now")
                .accessibilityLabel("\(branch.repository), quiet")
        } else {
            let room = CGFloat(plan.firstPerch - 22 - TreePlan.labelX) * u
            TreeHaloText(text: branch.repository, size: 10, weight: .bold, tracking: 0.4, colour: .white.opacity(0.86),
                         ink: style.ink, halo: style.halo, lines: 2, alignment: .leading)
                .frame(width: room, height: 28, alignment: .bottomLeading)
                .offset(x: x, y: base - 28)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Owlets hatch onto their branch, and fly home to the nest when they finish.
    private func transition(for perch: TreePlan.Perch) -> AnyTransition {
        guard moves else { return .opacity }
        let home = CGSize(width: CGFloat(TreePlan.nest.x - perch.x) * u, height: CGFloat(TreePlan.nest.y - 6 - perch.top) * u)
        return .asymmetric(
            insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
                .animation(.spring(response: 0.22, dampingFraction: 0.6)),
            removal: .offset(home).combined(with: .scale(scale: 0.4)).combined(with: .opacity)
                .animation(.spring(response: 0.55, dampingFraction: 0.9)))
    }

    /// Picks the next owlet of a group, so repeated clicks reach each one.
    private func cycle(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        if let current = selected, let index = ids.firstIndex(of: current) {
            select(ids[(index + 1) % ids.count])
        } else {
            select(ids[0])
        }
    }

    private func list(_ names: [String]) -> String {
        names.count > 8 ? names.prefix(8).joined(separator: ", ") + " and \(names.count - 8) more" : names.joined(separator: ", ")
    }

    /// Napping owlets, curled up together in the trunk's hollow, their count beside it.
    @ViewBuilder
    private var hollow: some View {
        let group = plan.hollow
        if group.count > 0 {
            let (hx, hy) = TreePlan.hollow
            let picked = selected.map(group.ids.contains) ?? false
            let labelRight = CGFloat(hx - 17) * u
            TreeHaloText(text: "\(group.count) napping", size: labelRight < 60 ? 9 : 10, weight: .semibold,
                         colour: .white.opacity(0.86), ink: style.ink, halo: style.halo, alignment: .trailing, shrink: 0.7)
                .frame(width: max(40, labelRight - 2), alignment: .trailing)
                .offset(x: 1, y: CGFloat(hy + 1) * u - 7)
            if picked { TreeSelectionMarks(width: 28, height: 20, unit: u).treeCell(hx - 14, hy - 10, u) }
            Color.clear
                .frame(width: CGFloat(hx + 13) * u, height: 22 * u)
                .contentShape(.rect)
                .offset(y: CGFloat(hy - 11) * u)
                .onTapGesture(count: 2) { model?.showRoost(picked ? selected : group.ids.first) }
                .onTapGesture { cycle(group.ids) }
                .help("Napping: \(list(group.names))")
                .accessibilityElement()
                .accessibilityLabel("Hollow, \(group.count) napping: \(list(group.names))")
                .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { cycle(group.ids) }
        }
    }

    /// The nest in the crown: owlets that finished today, asleep.
    @ViewBuilder
    private var nest: some View {
        let group = plan.nest
        if group.count > 0 {
            let (x, y) = TreePlan.nest
            let picked = selected.map(group.ids.contains) ?? false
            TreeHaloText(text: "\(group.count) home today", size: 9.5, weight: .semibold, colour: .white.opacity(0.84),
                         ink: style.ink, halo: style.halo)
                .frame(width: 120)
                .offset(x: CGFloat(x + 1) * u - 60, y: CGFloat(y - 21) * u - 12)
            if picked { TreeSelectionMarks(width: 36, height: 24, unit: u).treeCell(x - 18, y - 18, u) }
            Color.clear
                .frame(width: 36 * u, height: 26 * u)
                .contentShape(.rect)
                .offset(x: CGFloat(x - 18) * u, y: CGFloat(y - 18) * u)
                .onTapGesture(count: 2) { model?.showRoost(picked ? selected : group.ids.first) }
                .onTapGesture { cycle(group.ids) }
                .help("Home today: \(list(group.names))")
                .accessibilityElement()
                .accessibilityLabel("Nest, \(group.count) home today: \(list(group.names))")
                .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { cycle(group.ids) }
        }
    }

    /// One label for a caller's helpers ("Asked by Vibe support · 7 working · 3 back"),
    /// and the ones past the first few, huddled at the twig's end. Either picks the caller,
    /// whose inspector lists them all.
    @ViewBuilder
    private func helpers(_ group: TreePlan.Helpers) -> some View {
        let picked = selected == group.caller
        var counts: [String] = []
        if group.working > 0 { counts.append("\(group.working) working") }
        if group.idle > 0 { counts.append("\(group.idle) idle") }
        if group.back > 0 { counts.append(group.working + group.idle == 0 ? "all \(group.back) back" : "\(group.back) back") }
        if let place = group.place { counts.append("in \(place)") }
        return Group {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: 0xF5B04F)).frame(width: 6, height: 6)
                (Text("Asked by ") + Text(group.callerName).fontWeight(.semibold) + Text(" · " + counts.joined(separator: " · ")))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(picked ? 1 : 0.9))
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(style.ink.opacity(0.62), in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(picked ? 0.5 : 0.14), lineWidth: 1) }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: CGFloat(plan.cols - group.labelX - 4) * u, alignment: .leading)
            .contentShape(.capsule)
            .onTapGesture { select(group.caller) }
            .help("Agents \(group.callerName) asked to help. Click to list them.")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select(group.caller) }
            .offset(x: CGFloat(group.labelX) * u, y: CGFloat(group.labelY) * u)

            if !group.flock.isEmpty {
                let shown = Array(group.flock.prefix(3))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, helper in
                        OwletSprite(sprite: helper.state.sprite, palette: helper.agent.palette, scale: u,
                                    seed: TreePlan.stableHash(helper.id), animated: moves && index == shown.count - 1)
                            .treeCell(13 * index, index == 1 ? 2 : index == 0 ? 4 : 0, u)
                    }
                }
                .treeCell(group.flockX - 16, group.flockTop - 32, u)
                .allowsHitTesting(false)
                TreeHaloText(text: "+\(group.flock.count)", size: 10, weight: .bold, colour: .white, ink: style.ink,
                             halo: style.halo)
                    .offset(x: CGFloat(group.flockX + 13 * (shown.count - 1) + 10) * u, y: CGFloat(group.flockTop - 34) * u)
                VStack(spacing: 1) {
                    TreeHaloText(text: "\(group.flock.count) more", size: 11, weight: .semibold, ink: style.ink, halo: style.halo)
                    TreeHaloText(text: TreePlan.makeUp(group.flock), size: 10, weight: .medium, colour: .white.opacity(0.78),
                                 ink: style.ink, halo: style.halo)
                }
                .frame(width: 150)
                .contentShape(.rect)
                .onTapGesture { select(group.caller) }
                .offset(x: CGFloat(group.flockX + 13 * (shown.count - 1) / 2) * u - 75, y: CGFloat(group.flockTop + 6) * u + 1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { select(group.caller) }
            }
        }
    }

    /// "+3" at the end of a crowded branch.
    private func more(_ overflow: TreePlan.Overflow) -> some View {
        let names = overflow.sessions.map(TreePlan.baseName)
        let picked = selected.map { id in overflow.sessions.contains { $0.id == id } } ?? false
        return TreeHaloText(text: "+\(overflow.sessions.count)", size: 11, weight: .bold,
                            colour: picked ? .white : .white.opacity(0.86), ink: style.ink, halo: style.halo)
            .padding(.horizontal, 4)
            .contentShape(.rect)
            .onTapGesture { cycle(overflow.sessions.map(\.id)) }
            .help("Also on \(overflow.repository): \(list(names))")
            .offset(x: CGFloat(overflow.x) * u, y: CGFloat(overflow.y - 14) * u - 8)
            .accessibilityLabel("\(overflow.sessions.count) more in \(overflow.repository): \(list(names))")
            .accessibilityAddTraits(.isButton)
    }

    /// Repositories that didn't fit, named at the foot of the tree.
    private var hiddenNote: some View {
        let hidden = plan.hidden
        let text = switch hidden.count {
        case 1: "\(hidden[0]) doesn't fit here"
        case 2: "\(hidden[0]) and \(hidden[1]) don't fit here"
        default: "\(hidden.count) more repos don't fit here"
        }
        return TreeHaloText(text: text,
                            size: 9.5, weight: .semibold, colour: .white.opacity(0.8), ink: style.ink, halo: style.halo)
            .help(plan.hidden.joined(separator: ", "))
            .frame(width: width - 24, alignment: .trailing)
            .offset(x: 0, y: height - 22)
    }

    private var quietLine: String {
        var parts: [String] = []
        if plan.hollow.count > 0 { parts.append("\(plan.hollow.count) napping") }
        if plan.nest.count > 0 { parts.append("\(plan.nest.count) home today") }
        return parts.isEmpty ? "Nobody's working right now." : parts.joined(separator: " · ")
    }

    /// A quiet line in the open sky: "No owlets out", or "All quiet".
    private func message(_ title: String, _ body: String) -> some View {
        let twigs = plan.branches.map(\.end).max() ?? TreePlan.branchRoot
        let left = CGFloat(max(twigs, TreePlan.branchRoot + 40) + 10) * u
        let centre = max(left + 130, (left + width) / 2)
        return VStack(spacing: 6) {
            TreeHaloText(text: title, size: 16, weight: .semibold, ink: style.ink, halo: style.halo)
            TreeHaloText(text: body, size: 11, weight: .medium, colour: .white.opacity(0.88), ink: style.ink, halo: style.halo,
                         lines: 2)
        }
        .frame(width: 250)
        .position(x: min(centre, width - 130), y: CGFloat(TreePlan.firstBranch + 8) * u)
        .accessibilityElement(children: .combine)
    }
}

// MARK: An owlet on its branch

/// An owlet, standing on its branch: its hatchlings or flock beside it, a
/// lantern when it needs you, a rain cloud when it's stuck, and its name and
/// state under its feet. Moves as one, so the labels travel with the bird.
private struct TreePerch: View {
    let perch: TreePlan.Perch
    let unit: CGFloat
    let labelBottom: Int
    let style: TreeStyle
    let selected: Bool
    let moves: Bool
    let model: AppModel?
    let select: (String?) -> Void

    /// The frame, in cells: this far either side of the feet, and this far above the branch.
    static let half = 90
    static let above = 50

    private var session: AgentSession { perch.session }
    private var palette: String { session.agent.palette }
    private var u: CGFloat { unit }

    var body: some View {
        let ax = Self.half, ay = Self.above
        ZStack(alignment: .topLeading) {
            if session.state.needsYou, let lantern = TreeArt.lantern {
                TreePixelImage(image: lantern, unit: u).treeCell(ax - 18, ay - 9, u)
            }
            OwletSprite(sprite: session.state.sprite, palette: palette, scale: u,
                        seed: TreePlan.stableHash(session.id), animated: perch.animated)
                .treeCell(ax - 16, ay - 28, u)
            ForEach(perch.kids.indices, id: \.self) { index in
                let kx = ax + 16 + 8 * index
                if perch.kids[index], let egg = TreeArt.egg(palette) {
                    TreePixelImage(image: egg, unit: u).treeCell(kx - 3, ay - 6, u)
                } else if let kid = TreeArt.kid(palette) {
                    TreePixelImage(image: kid, unit: u).treeCell(kx - 3, ay - 8, u)
                }
            }
            if perch.flock > 0 {
                let fx = ax + perch.flockX - perch.x
                TreeFlock(count: min(perch.flock - 5, 16), seed: perch.flock, palette: palette, unit: u,
                          animated: perch.animated && moves)
                    .treeCell(fx - TreeFlock.size.width / 2, ay - 30 - TreeFlock.size.height / 2, u)
                TreeHaloText(text: "\(perch.flock) helpers", size: 9.5, weight: .semibold, colour: .white.opacity(0.84),
                             ink: style.ink, halo: style.halo)
                    .frame(width: 100)
                    .offset(x: CGFloat(fx + 1) * u - 50, y: CGFloat(ay - 41) * u - 11)
            }
            if session.state == .stuck {
                TreeRainCloud(day: style.light == .day, unit: u, animated: perch.animated && moves)
                    .treeCell(ax - 1 - TreeRainCloud.origin.x, ay - 30 - TreeRainCloud.origin.y, u)
            }
            if session.state.needsYou, let glow = TreeArt.glow(style.lantern) {
                TreePixelImage(image: glow, unit: u).treeCell(ax - 15 - TreeArt.glowRadius, ay - 4 - TreeArt.glowRadius, u)
                    .allowsHitTesting(false)
            }
            if selected { TreeSelectionMarks(width: 27, height: 30, unit: u).treeCell(ax - 13, ay - 28, u) }
            labels
        }
        .frame(width: CGFloat(Self.half * 2) * u, height: CGFloat(Self.above + labelBottom + 2) * u, alignment: .topLeading)
        .contentShape(TreeHitArea(rects: hitRects))
        .onTapGesture(count: 2) { AgentActions.show(session) }
        .onTapGesture { select(session.id) }
        .contextMenu {
            if let model { AgentMenu(session: session, model: model, close: {}) }
        }
        .help(session.detail ?? session.state.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(session.id) }
        .accessibilityAction(named: "Show") { AgentActions.show(session) }
    }

    private var stateText: String { session.detail ?? session.state.label }

    private var stateColour: Color {
        if session.state.needsYou { return Color(hex: 0xFFC56B) }
        if session.state == .stuck { return Color(hex: 0xFF9A85) }
        return .white.opacity(0.78)
    }

    /// Two lines under its feet, always: its name, then what it's doing.
    @ViewBuilder
    private var labels: some View {
        let top = CGFloat(Self.above + 6) * u + 1
        let left = CGFloat(Self.half) * u - perch.labelWidth / 2
        TreeFitText(text: perch.name, suffix: perch.suffix, size: 11, weight: .semibold,
                    colour: .white.opacity(selected ? 1 : 0.96), ink: style.ink, halo: style.halo)
            .frame(width: perch.labelWidth)
            .offset(x: left, y: top)
        let warns = session.state.needsYou || session.state == .stuck
        TreeFitText(text: stateText, size: 10, weight: warns ? .semibold : .medium, colour: stateColour, ink: style.ink,
                    halo: style.halo)
            .frame(width: perch.labelWidth)
            .offset(x: left, y: top + 14.5)
    }

    /// The owlet, its hatchlings and its labels: clicks elsewhere in the frame fall through.
    private var hitRects: [CGRect] {
        let ax = CGFloat(Self.half) * u, ay = CGFloat(Self.above) * u
        var rects = [CGRect(x: ax - 12 * u, y: ay - 27 * u, width: 24 * u, height: 28 * u),
                     CGRect(x: ax - perch.labelWidth / 2, y: ay + 4, width: perch.labelWidth, height: 6 * u + 30)]
        if !perch.kids.isEmpty {
            rects.append(CGRect(x: ax + 12 * u, y: ay - 9 * u, width: CGFloat(8 * perch.kids.count + 4) * u, height: 9 * u))
        }
        if perch.flock > 0 {
            let fx = CGFloat(Self.half + perch.flockX - perch.x) * u
            rects.append(CGRect(x: fx - 22 * u, y: ay - 46 * u, width: 44 * u, height: 24 * u))
        }
        return rects
    }

    private var accessibilityText: String {
        var parts = [session.placeName, perch.name + (perch.suffix.map { " · \($0)" } ?? ""), session.agent.name, stateText]
        let working = session.helpers.filter(\.isWorking).count
        if !session.helpers.isEmpty {
            parts.append(session.helpers.count == 1 ? "1 helper" : "\(session.helpers.count) helpers")
            if working > 0, working < session.helpers.count { parts.append("\(working) working") }
        }
        return parts.joined(separator: ", ")
    }
}

private struct TreeHitArea: Shape {
    var rects: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for rect in rects { path.addRect(rect) }
        return path
    }
}

/// Four pixel corners around what you picked.
private struct TreeSelectionMarks: View {
    let width: Int
    let height: Int
    let unit: CGFloat

    var body: some View {
        Canvas { context, size in
            let g = unit, arm = unit * 4
            let colour = GraphicsContext.Shading.color(.white.opacity(0.9))
            for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (size.width, 0, -1, 1), (0, size.height, 1, -1),
                                   (size.width, size.height, -1, -1)] {
                let ox = dx > 0 ? x : x - g, oy = dy > 0 ? y : y - g
                context.fill(Path(CGRect(x: dx > 0 ? x : x - arm, y: oy, width: arm, height: g)), with: colour)
                context.fill(Path(CGRect(x: ox, y: dy > 0 ? y : y - arm, width: g, height: arm)), with: colour)
            }
        }
        .frame(width: CGFloat(width) * unit, height: CGFloat(height) * unit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// More than five helpers: they wheel above the branch as one small flock.
private struct TreeFlock: View {
    let count: Int
    let seed: Int
    let palette: String
    let unit: CGFloat
    let animated: Bool

    static let size = (width: 40, height: 18)

    var body: some View {
        Group {
            if animated {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    birds(tick: Int(context.date.timeIntervalSinceReferenceDate * 2))
                }
            } else {
                birds(tick: 0)
            }
        }
        .frame(width: CGFloat(Self.size.width) * unit, height: CGFloat(Self.size.height) * unit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func birds(tick: Int) -> some View {
        let colours = OwletArt.palettes[palette] ?? OwletArt.palettes["golden"] ?? [:]
        let wing = Color(hex: colours["r"] ?? 0xA9572A), body = Color(hex: colours["d"] ?? 0xC8742C)
        let u = unit
        return Canvas { context, _ in
            var random = TreeRandom(seed)
            let cx = Double(Self.size.width / 2), cy = Double(Self.size.height / 2)
            for bird in 0..<count {
                let angle = random.next() * 6.283, reach = pow(random.next(), 0.7)
                let t = Double(tick) * 0.5
                let drift = (x: (2 * sin(t * 0.9 + angle)).rounded(), y: cos(t * 1.3 + angle * 2).rounded())
                let bx = Int(cx + cos(angle) * 17 * reach + drift.x), by = Int(cy + sin(angle) * 7 * reach + drift.y)
                let up = (bird + tick) % 2 == 1
                let shape = up ? [(0, 0), (1, 1), (2, 0)] : [(0, 1), (1, 0), (2, 1)]
                for (dx, dy) in shape {
                    let colour = dy == (up ? 1 : 0) ? wing : body
                    context.fill(Path(CGRect(x: CGFloat(bx + dx) * u, y: CGFloat(by + dy) * u, width: u, height: u)),
                                 with: .color(colour))
                }
            }
        }
    }
}

/// A small cool cloud over an owlet whose commands keep failing. Two frames of rain.
private struct TreeRainCloud: View {
    let day: Bool
    let unit: CGFloat
    let animated: Bool

    /// Where the cloud's anchor sits inside its image.
    static let origin = (x: 12, y: 11)

    var body: some View {
        Group {
            if animated {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    frame(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2)
                }
            } else {
                frame(0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frame(_ index: Int) -> some View {
        if let image = TreeArt.rain(small: false, day: day, frame: index) { TreePixelImage(image: image, unit: unit) }
    }
}

/// White type with a thin halo of the light's ink, so labels read on any
/// part of the scene without a box.
struct TreeHaloText: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight
    var tracking: CGFloat = 0
    var colour: Color = .white
    let ink: Color
    var halo = 0.62
    var lines = 1
    var alignment: TextAlignment = .center
    /// How far a one-line label may shrink before it truncates.
    var shrink: CGFloat = 1

    private static let ring: [CGSize] = [CGSize(width: -1.5, height: 0), CGSize(width: 1.5, height: 0),
                                         CGSize(width: 0, height: -1.5), CGSize(width: 0, height: 1.5),
                                         CGSize(width: -1, height: -1), CGSize(width: 1, height: -1),
                                         CGSize(width: -1, height: 1), CGSize(width: 1, height: 1)]

    var body: some View {
        label.foregroundStyle(colour)
            .background {
                ZStack {
                    ForEach(Self.ring.indices, id: \.self) { index in
                        label.foregroundStyle(ink).offset(Self.ring[index])
                    }
                }
                .compositingGroup()
                .opacity(halo)
                .accessibilityHidden(true)
            }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .lineLimit(lines)
            .minimumScaleFactor(shrink)
            .truncationMode(.tail)
            .multilineTextAlignment(alignment)
    }
}

/// One line of halo text that, when it doesn't fit, drops whole words from
/// the end ("Fix the Perch tint…") rather than cutting one in half.
struct TreeFitText: View {
    let text: String
    /// Kept whole at the end, however short the text gets: " · 21:04".
    var suffix: String? = nil
    var size: CGFloat
    var weight: Font.Weight
    var colour: Color = .white
    let ink: Color
    var halo = 0.62

    var body: some View {
        let options = Self.shortenings(text).map { option in suffix.map { "\(option) · \($0)" } ?? option }
        ViewThatFits(in: .horizontal) {
            ForEach(options.indices, id: \.self) { index in
                let label = TreeHaloText(text: options[index], size: size, weight: weight, colour: colour, ink: ink, halo: halo)
                if index < options.count - 1 { label.fixedSize(horizontal: true, vertical: false) } else { label }
            }
        }
    }

    /// The whole text, then fewer and fewer words with an ellipsis.
    static func shortenings(_ text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        var options = [text]
        guard words.count > 1 else { return options }
        for count in stride(from: words.count - 1, through: 1, by: -1) {
            var head = words.prefix(count).joined(separator: " ")
            while let last = head.last, "·,;:–—-(/&+ ".contains(last) { head.removeLast() }
            let option = head + "…"
            if !head.isEmpty, !options.contains(option) { options.append(option) }
        }
        return options
    }
}

/// A pixel image at a whole number of device pixels per pixel, never smoothed.
private struct TreePixelImage: View {
    let image: CGImage
    let unit: CGFloat

    var body: some View {
        Image(decorative: image, scale: 1 / unit)
            .interpolation(.none)
            .accessibilityHidden(true)
    }
}

private extension View {
    /// Places a view's top-left corner on a cell of the scene's grid.
    func treeCell(_ x: Int, _ y: Int, _ unit: CGFloat) -> some View {
        offset(x: CGFloat(x) * unit, y: CGFloat(y) * unit)
    }
}

// MARK: - Painting

/// Colours for one light. The backdrop lives in a narrow, muted value band and
/// the tree is a step darker; saturated colour belongs to the owlets.
struct TreePalette {
    var sky: [UInt32]
    var stars: Double
    var ridge: UInt32?
    var ridgeRim: UInt32?
    var hill: UInt32
    var meadow: UInt32
    var meadowHigh: UInt32
    var foreground: UInt32
    var bark: UInt32
    var barkDark: UInt32
    var barkLight: UInt32
    var rim: UInt32?
    var leaves: [UInt32]
    var leafRim: UInt32?
    var ink: UInt32
    var light: (x: Double, y: Double)

    static func of(_ light: RoostSky.Light?, contrast: Bool = false) -> TreePalette {
        var palette = base(light)
        if contrast {
            // Increase Contrast: the tree and owlets on a flat, darker sky.
            palette.sky = [TreeColour.mix(palette.sky[0], 0x000000, 0.35)]
            palette.stars = 0
        }
        return palette
    }

    private static func base(_ light: RoostSky.Light?) -> TreePalette {
        switch light {
        case .day:
            TreePalette(sky: [0x3F7CC0, 0x5B93CF, 0x7EAAD8, 0xA6C3DF, 0xCFDCE2], stars: 0, ridge: 0xA9BFD0, ridgeRim: nil,
                        hill: 0x73986A, meadow: 0x5F8F4F, meadowHigh: 0x7EAB5B, foreground: 0x3F6A40, bark: 0x6E4D37,
                        barkDark: 0x4D3527, barkLight: 0x8E6B4D, rim: nil, leaves: [0x3C6A3F, 0x56904A, 0x86B956],
                        leafRim: nil, ink: 0x13213A, light: (0.6, -0.8))
        case .golden:
            TreePalette(sky: [0x36457F, 0x6A64A0, 0xB77796, 0xEC9A7A, 0xFFC677], stars: 0, ridge: 0xB77B8B,
                        ridgeRim: 0xF6A77E, hill: 0x5D3E63, meadow: 0x4A3654, meadowHigh: 0x6A4A62, foreground: 0x2C2139,
                        bark: 0x573640, barkDark: 0x3A232E, barkLight: 0x77494C, rim: 0xFFAD66,
                        leaves: [0x7D3540, 0xBC5338, 0xE58D3F], leafRim: 0xFFD27E, ink: 0x24142A, light: (0.9, -0.3))
        case .night:
            TreePalette(sky: [0x090B22, 0x0F1233, 0x161A44, 0x1F2453, 0x2C3264], stars: 1, ridge: 0x252A59, ridgeRim: nil,
                        hill: 0x161A3D, meadow: 0x131735, meadowHigh: 0x1B2044, foreground: 0x0A0B20, bark: 0x352A45,
                        barkDark: 0x231B32, barkLight: 0x4A3D5E, rim: nil, leaves: [0x12273A, 0x1A3848, 0x2A5868],
                        leafRim: nil, ink: 0x05061A, light: (0.7, -0.7))
        case .dusk:
            TreePalette(sky: [0x1D2050, 0x363470, 0x664E87, 0xAC6B8C, 0xE8A28C], stars: 0.45, ridge: 0x5E4F86,
                        ridgeRim: 0xC3A0C6, hill: 0x3A2F58, meadow: 0x33294F, meadowHigh: 0x44375F, foreground: 0x211A38,
                        bark: 0x4A3550, barkDark: 0x33243C, barkLight: 0x634866, rim: nil,
                        leaves: [0x1F2E46, 0x2C4458, 0x48667A], leafRim: nil, ink: 0x1A1438, light: (0.9, -0.35))
        case nil:
            // Plain: one flat sky, no sun, moon or stars.
            TreePalette(sky: [0x1A1936], stars: 0, ridge: nil, ridgeRim: nil, hill: 0x1F1D3F, meadow: 0x191834,
                        meadowHigh: 0x232147, foreground: 0x100F26, bark: 0x3A2E4C, barkDark: 0x261E35, barkLight: 0x52446A,
                        rim: nil, leaves: [0x14283A, 0x1D3A4B, 0x2D5868], leafRim: nil, ink: 0x07061A, light: (0.7, -0.7))
        }
    }
}

enum TreeColour {
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

/// A deterministic random sequence (SplitMix64), so the same tree grows the same way every time.
struct TreeRandom {
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

    mutating func uniform(_ low: Double, _ high: Double) -> Double { low + (high - low) * next() }
}

/// A pixel buffer on the scene's grid: one colour and one kind per cell.
struct TreePixels {
    enum Kind: UInt8 { case empty, sky, ridge, hill, meadow, ground, bark, leaf, nest, owl, light, other }

    let width: Int
    let height: Int
    var colour: [UInt32]
    var kind: [Kind]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        colour = Array(repeating: 0, count: width * height)
        kind = Array(repeating: .empty, count: width * height)
    }

    func kind(_ x: Int, _ y: Int) -> Kind {
        x >= 0 && x < width && y >= 0 && y < height ? kind[y * width + x] : .empty
    }

    mutating func put(_ x: Int, _ y: Int, _ c: UInt32, _ k: Kind? = nil) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let index = y * width + x
        colour[index] = c
        if let k { kind[index] = k } else if kind[index] == .empty { kind[index] = .other }
    }

    mutating func put(_ x: Double, _ y: Double, _ c: UInt32, _ k: Kind? = nil) { put(Int(x), Int(y), c, k) }

    mutating func blend(_ x: Int, _ y: Int, _ c: UInt32, _ amount: Double) {
        guard x >= 0, x < width, y >= 0, y < height, kind[y * width + x] != .empty else { return }
        colour[y * width + x] = TreeColour.mix(colour[y * width + x], c, amount)
    }

    /// Stepped radial light: each ring adds its amount inside its radius, with a checkerboard edge.
    mutating func glow(_ cx: Double, _ cy: Double, _ rings: [(Double, Double)], _ c: UInt32) {
        let radius = rings.map(\.0).max() ?? 0
        for y in Int(cy - radius)...Int(cy + radius) {
            for x in Int(cx - radius)...Int(cx + radius) {
                let d = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
                var amount = 0.0
                for (r, a) in rings where d <= r - 1 || (d <= r && (x + y) % 2 == 0) { amount += a }
                if amount > 0 { blend(x, y, c, min(amount, 0.9)) }
            }
        }
    }

    func image() -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) where kind[index] != .empty {
            let c = colour[index]
            bytes[index * 4] = UInt8((c >> 16) & 0xFF)
            bytes[index * 4 + 1] = UInt8((c >> 8) & 0xFF)
            bytes[index * 4 + 2] = UInt8(c & 0xFF)
            bytes[index * 4 + 3] = 0xFF
        }
        return TreePixels.cgImage(bytes, width: width, height: height)
    }

    static func cgImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
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

/// The baked backdrop and tree, cached by everything that changes them.
@MainActor
enum TreeScenery {
    struct Key: Hashable {
        var cols: Int
        var rows: Int
        var skyRows: Int
        var light: RoostSky.Light?
        var moon: Int
        var contrast: Bool
        var branches: [TreePlan.Branch]
        var twigs: [TreePlan.Twig]
        /// Who sleeps in the nest, and who's curled up in the hollow.
        var sleepers: [String]
        var nappers: [String]

        init(plan: TreePlan, style: TreeStyle, skyRows: Int) {
            cols = plan.cols
            rows = plan.rows
            self.skyRows = skyRows
            light = style.light
            moon = style.light == .night ? style.moon : 0
            contrast = style.contrast
            branches = plan.branches
            twigs = plan.twigs
            sleepers = plan.nest.palettes
            nappers = plan.hollow.palettes
        }
    }

    struct Images {
        var sky: CGImage?
        var tree: CGImage?
    }

    private static var cache: [Key: Images] = [:]
    private static var recent: [Key] = []

    static func images(for key: Key) -> Images {
        if let images = cache[key] { return images }
        let palette = TreePalette.of(key.light, contrast: key.contrast)
        let images = Images(sky: TreePainter.sky(key, palette).image(), tree: TreePainter.tree(key, palette).image())
        cache[key] = images
        recent.append(key)
        // A few sizes are enough for a window being resized; drop the rest.
        while recent.count > 4 { cache[recent.removeFirst()] = nil }
        return images
    }
}

/// Paints the scene, cell by cell: sky, one ridge, the meadow, and the tree.
enum TreePainter {
    // MARK: Backdrop

    static func sky(_ key: TreeScenery.Key, _ p: TreePalette) -> TreePixels {
        var canvas = TreePixels(width: key.cols, height: key.skyRows)
        let w = key.cols, bottom = key.skyRows
        let horizon = bottom - 44
        bands(&canvas, p, horizon: horizon)
        if p.stars > 0 { stars(&canvas, p, horizon: horizon) }
        switch key.light {
        case .day:
            sun(&canvas, Double(w - 52), 34, 7, core: 0xFFFBEA, ring: 0xFFF1C2, halo: [(11, 0.2), (17, 0.08)])
        case .golden:
            sun(&canvas, Double(w - 58), Double(bottom - 72), 13, core: 0xFFF4CF, ring: 0xFFD98C,
                halo: [(18, 0.28), (28, 0.14), (42, 0.07), (60, 0.04)])
        case .night:
            if !key.contrast { moon(&canvas, Double(w - 58), 40, 9, phase: Double(key.moon) / 64, dark: 0x262B5A) }
        case .dusk:
            canvas.glow(Double(w - 120), Double(bottom - 66), [(26, 0.08), (46, 0.05)], 0xFFC9A8)
        case nil:
            break
        }
        if let ridge = p.ridge {
            self.ridge(&canvas, base: bottom - 76, amps: [(7, 41), (4, 17), (2, 7)], colour: ridge, seed: 1.2, rim: p.ridgeRim,
                       kind: .ridge)
        }
        self.ridge(&canvas, base: bottom - 48, amps: [(4, 61), (2, 29)], colour: p.hill, seed: 4.1, rim: nil, kind: .hill)
        return canvas
    }

    /// Fifteen flat bands with a two-row checker between them: calm, and free of gradient noise.
    private static func bands(_ canvas: inout TreePixels, _ p: TreePalette, horizon: Int, count: Int = 15) {
        let height = Double(max(horizon, 1)) / Double(count)
        let colours = (0..<count).map { TreeColour.ramp(p.sky, Double($0) / Double(count - 1)) }
        for y in 0..<canvas.height {
            let band = min(Int(Double(y) / height), count - 1)
            let inBand = y - Int(Double(band) * height)
            let colour = colours[band], previous = band > 0 ? colours[band - 1] : colour
            for x in 0..<canvas.width {
                canvas.put(x, y, inBand < 2 && (x + y) % 2 == 0 ? previous : colour, .sky)
            }
        }
    }

    private static func stars(_ canvas: inout TreePixels, _ p: TreePalette, horizon: Int) {
        var random = TreeRandom(p.stars > 0.8 ? 11 : 4)
        let count = Int(90 * Double(canvas.width * horizon) / (450 * 236))
        let top = Double(horizon) * 0.72
        for _ in 0..<count {
            let x = random.int(0..<canvas.width), y = Int(pow(random.next(), 1.4) * top)
            let bright = random.next()
            canvas.blend(x, y, 0xF1EEFF, (0.25 + 0.6 * bright) * p.stars)
            if bright > 0.93 && p.stars > 0.8 {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { canvas.blend(x + dx, y + dy, 0xF1EEFF, 0.3) }
            }
        }
    }

    private static func sun(_ canvas: inout TreePixels, _ cx: Double, _ cy: Double, _ r: Double, core: UInt32, ring: UInt32,
                            halo: [(Double, Double)]) {
        canvas.glow(cx, cy, halo, ring)
        for (x, y) in TreePixels.disc(cx, cy, r) {
            let d = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
            canvas.put(x, y, d < r - 1.6 ? core : ring, .light)
        }
    }

    /// Tonight's moon in its real phase: lit on the right while it waxes, on the left while it wanes.
    private static func moon(_ canvas: inout TreePixels, _ cx: Double, _ cy: Double, _ r: Double, phase: Double,
                             dark: UInt32) {
        canvas.glow(cx, cy, [(r + 4, 0.07), (r + 10, 0.04)], 0xC9C6FF)
        let turn = cos(phase * 2 * .pi)
        let craters: Set<[Int]> = [[2, -3], [3, -3], [4, 1], [1, 3], [2, 3], [5, -1]]
        for (x, y) in TreePixels.disc(cx, cy, r) {
            let dy = Double(y) + 0.5 - cy
            let half = max(0, r * r - dy * dy).squareRoot()
            let mx = Double(x) + 0.5 - cx
            let lit = phase < 0.5 ? mx > half * turn : mx < -half * turn
            if lit {
                canvas.put(x, y, craters.contains([x - Int(cx), y - Int(cy)]) ? 0xD9CDB8 : 0xF4EAD6, .light)
            } else {
                canvas.put(x, y, dark, .light)
            }
        }
    }

    private static func ridge(_ canvas: inout TreePixels, base: Int, amps: [(Double, Double)], colour: UInt32, seed: Double,
                              rim: UInt32?, kind: TreePixels.Kind) {
        let heights = (0..<canvas.width).map { x in
            var h = Double(base)
            for (index, (a, f)) in amps.enumerated() { h += a * sin(Double(x) / f + seed * (Double(index) + 1.7)) }
            return Int(h.rounded())
        }
        for x in 0..<canvas.width {
            for y in max(0, heights[x])..<canvas.height { canvas.put(x, y, colour, kind) }
            if let rim, x + 1 < canvas.width, heights[x + 1] > heights[x] { canvas.put(x, heights[x], rim, kind) }
        }
    }

    // MARK: Ground and tree

    static func tree(_ key: TreeScenery.Key, _ p: TreePalette) -> TreePixels {
        var canvas = TreePixels(width: key.cols, height: key.rows)
        let meadowTop = key.rows - TreePlan.ground
        meadow(&canvas, p, base: meadowTop)
        let cx = TreePlan.trunkX, top = TreePlan.trunkTop, ground = meadowTop + 6
        trunk(&canvas, p, cx: cx, top: top, ground: ground)
        var random = TreeRandom(7)
        crown(&canvas, p, cx: Double(cx), top: Double(top), random: &random)
        var sprays: [[Spray]] = []
        for branch in key.branches {
            let leaves = self.branch(&canvas, p, branch)
            if !branch.bare { sprays.append(leaves) }
        }
        for twig in key.twigs { sprays.append(self.twig(&canvas, p, twig)) }
        shadeBark(&canvas, p)
        barkDetail(&canvas, p, cx: cx, top: top + 4, ground: ground - 4)
        hollow(&canvas, p, nappers: key.nappers)

        // The canopy: a darker back layer, then the front clumps.
        let back = [TreeColour.mix(p.leaves[0], p.sky[0], 0.25), TreeColour.mix(p.leaves[0], p.sky[0], 0.25),
                    TreeColour.mix(p.leaves[1], p.sky[0], 0.25)]
        for (x, y, r) in [(22, 4, 32.0), (94, -4, 32), (150, 6, 20), (-6, 46, 20), (60, 26, 26)] {
            clump(&canvas, Double(x), Double(y), r, back, p.light, seed: x + 3)
        }
        for (x, y, r) in [(30, 18, 22.0), (80, 8, 24), (124, 16, 18), (6, 40, 15), (166, 4, 14), (30, 46, 11), (104, 38, 11),
                          (148, 30, 9)] {
            clump(&canvas, Double(x), Double(y), r, p.leaves, p.light, seed: x * 7 + 1, rim: p.leafRim)
        }
        for (index, branchSprays) in sprays.enumerated() {
            for (offset, spray) in branchSprays.enumerated() where spray.r >= 2 {
                clump(&canvas, spray.x, spray.y, spray.r, p.leaves, p.light, seed: 40 + index + offset * 3, rim: p.leafRim,
                      squash: spray.squash)
            }
        }
        nest(&canvas, p, sleepers: key.sleepers)
        foreground(&canvas, p)
        return canvas
    }

    private static func meadow(_ canvas: inout TreePixels, _ p: TreePalette, base: Int) {
        var random = TreeRandom(5)
        var tops: [Int] = []
        for x in 0..<canvas.width {
            let t = Int(Double(base) + 2.2 * sin(Double(x) / 37 + 1) + 1.4 * sin(Double(x) / 13))
            tops.append(t)
            for y in max(0, t)..<canvas.height { canvas.put(x, y, y == t ? p.meadowHigh : p.meadow, .meadow) }
        }
        let scale = Double(canvas.width) / 450
        for _ in 0..<Int(160 * scale) {
            let x = random.int(0..<canvas.width)
            let h = [1, 1, 2, 2, 3][random.int(0..<5)]
            for k in 0..<h { canvas.put(x, tops[x] - 1 - k, k < h - 1 ? p.meadowHigh : p.meadow, .meadow) }
        }
        let texture = TreeColour.mix(p.meadow, p.foreground, 0.45)
        for _ in 0..<Int(260 * scale) {
            let x = random.int(0..<canvas.width), y = random.int((base + 4)..<canvas.height)
            if y > tops[x] + 1 { canvas.put(x, y, texture, .meadow) }
        }
    }

    private static func foreground(_ canvas: inout TreePixels, _ p: TreePalette) {
        var random = TreeRandom(9)
        let h = canvas.height, w = canvas.width
        for x in 0..<w {
            let t = Int(Double(h - 12) + 3 * sin(Double(x) / 19 + 2) + 2 * sin(Double(x) / 7))
            for y in t..<h { canvas.put(x, y, p.foreground, .ground) }
            if random.next() < 0.35 {
                for k in 0..<[1, 2, 3, 4][random.int(0..<4)] { canvas.put(x, t - 1 - k, p.foreground, .ground) }
            }
        }
        let tones = [TreeColour.mix(p.foreground, 0x000000, 0.15), p.foreground, TreeColour.mix(p.foreground, p.meadow, 0.5)]
        clump(&canvas, Double(w - 12), Double(h - 10), 20, tones, p.light, seed: 31, kind: .ground)
        clump(&canvas, Double(w - 38), Double(h - 2), 13, tones, p.light, seed: 32, kind: .ground)
    }

    private static func trunk(_ canvas: inout TreePixels, _ p: TreePalette, cx: Int, top: Int, ground: Int) {
        for y in top..<(ground + 6) {
            let lean = 2.5 * sin(Double(y - top) / 60)
            let flare = pow(Double(max(0, y - (ground - 26))), 1.5) * 0.2
            let w = 26 + min(Double(y - top) * 0.035, 6) + flare
            let x0 = Int(Double(cx) + lean - w / 2)
            for x in x0..<Int(Double(x0) + w) { canvas.put(x, y, p.bark, .bark) }
        }
        let g = Double(ground)
        for (sx, ex, ey) in [(cx - 8, cx - 34, g + 6), (cx + 10, cx + 36, g + 5), (cx - 4, cx - 20, g + 9),
                             (cx + 6, cx + 24, g + 9)] {
            thickLine(&canvas, p, Double(sx), g - 4, Double(ex), ey, 8, 2)
        }
    }

    private static func thickLine(_ canvas: inout TreePixels, _ p: TreePalette, _ x0: Double, _ y0: Double, _ x1: Double,
                                  _ y1: Double, _ t0: Double, _ t1: Double) {
        let n = Int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in 0...n {
            let u = Double(i) / Double(n)
            let x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * u, t = t0 + (t1 - t0) * u
            for (px, py) in TreePixels.disc(x, y, t / 2) { canvas.put(px, py, p.bark, .bark) }
        }
    }

    private static func polyline(_ canvas: inout TreePixels, _ p: TreePalette, _ points: [(Double, Double)], _ t0: Double,
                                 _ t1: Double) {
        let segments = zip(points, points.dropFirst()).map { ($0, $1) }
        let total = segments.reduce(0) { $0 + hypot($1.1.0 - $1.0.0, $1.1.1 - $1.0.1) }
        var run = 0.0
        for (a, b) in segments {
            let length = hypot(b.0 - a.0, b.1 - a.1)
            thickLine(&canvas, p, a.0, a.1, b.0, b.1, t0 + (t1 - t0) * run / total, t0 + (t1 - t0) * (run + length) / total)
            run += length
        }
    }

    /// The trunk forks into two limbs with a thinner leader between them: a V the nest sits in.
    private static func crown(_ canvas: inout TreePixels, _ p: TreePalette, cx: Double, top: Double,
                              random: inout TreeRandom) {
        let limbs: [([(Double, Double)], Double, Double, Double)] = [
            ([(cx - 4, top + 16), (cx - 13, top - 14), (cx - 38, top - 48)], 13, 6, -2.3),
            ([(cx + 4, top + 16), (cx + 13, top - 16), (cx + 40, top - 52)], 12, 5, -0.9),
            ([(cx, top + 4), (cx + 3, top - 36), (cx + 8, top - 70)], 8, 4, -1.45),
        ]
        for (points, t0, t1, angle) in limbs {
            polyline(&canvas, p, points, t0, t1)
            if let end = points.last { limb(&canvas, p, end.0, end.1, angle, 16, t1 * 0.8, 1, &random) }
        }
    }

    private static func limb(_ canvas: inout TreePixels, _ p: TreePalette, _ x: Double, _ y: Double, _ angle: Double,
                             _ length: Double, _ thickness: Double, _ depth: Int, _ random: inout TreeRandom) {
        let x1 = x + cos(angle) * length, y1 = y + sin(angle) * length
        thickLine(&canvas, p, x, y, x1, y1, thickness, max(1, thickness * 0.7))
        guard depth > 0 else { return }
        for side in [-1.0, 1.0] where random.next() < 0.9 {
            limb(&canvas, p, x1, y1, angle + side * random.uniform(0.3, 0.65), length * random.uniform(0.6, 0.78),
                 max(1, thickness * 0.62), depth - 1, &random)
        }
    }

    struct Spray {
        var x: Double
        var y: Double
        var r: Double
        var squash: Double
    }

    /// A repository's branch: thick at the trunk, thinning to the tip, with
    /// twigs in the gaps and leaf sprays that grow with the day's work.
    private static func branch(_ canvas: inout TreePixels, _ p: TreePalette, _ branch: TreePlan.Branch) -> [Spray] {
        let root = TreePlan.branchRoot, end = branch.end
        let length = Double(end - root)
        for x in (root - 2)...end {
            let y = TreePlan.top(of: branch, at: x)
            let t = Int((6.6 - 3.8 * Double(max(0, x - root)) / length).rounded())
            for k in 0..<max(t, 2) { canvas.put(x, y + k, p.bark, .bark) }
        }
        var random = TreeRandom(branch.seed)
        var sprays: [Spray] = []
        let clear = { (x: Int) in branch.avoid.allSatisfy { abs(x - $0) > 19 } }
        let gaps = stride(from: root + 34, to: end - 8, by: 4).filter(clear)
        for x in stride(from: 0, to: gaps.count, by: 5).map({ gaps[$0] }) where random.next() < (branch.bare ? 0.6 : 0.35) {
            let up = random.next() < 0.7
            let dx = random.int(3..<7), dy = up ? -random.int(4..<8) : random.int(3..<5)
            let y = TreePlan.top(of: branch, at: x)
            thickLine(&canvas, p, Double(x), Double(y + 1), Double(x + dx), Double(y + dy), 2, 1)
            if up { sprays.append(Spray(x: Double(x + dx), y: Double(y + dy), r: 2.2 + 2.2 * branch.leafy, squash: 0.8)) }
        }
        let count = Int(2 + 6 * branch.leafy)
        for i in 0..<count {
            let u = 1 - pow(Double(i) / Double(max(count - 1, 1)), 1.3) * 0.55
            let x = Int(Double(root) + length * u)
            guard branch.avoid.allSatisfy({ abs(x - $0) >= 19 }) else { continue }
            let y = TreePlan.top(of: branch, at: min(x, end))
            sprays.append(Spray(x: Double(x + random.int(-3..<4)), y: Double(y - random.int(0..<3)),
                                r: (3 + 5 * branch.leafy) * (0.55 + 0.45 * u), squash: 0.62))
        }
        sprays.append(Spray(x: Double(end + 3), y: Double(TreePlan.top(of: branch, at: end) - 1), r: 5 + 6 * branch.leafy,
                            squash: 0.7))
        return sprays
    }

    /// A helpers' twig: five cells thick where it leaves the branch, three at
    /// the tip, with a small spray of leaves at the end.
    private static func twig(_ canvas: inout TreePixels, _ p: TreePalette, _ twig: TreePlan.Twig) -> [Spray] {
        // Discs along its middle keep it whole down the steep fall as well as along the level.
        let points = stride(from: twig.x, through: twig.end, by: 2).map { (Double($0), Double(twig.top(at: $0)) + 2) }
        polyline(&canvas, p, points, 5, 3)
        return [Spray(x: Double(twig.end + 2), y: Double(twig.top(at: twig.end) - 1), r: 4, squash: 0.7)]
    }

    /// A leafy clump, lit from the light's side, with small two-pixel leaf marks.
    private static func clump(_ canvas: inout TreePixels, _ cx: Double, _ cy: Double, _ r: Double, _ tones: [UInt32],
                              _ light: (x: Double, y: Double), seed: Int, rim: UInt32? = nil, kind: TreePixels.Kind = .leaf,
                              squash: Double = 1) {
        var random = TreeRandom(seed)
        let phase = random.next() * 6.28, phase2 = random.next() * 6.28
        for y in (Int(cy - r * 1.2) - 1)...(Int(cy + r * 1.2) + 1) {
            for x in (Int(cx - r * 1.2) - 1)...(Int(cx + r * 1.2) + 1) {
                let dx = Double(x) + 0.5 - cx, dy = (Double(y) + 0.5 - cy) / squash
                let d = hypot(dx, dy)
                let angle = atan2(dy, dx)
                let reach = r * (1 + 0.09 * sin(6 * angle + phase) + 0.05 * sin(13 * angle + phase2))
                guard d <= reach else { continue }
                let lit = (dx * light.x + dy * light.y) / max(reach, 1) + (TreePixels.noise(x, y, seed) - 0.5) * 0.45
                var c = lit > 0.3 ? tones[2] : lit > -0.3 ? tones[1] : tones[0]
                let speckle = TreePixels.noise(Int((Double(x) / 2).rounded(.down)), y, seed + 7)
                if speckle > 0.9 && c == tones[1] {
                    c = lit > 0 ? tones[2] : tones[0]
                } else if speckle < 0.06 && c == tones[2] {
                    c = tones[1]
                }
                if let rim, d > reach - 1.3, lit > 0.2 { c = rim }
                canvas.put(x, y, c, kind)
            }
        }
    }

    /// Light and dark edges on every bark cell, from the light's direction; top surfaces lit.
    private static func shadeBark(_ canvas: inout TreePixels, _ p: TreePalette) {
        var changes: [(Int, UInt32)] = []
        for y in 0..<canvas.height {
            for x in 0..<canvas.width where canvas.kind[y * canvas.width + x] == .bark {
                let up = canvas.kind(x, y - 1) != .bark, down = canvas.kind(x, y + 1) != .bark
                let left = canvas.kind(x - 1, y) != .bark, right = canvas.kind(x + 1, y) != .bark
                var c = p.bark
                if down || left {
                    c = p.barkDark
                } else if up || right {
                    c = p.rim ?? p.barkLight
                } else if canvas.kind(x + 2, y) != .bark {
                    c = p.barkLight
                }
                changes.append((y * canvas.width + x, c))
            }
        }
        for (index, c) in changes { canvas.colour[index] = c }
    }

    private static func barkDetail(_ canvas: inout TreePixels, _ p: TreePalette, cx: Int, top: Int, ground: Int) {
        var random = TreeRandom(4)
        let count = max(12, 34 * (ground - top) / 156)
        for _ in 0..<count {
            let x = cx + random.int(-7..<6), y = random.int((top + 6)..<max(top + 7, ground - 6))
            for k in 0..<random.int(4..<12)
                where canvas.kind(x, y + k) == .bark && canvas.kind(x - 1, y + k) == .bark && canvas.kind(x + 1, y + k) == .bark {
                canvas.put(x, y + k, p.barkDark)
            }
        }
    }

    /// The hollow in the trunk: a dark arch with a lit lip, and the napping
    /// owlets curled up inside it, one in front of the others.
    private static func hollow(_ canvas: inout TreePixels, _ p: TreePalette, nappers: [String]) {
        let hx = Double(TreePlan.hollow.x) + 0.5, hy = Double(TreePlan.hollow.y)
        let rx = 10.0, ry = 6.5
        func inside(_ x: Int, _ y: Int, grow: Double) -> Bool {
            let dx = (Double(x) + 0.5 - hx) / (rx + grow), dy = (Double(y) + 0.5 - hy) / (ry + grow)
            // Rounded on top, flatter at the bottom, like a knot hole worn open.
            return dy < 0 ? dx * dx + dy * dy <= 1 : abs(dx) <= 1 && dy <= 1 - dx * dx * 0.25
        }
        let core: UInt32 = 0x140D1A, depth = TreeColour.mix(core, p.barkDark, 0.45)
        for y in Int(hy - ry - 2)...Int(hy + ry + 2) {
            for x in Int(hx - rx - 2)...Int(hx + rx + 2) {
                if inside(x, y, grow: 0) {
                    canvas.put(x, y, inside(x, y, grow: -2.5) ? core : depth)
                } else if inside(x, y, grow: 1.2) {
                    canvas.put(x, y, Double(y) + 0.5 > hy + ry - 1 ? p.barkLight : p.barkDark)
                }
            }
        }
        // Curled up together: the middle one in front, the others a little in shadow behind it.
        let offsets: [Int] = switch nappers.count {
        case 0: []
        case 1: [0]
        case 2: [-4, 4]
        default: [-7, 7, 0]
        }
        let order = nappers.count >= 3 ? [1, 2, 0] : Array(nappers.indices)
        for (slot, index) in order.enumerated() where slot < offsets.count {
            let colours = OwletArt.palettes[nappers[index]] ?? OwletArt.palettes["golden"] ?? [:]
            let behind = nappers.count > 1 && slot < offsets.count - 1
            let ox = Int(hx) - 5 + offsets[slot], oy = Int(hy + ry) - Self.curled.count + 1 + (behind ? 0 : 1)
            for (y, row) in Self.curled.enumerated() {
                for (x, key) in row.enumerated() where key != "." {
                    guard let c = colours[key], inside(ox + x, oy + y, grow: 0) else { continue }
                    canvas.put(ox + x, oy + y, behind ? TreeColour.mix(c, core, 0.35) : c, .owl)
                }
            }
        }
    }

    /// An owlet curled up asleep in its nightcap, small enough for three to share the hollow.
    static let curled = ["....mlL...", "...mllLL..", "..oLLLLLo.", ".ohhggggdo", "ohwwgwwgdo", "oweewweedo", "ogwwawwgdo",
                         ".ogddddgo.", "..oooooo.."]

    /// A woven nest in the crown's fork; owlets that finished today asleep in it, only their heads showing.
    private static func nest(_ canvas: inout TreePixels, _ p: TreePalette, sleepers: [String]) {
        let cx = Double(TreePlan.nest.x), top = TreePlan.nest.y
        if let frame = OwletArt.states["nap"]?.frames.first {
            let cells = Array(frame)
            for (index, palette) in sleepers.enumerated() {
                let colours = OwletArt.palettes[palette] ?? OwletArt.palettes["golden"] ?? [:]
                let ox = cx - 16 + (Double(index) - Double(sleepers.count - 1) / 2) * 13
                for y in 0..<20 {
                    for x in 0..<26 {
                        let key = cells[y * OwletArt.width + x]
                        guard key != ".", let c = colours[key] else { continue }
                        canvas.put(ox + Double(x), Double(top - 18 + y), c, .owl)
                    }
                }
            }
        }
        let c1: UInt32 = 0x6B4433, c2: UInt32 = 0x8E5E3E, c3: UInt32 = 0x4A2E25
        let insets = [3, 1, 0, 0, 0, 1, 2, 4]
        for y in top..<(top + 8) {
            let inset = Double(insets[y - top])
            for x in Int(cx - 15 + inset)..<Int(cx + 15 - inset) {
                var c = (x + 2 * (y - top)) % 5 < 2 ? c2 : c1
                if y == top { c = x % 3 != 0 ? c2 : c3 }
                if y >= top + 6 { c = c3 }
                canvas.put(x, y, c, .nest)
            }
        }
        for dx in [-17, 15] {
            canvas.put(Int(cx) + dx, top + 1, c1, .nest)
            canvas.put(Int(cx) + dx + (dx > 0 ? 1 : -1), top, c1, .nest)
        }
        // A few front leaves tuck the nest into the crown.
        clump(&canvas, cx - 18, Double(top + 1), 5, p.leaves, p.light, seed: 91, squash: 0.7)
        clump(&canvas, cx + 19, Double(top), 4, p.leaves, p.light, seed: 92, squash: 0.7)
    }
}

/// The small pieces of art that live on top of the scene: hatchlings, eggs,
/// the lantern, its light, and the rain cloud. Drawn once each.
@MainActor
enum TreeArt {
    private static var cache: [String: CGImage] = [:]

    /// A hatchling watching from the branch, the same pixel size as its parent.
    static func kid(_ palette: String) -> CGImage? {
        art("kid|\(palette)", ["...o...", ".oohdo.", "owwgwwo", "owewewo", "ogwawdo", ".ogwdo.", "..ooo..", "..a.a.."], palette)
    }

    static func egg(_ palette: String) -> CGImage? {
        art("egg|\(palette)", ["..oo..", ".owwo.", "owwwco", "owqwco", "owwcco", ".oqqo."], palette)
    }

    /// A lantern standing on the branch: handle, cap, glass, base. It doesn't flicker.
    static var lantern: CGImage? {
        let rows = ["..fff..", ".f...f.", ".fffff.", "fffffff", ".fgggf.", ".fghgf.", ".fghgf.", ".fgggf.", "fffffff"]
        return cached("lantern") {
            pixels(rows) { ["f": 0x3A2430, "g": 0xFFE3A0, "h": 0xFFF6DA][$0] }
        }
    }

    static let glowRadius = 29

    /// The lantern's stepped, dither-edged halo, laid over everything near it, the owlet's feathers included.
    static func glow(_ strength: Double) -> CGImage? {
        cached("glow|\(Int(strength * 100))") {
            let size = glowRadius * 2 + 1
            let centre = Double(glowRadius) + 0.5
            let rings = [(5.0, 0.2), (11, 0.12), (19, 0.07), (28, 0.04)]
            var bytes = [UInt8](repeating: 0, count: size * size * 4)
            for y in 0..<size {
                for x in 0..<size {
                    let d = hypot(Double(x) + 0.5 - centre, Double(y) + 0.5 - centre)
                    var amount = 0.0
                    for (r, a) in rings where d <= r - 1 || (d <= r && (x + y) % 2 == 0) { amount += a * strength }
                    guard amount > 0 else { continue }
                    let index = (y * size + x) * 4
                    bytes[index] = 0xFF
                    bytes[index + 1] = 0xC1
                    bytes[index + 2] = 0x65
                    bytes[index + 3] = UInt8(min(0.9, amount) * 255)
                }
            }
            return TreePixels.cgImage(bytes, width: size, height: size)
        }
    }

    /// A small rain cloud in cool grey, never amber: the lantern is the only warm light.
    static func rain(small: Bool, day: Bool, frame: Int) -> CGImage? {
        cached("rain|\(small)|\(day)|\(frame)") {
            let (base, shade, drop): (UInt32, UInt32, UInt32) = day ? (0x9AA3B8, 0x7C859C, 0x5B86C6) : (0x8A84AA, 0x6C6690, 0xA9C4FF)
            let ox = TreeRainCloud.origin.x, oy = TreeRainCloud.origin.y
            var canvas = TreePixels(width: 26, height: 18)
            let lumps: [(Double, Double, Double)] = small ? [(-5, -1, 3), (1, -3, 4.4), (6, -1, 3)]
                : [(-6, -2, 4.2), (1, -4, 6), (7, -2, 4.2)]
            var cells: Set<[Int]> = []
            for (lx, ly, r) in lumps {
                for (x, y) in TreePixels.disc(lx, ly, r) where y <= 0 { cells.insert([x, y]) }
            }
            for cell in cells {
                canvas.put(cell[0] + ox, cell[1] + oy, cells.contains([cell[0], cell[1] + 2]) ? base : shade)
            }
            for (index, dx) in [-7, -3, 1, 5, 9].enumerated() {
                let step = (index + frame) % 2
                let dy = small ? 1 + step : 2 + step * 2
                canvas.put(dx + ox, dy + oy, drop)
                canvas.put(dx + ox, dy + oy + 1, drop)
            }
            return canvas.image()
        }
    }

    private static func art(_ key: String, _ rows: [String], _ palette: String) -> CGImage? {
        cached(key) {
            let colours = OwletArt.palettes[palette] ?? OwletArt.palettes["golden"] ?? [:]
            return pixels(rows) { colours[$0] }
        }
    }

    private static func pixels(_ rows: [String], colour: (Character) -> UInt32?) -> CGImage? {
        let width = rows.map(\.count).max() ?? 0
        var canvas = TreePixels(width: width, height: rows.count)
        for (y, row) in rows.enumerated() {
            for (x, key) in row.enumerated() where key != "." {
                if let c = colour(key) { canvas.put(x, y, c) }
            }
        }
        return canvas.image()
    }

    private static func cached(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        if let image = cache[key] { return image }
        let image = make()
        cache[key] = image
        return image
    }
}

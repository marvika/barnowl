import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - What the card says

/// The recap's words and numbers, worked out from a week. Times and counts
/// only; repository names appear only when asked for, else "Tree A".
struct RecapFacts {
    let week: WeekSummary
    var showsNames = false

    struct Stat: Identifiable {
        var label: String
        var value: [(number: String, unit: String?)]
        var foot: String
        /// Little squares beside "Most at once", one per owlet.
        var dots = 0
        var id: String { label }
    }

    /// "31 h 40 m" as number–unit pairs.
    static func parts(_ seconds: TimeInterval) -> [(number: String, unit: String?)] {
        let seconds = max(0, seconds)
        if seconds < 59.5 { return [("\(Int(seconds.rounded()))", "s")] }
        let minutes = Int((seconds / 60).rounded())
        if seconds < 600 {
            let rest = Int(seconds.rounded()) % 60
            return rest == 0 ? [("\(Int(seconds.rounded()) / 60)", "m")] : [("\(Int(seconds) / 60)", "m"), ("\(rest)", "s")]
        }
        if minutes < 60 { return [("\(minutes)", "m")] }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? [("\(hours)", "h")] : [("\(hours)", "h"), (String(format: "%02d", rest), "m")]
    }

    /// "31 h 40 m", for a row.
    static func text(_ seconds: TimeInterval) -> String {
        parts(seconds).map { "\($0.number) \($0.unit ?? "")" }.joined(separator: " ")
    }

    /// "52 min", "1 h 5 min".
    static func plain(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// "Wed 15:12", in the Mac's own clock style.
    static func when(_ date: Date?) -> String? {
        guard let date else { return nil }
        let day = date.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) \(date.formatted(date: .omitted, time: .shortened))"
    }

    var hero: [(number: String, unit: String?)] { Self.parts(week.working) }

    /// "13–19 Oct", in the Mac's own date style.
    var dates: String {
        (week.start..<week.end).formatted(.interval.day().month(.abbreviated))
    }

    var treesPhrase: String? {
        switch week.trees {
        case 0: nil
        case 1: "one tree"
        default: "\(week.trees) trees"
        }
    }

    /// You were needed for this long, worth mentioning.
    var needed: String? { week.needed >= 60 ? Self.plain(week.needed) : nil }

    /// "just" only when it truly was little.
    var neededIsLittle: Bool { week.needed <= week.working * 0.1 }

    /// The four best things to say, in order; never a zero.
    var stats: [Stat] {
        var all: [Stat] = []
        let peak = week.peak
        if peak.count > 0 {
            let at = Self.when(peak.at)
            let foot = peak.count >= 5 ? ["a parliament", at].compactMap(\.self).joined(separator: " · ")
                : (peak.count == 1 ? ["one at a time", at].compactMap(\.self).joined(separator: " · ") : at ?? "")
            all.append(Stat(label: "Most at once", value: [("\(peak.count)", nil)], foot: foot,
                            dots: peak.count >= 2 ? min(peak.count, 8) : 0))
        }
        let longest = week.longest
        if longest.seconds >= 60 {
            all.append(Stat(label: "Longest flight", value: Self.parts(longest.seconds),
                            foot: ["one session", Self.when(longest.start)].compactMap(\.self).joined(separator: ", ")))
        }
        if week.shipped > 0 {
            all.append(Stat(label: "Shipped", value: [("\(week.shipped)", nil)],
                            foot: week.shipped == 1 ? "pull request opened" : "pull requests opened"))
        }
        if let wait = week.typicalWait {
            all.append(Stat(label: "Your replies", value: Self.parts(wait), foot: "typical wait for you"))
        }
        if week.night >= 600 {
            all.append(Stat(label: "Night shift", value: Self.parts(week.night), foot: "between 22:00 and 06:00"))
        }
        if week.sessions > 0 {
            all.append(Stat(label: "Sessions", value: [("\(week.sessions)", nil)],
                            foot: week.sessions == 1 ? "one agent session" : "agent sessions"))
        }
        if week.trees > 0 {
            all.append(Stat(label: "Trees", value: [("\(week.trees)", nil)], foot: "repositories with agent work"))
        }
        return Array(all.prefix(4))
    }

    /// The busiest repository's name (or "Tree A") and its share of the work.
    var busiest: (name: String, share: Double)? {
        // With one tree it would only say 100%.
        guard week.trees >= 2, let top = week.repositories.first, week.working > 0 else { return nil }
        return (showsNames ? top.name : "Tree A", min(1, top.seconds / week.working))
    }

    /// Owlets for the branch: one per tree (up to `limit`), each in a pose that
    /// happened this week: a ship, a finish, a night shift; the rest rest.
    func perch(limit: Int) -> [RecapPose] {
        var poses: [RecapPose] = []
        if week.shipped > 0 { poses.append(RecapPose(sprite: "ship", frame: 2, palette: "golden")) }
        if week.working > 0 { poses.append(RecapPose(sprite: "done", frame: 1, palette: "golden")) }
        if week.night >= 600 { poses.append(RecapPose(sprite: "night", frame: 0, palette: "ghost")) }
        let resting = [RecapPose(sprite: "idle", frame: 0, palette: "ember"), RecapPose(sprite: "nap", frame: 3, palette: "lilac"),
                       RecapPose(sprite: "idle", frame: 0, palette: "ghost"), RecapPose(sprite: "nap", frame: 1, palette: "golden")]
        let count = min(limit, max(1, week.trees, min(poses.count, limit)))
        var index = 0
        while poses.count < count {
            poses.append(resting[index % resting.count])
            index += 1
        }
        // Resting owlets sit at the end, like the mock: the latest napping last.
        return Array(poses.prefix(count))
    }
}

struct RecapPose: Hashable {
    var sprite: String
    var frame: Int
    var palette: String
}

// MARK: - The card

/// The weekly Roost recap, as an image to share: a night sky, the week's
/// numbers, when the owlets flew, and a few owlets on a branch.
struct RecapCard: View {
    enum Size: String, CaseIterable, Identifiable, Sendable {
        /// 1200 × 630: Slack, X, LinkedIn and Mastodon link previews.
        case wide
        /// 9:16, 1080 × 1920 when rendered at 2x: Stories and Messages.
        case story

        var id: Self { self }

        /// The card's size in points; it renders at 2x.
        var points: CGSize {
            switch self {
            case .wide: CGSize(width: 1200, height: 630)
            case .story: CGSize(width: 540, height: 960)
            }
        }

        var title: String {
            switch self {
            case .wide: "Wide"
            case .story: "Story"
            }
        }
    }

    let week: WeekSummary
    var showsNames = false
    var size: Size = .wide

    var body: some View {
        let facts = RecapFacts(week: week, showsNames: showsNames)
        ZStack(alignment: .topLeading) {
            RecapInk.sky
            switch size {
            case .wide: RecapWide(facts: facts)
            case .story: RecapStory(facts: facts)
            }
        }
        .frame(width: size.points.width, height: size.points.height)
        .clipped()
        .environment(\.colorScheme, .dark)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roost recap, week \(week.week): \(RecapFacts.text(week.working)) of agent flight")
    }
}

private enum RecapInk {
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.74)
    static let ink3 = Color.white.opacity(0.52)
    static let amber = Color(hex: 0xF5A633)
    static let lilac = Color(hex: 0xA9A5FF)
    static let lilacPale = Color(hex: 0xDEDCFF)
    static let panel = Color.white.opacity(0.065)
    static let panelLine = Color.white.opacity(0.11)
    static let sky = LinearGradient(stops: [
        .init(color: Color(hex: 0x141235), location: 0), .init(color: Color(hex: 0x1D1B48), location: 0.34),
        .init(color: Color(hex: 0x2C2862), location: 0.60), .init(color: Color(hex: 0x4A3A78), location: 0.82),
        .init(color: Color(hex: 0x7A5288), location: 1),
    ], startPoint: .top, endPoint: .bottom)
}

/// 1200 × 630.
private struct RecapWide: View {
    let facts: RecapFacts

    var body: some View {
        let week = facts.week
        ZStack(alignment: .topLeading) {
            RecapStars(count: 34, seed: UInt64(week.week) &+ 7, area: CGSize(width: 1200, height: 600),
                       avoid: [CGRect(x: 50, y: 40, width: 610, height: 400), CGRect(x: 690, y: 40, width: 470, height: 550),
                               CGRect(x: 0, y: 440, width: 660, height: 190)])
            RecapMoon(phase: MoonPhase.fraction(at: week.end))
                .frame(width: 48, height: 48)
                .offset(x: 588, y: 56)

            VStack(alignment: .leading, spacing: 0) {
                RecapEyebrow(title: "Roost recap", detail: "Week \(week.week) · \(facts.dates)", size: 13, icon: 1)
                RecapHero(parts: facts.hero, size: 92)
                    .padding(.top, 30)
                caption
                    .font(.system(size: 19))
                    .foregroundStyle(RecapInk.ink2)
                    .lineSpacing(3)
                    .frame(width: 425, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if let species = week.newSpecies.first {
                    RecapSpeciesPill(species: species, compact: false, k: 1)
                        .padding(.top, 28)
                }
            }
            .frame(width: 560, alignment: .leading)
            .offset(x: 60, y: 54)

            RecapHills()
                .frame(width: 1200, height: 62)
                .offset(y: 568)

            RecapPerch(poses: facts.perch(limit: 5), scale: 3.5, leading: 30, trailing: 18)
                .frame(width: 650, height: 572, alignment: .bottom)

            panel
                .frame(width: 468, height: 526)
                .offset(x: 680, y: 52)
        }
        .frame(width: 1200, height: 630, alignment: .topLeading)
    }

    private var caption: Text {
        var text = Text("of agent flight")
        if let trees = facts.treesPhrase {
            text = Text("\(text) \(facts.week.trees == 1 ? "in" : "across") \(Text(trees).foregroundStyle(RecapInk.ink).fontWeight(.semibold))")
        }
        if let needed = facts.needed {
            let just = facts.neededIsLittle ? "just " : ""
            return Text("\(text), while you were needed for \(just)\(Text(needed).foregroundStyle(RecapInk.ink).fontWeight(.semibold)) of it.")
        }
        return Text("\(text).")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecapStatsGrid(stats: facts.stats, k: 1, columnGap: 18, rowGap: 20)
            if let busiest = facts.busiest {
                RecapBusiest(name: busiest.name, share: busiest.share, k: 1)
                    .padding(.top, 18)
                    .overlay(alignment: .top) { Rectangle().fill(RecapInk.panelLine).frame(height: 1) }
                    .padding(.vertical, 22)
            } else {
                Spacer().frame(height: 26)
            }
            RecapSectionLabel(title: "When they flew", k: 1) {
                RecapLegend(night: facts.week.night > 0, k: 1)
            }
            .padding(.bottom, 10)
            RecapHeatmap(hours: facts.week.heatmap, cell: 13, gap: 3, labelWidth: 30, compact: false, k: 1)
            Spacer(minLength: 0)
            RecapFooter(showsNames: facts.showsNames, k: 1, long: true)
        }
        .padding(EdgeInsets(top: 26, leading: 26, bottom: 22, trailing: 26))
        .background(RecapInk.panel, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RecapInk.panelLine, lineWidth: 1))
    }
}

/// 540 × 960 (1080 × 1920 at 2x): the mock's 360 × 640 phone card at 1.5x.
private struct RecapStory: View {
    let facts: RecapFacts
    private let k: CGFloat = 1.5

    var body: some View {
        let week = facts.week
        ZStack(alignment: .topLeading) {
            RecapStars(count: 16, seed: UInt64(week.week) &+ 11, area: CGSize(width: 540, height: 450),
                       avoid: [CGRect(x: 24, y: 30, width: 351, height: 330), CGRect(x: 0, y: 360, width: 540, height: 90)])
            RecapMoon(phase: MoonPhase.fraction(at: week.end))
                .frame(width: 48, height: 48)
                .offset(x: 540 - 39 - 48, y: 45)

            VStack(alignment: .leading, spacing: 0) {
                RecapEyebrow(title: "Roost recap", detail: "Wk \(week.week)", size: 11 * k, icon: 1.5)
                RecapHero(parts: facts.hero, size: 54 * k)
                    .padding(.top, 14 * k)
                caption
                    .font(.system(size: 14.5 * k))
                    .foregroundStyle(RecapInk.ink2)
                    .lineSpacing(2 * k)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6 * k)
                RecapPerch(poses: facts.perch(limit: 3), scale: 4, leading: 22 * k, trailing: 22 * k)
                    .padding(.horizontal, -24 * k)
                    .padding(.top, 8 * k)
                RecapStatsGrid(stats: facts.stats, k: k * 0.74, columnGap: 12 * k, rowGap: 12 * k)
                    .padding(.top, 16 * k)
                RecapSectionLabel(title: "When they flew", k: k * 0.84) {
                    Text(facts.dates).font(.system(size: 12 * k * 0.84, weight: .medium)).foregroundStyle(RecapInk.ink3)
                }
                .padding(.top, 16 * k)
                .padding(.bottom, 7 * k)
                RecapHeatmap(hours: week.heatmap, cell: 15, gap: 3, labelWidth: 27, compact: true, k: k * 0.86)
                if let species = week.newSpecies.first {
                    RecapSpeciesPill(species: species, compact: true, k: k * 0.8)
                        .padding(.top, 13 * k)
                }
                Spacer(minLength: 0)
                RecapFooter(showsNames: facts.showsNames, k: k * 0.88, long: false)
            }
            .padding(EdgeInsets(top: 30 * k, leading: 24 * k, bottom: 22 * k, trailing: 24 * k))
            .frame(width: 540, height: 960, alignment: .topLeading)
        }
        .frame(width: 540, height: 960, alignment: .topLeading)
    }

    private var caption: Text {
        var text = Text("of agent flight")
        if let trees = facts.treesPhrase {
            text = Text("\(text) \(facts.week.trees == 1 ? "in" : "across") \(Text(trees).foregroundStyle(RecapInk.ink).fontWeight(.semibold))")
        }
        text = Text("\(text).")
        if let needed = facts.needed {
            return Text("\(text)\nYou were needed for \(Text(needed).foregroundStyle(RecapInk.ink).fontWeight(.semibold)).")
        }
        return text
    }
}

// MARK: - Pieces

private struct RecapEyebrow: View {
    let title: String
    let detail: String
    let size: CGFloat
    let icon: CGFloat

    var body: some View {
        HStack(spacing: size * 0.6) {
            OwletIcon(icon: "done", palette: "golden", scale: icon, animated: false)
            Text("\(Text(title.uppercased()).foregroundStyle(RecapInk.lilacPale))  \(Text("· \(detail.uppercased())").foregroundStyle(RecapInk.ink3))")
                .font(.system(size: size, weight: .semibold))
                .tracking(size * 0.14)
        }
    }
}

private struct RecapHero: View {
    let parts: [(number: String, unit: String?)]
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part.number)
                    .font(.system(size: size, weight: .bold))
                    .tracking(-size * 0.035)
                    .foregroundStyle(RecapInk.ink)
                if let unit = part.unit {
                    Text(unit)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(RecapInk.ink2)
                        .padding(.leading, size * 0.04)
                        .padding(.trailing, index < parts.count - 1 ? size * 0.1 : 0)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct RecapStatsGrid: View {
    let stats: [RecapFacts.Stat]
    let k: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: columnGap, verticalSpacing: rowGap) {
            ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { row in
                GridRow {
                    RecapStatView(stat: stats[row], k: k)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if row + 1 < stats.count {
                        RecapStatView(stat: stats[row + 1], k: k)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct RecapStatView: View {
    let stat: RecapFacts.Stat
    let k: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(stat.label.uppercased())
                .font(.system(size: 12.5 * k, weight: .semibold))
                .tracking(12.5 * k * 0.06)
                .foregroundStyle(RecapInk.ink3)
            HStack(alignment: .center, spacing: 10 * k) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(Array(stat.value.enumerated()), id: \.offset) { index, part in
                        Text(part.number)
                            .font(.system(size: 34 * k, weight: .bold))
                            .tracking(-34 * k * 0.02)
                            .foregroundStyle(RecapInk.ink)
                        if let unit = part.unit {
                            Text(unit)
                                .font(.system(size: 18 * k, weight: .semibold))
                                .foregroundStyle(RecapInk.ink2)
                                .padding(.leading, 3 * k)
                                .padding(.trailing, index < stat.value.count - 1 ? 5 * k : 0)
                        }
                    }
                }
                if stat.dots > 0 {
                    HStack(spacing: 3 * k) {
                        ForEach(0..<stat.dots, id: \.self) { index in
                            Rectangle()
                                .fill(index.isMultiple(of: 2) ? RecapInk.amber : RecapInk.lilac)
                                .frame(width: 7 * k, height: 7 * k)
                        }
                    }
                }
            }
            .padding(.top, 4 * k)
            Text(stat.foot)
                .font(.system(size: 13 * k))
                .foregroundStyle(RecapInk.ink2)
                .lineLimit(1)
                .padding(.top, 2 * k)
        }
    }
}

private struct RecapBusiest: View {
    let name: String
    let share: Double
    let k: CGFloat

    var body: some View {
        HStack(spacing: 10 * k) {
            RecapTreeIcon(scale: 2 * k)
            Text("Busiest tree").foregroundStyle(RecapInk.ink2)
            Text(name).fontWeight(.semibold).foregroundStyle(RecapInk.ink).lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(RecapInk.lilac).frame(width: max(6 * k, proxy.size.width * share))
                }
            }
            .frame(height: 6 * k)
            Text("\(Int((share * 100).rounded()))%").foregroundStyle(RecapInk.ink2)
        }
        .font(.system(size: 14 * k))
    }
}

private struct RecapSectionLabel<Trailing: View>: View {
    let title: String
    let k: CGFloat
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 12.5 * k, weight: .semibold))
                .tracking(12.5 * k * 0.06)
                .foregroundStyle(RecapInk.ink3)
            Spacer(minLength: 8)
            trailing
        }
    }
}

private struct RecapLegend: View {
    let night: Bool
    let k: CGFloat

    var body: some View {
        HStack(spacing: 4 * k) {
            key(RecapInk.lilacPale)
            Text("day")
            if night {
                key(RecapInk.amber).padding(.leading, 6 * k)
                Text("night shift")
            }
        }
        .font(.system(size: 12 * k, weight: .medium))
        .foregroundStyle(RecapInk.ink3)
    }

    private func key(_ colour: Color) -> some View {
        RoundedRectangle(cornerRadius: 2 * k).fill(colour).frame(width: 8 * k, height: 8 * k)
    }
}

/// Seven days by 24 hours: lilac by day, amber for the night shift.
private struct RecapHeatmap: View {
    let hours: [[TimeInterval]]
    let cell: CGFloat
    let gap: CGFloat
    let labelWidth: CGFloat
    let compact: Bool
    let k: CGFloat

    private static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let top = hours.flatMap(\.self).max() ?? 0
        VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: gap) {
                    Text(compact ? String(Self.days[day].prefix(1)) : Self.days[day])
                        .font(.system(size: 11 * k))
                        .foregroundStyle(RecapInk.ink3)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        let value = hours.indices.contains(day) && hours[day].indices.contains(hour) ? hours[day][hour] : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colour(value, top: top, night: hour < 6 || hour >= 22))
                            .frame(width: cell, height: cell)
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 10.5 * k))
                        .foregroundStyle(RecapInk.ink3)
                        .offset(x: labelWidth + gap + CGFloat(hour) * (cell + gap))
                }
            }
            .padding(.top, 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("When the agents worked, by day and hour")
    }

    private func colour(_ value: TimeInterval, top: TimeInterval, night: Bool) -> Color {
        guard value >= 30, top > 0 else { return Color.white.opacity(0.07) }
        let level = value / top
        if night {
            return level <= 0.25 ? RecapInk.amber.opacity(0.5) : level <= 0.5 ? RecapInk.amber.opacity(0.75) : RecapInk.amber
        }
        if level <= 0.25 { return RecapInk.lilac.opacity(0.32) }
        if level <= 0.5 { return RecapInk.lilac.opacity(0.55) }
        if level <= 0.75 { return RecapInk.lilac.opacity(0.8) }
        return RecapInk.lilacPale
    }
}

private struct RecapSpeciesPill: View {
    let species: FieldGuideSpecies
    let compact: Bool
    let k: CGFloat

    var body: some View {
        HStack(spacing: 12 * k) {
            RecapSpeciesOwlet(species: species, scale: 1.5)
            VStack(alignment: .leading, spacing: 1 * k) {
                Text("NEW IN YOUR FIELD GUIDE")
                    .font(.system(size: 11.5 * k, weight: .semibold))
                    .tracking(11.5 * k * 0.08)
                    .foregroundStyle(RecapInk.amber)
                if compact {
                    Text(species.name).font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(RecapInk.ink)
                } else {
                    Text("\(Text(species.name).fontWeight(.semibold).foregroundStyle(RecapInk.ink)) · \(species.reason)")
                        .font(.system(size: 15 * k))
                        .foregroundStyle(RecapInk.ink2)
                }
            }
        }
        .padding(EdgeInsets(top: 8 * k, leading: 8 * k, bottom: 8 * k, trailing: 18 * k))
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 18 * k))
        .overlay(RoundedRectangle(cornerRadius: 18 * k).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .fixedSize()
    }
}

private struct RecapFooter: View {
    let showsNames: Bool
    let k: CGFloat
    let long: Bool

    var body: some View {
        HStack(spacing: 7 * k) {
            OwletIcon(icon: "done", palette: "golden", scale: k >= 1.25 ? 1.5 : 1, animated: false)
            Text("\(Text("Barn Owl").fontWeight(.semibold).foregroundStyle(RecapInk.ink2))\(long ? " for macOS" : "")")
                .foregroundStyle(RecapInk.ink3)
            Spacer(minLength: 0)
            if !showsNames {
                HStack(spacing: 5 * k) {
                    RecapLockIcon().frame(width: 10 * k, height: 11 * k)
                    Text("names hidden")
                }
                .foregroundStyle(RecapInk.ink3)
                .padding(.horizontal, 9 * k)
                .padding(.vertical, 3 * k)
                .background(Color.white.opacity(0.07), in: .capsule)
            }
        }
        .font(.system(size: 13 * k))
    }
}

/// Owlets on one branch, spread out, standing on it like the sprites stand
/// on their own (the frames' last two rows are where the branch goes).
private struct RecapPerch: View {
    let poses: [RecapPose]
    let scale: CGFloat
    let leading: CGFloat
    let trailing: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            OwletBranch(scale: scale)
            // Spread to the ends like the mock; one or two sit nearer the middle.
            HStack(alignment: .bottom, spacing: 0) {
                if poses.count <= 2 { Spacer(minLength: 0) }
                ForEach(Array(poses.enumerated()), id: \.offset) { index, pose in
                    if index > 0 { Spacer(minLength: 0) }
                    RecapSprite(pose: pose, scale: scale)
                }
                if poses.count <= 2 { Spacer(minLength: 0) }
            }
            .padding(.leading, leading)
            .padding(.trailing, trailing)
        }
    }
}

/// One frame of an owlet, standing still: the card is a picture.
private struct RecapSprite: View {
    let pose: RecapPose
    let scale: CGFloat

    var body: some View {
        let frames = OwletArt.states[pose.sprite]?.frames ?? OwletArt.states["idle"]?.frames ?? []
        let index = frames.indices.contains(pose.frame) ? pose.frame : 0
        Group {
            if frames.indices.contains(index),
               let image = OwletRenderer.image(frames[index], name: "state:\(pose.sprite):\(index)", width: OwletArt.width,
                                               height: OwletArt.height, palette: pose.palette) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
            }
        }
        .frame(width: CGFloat(OwletArt.width) * scale, height: CGFloat(OwletArt.height) * scale)
        .accessibilityHidden(true)
    }
}

/// A species from the field guide: the resting owlet in that owl's colours.
private struct RecapSpeciesOwlet: View {
    let species: FieldGuideSpecies
    let scale: CGFloat

    private var colours: [Character: UInt32] {
        let ghost = OwletArt.palettes["ghost"] ?? [:]
        let golden = OwletArt.palettes["golden"] ?? [:]
        switch species {
        case .snowy:
            return ghost.merging(["o": 0x4B5170, "r": 0x9AA0B8, "f": 0xB9BFD4, "d": 0xCFD3E2, "g": 0xF3F4FA,
                                  "h": 0xFFFFFF, "e": 0x2A2440, "b": 0xFFB3C4]) { $1 }
        case .greatGrey:
            return golden.merging(["o": 0x34313F, "e": 0x1C1A24, "h": 0xDCD9E3, "g": 0xB9B5C6, "d": 0x8F8A9E,
                                   "r": 0x6D6880, "f": 0x6D6880, "w": 0xF4F2F8, "c": 0xE2DFEA, "q": 0xC2BFCC]) { $1 }
        case .longEared: return OwletArt.palettes["ember"] ?? golden
        case .eagleOwl: return golden
        }
    }

    var body: some View {
        let frame = OwletArt.states["idle"]?.frames.first ?? ""
        Group {
            if let image = RecapPixels.image(frame, width: OwletArt.width, height: OwletArt.height, colours: colours) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
            }
        }
        .frame(width: CGFloat(OwletArt.width) * scale, height: CGFloat(OwletArt.height) * scale)
        .accessibilityHidden(true)
    }
}

/// Pixel art from rows of palette keys.
private enum RecapPixels {
    static func image(_ frame: String, width: Int, height: Int, colours: [Character: UInt32]) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (index, key) in frame.enumerated() where index < width * height && key != "." {
            guard let rgb = colours[key] else { continue }
            pixels[index * 4] = UInt8((rgb >> 16) & 0xFF)
            pixels[index * 4 + 1] = UInt8((rgb >> 8) & 0xFF)
            pixels[index * 4 + 2] = UInt8(rgb & 0xFF)
            pixels[index * 4 + 3] = 0xFF
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Draws `rows` (one character per pixel) into a Canvas, `.` empty.
    static func draw(_ rows: [String], colours: [Character: Color], in context: GraphicsContext, size: CGSize) {
        let height = CGFloat(rows.count), width = CGFloat(rows.map(\.count).max() ?? 1)
        let px = size.width / width, py = size.height / height
        for (y, row) in rows.enumerated() {
            for (x, key) in row.enumerated() {
                guard let colour = colours[key] else { continue }
                context.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * py, width: px, height: py)), with: .color(colour))
            }
        }
    }
}

/// A little pixel tree: a repository.
struct RecapTreeIcon: View {
    var scale: CGFloat = 2

    private static let rows = ["..ggg..", ".ggggg.", "gggGggg", ".gGggg.", "ggggGgg", ".ggggg.", "...b...", "...b..."]

    var body: some View {
        Canvas { context, size in
            RecapPixels.draw(Self.rows, colours: ["g": Color(hex: 0x7C76EE), "G": Color(hex: 0xA9A5FF), "b": Color(hex: 0x8C5A3C)],
                             in: context, size: size)
        }
        .frame(width: 7 * scale, height: 8 * scale)
        .accessibilityHidden(true)
    }
}

private struct RecapLockIcon: View {
    private static let rows = ["..xxxxxx..", ".x......x.", ".x......x.", ".x......x.", ".x......x.",
                               "xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx"]

    var body: some View {
        Canvas { context, size in
            RecapPixels.draw(Self.rows, colours: ["x": RecapInk.ink3], in: context, size: size)
        }
    }
}

/// The week's moon, in its real phase, as 12 × 12 pixels.
private struct RecapMoon: View {
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let g = size.width / 12
            let lit = (1 - cos(phase * 2 * .pi)) / 2 // how much of the disc is lit
            let rows = ["....xxxx....", "..xxxxxxxx..", ".xxxxxxxxxx.", ".xxxxxxxxxx.", "xxxxxxxxxxxx", "xxxxxxxxxxxx",
                        "xxxxxxxxxxxx", "xxxxxxxxxxxx", ".xxxxxxxxxx.", ".xxxxxxxxxx.", "..xxxxxxxx..", "....xxxx...."]
            for (y, row) in rows.enumerated() {
                let xs = row.enumerated().filter { $0.element == "x" }.map(\.offset)
                guard let first = xs.first else { continue }
                let width = xs.count
                let litCount = Int((Double(width) * lit).rounded())
                for x in xs {
                    let fromRight = phase < 0.5 // waxing: lit on the right
                    let isLit = fromRight ? x >= first + width - litCount : x < first + litCount
                    var colour = isLit ? Color(hex: 0xFFF4DC) : Color(hex: 0x3A3670)
                    if isLit && ((x == 7 || x == 8) && y == 4 || x == 8 && y == 8) { colour = Color(hex: 0xEFE0BF) }
                    context.fill(Path(CGRect(x: CGFloat(x) * g, y: CGFloat(y) * g, width: g, height: g)), with: .color(colour))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Stepped pixel hills along the bottom, with the barn and its lit window.
private struct RecapHills: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 300, sy = size.height / 24
            let steps: [(CGFloat, CGFloat)] = [(0, 14), (16, 12), (34, 11), (60, 11), (84, 12), (104, 14), (122, 16), (146, 18),
                                               (176, 19), (210, 18), (240, 17), (270, 16), (300, 16)]
            for (a, b) in zip(steps, steps.dropFirst()) {
                context.fill(Path(CGRect(x: a.0 * sx, y: a.1 * sy, width: (b.0 - a.0) * sx + 0.5, height: (24 - a.1) * sy)),
                             with: .color(Color(hex: 0x2A2556)))
            }
            let barn = Color(hex: 0x1F1B45)
            for (x, y, w, h) in [(130.0, 9.0, 7.0, 7.0), (131, 8, 5, 1), (132, 7, 3, 1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                context.fill(Path(CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)), with: .color(barn))
            }
            context.fill(Path(CGRect(x: 133 * sx, y: 11 * sy, width: 1 * sx, height: 2 * sy)), with: .color(RecapInk.amber))
        }
        .accessibilityHidden(true)
    }
}

/// A few square stars, always in the same places for the same week.
private struct RecapStars: View {
    let count: Int
    let seed: UInt64
    let area: CGSize
    let avoid: [CGRect]

    var body: some View {
        Canvas { context, _ in
            var state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
            func next() -> UInt64 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return state >> 33
            }
            var placed = 0, tries = 0
            while placed < count, tries < count * 50 {
                tries += 1
                let point = CGPoint(x: CGFloat(next() % UInt64(area.width)), y: CGFloat(next() % UInt64(area.height)))
                guard !avoid.contains(where: { $0.contains(point) }) else { continue }
                let side: CGFloat = next() % 4 == 0 ? 3 : 2
                let opacity = [0.35, 0.5, 0.7, 0.9][Int(next() % 4)]
                context.fill(Path(CGRect(x: point.x, y: point.y, width: side, height: side)), with: .color(.white.opacity(opacity)))
                placed += 1
            }
        }
        .frame(width: area.width, height: area.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Rendering

@MainActor
enum RecapImage {
    /// The card as a PNG at 2x: 2400 × 1260 wide, 1080 × 1920 story.
    static func png(week: WeekSummary, showsNames: Bool, size: RecapCard.Size) -> Data? {
        let renderer = ImageRenderer(content: RecapCard(week: week, showsNames: showsNames, size: size))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = size.points
        return rep.representation(using: .png, properties: [:])
    }

    static func fileName(week: WeekSummary, size: RecapCard.Size) -> String {
        "Roost recap, week \(week.week)\(size == .story ? " (story)" : "").png"
    }
}

// MARK: - The window

@MainActor
@Observable
private final class RecapWindowState {
    var week: WeekSummary
    var showsNames = false
    var size = RecapCard.Size.wide
    var copied = false
    @ObservationIgnored weak var shareAnchor: NSView?
    @ObservationIgnored weak var window: NSWindow?

    init(week: WeekSummary) { self.week = week }

    func png() -> Data? { RecapImage.png(week: week, showsNames: showsNames, size: size) }

    func copy() {
        guard let data = png() else { return }
        let board = NSPasteboard.general
        board.clearContents()
        if let image = NSImage(data: data) { board.writeObjects([image]) }
        board.setData(data, forType: .png)
        copied = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            self?.copied = false
        }
    }

    func save() {
        guard let data = png() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = RecapImage.fileName(week: week, size: size)
        panel.canCreateDirectories = true
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }

    func share() {
        guard let data = png(), let anchor = shareAnchor else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Roost recap", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: RecapImage.fileName(week: week, size: size))
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }
}

/// The recap's window: the card, whether names show, its size, and ways to
/// take it elsewhere. Names start hidden every time it opens.
@MainActor
final class RecapWindowController {
    private var window: NSWindow?
    private var state: RecapWindowState?

    init() {}

    func show(week: WeekSummary) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let state {
            state.week = week
            state.showsNames = false
        } else {
            let state = RecapWindowState(week: week)
            state.window = window
            self.state = state
            window.contentViewController = NSHostingController(rootView: RecapWindowView(state: state).tint(Brand.accent))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Friday from 16:00 through Sunday: when the week's recap is on offer.
    nonisolated static func isRecapTime(_ now: Date, calendar: Calendar = .current) -> Bool {
        switch calendar.component(.weekday, from: now) {
        case 6: calendar.component(.hour, from: now) >= 16 // Friday
        case 7, 1: true // Saturday, Sunday
        default: false
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.title = "Your week in the Roost"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 520)
        if !window.setFrameUsingName("BarnOwlRecap") { window.center() }
        window.setFrameAutosaveName("BarnOwlRecap")
        return window
    }
}

private struct RecapWindowView: View {
    @Bindable var state: RecapWindowState

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Picker("Repository names", selection: $state.showsNames) {
                    Text("Hidden").tag(false)
                    Text("Shown").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Picker("Size", selection: $state.size) {
                    ForEach(RecapCard.Size.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            GeometryReader { proxy in
                let points = state.size.points
                let fit = min(proxy.size.width / points.width, proxy.size.height / points.height, 1)
                RecapCard(week: state.week, showsNames: state.showsNames, size: state.size)
                    .scaleEffect(fit, anchor: .topLeading)
                    .frame(width: points.width * fit, height: points.height * fit, alignment: .topLeading)
                    .clipShape(.rect(cornerRadius: 28 * fit))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }

            HStack(spacing: 10) {
                Text("Only times and counts. Nothing from prompts, code or branch names.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button(state.copied ? "Copied" : "Copy Image") { state.copy() }
                Button("Save Image…") { state.save() }
                Button { state.share() } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .background(ShareAnchor { state.shareAnchor = $0 })
            }
            .controlSize(.large)
        }
        .padding(EdgeInsets(top: 34, leading: 20, bottom: 18, trailing: 20))
        .frame(minWidth: 580, minHeight: 480)
    }
}

/// Hands over the AppKit view the share picker opens from.
private struct ShareAnchor: NSViewRepresentable {
    let found: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        found(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - The quick panel row

/// "Your week in the Roost · 31 h 40 m ›", for the quick panel at recap time.
struct RecapEntryRow: View {
    let week: WeekSummary
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                RecapTreeIcon(scale: 2)
                Text("Your week in the Roost \(Text("· \(RecapFacts.text(week.working))").foregroundStyle(.secondary))")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: Theme.rowRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Your week in the Roost, \(RecapFacts.plain(week.working)) of agent flight")
        .accessibilityHint("Opens the weekly recap")
    }
}

// MARK: - Demo

extension WeekSummary {
    /// A made-up week, for demo mode and previews: 31 h 40 m across four trees.
    static func demo(now: Date, calendar: Calendar = .current) -> WeekSummary {
        let monday = DailyLog.monday(of: now, calendar: calendar)
        // When the owlets flew, 0–4 per hour; a night shift from Thursday into Friday.
        let rhythm = ["000000000123443343210000", "000000000234444432110000", "000000000134434443322100",
                      "110000000233443432123334", "433210000123342210000000", "000000000000122100000000",
                      "000000000000000001221000"]
        let levels = rhythm.map { $0.compactMap { $0.wholeNumberValue } }
        let unit = 114_000 / Double(levels.joined().reduce(0, +)) // 31 h 40 m in all
        let trees = [("barnowl", 0.46), ("tk-app-2026", 0.27), ("dotfiles", 0.17), ("site", 0.10)]
        let shipped = [2, 1, 3, 2, 1, 0, 0]
        let waits: [[TimeInterval]] = [[18, 41, 95], [22, 30, 41, 300], [12, 41, 64, 41], [35, 41, 120], [28, 55, 41], [], [40]]
        let needed: [TimeInterval] = [11, 9, 14, 10, 6, 0, 2]
        let sessions = [6, 5, 8, 7, 4, 1, 1]
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            let date = calendar.date(byAdding: .day, value: day, to: monday) ?? monday
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        var days: [DaySummary] = []
        for (index, row) in levels.enumerated() {
            let date = calendar.date(byAdding: .day, value: index, to: monday) ?? monday
            var day = DaySummary(day: DailyLog.dayKey(date, calendar: calendar))
            day.hours = row.map { Double($0) * unit }
            day.working = day.hours.reduce(0, +)
            day.night = day.hours.enumerated().filter { $0.offset < 6 || $0.offset >= 22 }.reduce(0) { $0 + $1.element }
            for (name, share) in trees where day.working > 0 { day.repositories[name] = day.working * share }
            day.shipped = shipped[index]
            day.waits = waits[index]
            day.waiting = waits[index].reduce(0, +) * 1.2
            day.needed = needed[index] * 60
            day.sessions = sessions[index]
            day.peak = [3, 4, 5, 4, 3, 1, 1][index]
            day.peakAt = at(index, 15, 12)
            day.longest = [5400, 6100, 7000, 11_520, 4000, 1500, 1200][index]
            day.longestStart = at(index, 13, 40)
            days.append(day)
        }
        return WeekSummary(start: monday, week: DailyLog.isoWeek(of: monday, calendar: calendar), days: days,
                           newSpecies: [.snowy])
    }
}

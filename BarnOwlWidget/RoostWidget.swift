import SwiftUI
import WidgetKit

@main
struct BarnOwlWidgets: WidgetBundle {
    var body: some Widget { RoostWidget() }
}

/// The Roost on the desktop, under a glass dome: something to glance at,
/// not something to manage. Who's busy, and whether anyone needs you.
struct RoostWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RoostSnapshot.widgetKind, provider: RoostTimeline()) { entry in
            RoostWidgetView(entry: entry)
        }
        .configurationDisplayName("Roost")
        .description("Your coding agents under a glass dome.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RoostEntry: TimelineEntry {
    let date: Date
    let snapshot: RoostSnapshot?
}

/// Barn Owl reloads the widget when something changes. In between, entries
/// (not reloads) keep it true: a minute apart while "shipped 2 min ago" is
/// showing, one when the reading turns old, and one at each change of light,
/// so the dome's sky follows the day.
struct RoostTimeline: TimelineProvider {
    func placeholder(in context: Context) -> RoostEntry { RoostEntry(date: .now, snapshot: .preview) }

    func getSnapshot(in context: Context, completion: @escaping (RoostEntry) -> Void) {
        completion(RoostEntry(date: .now, snapshot: context.isPreview ? .preview : RoostSnapshot.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoostEntry>) -> Void) {
        let now = Date()
        let snapshot = RoostSnapshot.load()
        var dates: Set<Date> = [now]
        if let snapshot, !snapshot.isStale(at: now) {
            let staleAt = snapshot.updated.addingTimeInterval(RoostSnapshot.freshFor + 1)
            dates.insert(staleAt)
            if snapshot.lastHome != nil {
                var minute = (now.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60
                while minute < staleAt.timeIntervalSinceReferenceDate {
                    dates.insert(Date(timeIntervalSinceReferenceDate: minute))
                    minute += 60
                }
            }
        }
        // The next two changes of light, within a day.
        var light = now
        for _ in 0..<2 {
            guard let next = PocketLight.nextChange(after: light, sky: snapshot?.sky) else { break }
            dates.insert(next.addingTimeInterval(1))
            light = next.addingTimeInterval(1)
        }
        let entries = dates.sorted().map { RoostEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: Views

private let amber = Color(red: 0.96, green: 0.65, blue: 0.2)
private let ink = Color(red: 0.96, green: 0.96, blue: 1)
private let quiet = Color(red: 0.69, green: 0.68, blue: 0.8)

struct RoostWidgetView: View {
    let entry: RoostEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        RoostWidgetContent(snapshot: entry.snapshot, date: entry.date, family: family)
            .containerBackground(for: .widget) { RoostBackdrop() }
            .environment(\.colorScheme, .dark)
            .widgetURL(URL(string: "barnowl://roost"))
    }
}

/// The widget's own night, a little lighter at the top.
struct RoostBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.16, blue: 0.31), Color(red: 0.08, green: 0.08, blue: 0.17)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// What the widget shows, by size. `linked` is off only where links can't be drawn.
struct RoostWidgetContent: View {
    let snapshot: RoostSnapshot?
    let date: Date
    let family: WidgetFamily
    var linked = true

    var body: some View {
        let light = PocketLight.at(date, sky: snapshot?.sky)
        if let snapshot, snapshot.running {
            let stale = snapshot.isStale(at: date)
            if family == .systemMedium {
                MediumRoost(snapshot: snapshot, date: date, light: light, stale: stale, linked: linked)
            } else {
                SmallRoost(snapshot: snapshot, date: date, light: light, stale: stale)
            }
        } else {
            Asleep(neverRan: snapshot == nil, family: family, light: light, date: date)
        }
    }
}

// MARK: The dome

/// The Roost under a glass dome. Owlets doing something sit on the branches,
/// the most important first; the rest are a "+N" on the trunk. Nappers curl
/// up in the hollow, owlets home today sleep in the nest, and the sky follows
/// the time of day.
private struct Dome: View {
    let snapshot: RoostSnapshot?
    let date: Date
    let light: PocketLight
    let diameter: CGFloat
    var linked = false

    var body: some View {
        let d = Int(diameter)
        let size = CGFloat(d)
        let layout = DomeLayout(diameter: d)
        let active = snapshot?.active ?? []
        let shown = Array(active.prefix(layout.perches.count))
        let scene = PocketScene.Dome(
            light: light, moon: PocketLight.moon(at: date),
            perched: shown.map {
                PocketScene.Perched(sprite: $0.sprite, palette: $0.palette, needsYou: $0.needsYou, stuck: $0.stuck ?? false,
                                    helpers: ($0.helpers ?? 0) > 0)
            },
            nappers: Array((snapshot?.napperPalettes ?? []).prefix(3)),
            home: Array((snapshot?.homePalettes ?? []).suffix(d < 120 ? 2 : 3)))
        ZStack(alignment: .topLeading) {
            if let image = PocketScene.dome(diameter: d, scene) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
                    .widgetAccentedRenderingMode(.fullColor)
                    .frame(width: size, height: size)
                    .overlay(alignment: .topLeading) {
                        ForEach(Array(zip(shown, layout.perches).enumerated()), id: \.offset) { _, pair in
                            if pair.0.needsYou {
                                let glass = layout.lantern(beside: pair.1)
                                let radius = size * 0.2
                                LanternGlow(radius: radius).offset(x: glass.x - radius, y: glass.y - 2 - radius)
                            }
                        }
                    }
                    .clipShape(Circle())
            }
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1.5)
                .frame(width: size, height: size)
            // The glass catching light at the upper left.
            Path { path in
                path.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: size * 0.42,
                            startAngle: .degrees(205), endAngle: .degrees(250), clockwise: false)
            }
            .stroke(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0)], startPoint: .bottomLeading,
                                   endPoint: .topTrailing),
                    style: StrokeStyle(lineWidth: max(2.5, size * 0.024), lineCap: .round))
            counts(layout, active: active.count, shown: shown.count)
            if linked {
                ForEach(Array(zip(shown, layout.perches)), id: \.0.id) { owlet, spot in
                    Link(destination: RoostLink.session(owlet.id)) {
                        Color.clear.frame(width: 30, height: 30).contentShape(.rect)
                    }
                    .offset(x: spot.x - 15, y: spot.y - 30)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(label(active: active.count))
    }

    /// Small counts: how many more are busy, napping, home.
    @ViewBuilder
    private func counts(_ layout: DomeLayout, active: Int, shown: Int) -> some View {
        if active > shown {
            DomeCount(text: "+\(active - shown)").position(x: layout.more.x, y: layout.more.y)
        }
        if let nappers = snapshot?.nappers, nappers > 1 {
            DomeCount(text: "\(nappers)").position(x: layout.hollow.x - 17, y: layout.hollow.y - 6)
        }
        if let home = snapshot?.homeToday, home > 1 {
            DomeCount(text: "\(home)").position(x: layout.nest.x + 20, y: layout.nest.y - 14)
        }
    }

    private func label(active: Int) -> String {
        var parts = ["The Roost"]
        if active > 0 { parts.append("\(active) on the branches") }
        if let nappers = snapshot?.nappers, nappers > 0 { parts.append("\(nappers) napping") }
        if let home = snapshot?.homeToday, home > 0 { parts.append("\(home) home today") }
        return parts.joined(separator: ", ")
    }
}

/// A count worn on the tree: a small dark pill with white digits.
private struct DomeCount: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 4.5).frame(height: 14)
            .background(Color(red: 0.1, green: 0.09, blue: 0.2).opacity(0.78), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .fixedSize()
    }
}

// MARK: The words

private enum RoostLink {
    static func session(_ id: String) -> URL {
        URL(string: "barnowl://roost?session=\(id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")")
            ?? URL(string: "barnowl://roost")!
    }
}

/// "1 needs you · 3 busy", "3 busy", or "All quiet".
private struct Headline: View {
    let snapshot: RoostSnapshot
    let stale: Bool
    var size: CGFloat = 15
    /// At most two parts, for the small widget.
    var compact = false

    var body: some View {
        let needing = snapshot.needing.count, working = snapshot.working.count
        let stuck = snapshot.owlets.filter { $0.stuck == true }.count
        var parts: [Text] = []
        if needing > 0 {
            parts.append(Text(needing == 1 ? "1 needs you" : "\(needing) need you").foregroundStyle(stale ? quiet : amber))
        }
        if working > 0 { parts.append(Text("\(working) busy")) }
        if stuck > 0 { parts.append(Text("\(stuck) stuck")) }
        if parts.isEmpty { parts.append(Text(snapshot.active.isEmpty ? "All quiet" : "\(snapshot.active.count) paused")) }
        if compact { parts = Array(parts.prefix(2)) }
        let line = parts.dropFirst().reduce(parts[0]) { $0 + Text(" · ") + $1 }
        // An old reading is quiet all through, so it never passes for now.
        return line.font(.system(size: size, weight: .semibold)).foregroundStyle(stale ? quiet : ink)
            .lineLimit(1).minimumScaleFactor(0.75)
            .widgetAccentable()
    }
}

/// The one most useful thing after the headline: what's asking, else what's
/// busy, else what came home; or, when the reading is old, how old.
private struct Detail: View {
    /// "As of 22:00", or "As of Sun 22:00" on another day.
    static func asOf(_ date: Date, now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDate(date, inSameDayAs: now) else { return "As of \(time)" }
        return "As of \(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    let snapshot: RoostSnapshot
    let date: Date
    let stale: Bool
    /// Rows it may take.
    var rows = 1

    var body: some View {
        Group {
            if stale {
                Text(Self.asOf(snapshot.updated, now: date)).italic()
            } else if let asking = snapshot.needing.first {
                if let request = asking.request {
                    Text("\(asking.name): ") .fontWeight(.semibold).foregroundStyle(ink)
                        + Text(asking.isCommand ? request : "“\(request)”")
                } else {
                    Text("\(asking.name) needs you").fontWeight(.semibold)
                }
            } else if !busy.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(busy, id: \.self) { Text($0).lineLimit(1) }
                }
            } else if let home = homeText {
                Text(home)
            } else {
                Text(restText)
            }
        }
        .lineLimit(rows)
        .foregroundStyle(quiet)
    }

    /// "Agents research · typing", one per row it may take.
    private var busy: [String] {
        snapshot.owlets.filter { $0.isActive && !$0.needsYou }.prefix(rows).map { owlet in
            "\(owlet.name) · \(owlet.label.prefix(1).lowercased() + owlet.label.dropFirst())"
        }
    }

    /// "docs shipped 2 min ago".
    private var homeText: String? {
        // Worth saying for an hour; after that the nest says it.
        guard let home = snapshot.lastHome, date.timeIntervalSince(home.at) < 3600 else { return nil }
        let seconds = date.timeIntervalSince(home.at)
        let ago = seconds < 60 ? "just now" : "\(Int(seconds / 60)) min ago"
        return "\(home.name) \(home.shipped ? "shipped" : "finished") \(ago)"
    }

    /// "7 napping · 1 home today".
    private var restText: String {
        var parts: [String] = []
        if let nappers = snapshot.nappers, nappers > 0 { parts.append("\(nappers) napping") }
        if let home = snapshot.homeToday, home > 0 { parts.append("\(home) home today") }
        return parts.isEmpty ? "No owlets out" : parts.joined(separator: " · ")
    }
}

/// The plan as small moons that wax as it's used; an old reading's are faded and dashed.
private struct Moons: View {
    let limits: [RoostSnapshot.Limit]
    let date: Date
    let stale: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(limits.prefix(2)) { limit in
                let old = stale || date.timeIntervalSince(limit.updated) > 30 * 60
                HStack(spacing: 5) {
                    PocketMoon(fraction: limit.used / 100, stale: old,
                               lit: limit.high && !old ? amber : old ? Color(red: 0.73, green: 0.71, blue: 0.81)
                                   : Color(red: 0.97, green: 0.92, blue: 0.83))
                        .frame(width: old ? 15 : 12, height: old ? 15 : 12)
                        .frame(width: 15, height: 15)
                    Text(limit.title.replacingOccurrences(of: "5-hour", with: "5 hours")).foregroundStyle(quiet)
                    Text("\(Int(limit.used.rounded()))%").fontWeight(.semibold)
                        .foregroundStyle(old ? quiet : limit.high ? amber : ink)
                }
                .font(.system(size: 11)).monospacedDigit()
                .italic(old)
                .lineLimit(1).fixedSize()
            }
        }
    }
}

// MARK: Sizes

private struct SmallRoost: View {
    let snapshot: RoostSnapshot
    let date: Date
    let light: PocketLight
    let stale: Bool

    var body: some View {
        GeometryReader { space in
            VStack(spacing: 2) {
                Dome(snapshot: snapshot, date: date, light: light,
                     diameter: min(space.size.width, space.size.height - 34))
                    .opacity(stale ? 0.7 : 1)
                    .padding(.bottom, 4)
                Headline(snapshot: snapshot, stale: stale, size: 13, compact: true)
                Detail(snapshot: snapshot, date: date, stale: stale)
                    .font(.system(size: 11))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MediumRoost: View {
    let snapshot: RoostSnapshot
    let date: Date
    let light: PocketLight
    let stale: Bool
    let linked: Bool

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 16) {
                Dome(snapshot: snapshot, date: date, light: light,
                     diameter: min(space.size.height, space.size.width * 0.45), linked: linked)
                    .opacity(stale ? 0.7 : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Headline(snapshot: snapshot, stale: stale, size: 16)
                    detail.padding(.top, 4)
                    if !snapshot.limits.isEmpty {
                        Moons(limits: snapshot.limits, date: date, stale: stale).padding(.top, 14)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        let text = Detail(snapshot: snapshot, date: date, stale: stale, rows: 2).font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
        if linked, !stale, let owlet = snapshot.needing.first ?? snapshot.active.first {
            Link(destination: RoostLink.session(owlet.id)) { text }
        } else {
            text
        }
    }
}

/// Barn Owl isn't running, or the agents feature is off: an empty dome.
private struct Asleep: View {
    let neverRan: Bool
    let family: WidgetFamily
    let light: PocketLight
    let date: Date

    var body: some View {
        GeometryReader { space in
            let text = Text(neverRan ? "Open Barn Owl to see your agents here" : "Barn Owl isn't watching agents right now")
                .font(.system(size: family == .systemSmall ? 11 : 12)).foregroundStyle(quiet)
            Group {
                if family == .systemMedium {
                    HStack(spacing: 16) {
                        Dome(snapshot: nil, date: date, light: light,
                             diameter: min(space.size.height, space.size.width * 0.45)).opacity(0.55)
                        text.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 6) {
                        Dome(snapshot: nil, date: date, light: light,
                             diameter: min(space.size.width, space.size.height - 32)).opacity(0.55)
                        text.multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension RoostSnapshot {
    /// For the widget gallery.
    static var preview: RoostSnapshot {
        let now = Date()
        return RoostSnapshot(updated: now, owlets: [
            Owlet(id: "a", name: "Perch tint", place: "barnowl", palette: "golden", sprite: "ask", icon: "ask",
                  label: "Asking you", needsYou: true, working: false,
                  request: "Which colour should the Perch follow when you switch Spaces?",
                  since: now.addingTimeInterval(-42)),
            Owlet(id: "b", name: "Agents research", place: "barnowl", palette: "golden", sprite: "typing", icon: "typing",
                  label: "Typing", needsYou: false, working: true, since: now.addingTimeInterval(-1860), helpers: 12),
            Owlet(id: "c", name: "tk-app-2026", place: "tk-app-2026", palette: "ghost", sprite: "command", icon: "typing",
                  label: "Running a command", needsYou: false, working: true, since: now.addingTimeInterval(-1380)),
            Owlet(id: "d", name: "Sync engine", place: "site", palette: "golden", sprite: "think", icon: "typing",
                  label: "Thinking", needsYou: false, working: true, since: now.addingTimeInterval(-600)),
        ], limits: [
            Limit(id: "s", title: "Claude 5-hour", used: 38, updated: now, resetsAt: nil, high: false),
            Limit(id: "w", title: "Claude week", used: 71, updated: now, resetsAt: nil, high: false),
        ], workedToday: 4 * 3600, lastHome: Homecoming(name: "docs", shipped: true, at: now.addingTimeInterval(-120)),
        nappers: 2, napperPalettes: ["lilac", "golden"], homeToday: 1, homePalettes: ["golden"])
    }
}

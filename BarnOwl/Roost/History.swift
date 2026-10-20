import SwiftUI

/// The last eight weeks from the daily log: the moon calendar, a few lines
/// of story, and when the owls fly. Worked out from what the log keeps for
/// each day; nothing new is tracked.
struct History: Equatable {
    static let weeks = 8
    /// A day this busy or busier is a full, bright moon.
    static let fullDay: TimeInterval = 6 * 3600

    /// Monday eight weeks back to today, oldest first.
    let days: [DaySummary]
    let today: String

    var total: TimeInterval { days.reduce(0) { $0 + $1.working } }

    /// The day with the most owl work.
    var busiest: DaySummary? {
        days.filter { $0.working >= 60 }.max { $0.working < $1.working }
    }

    /// Days in a row with owl work, up to today (or yesterday, early on a quiet day).
    var streak: Int {
        var run = days.reversed().drop { $0.day == today && $0.working < 60 }
        var count = 0
        while let day = run.first, day.working >= 60 {
            count += 1
            run = run.dropFirst()
        }
        return count
    }

    /// The repository most of the time went to, and its share.
    var mostly: (name: String, share: Double)? {
        var times: [String: TimeInterval] = [:]
        for day in days { for (name, time) in day.repositories { times[name, default: 0] += time } }
        let total = times.values.reduce(0, +)
        guard total > 0, let top = times.max(by: { $0.value < $1.value }) else { return nil }
        return (top.key, top.value / total)
    }

    /// Owl work by weekday (Monday first) and hour of the day.
    func heat(calendar: Calendar = .current) -> [[TimeInterval]] {
        var heat = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        for day in days {
            guard let date = Self.date(of: day.day, calendar: calendar) else { continue }
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7
            for (hour, time) in day.hours.prefix(24).enumerated() { heat[weekday][hour] += time }
        }
        return heat
    }

    /// One plain sentence about when the owls fly: "Mostly afternoons, with a
    /// night shift now and then."
    func pattern(calendar: Calendar = .current) -> String? {
        let heat = heat(calendar: calendar)
        let byHour = (0..<24).map { hour in heat.reduce(0) { $0 + $1[hour] } }
        let total = byHour.reduce(0, +)
        guard total >= 3600 else { return nil }
        let parts: [(name: String, hours: Range<Int>)] = [("mornings", 6..<12), ("afternoons", 12..<18), ("evenings", 18..<23)]
        let night = (byHour[23] + byHour[0..<6].reduce(0, +)) / total
        let weekend = (heat[5] + heat[6]).reduce(0, +) / total
        guard let top = parts.max(by: { byHour[$0.hours].reduce(0, +) < byHour[$1.hours].reduce(0, +) }) else { return nil }
        var sentence = night > 0.4 ? "Mostly at night" : "Mostly \(top.name)"
        if night > 0.12 && night <= 0.4 {
            sentence += ", with a night shift now and then"
        } else if weekend > 0.25 {
            sentence += ", weekends included"
        } else if weekend < 0.03 {
            sentence += ", and weekends off"
        }
        return sentence + "."
    }

    /// How bright a day's moon is: 0 for none, 1 for a full day.
    static func brightness(_ day: DaySummary) -> Double {
        min(1, day.working / fullDay)
    }

    static func date(of key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Made-up weeks for demo mode, so screenshots never show a real log.
    static func demo(now: Date, calendar: Calendar = .current) -> History {
        let monday = DailyLog.monday(of: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: monday) ?? monday
        var random = DemoRandom(seed: 11)
        var days: [DaySummary] = []
        var date = start
        while date <= now {
            var day = DaySummary(day: DailyLog.dayKey(date, calendar: calendar))
            let weekend = calendar.isDateInWeekend(date)
            if random.next() > (weekend ? 0.45 : 0.08) {
                let hours = weekend ? 0.6 + random.next() * 2.4 : 1.5 + random.next() * 5
                day.working = hours * 3600
                let shape: [Double] = (0..<24).map { hour in
                    let h = Double(hour)
                    if weekend { return bump(h, at: 20.5, width: 2.4) }
                    let morning: Double = bump(h, at: 11, width: 2.4)
                    let afternoon: Double = bump(h, at: 15, width: 2.2)
                    let night: Double = 0.35 * bump(h, at: 22, width: 1.4)
                    return morning + afternoon + night
                }
                let sum = shape.reduce(0, +)
                day.hours = shape.map { $0 / sum * day.working }
                day.peak = 1 + Int(random.next() * 6)
                day.shipped = random.next() > 0.6 ? 1 + Int(random.next() * 2) : 0
                day.repositories = ["barnowl": day.working * 0.6, "site": day.working * 0.3, "dotfiles": day.working * 0.1]
            }
            days.append(day)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? now.addingTimeInterval(1)
        }
        return History(days: days, today: DailyLog.dayKey(now, calendar: calendar))
    }
}

/// A bell-shaped bump of work around an hour, for the demo's days.
private func bump(_ hour: Double, at centre: Double, width: Double) -> Double {
    let distance: Double = (hour - centre) / width
    return exp(-(distance * distance))
}

/// A small repeatable sequence for demo data.
private struct DemoRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: The card

/// The Today card's other view: the last eight weeks, and any day in them.
struct HistoryPanel: View {
    let history: History
    @Binding var picked: String?

    var body: some View {
        if let key = picked, let day = history.days.first(where: { $0.day == key }) {
            PickedDay(day: day, history: history, picked: $picked)
        } else {
            weeks
        }
    }

    private var weeks: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(history.total >= 60 ? Self.hours(history.total) : "Quiet so far")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(RoostInk.primary)
                Text(since).font(.callout).foregroundStyle(RoostInk.secondary)
            }
            VStack(alignment: .trailing, spacing: 10) {
                MoonCalendar(history: history, picked: $picked)
                MoonScale()
            }
            story
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("When your owls fly").font(.system(size: 15, weight: .bold)).foregroundStyle(RoostInk.primary)
                FlightHeat(heat: history.heat())
                if let pattern = history.pattern() {
                    Text(pattern).font(.callout).foregroundStyle(RoostInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var since: String {
        let first = history.days.first.flatMap { History.date(of: $0.day) }
        return "of owl work since " + (first?.formatted(.dateTime.day().month(.abbreviated)) ?? "eight weeks ago")
    }

    @ViewBuilder private var story: some View {
        let lines: [(String, String)] = [
            history.busiest.map { ("Busiest", "\(Self.dayName($0.day)) · \(RoostNumbers.duration($0.working, long: true))") },
            history.streak > 1 ? ("Streak", "\(history.streak) days in a row") : nil,
            history.mostly.map { ("Mostly", "\($0.name) · \(Int(($0.share * 100).rounded()))%") },
        ].compactMap { $0 }
        if !lines.isEmpty {
            VStack(spacing: 7) {
                ForEach(lines, id: \.0) { line in
                    HStack {
                        Text(line.0).font(.callout.weight(.semibold)).foregroundStyle(RoostInk.secondary)
                        Spacer()
                        Text(line.1).font(.callout).foregroundStyle(RoostInk.primary).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Whole hours once there are ten: "170 h", not "169 h 58 min".
    static func hours(_ time: TimeInterval) -> String {
        time >= 10 * 3600 ? "\(Int((time / 3600).rounded())) h" : RoostNumbers.duration(time, long: true)
    }

    /// "Wed 14 Oct"
    static func dayName(_ key: String) -> String {
        History.date(of: key)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? key
    }
}

/// One moon per day, Monday first: bigger and brighter the more the owls worked.
private struct MoonCalendar: View {
    let history: History
    @Binding var picked: String?

    var body: some View {
        let rows = stride(from: 0, to: history.days.count, by: 7).map { Array(history.days[$0..<min($0 + 7, history.days.count)]) }
        Grid(horizontalSpacing: 0, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 44, height: 1)
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.caption2).foregroundStyle(RoostInk.quiet).frame(maxWidth: .infinity)
                }
            }
            ForEach(rows, id: \.first?.day) { week in
                GridRow {
                    Text(week.first.map { History.date(of: $0.day)?.formatted(.dateTime.day().month(.abbreviated)) ?? "" } ?? "")
                        .font(.caption2).foregroundStyle(RoostInk.quiet).frame(width: 44, alignment: .leading)
                    ForEach(0..<7, id: \.self) { index in
                        if index < week.count {
                            let day = week[index]
                            DayMoon(brightness: History.brightness(day), worked: day.working >= 60,
                                    today: day.day == history.today, picked: day.day == picked)
                                .frame(width: 24, height: 24)
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect)
                                .onTapGesture { picked = day.day }
                                .help(label(day))
                                .accessibilityElement()
                                .accessibilityLabel(label(day))
                                .accessibilityAddTraits(day.day == picked ? [.isButton, .isSelected] : .isButton)
                                .accessibilityAction { picked = day.day }
                        } else {
                            Color.clear.frame(width: 24, height: 24).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func label(_ day: DaySummary) -> String {
        let name = HistoryPanel.dayName(day.day)
        return day.working >= 60 ? "\(name) · \(RoostNumbers.duration(day.working, long: true))" : "\(name) · resting"
    }
}

/// A day as a moon: a dim lavender dot when quiet, a big warm moon when busy,
/// an empty socket with no work at all.
struct DayMoon: View {
    let brightness: Double
    var worked = true
    var today = false
    var picked = false

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            func disc(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            }
            if worked {
                let t = pow(min(1, max(0, brightness)), 0.8)
                // A ringed day's moon is a little smaller, so its ring stands clear of it.
                let radius = (3.2 + t * (size.width / 2 - 4.2)) * (today || picked ? 0.72 : 1)
                let colour = Self.colour(t)
                if t > 0.35, !(today || picked) { context.fill(disc(radius + 3), with: .color(colour.opacity(0.1 + 0.22 * t))) }
                context.fill(disc(radius), with: .color(colour))
            } else {
                context.fill(disc(2.2), with: .color(RoostInk.moonDark))
            }
            if today || picked {
                context.stroke(disc(size.width / 2 - 0.8), with: .color(picked ? RoostInk.primary : RoostInk.lilac),
                               lineWidth: picked ? 1.6 : 1.4)
            }
        }
    }

    /// Dim lavender, through lilac, to warm moonlight.
    static func colour(_ t: Double) -> Color {
        let stops: [(Double, Double, Double)] = [(0x5E, 0x59, 0xC8), (0xB5, 0xB1, 0xFF), (0xF6, 0xEA, 0xD6)]
        let low = t < 0.5 ? stops[0] : stops[1]
        let high = t < 0.5 ? stops[1] : stops[2]
        let u: Double = t < 0.5 ? t / 0.5 : (t - 0.5) / 0.5
        func mix(_ from: Double, _ to: Double) -> Double { (from + (to - from) * u) / 255 }
        return Color(red: mix(low.0, high.0), green: mix(low.1, high.1), blue: mix(low.2, high.2))
    }
}

private struct MoonScale: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("Quiet").padding(.trailing, 4)
            ForEach([0.08, 0.3, 0.55, 0.8, 1.0], id: \.self) { brightness in
                DayMoon(brightness: brightness).frame(width: 18, height: 18)
            }
            Text("Busy").padding(.leading, 4)
        }
        .font(.caption2).foregroundStyle(RoostInk.quiet)
        .accessibilityHidden(true)
    }
}

/// Owl work by weekday and hour, eight weeks of it.
private struct FlightHeat: View {
    let heat: [[TimeInterval]]

    var body: some View {
        let most = max(1, heat.flatMap { $0 }.max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].enumerated()), id: \.offset) { weekday, name in
                HStack(spacing: 2) {
                    Text(name).font(.caption2).foregroundStyle(RoostInk.quiet).frame(width: 30, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        let share = heat[weekday][hour] / most
                        RoundedRectangle(cornerRadius: 2)
                            .fill(share > 0.08 ? RoostInk.lavender.opacity(0.12 + 0.88 * share) : .white.opacity(0.05))
                            .frame(height: 11)
                    }
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 32, height: 1)
                ForEach(["00", "06", "12", "18"], id: \.self) { hour in
                    Text(hour).font(.caption2).foregroundStyle(RoostInk.quiet).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("24").font(.caption2).foregroundStyle(RoostInk.quiet)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("When your owls fly, by weekday and hour")
    }
}

/// A day picked from the moons: the same picture as Today, for that day.
private struct PickedDay: View {
    let day: DaySummary
    let history: History
    @Binding var picked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.working >= 60 ? RoostNumbers.duration(day.working, long: true) : "A quiet day")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(RoostInk.primary)
                Text(subtitle).font(.callout).foregroundStyle(RoostInk.secondary)
            }
            if day.working >= 60 {
                DayBars(hours: day.hours).frame(height: 96)
            }
            let repositories = day.repositories.filter { $0.value >= 30 }.sorted { $0.value > $1.value }
            if !repositories.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                VStack(alignment: .leading, spacing: 9) {
                    Text("By repo").font(.system(size: 15, weight: .bold)).foregroundStyle(RoostInk.primary)
                    let most = repositories.first?.value ?? 1
                    ForEach(Array(repositories.prefix(6).enumerated()), id: \.element.key) { index, entry in
                        HStack(spacing: 12) {
                            Text(entry.key).font(.callout).foregroundStyle(RoostInk.secondary).lineLimit(1)
                                .frame(width: 92, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(RoostInk.lavender.opacity(1 - Double(index) * 0.12))
                                    .frame(width: max(6, proxy.size.width * entry.value / max(1, most)), height: 7)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: 14)
                            Text(RoostNumbers.duration(entry.value)).font(.callout.monospacedDigit()).foregroundStyle(RoostInk.secondary)
                                .frame(width: 46, alignment: .trailing)
                        }
                    }
                }
            }
            MoonCalendar(history: history, picked: $picked)
        }
    }

    /// "of owl work · up to 9 at once · 2 shipped"
    private var subtitle: String {
        var parts = ["of owl work"]
        if day.peak > 1 { parts.append("up to \(day.peak) at once") }
        if day.shipped > 0 { parts.append("\(day.shipped) shipped") }
        if day.waiting >= 60 { parts.append("waited on you \(RoostNumbers.duration(day.waiting))") }
        return parts.joined(separator: " · ")
    }
}

/// A day's owl work, hour by hour.
private struct DayBars: View {
    let hours: [TimeInterval]

    var body: some View {
        let most = max(1800, hours.max() ?? 1)
        VStack(spacing: 6) {
            Canvas { context, size in
                let slot = size.width / 24
                let width = max(3, slot * 0.72)
                let room = size.height - 10
                for (index, work) in hours.prefix(24).enumerated() {
                    let x = CGFloat(index) * slot + (slot - width) / 2
                    context.fill(Path(roundedRect: CGRect(x: x, y: 10, width: width, height: room), cornerRadius: 4),
                                 with: .color(.white.opacity(0.05)))
                    guard work > 0 else { continue }
                    let height = max(6, room * work / most)
                    context.fill(Path(roundedRect: CGRect(x: x, y: size.height - height, width: width, height: height),
                                      cornerRadius: 4), with: .color(RoostInk.lavender))
                }
            }
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { hour in
                    Text(hour).font(.caption2).foregroundStyle(RoostInk.quiet)
                    if hour != "24" { Spacer() }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Owl work by hour")
    }
}

import SwiftUI

/// One plan window as a quiet line: "Claude · this week ▬▬▬ 71% · resets Thu".
/// The bar turns amber from 80%, like the disk ring when the disk is nearly full.
struct PlanMeterRow: View {
    let limit: PlanLimit
    /// Name the agent when more than one has limits.
    var showsAgent = true

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(minWidth: 64, alignment: .leading)
            let stale = limit.isStale()
            ProgressBar(fraction: limit.used / 100,
                        colour: stale ? .secondary.opacity(0.5) : limit.isHigh ? Brand.amber : Brand.lavender)
            Text(limit.summary()).font(.caption.monospacedDigit())
                .foregroundStyle(limit.isHigh && !stale ? Brand.amber : .secondary)
                .lineLimit(1).fixedSize()
        }
        .help(PlanMeterRow.help(for: limit))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(limit.summary())")
    }

    private var title: String {
        let window = limit.window == .session ? "5-hour" : "Weekly"
        return showsAgent ? "\(limit.agent == .claude ? "Claude" : limit.agent.name) · \(window)" : window
    }

    static func help(for limit: PlanLimit, now: Date = Date()) -> String {
        var lines: [String] = []
        if let full = limit.fullAt { lines.append("At this pace, it's used up \(PlanLimit.moment(full, now: now))") }
        let age = Int(now.timeIntervalSince(limit.updated) / 60)
        lines.append(age < 2 ? "Updated just now" : "Updated \(ClaudeSource.duration(now.timeIntervalSince(limit.updated))) ago")
        return lines.joined(separator: "\n")
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(colour).frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

/// The plan lines for the quick panel: at most two, the fullest first.
struct PlanMeter: View {
    let limits: [PlanLimit]

    var body: some View {
        let agents = Set(limits.map(\.agent))
        let shown = limits.sorted { $0.used > $1.used }.prefix(2)
        VStack(spacing: 5) {
            ForEach(Array(shown)) { limit in
                PlanMeterRow(limit: limit, showsAgent: agents.count > 1 || limit.agent != .claude)
            }
        }
    }
}

import SwiftUI

/// The Barn: how full your disk is, what the owl found to tidy, and a map of
/// everything on it.
struct BarnView: View {
    enum Tab: String, CaseIterable { case tidy = "Tidy Up", explore = "Explore" }

    @Bindable var barn: BarnModel
    @State private var tab = Tab.tidy
    @State private var owlCue: OwlCue?

    var body: some View {
        VStack(spacing: 0) {
            BarnHeader(barn: barn, owlCue: owlCue)
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.vertical, 12)
            Divider()
            switch tab {
            case .tidy: TidyUpView(barn: barn)
            case .explore: ExploreView(barn: barn)
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .overlay(alignment: .bottom) {
            if let report = barn.report {
                ReportBanner(report: report, undo: barn.undoLast, dismiss: barn.dismissReport)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: barn.report != nil)
        .onChange(of: barn.report?.title) { _, title in
            guard let report = barn.report, title != nil else { return }
            let amount = report.freed > 0 ? report.freed : report.trashedSize
            if amount > 0 {
                owlCue = OwlCue(.cleaned(report.freed > 0 ? "Freed \(Bytes.format(amount))!" : "Swept!"))
            }
        }
        .onChange(of: barn.isMeasuring) { _, measuring in
            if !measuring, let biggest = barn.suggestions.map(\.size).max(), biggest > 10_000_000_000 {
                owlCue = OwlCue(.bigFind("Whoa, \(Bytes.format(biggest))!"))
            }
        }
        .task { barn.measure() }
    }
}

// MARK: - Header

private struct BarnHeader: View {
    let barn: BarnModel
    let owlCue: OwlCue?

    private var scanning: Bool {
        if case .scanning = barn.scan { return true }
        return barn.isMeasuring
    }

    var body: some View {
        HStack(spacing: 20) {
            WatchingOwl(happy: barn.report != nil, glows: scanning, cue: owlCue)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The Barn").font(.largeTitle.bold())
                    Spacer()
                    if let space = barn.space {
                        Text("\(Bytes.format(space.available)) free of \(Bytes.format(space.total))")
                            .font(.title3.weight(.medium)).monospacedDigit()
                    }
                }
                if let space = barn.space {
                    StorageBar(space: space)
                }
                Text(subtitle).font(.callout).foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(DuskSky())
        .environment(\.colorScheme, .dark)
    }

    private var subtitle: String {
        if barn.isMeasuring { return "The owl is looking around…" }
        if case .scanning(let progress) = barn.scan {
            return "Looking through \(progress.files.formatted()) files, \(Bytes.format(progress.bytes)) so far…"
        }
        let total = barn.safeTotal
        if total > 0 { return "The owl found \(Bytes.format(total)) that's safe to clean, and more to look at." }
        if barn.reviewTotal > 0 { return "All the easy bits are done. A few more things are worth a look." }
        return "Your barn is tidy."
    }
}

/// The whole disk in one bar: macOS, your things, what macOS can purge, and free.
struct StorageBar: View {
    let space: DiskSpace
    var height: CGFloat = 14

    private var segments: [(String, Int64, Color)] {
        [("Apps and files", space.yours, Brand.golden),
         ("macOS", space.system, Color.white.opacity(0.6)),
         ("System data", space.otherSystem, Color.white.opacity(0.35)),
         ("Purgeable", space.purgeable, Brand.lavender),
         ("Free", space.free, Color.white.opacity(0.14))]
    }

    private static let explanations = [
        "Your apps, documents and settings.",
        "macOS itself, on its own sealed volume.",
        "Swap, startup and recovery files, and snapshots macOS keeps.",
        "Caches, iCloud copies and snapshots macOS removes by itself when it needs the room.",
        "",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { index in
                        let segment = segments[index]
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segment.2)
                            .frame(width: max(2, proxy.size.width * CGFloat(segment.1) / CGFloat(max(1, space.total)) - 2))
                            .help("\(segment.0): \(Bytes.format(segment.1))")
                    }
                }
            }
            .frame(height: height)
            .clipShape(.capsule)
            HStack(spacing: 14) {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    HStack(spacing: 5) {
                        Circle().fill(segment.2).frame(width: 8, height: 8)
                        Text("\(segment.0) \(Bytes.format(segment.1))")
                    }
                    .font(.caption)
                    .help(Self.explanations[index])
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tidy up

private struct TidyUpView: View {
    let barn: BarnModel
    @State private var picking: BarnModel.Suggestion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !barn.fullDiskAccess { FullDiskAccessCallout() }
                if barn.safeTotal > 0 || barn.cleaning == "all" { cleanEverything }
                ForEach(CleanupRule.Group.allCases, id: \.self) { group in
                    let cards = barn.suggestions(in: group)
                    if !cards.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.rawValue).font(.headline)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                      spacing: 12) {
                                ForEach(cards) { suggestion in
                                    SuggestionCard(suggestion: suggestion, cleaning: barn.cleaning == suggestion.id,
                                                   busy: barn.cleaning != nil) {
                                        if suggestion.rule.pickItems { picking = suggestion }
                                        else { Task { await barn.clean(suggestion) } }
                                    }
                                }
                            }
                        }
                    }
                }
                KeepItClean()
                if barn.isMeasuring {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Still looking…").foregroundStyle(.secondary)
                    }
                } else if barn.suggestions.isEmpty {
                    ContentUnavailableView("Nothing to tidy", systemImage: "sparkles",
                                           description: Text("The owl looked everywhere it knows about. Try Explore to see what takes the most space."))
                }
                Color.clear.frame(height: 60)
            }
            .padding(24)
        }
        .sheet(item: $picking) { suggestion in
            PickItemsSheet(suggestion: suggestion) { paths in
                picking = nil
                Task { await barn.clean(suggestion, items: paths) }
            } cancel: { picking = nil }
        }
    }

    private var cleanEverything: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles").font(.title).foregroundStyle(Brand.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Clean everything that's safe").font(.headline)
                Text("Caches and build files that apps and tools make again when they need them. Nothing of yours.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await barn.cleanAllSafe() }
            } label: {
                if barn.cleaning == "all" {
                    ProgressView().controlSize(.small).frame(width: 120)
                } else {
                    Text("Free Up \(Bytes.format(barn.safeTotal))").frame(minWidth: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(barn.cleaning != nil || barn.isMeasuring)
        }
        .padding(16)
        .background(Brand.amber.opacity(0.12), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.amber.opacity(0.35)))
    }
}

private struct SuggestionCard: View {
    let suggestion: BarnModel.Suggestion
    let cleaning: Bool
    let busy: Bool
    let action: () -> Void

    private var rule: CleanupRule { suggestion.rule }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: rule.symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(safetyColour.gradient, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title).font(.headline)
                    SafetyChip(safety: rule.safety)
                }
                Spacer()
                Text(suggestion.blockedBy == "Needs Full Disk Access" ? "?" : Bytes.format(suggestion.size))
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }
            Text(rule.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                if let blocked = suggestion.blockedBy {
                    Label(blocked, systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                actionButton
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
    }

    @ViewBuilder private var actionButton: some View {
        switch rule.safety {
        case .yourCall:
            Button("Show in Finder") {
                if let path = rule.expandedPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }
        case .safe, .review:
            Button {
                action()
            } label: {
                if cleaning { ProgressView().controlSize(.small) } else { Text(rule.pickItems ? "Choose…" : "Clean") }
            }
            .disabled(busy || suggestion.blockedBy != nil)
        }
    }

    private var safetyColour: Color {
        switch rule.safety {
        case .safe: .green
        case .review: Brand.amber
        case .yourCall: Brand.lavender
        }
    }
}

struct SafetyChip: View {
    let safety: CleanupRule.Safety

    var body: some View {
        let (text, colour): (String, Color) = switch safety {
        case .safe: ("Safe to clean", .green)
        case .review: ("Pick what goes", Brand.amber)
        case .yourCall: ("Your call", Brand.lavender)
        }
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour.opacity(0.18), in: .capsule)
            .foregroundStyle(colour)
    }
}

private struct PickItemsSheet: View {
    let suggestion: BarnModel.Suggestion
    let clean: ([String]) -> Void
    let cancel: () -> Void
    @State private var picked: Set<String> = []

    private var total: Int64 { suggestion.items.filter { picked.contains($0.path) }.map(\.size).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.rule.title).font(.title2.bold())
            Text(suggestion.rule.detail).foregroundStyle(.secondary)
            List(suggestion.items) { item in
                Toggle(isOn: Binding(get: { picked.contains(item.path) },
                                     set: { if $0 { picked.insert(item.path) } else { picked.remove(item.path) } })) {
                    HStack {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if let modified = item.modified {
                            Text(modified, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                        }
                        Text(Bytes.format(item.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                }
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "") }
                }
            }
            .frame(minHeight: 280)
            HStack {
                Button(picked.count == suggestion.items.count ? "Select None" : "Select All") {
                    picked = picked.count == suggestion.items.count ? [] : Set(suggestion.items.map(\.path))
                }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(cleanTitle) { clean(Array(picked)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var cleanTitle: String {
        let verb = if case .trash = suggestion.rule.method { "Move to Trash" } else { "Clean" }
        return picked.isEmpty ? verb : "\(verb) (\(Bytes.format(total)))"
    }
}

/// The owl keeping an eye on things.
private struct KeepItClean: View {
    @AppStorage(PrefKey.barnLowSpaceWarning) private var lowSpace = true
    @AppStorage(PrefKey.barnWeeklyCheck) private var weekly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep it clean").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Warn me when the disk is nearly full", isOn: $lowSpace)
                Toggle("Look for things to tidy once a week, and tell me if there's much", isOn: $weekly)
                Text("The owl only ever looks and tells you. It never cleans anything by itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
        }
    }
}

private struct FullDiskAccessCallout: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(Brand.lavender)
            VStack(alignment: .leading, spacing: 2) {
                Text("See everything with Full Disk Access").font(.headline)
                Text("Without it, the owl can't look in the Trash, Safari, Mail, iPhone backups or other apps' private folders. Turn on Barn Owl in the list, then come back.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
        }
        .padding(14)
        .background(Brand.lavender.opacity(0.1), in: .rect(cornerRadius: 14))
    }
}

private struct ReportBanner: View {
    let report: BarnModel.Report
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: report.problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(report.problems.isEmpty ? .green : Brand.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                if !report.trashed.isEmpty {
                    Text("Moved to the Trash. It frees the space when you empty the Trash.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let problem = report.problems.first {
                    Text(report.problems.count == 1 ? problem : "\(problem), and \(report.problems.count - 1) more")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if !report.trashed.isEmpty { Button("Undo", action: undo) }
            Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    private var headline: String {
        if report.freed > 0 { return "\(report.title): freed \(Bytes.format(report.freed))" }
        if report.trashedSize > 0 { return "\(report.title): \(Bytes.format(report.trashedSize)) moved to the Trash" }
        return report.problems.isEmpty ? "\(report.title): done" : "\(report.title): some things were kept"
    }
}

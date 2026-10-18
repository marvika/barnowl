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
                ReportBanner(report: report, busy: barn.cleaning != nil, stuck: !barn.stuckInTrash.isEmpty,
                             undo: barn.undoLast, emptyTrashed: { Task { await barn.emptyTrashed() } },
                             showStuck: barn.showStuckInTrash, dismiss: barn.dismissReport)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: barn.report != nil)
        .onChange(of: barn.report?.title) { _, title in
            guard let report = barn.report, title != nil else { return }
            let freed = max(report.freed, report.expected)
            if freed > 0 {
                owlCue = OwlCue(.cleaned("Freed \(Bytes.format(freed))!"))
            } else if report.trashedSize > 0 {
                owlCue = OwlCue(.cleaned("Swept!"))
            }
        }
        .onChange(of: barn.isMeasuring) { _, measuring in
            // Something big it can actually help with, and only once a day each.
            guard !measuring,
                  let biggest = barn.suggestions.filter({ $0.rule.safety != .yourCall && $0.blockedBy == nil })
                      .max(by: { $0.size < $1.size }),
                  biggest.size > 5_000_000_000,
                  OwlOccasions.firstTime("bigFind-\(biggest.id)", period: OwlOccasions.today) else { return }
            owlCue = OwlCue(.bigFind("Whoa, \(Bytes.format(biggest.size))!"))
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
                        Text("\(Bytes.format(space.available)) available of \(Bytes.format(space.total))")
                            .font(.title3.weight(.medium)).monospacedDigit()
                            .help("Free space plus what macOS can purge by itself, as Finder counts it.")
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
        .background(DuskSky(showsMoon: false))
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
    /// Asks before anything that can't be undone.
    @State private var confirming: Confirmation?

    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let button: String
        let run: () async -> Void
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !barn.fullDiskAccess { FullDiskAccessCallout() }
                if barn.safeTotal > 0 || barn.cleaning == "all" { cleanEverything }
                ForEach([CleanupRule.Safety.safe, .review, .yourCall], id: \.self) { safety in
                    let rows = barn.suggestions.filter { $0.rule.safety == safety }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeading(safety: safety, total: rows.filter { $0.blockedBy == nil }.map(\.size).reduce(0, +))
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { position, suggestion in
                                    if position > 0 { Divider().padding(.leading, 58) }
                                    SuggestionRow(suggestion: suggestion, cleaning: barn.cleaning == suggestion.id,
                                                  busy: barn.cleaning != nil) { start(suggestion) }
                                }
                            }
                            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Theme.cardRadius))
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
                if suggestion.rule.needsConfirmation {
                    let size = suggestion.items.filter { paths.contains($0.path) }.map(\.size).reduce(0, +)
                    confirming = Confirmation(title: "Remove \(paths.count) \(paths.count == 1 ? "item" : "items")?",
                                              message: "\(Bytes.format(size)) will be removed for good. This can't be undone.",
                                              button: "Remove") {
                        await barn.clean(suggestion, items: paths)
                    }
                } else {
                    Task { await barn.clean(suggestion, items: paths) }
                }
            } cancel: { picking = nil }
        }
        .alert(confirming?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
               presenting: confirming) { confirmation in
            Button(confirmation.button, role: .destructive) { Task { await confirmation.run() } }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private func start(_ suggestion: BarnModel.Suggestion) {
        let rule = suggestion.rule
        if rule.pickItems {
            picking = suggestion
        } else if rule.id == "trash" {
            // Measured again now: things may have gone in since.
            Task {
                let size = await barn.currentSize(of: rule)
                let pending = barn.report?.trashed.count ?? 0
                confirming = Confirmation(
                    title: "Empty the Trash?",
                    message: "\(Bytes.format(size)) will be removed for good. "
                        + (pending > 0 ? "That includes the \(pending == 1 ? "item" : "\(pending) items") you just moved there, which you then can't undo. " : "")
                        + "This can't be undone.",
                    button: "Empty Trash") { await barn.clean(suggestion) }
            }
        } else if rule.needsConfirmation {
            let names = suggestion.items.prefix(8).map(\.name).joined(separator: ", ")
            let more = suggestion.items.count > 8 ? ", and \(suggestion.items.count - 8) more" : ""
            confirming = Confirmation(
                title: "Remove \(rule.title)?",
                message: (names.isEmpty ? "" : names + more + ". ")
                    + "\(Bytes.format(suggestion.size)) will be removed for good. This can't be undone.",
                button: "Remove") { await barn.clean(suggestion) }
        } else {
            Task { await barn.clean(suggestion) }
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
                let safe = barn.safeSuggestions
                confirming = Confirmation(
                    title: "Free up \(Bytes.format(barn.safeTotal))?",
                    message: "The owl will clean: " + safe.map { "\($0.rule.title) (\(Bytes.format($0.size)))" }
                        .joined(separator: ", ") + ". Apps and tools make these again when they need them.",
                    button: "Free Up") {
                    await barn.cleanAllSafe(safe)
                }
            } label: {
                if barn.cleaning == "all" {
                    ProgressView().controlSize(.small).frame(width: 120)
                } else {
                    Text("Free Up \(Bytes.format(barn.safeTotal))").frame(minWidth: 120)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(barn.cleaning != nil || barn.isMeasuring)
        }
        .padding(16)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Brand.accent.opacity(0.3)))
    }
}

/// One heading per kind of safety, so you know before you read on.
private struct SectionHeading: View {
    let safety: CleanupRule.Safety
    let total: Int64

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(safety.colour).frame(width: 9, height: 9)
            Text(safety.heading).font(.headline)
            Text(safety.explanation).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(Bytes.format(total)).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

extension CleanupRule.Safety {
    var heading: String {
        switch self {
        case .safe: "Safe to clean"
        case .review: "Check first"
        case .yourCall: "Only you know"
        }
    }

    var explanation: String {
        switch self {
        case .safe: "Apps and tools make these again when they need them."
        case .review: "Probably fine to clean, but have a look at what goes."
        case .yourCall: "Big, but yours. The owl shows you where; it never cleans these."
        }
    }

    var colour: Color {
        switch self {
        case .safe: .green
        case .review: Brand.amber
        case .yourCall: Brand.lavender
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: BarnModel.Suggestion
    let cleaning: Bool
    let busy: Bool
    let action: () -> Void

    private var rule: CleanupRule { suggestion.rule }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.symbol)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(rule.safety.colour.gradient, in: .rect(cornerRadius: Theme.rowRadius))
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title).font(.body.weight(.semibold))
                Text(rule.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(rule.detail)
                HStack(spacing: 10) {
                    Label(rule.methodSummary, systemImage: methodSymbol)
                    if let blocked = suggestion.blockedBy {
                        Label(blocked, systemImage: "pause.circle").foregroundStyle(Brand.amber)
                    }
                }
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(suggestion.blockedBy == "Needs Full Disk Access" ? "?" : Bytes.format(suggestion.size))
                .font(.body.weight(.semibold)).monospacedDigit()
            actionButton.frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var actionButton: some View {
        switch rule.safety {
        case .yourCall:
            Button("Show") {
                if let path = rule.expandedPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }
        case .safe, .review:
            Button {
                action()
            } label: {
                if cleaning { ProgressView().controlSize(.small) } else { Text(buttonTitle) }
            }
            .disabled(busy || suggestion.blockedBy != nil)
        }
    }

    private var buttonTitle: String {
        if rule.pickItems { return "Choose…" }
        if rule.id == "trash" { return "Empty…" }
        return rule.needsConfirmation ? "Remove…" : "Clean"
    }

    private var methodSymbol: String {
        switch rule.method {
        case .delete: "xmark.bin"
        case .trash: "arrow.uturn.backward"
        case .command: "terminal"
        case .none: "eye"
        }
    }
}

private struct PickItemsSheet: View {
    let suggestion: BarnModel.Suggestion
    let clean: ([String]) -> Void
    let cancel: () -> Void
    @State private var picked: Set<String> = []
    @State private var search = ""

    private var total: Int64 { suggestion.items.filter { picked.contains($0.path) }.map(\.size).reduce(0, +) }

    private var shown: [BarnModel.Item] {
        search.isEmpty ? suggestion.items : suggestion.items.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.rule.title).font(.title2.bold())
            Text(suggestion.rule.detail).foregroundStyle(.secondary)
            if suggestion.items.count > 10 {
                TextField("Search \(suggestion.items.count) items", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            List(shown) { item in
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
                let all = Set(shown.map(\.path))
                Button(all.isSubset(of: picked) ? "Select None" : "Select All") {
                    if all.isSubset(of: picked) { picked.subtract(all) } else { picked.formUnion(all) }
                }
                if !picked.isEmpty {
                    Text("\(picked.count) picked").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(cleanTitle) { clean(Array(picked)) }
                    .buttonStyle(.glassProminent)
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
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Theme.cardRadius))
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
        .background(Brand.lavender.opacity(0.1), in: .rect(cornerRadius: Theme.cardRadius))
    }
}

private struct ReportBanner: View {
    let report: BarnModel.Report
    let busy: Bool
    let stuck: Bool
    let undo: () -> Void
    let emptyTrashed: () -> Void
    let showStuck: () -> Void
    let dismiss: () -> Void
    @State private var confirmingEmpty = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: report.problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(report.problems.isEmpty ? .green : Brand.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                if !report.trashed.isEmpty {
                    Text("It frees the space once it's gone from the Trash.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if report.freed == 0, report.expected > 0 {
                    Text("macOS can take a little while to count it as free, while a snapshot holds on to it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let problem = report.problems.first {
                    Text(report.problems.count == 1 ? problem : "\(problem), and \(report.problems.count - 1) more")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if stuck { Button("Show in Trash", action: showStuck) }
            if !report.trashed.isEmpty {
                Button("Undo", action: undo).disabled(busy)
                Button("Empty from Trash…") { confirmingEmpty = true }.disabled(busy)
            }
            Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
        }
        .alert("Remove these from the Trash?", isPresented: $confirmingEmpty) {
            Button("Remove", role: .destructive, action: emptyTrashed)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(report.trashed.count == 1
                 ? "Only what was just moved there (\(Bytes.format(report.trashedSize))) is removed for good. The rest of your Trash stays. This can't be undone."
                 : "Only the \(report.trashed.count) items just moved there (\(Bytes.format(report.trashedSize))) are removed for good. The rest of your Trash stays. This can't be undone.")
        }
        .padding(14)
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    private var headline: String {
        if report.freed > 0 { return "\(report.title): freed \(Bytes.format(report.freed))" }
        if report.trashed.isEmpty, report.expected > 0 { return "\(report.title): cleared about \(Bytes.format(report.expected))" }
        if report.trashedSize > 0 { return "\(report.title): \(Bytes.format(report.trashedSize)) moved to the Trash" }
        return report.problems.isEmpty ? "\(report.title): done" : "\(report.title): some things were kept"
    }
}

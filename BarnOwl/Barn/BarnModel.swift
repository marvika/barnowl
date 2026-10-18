import AppKit
import Foundation
import Observation

/// Everything the Barn shows: how full the disk is, what the owl found to
/// tidy, and the full scan for exploring.
@MainActor
@Observable
final class BarnModel {
    struct Item: Identifiable, Hashable, Sendable {
        let path: String
        let name: String
        let size: Int64
        let modified: Date?
        var id: String { path }
    }

    struct Suggestion: Identifiable {
        let rule: CleanupRule
        /// What cleaning it frees, as far as anyone can tell beforehand.
        var size: Int64
        /// What's inside, for rules where you pick.
        var items: [Item] = []
        /// Why it can't be cleaned right now.
        var blockedBy: String?
        var id: String { rule.id }
    }

    struct Report {
        var title: String
        /// Measured: free space after minus before.
        var freed: Int64
        var trashed: [(from: URL, to: URL)] = []
        var trashedSize: Int64 = 0
        var problems: [String] = []
        /// What it should have freed. macOS can take a while to show space
        /// as free (a snapshot may hold on to it), so this is the fallback.
        var expected: Int64 = 0
    }

    enum ScanState {
        case idle
        case scanning(DiskScanner.Progress)
        case done(DiskScan)
    }

    private(set) var space = DemoMode.isOn ? BarnDemo.space : DiskSpace.current()
    private(set) var fullDiskAccess = DemoMode.isOn || FullDiskAccess.isGranted
    private(set) var suggestions: [Suggestion] = []
    private(set) var isMeasuring = false
    private(set) var lastMeasured: Date?
    /// The rule being cleaned right now.
    private(set) var cleaning: String?
    private(set) var report: Report?
    private(set) var scan = ScanState.idle
    /// Things put aside in Explore, to move to the Trash together.
    var basket: [Item] = []

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var measureTask: Task<Void, Never>?
    /// Bumped on each new measure, so an older one still finishing can't
    /// overwrite what a newer one found.
    @ObservationIgnored private var measureRun = 0

    /// Everything safe, in one click.
    var safeTotal: Int64 {
        suggestions.filter { $0.rule.safety == .safe && $0.blockedBy == nil }.map(\.size).reduce(0, +)
    }

    var reviewTotal: Int64 {
        suggestions.filter { $0.rule.safety == .review }.map(\.size).reduce(0, +)
    }

    func suggestions(in group: CleanupRule.Group) -> [Suggestion] {
        suggestions.filter { $0.rule.group == group }
    }

    // MARK: Measuring

    func refreshSpace() {
        guard !DemoMode.isOn else { return }
        space = DiskSpace.current()
        fullDiskAccess = FullDiskAccess.isGranted
    }

    /// Measures every rule that applies on this Mac.
    func measure() {
        guard measureTask == nil else { return }
        if DemoMode.isOn {
            suggestions = BarnDemo.suggestions()
            lastMeasured = Date()
            return
        }
        refreshSpace()
        isMeasuring = true
        measureRun += 1
        let run = measureRun
        measureTask = Task {
            var found: [Suggestion] = []
            for rule in CleanupRule.all {
                if Task.isCancelled || run != measureRun { return }
                if let suggestion = await Self.measure(rule, fullDiskAccess: fullDiskAccess) {
                    found.append(suggestion)
                    // Show them as they come in.
                    if run == measureRun { suggestions = Self.ordered(found) }
                }
            }
            guard run == measureRun else { return }
            suggestions = Self.ordered(found)
            isMeasuring = false
            lastMeasured = Date()
            measureTask = nil
        }
    }

    /// Starts measuring afresh, dropping one that's under way.
    private func measureFresh() {
        measureTask?.cancel()
        measureTask = nil
        measure()
    }

    private static func ordered(_ suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.sorted { ($0.rule.safety, -$0.size) < ($1.rule.safety, -$1.size) }
    }

    /// How much one rule would free, or nil if it doesn't apply here.
    nonisolated private static func measure(_ rule: CleanupRule, fullDiskAccess: Bool) async -> Suggestion? {
        if let tool = rule.tool, !(await CleanupRunner.hasTool(tool)) { return nil }
        if rule.needsFullDiskAccess && !fullDiskAccess {
            // Worth mentioning only if the place exists at all.
            guard rule.expandedPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
            return Suggestion(rule: rule, size: 0, blockedBy: "Needs Full Disk Access")
        }
        var suggestion = Suggestion(rule: rule, size: 0)
        if rule.id == "simulators-unavailable" {
            (suggestion.size, suggestion.items) = await unavailableSimulators()
        } else if rule.pickItems {
            suggestion.items = await items(for: rule)
            suggestion.size = suggestion.items.map(\.size).reduce(0, +)
        } else {
            for path in rule.expandedPaths where FileManager.default.fileExists(atPath: path) {
                if let scan = await DiskScanner().scan(root: path, workers: 4, progress: { _ in }) {
                    suggestion.size += rule.safety == .yourCall ? scan.total.size : scan.total.reclaimable
                }
            }
        }
        // Not worth a card for less than a megabyte.
        guard suggestion.size >= 1 << 20 else { return nil }
        if let running = await runningOwner(of: rule) { suggestion.blockedBy = "Quit \(running) first" }
        return suggestion
    }

    /// The things inside a rule's folders, biggest first: only what the
    /// rule allows, and never what the safety gate would refuse.
    nonisolated static func items(for rule: CleanupRule, home: String = CleanupRule.realHome) async -> [Item] {
        var items: [Item] = []
        let running = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey,
                                      .totalFileAllocatedSizeKey]
        for folder in rule.expandedPaths(home: home) where FileManager.default.fileExists(atPath: folder) {
            // Everything directly inside, files and folders alike.
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys) else { continue }
            for child in children {
                let name = child.lastPathComponent
                guard !running.contains(name.lowercased()), rule.allows(child, size: nil) else { continue }
                let values = try? child.resourceValues(forKeys: Set(keys))
                if values?.isSymbolicLink == true { continue }
                // Only what the gate would let through.
                let path = folder + "/" + name
                guard CleanupGate.check(path, rule: rule, home: home) == nil else { continue }
                var size = Int64(values?.totalFileAllocatedSize ?? 0)
                if values?.isDirectory == true {
                    size = await DiskScanner().scan(root: path, workers: 2, progress: { _ in })?.total.reclaimable ?? 0
                }
                guard rule.allows(child, size: size) else { continue }
                items.append(Item(path: path, name: name, size: size, modified: values?.contentModificationDate))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Simulators whose runtime is gone, from simctl's own list, with their names.
    nonisolated private static func unavailableSimulators() async -> (Int64, [Item]) {
        let (status, output) = await CleanupRunner.shell("xcrun simctl list devices unavailable -j")
        guard status == 0, let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return (0, []) }
        let root = ("~/Library/Developer/CoreSimulator/Devices" as NSString).expandingTildeInPath
        var total: Int64 = 0
        var items: [Item] = []
        for (runtime, list) in devices {
            // com.apple.CoreSimulator.SimRuntime.iOS-17-2 → iOS 17.2
            let version = runtime.components(separatedBy: ".").last?.replacingOccurrences(of: "-", with: " ", options: [], range: nil)
                .replacingOccurrences(of: #"(\d+) (\d+)"#, with: "$1.$2", options: .regularExpression) ?? runtime
            for device in list {
                guard let udid = device["udid"] as? String else { continue }
                let size = await DiskScanner().scan(root: root + "/" + udid, workers: 2, progress: { _ in })?.total.reclaimable ?? 0
                total += size
                items.append(Item(path: root + "/" + udid, name: "\(device["name"] as? String ?? udid) (\(version))",
                                  size: size, modified: nil))
            }
        }
        return (total, items.sorted { $0.size > $1.size })
    }

    /// How much a rule's folders hold right now, for a confirmation.
    func currentSize(of rule: CleanupRule) async -> Int64 {
        guard !DemoMode.isOn else { return suggestions.first { $0.id == rule.id }?.size ?? 0 }
        return await Self.measure(rule, fullDiskAccess: fullDiskAccess)?.size ?? 0
    }

    nonisolated private static func runningOwner(of rule: CleanupRule) async -> String? {
        await MainActor.run {
            for id in rule.ownerApps {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                    return app.localizedName ?? id
                }
            }
            return nil
        }
    }

    // MARK: Cleaning

    /// Cleans one suggestion: all of it, or the picked items.
    func clean(_ suggestion: Suggestion, items: [String] = []) async {
        guard cleaning == nil else { return }
        if DemoMode.isOn { return await pretendToClean([suggestion], title: suggestion.rule.title) }
        cleaning = suggestion.id
        let before = DiskSpace.current()?.free ?? 0
        let outcome = await CleanupRunner.run(suggestion.rule, items: items)
        refreshSpace()
        let trashedSize = suggestion.items.filter { picked in outcome.trashed.contains { $0.from.path == picked.path } }
            .map(\.size).reduce(0, +)
        let expected = items.isEmpty ? suggestion.size
            : suggestion.items.filter { picked in outcome.done.contains(picked.path) }.map(\.size).reduce(0, +)
        show(Report(title: suggestion.rule.title, freed: max(0, (space?.free ?? before) - before),
                    trashed: outcome.trashed, trashedSize: trashedSize,
                    problems: outcome.skipped.map { "\(($0.0 as NSString).lastPathComponent): \($0.1)" },
                    expected: outcome.done.isEmpty ? 0 : expected))
        cleaning = nil
        measureAgain(suggestion.rule)
        if !outcome.trashed.isEmpty { measureAgain(CleanupRule.trash) }
    }

    /// The safe suggestions that "Free Up" cleans.
    var safeSuggestions: [Suggestion] {
        suggestions.filter { $0.rule.safety == .safe && $0.blockedBy == nil }
    }

    /// Every safe suggestion, one after the other: exactly the ones you were
    /// shown when you said yes.
    func cleanAllSafe(_ safe: [Suggestion]) async {
        guard cleaning == nil else { return }
        let safe = safe.filter { $0.rule.safety == .safe }
        guard !safe.isEmpty else { return }
        if DemoMode.isOn { return await pretendToClean(safe, title: "Everything safe") }
        cleaning = "all"
        let before = DiskSpace.current()?.free ?? 0
        var problems: [String] = []
        var expected: Int64 = 0
        for suggestion in safe {
            let outcome = await CleanupRunner.run(suggestion.rule, items: [])
            problems += outcome.skipped.map { "\(suggestion.rule.title): \($0.1)" }
            if !outcome.done.isEmpty { expected += suggestion.size }
        }
        refreshSpace()
        show(Report(title: "Everything safe", freed: max(0, (space?.free ?? before) - before), problems: problems,
                    expected: expected))
        cleaning = nil
        measureFresh()
    }

    /// Shows a report. Anything the one before moved to the Trash stays
    /// undoable with it, so a second clean-up never strands the first.
    private func show(_ new: Report) {
        var new = new
        if let old = report, !old.trashed.isEmpty {
            new.trashed = old.trashed + new.trashed
            new.trashedSize += old.trashedSize
        }
        report = new
    }

    /// Demo mode: looks like cleaning, touches nothing.
    private func pretendToClean(_ cleaned: [Suggestion], title: String) async {
        cleaning = cleaned.count == 1 ? cleaned[0].id : "all"
        try? await Task.sleep(for: .seconds(1.2))
        let freed = cleaned.map(\.size).reduce(0, +)
        suggestions.removeAll { gone in cleaned.contains { $0.id == gone.id } }
        space?.free += freed
        space?.data -= freed
        report = Report(title: title, freed: freed)
        cleaning = nil
    }

    /// Puts back what the last clean-up moved to the Trash, and says so if
    /// something couldn't go back.
    func undoLast() {
        guard let trashed = report?.trashed, !trashed.isEmpty, cleaning == nil else { return }
        if DemoMode.isOn { report = nil; return }
        let stuck = CleanupRunner.undo(trashed)
        if stuck.isEmpty {
            report = nil
        } else {
            report = Report(title: "Undo", freed: 0, trashedSize: 0,
                            problems: stuck.map { "\($0.from.lastPathComponent) is still in the Trash: something new is in its place" })
            stuckInTrash = stuck.map(\.to)
        }
        refreshSpace()
        measureFresh()
    }

    /// What Undo couldn't put back, to show in the Trash.
    private(set) var stuckInTrash: [URL] = []

    func showStuckInTrash() {
        NSWorkspace.shared.activateFileViewerSelecting(stuckInTrash)
    }

    func dismissReport() {
        report = nil
        stuckInTrash = []
    }

    /// Removes for good what the last clean-up moved to the Trash, and only
    /// that: each item must still be straight inside the Trash.
    func emptyTrashed() async {
        guard let trashed = report?.trashed, !trashed.isEmpty, cleaning == nil else { return }
        let title = report?.title ?? ""
        if DemoMode.isOn {
            report = Report(title: title, freed: report?.trashedSize ?? 0)
            return
        }
        cleaning = "emptying"
        let before = DiskSpace.current()?.free ?? 0
        let size = report?.trashedSize ?? 0
        var problems: [String] = []
        for item in trashed {
            do {
                try CleanupRunner.removeFromTrash(item.to)
            } catch {
                problems.append("\(item.to.lastPathComponent): \(error.localizedDescription)")
            }
        }
        refreshSpace()
        report = Report(title: title, freed: max(0, (space?.free ?? before) - before), problems: problems,
                        expected: problems.count == trashed.count ? 0 : size)
        cleaning = nil
        measureAgain(CleanupRule.trash)
    }

    private func measureAgain(_ rule: CleanupRule) {
        Task {
            let fresh = await Self.measure(rule, fullDiskAccess: fullDiskAccess)
            suggestions.removeAll { $0.id == rule.id }
            if let fresh { suggestions = Self.ordered(suggestions + [fresh]) }
        }
    }

    // MARK: Exploring

    func startScan() {
        scanTask?.cancel()
        if DemoMode.isOn {
            scanTask = Task {
                for step in 1...12 {
                    scan = .scanning(DiskScanner.Progress(files: Int64(step) * 241_000, bytes: Int64(step) * 31_000_000_000,
                                                          folder: "/Users/you/Projects/ml-experiments/node_modules"))
                    try? await Task.sleep(for: .milliseconds(150))
                }
                scan = .done(BarnDemo.scan())
            }
            return
        }
        scan = .scanning(DiskScanner.Progress(files: 0, bytes: 0, folder: "/"))
        // Without Full Disk Access, other apps' private folders are listed
        // but not entered: each look would make macOS ask for permission.
        let home = DiskScanner.dataVolume + FileManager.default.homeDirectoryForCurrentUser.path
        let skipping: Set<String> = fullDiskAccess ? [] : [home + "/Library/Containers", home + "/Library/Group Containers"]
        scanTask = Task {
            let result = await DiskScanner().scan(skipping: skipping) { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .scanning = self.scan else { return }
                    self.scan = .scanning(progress)
                }
            }
            guard !Task.isCancelled else { return }
            if let result { scan = .done(result) } else { scan = .idle }
            refreshSpace()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scan = .idle
    }

    /// Whether something found in Explore may go in the basket. Never the
    /// system, your main folders, or anything inside the places where apps
    /// and iCloud keep data you'd miss: removing there can delete it on all
    /// your devices or break an app.
    func canCollect(_ path: String) -> Bool {
        Self.basketRefusal(DiskScanner.displayPath(path)) == nil
            && !basket.contains { $0.path == path || path.hasPrefix($0.path + "/") }
    }

    /// Why something can't go in the basket, or nil if it can.
    nonisolated static func basketRefusal(_ shown: String, home: String = CleanupRule.realHome) -> String? {
        let never = ["/", "/System", "/Library", "/Applications", "/Users", "/private", "/usr", "/bin", "/sbin", "/opt",
                     "/Volumes", "/cores", home, home + "/Library", home + "/Documents", home + "/Desktop", home + "/Downloads",
                     home + "/Pictures", home + "/Movies", home + "/Music", home + "/Public", home + "/Applications"]
        if never.contains(shown) { return "a main folder" }
        let nothingInside = ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/opt/homebrew/Cellar",
                             home + "/Library/Mobile Documents", home + "/Library/CloudStorage",
                             home + "/Library/Application Support", home + "/Library/Mail", home + "/Library/Messages",
                             home + "/Library/Containers", home + "/Library/Group Containers", home + "/Library/Preferences",
                             home + "/Library/Keychains", home + "/Library/Accounts", home + "/Library/Calendars",
                             home + "/Library/Photos", home + "/Library/Safari", home + "/Library/Cookies",
                             home + "/.ssh", home + "/.gnupg", home + "/.config", home + "/.local", home + "/.claude"]
        if nothingInside.contains(where: { shown.hasPrefix($0 + "/") }) { return "where apps or iCloud keep data you'd miss" }
        if shown.hasPrefix("/Applications/"), (shown as NSString).pathComponents.count > 3 { return "inside an app" }
        // Only in iCloud, or kept in sync by it: removing it removes it everywhere.
        let values = try? URL(fileURLWithPath: shown).resourceValues(forKeys: [.isUbiquitousItemKey])
        if values?.isUbiquitousItem == true { return "kept in iCloud" }
        return nil
    }

    /// Puts something from Explore in the basket. Taking a folder takes
    /// what's inside it out of the basket, so nothing is counted twice.
    func collect(_ item: Item) {
        guard canCollect(item.path) else { return }
        var item = item
        var info = stat()
        if item.modified == nil, lstat(item.path, &info) == 0 {
            // Noted now, so a change before it's trashed is noticed.
            item = Item(path: item.path, name: item.name, size: item.size,
                        modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)))
        }
        basket.removeAll { $0.path.hasPrefix(item.path + "/") }
        basket.append(item)
    }

    /// Moves everything in the basket to the Trash, checking each again
    /// first: the scan may be old, and the path may hold something else now.
    func trashBasket() {
        guard cleaning == nil else { return }
        if DemoMode.isOn {
            report = Report(title: "Your basket", freed: 0, trashedSize: basket.map(\.size).reduce(0, +))
            basket = []
            return
        }
        var trashed: [(from: URL, to: URL)] = []
        var problems: [String] = []
        var size: Int64 = 0
        for item in basket {
            if let refusal = Self.basketRefusal(DiskScanner.displayPath(item.path)) {
                problems.append("\(item.name): kept, it's \(refusal)")
                continue
            }
            var info = stat()
            guard lstat(item.path, &info) == 0 else {
                problems.append("\(item.name): no longer there")
                continue
            }
            if let modified = item.modified,
               abs(Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)).timeIntervalSince(modified)) > 1 {
                problems.append("\(item.name): kept, it changed since the owl looked")
                continue
            }
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resulting)
                if let resulting { trashed.append((URL(fileURLWithPath: item.path), resulting as URL)) }
                size += item.size
                CleanupRunner.log("trashed \(item.path) from Explore")
            } catch {
                problems.append("\(item.name): \(error.localizedDescription)")
            }
        }
        basket = []
        show(Report(title: "Your basket", freed: 0, trashed: trashed, trashedSize: size, problems: problems))
        refreshSpace()
        measureAgain(CleanupRule.trash)
    }
}

extension CleanupRule {
    static var trash: CleanupRule { all.first { $0.id == "trash" }! }
}

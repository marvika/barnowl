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
    }

    enum ScanState {
        case idle
        case scanning(DiskScanner.Progress)
        case done(DiskScan)
    }

    private(set) var space = DiskSpace.current()
    private(set) var fullDiskAccess = FullDiskAccess.isGranted
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
        space = DiskSpace.current()
        fullDiskAccess = FullDiskAccess.isGranted
    }

    /// Measures every rule that applies on this Mac.
    func measure() {
        guard measureTask == nil else { return }
        refreshSpace()
        isMeasuring = true
        measureTask = Task {
            var found: [Suggestion] = []
            for rule in CleanupRule.all {
                if let suggestion = await Self.measure(rule, fullDiskAccess: fullDiskAccess) {
                    found.append(suggestion)
                    // Show them as they come in.
                    suggestions = Self.ordered(found)
                }
            }
            suggestions = Self.ordered(found)
            isMeasuring = false
            lastMeasured = Date()
            measureTask = nil
        }
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
            suggestion.size = await unavailableSimulatorsSize()
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

    /// The things inside a rule's folders, biggest first.
    nonisolated private static func items(for rule: CleanupRule) async -> [Item] {
        var items: [Item] = []
        let oldest = rule.olderThanDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        for folder in rule.expandedPaths where FileManager.default.fileExists(atPath: folder) {
            guard let scan = await DiskScanner().scan(root: folder, workers: 4, progress: { _ in }) else { continue }
            for child in scan.children(of: 0) {
                let node = scan.nodes[Int(child)]
                let path = scan.path(of: child)
                guard !rule.keep.contains(node.name), !node.name.hasPrefix(".") else { continue }
                if let extensions = rule.extensions,
                   !extensions.contains((node.name as NSString).pathExtension.lowercased()) { continue }
                let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
                if let oldest, let modified, modified > oldest { continue }
                guard node.reclaimable >= 100_000 else { continue }
                items.append(Item(path: path, name: node.name, size: node.reclaimable, modified: modified))
            }
            // Loose files folded into the folder itself can't be picked one by one; the rest can.
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Simulators whose runtime is gone, from simctl's own list.
    nonisolated private static func unavailableSimulatorsSize() async -> Int64 {
        let (status, output) = await CleanupRunner.shell("xcrun simctl list devices unavailable -j")
        guard status == 0, let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return 0 }
        let root = ("~/Library/Developer/CoreSimulator/Devices" as NSString).expandingTildeInPath
        var total: Int64 = 0
        for udid in devices.values.flatMap({ $0 }).compactMap({ $0["udid"] as? String }) {
            if let scan = await DiskScanner().scan(root: root + "/" + udid, workers: 2, progress: { _ in }) {
                total += scan.total.reclaimable
            }
        }
        return total
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
        cleaning = suggestion.id
        let before = DiskSpace.current()?.free ?? 0
        let outcome = await CleanupRunner.run(suggestion.rule, items: items)
        refreshSpace()
        let trashedSize = suggestion.items.filter { picked in outcome.trashed.contains { $0.from.path == picked.path } }
            .map(\.size).reduce(0, +)
        report = Report(title: suggestion.rule.title, freed: max(0, (space?.free ?? before) - before),
                        trashed: outcome.trashed, trashedSize: trashedSize,
                        problems: outcome.skipped.map { "\(($0.0 as NSString).lastPathComponent): \($0.1)" })
        cleaning = nil
        measureAgain(suggestion.rule)
    }

    /// Every safe suggestion, one after the other.
    func cleanAllSafe() async {
        guard cleaning == nil else { return }
        let safe = suggestions.filter { $0.rule.safety == .safe && $0.blockedBy == nil }
        guard !safe.isEmpty else { return }
        cleaning = "all"
        let before = DiskSpace.current()?.free ?? 0
        var problems: [String] = []
        for suggestion in safe {
            let outcome = await CleanupRunner.run(suggestion.rule, items: [])
            problems += outcome.skipped.map { "\(suggestion.rule.title): \($0.1)" }
        }
        refreshSpace()
        report = Report(title: "Everything safe", freed: max(0, (space?.free ?? before) - before), problems: problems)
        cleaning = nil
        measureTask?.cancel()
        measureTask = nil
        measure()
    }

    /// Puts back what the last clean-up moved to the Trash.
    func undoLast() {
        guard let trashed = report?.trashed, !trashed.isEmpty else { return }
        _ = CleanupRunner.undo(trashed)
        report = nil
        refreshSpace()
        measureTask?.cancel()
        measureTask = nil
        measure()
    }

    func dismissReport() { report = nil }

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

    /// Whether something found in Explore may go in the basket: never your
    /// home folder, Library, the system or whole app folders.
    func canCollect(_ path: String) -> Bool {
        let shown = DiskScanner.displayPath(path)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let never = ["/", "/System", "/Library", "/Applications", "/Users", "/private", "/usr", "/bin", "/sbin", "/opt",
                     "/Volumes", home, home + "/Library", home + "/Documents", home + "/Desktop", home + "/Downloads",
                     home + "/Pictures", home + "/Movies", home + "/Music", home + "/Library/Mobile Documents"]
        if never.contains(shown) { return false }
        for root in ["/System/", "/usr/", "/bin/", "/sbin/", "/private/var/db/", home + "/Library/Keychains/"]
            where shown.hasPrefix(root) { return false }
        return !basket.contains { $0.path == path }
    }

    /// Moves everything in the basket to the Trash.
    func trashBasket() {
        var trashed: [(from: URL, to: URL)] = []
        var problems: [String] = []
        let size = basket.map(\.size).reduce(0, +)
        for item in basket {
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resulting)
                if let resulting { trashed.append((URL(fileURLWithPath: item.path), resulting as URL)) }
                CleanupRunner.log("trashed \(item.path) from Explore")
            } catch {
                problems.append("\(item.name): \(error.localizedDescription)")
            }
        }
        basket = []
        report = Report(title: "Your basket", freed: 0, trashed: trashed, trashedSize: size, problems: problems)
        refreshSpace()
    }
}

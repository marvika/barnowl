import AppKit
import ApplicationServices
import Observation

/// Keeps a live list of every other app's menu bar item: Accessibility says
/// which app owns what, and the window list says where each item really is.
/// A full read takes up to a second, so it runs off the main thread and the
/// panels show the last list until it finishes.
///
/// macOS 27 has no item windows: there the list is what Accessibility says,
/// macOS's own icons included, and an item's section comes from the saved
/// layout (`sectionOf`) rather than from where it sits.
@MainActor
@Observable
final class ItemScanner {
    private(set) var items: [MenuBarItem] = []
    private(set) var lastScan: Date?

    @ObservationIgnored private let statusItems: StatusItems
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanRequested = false
    /// Scans in a row that matched suspiciously few items.
    @ObservationIgnored private var thinScans = 0
    @ObservationIgnored private var appsObservation: NSKeyValueObservation?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var publishedWindowIDs: Set<CGWindowID> = []
    /// Called after each full scan.
    @ObservationIgnored var onScan: (() -> Void)?
    /// Frames of Barn Owl's own windows (dividers, cup, group icons), so they're
    /// never mistaken for another app's icon.
    @ObservationIgnored var ownWindowFrames: () -> [CGRect] = { [] }
    /// macOS 27: the section the layout has an item in.
    @ObservationIgnored var sectionOf: (MenuBarItem) -> MenuBarSection = { _ in .visible }
    /// macOS 27: how many icons were in view at the last look.
    @ObservationIgnored private var visibleCount = 0

    init(statusItems: StatusItems) {
        self.statusItems = statusItems
    }

    /// Demo mode: a made-up list that's never rescanned.
    func loadDemo(_ demoItems: [MenuBarItem]) {
        items = demoItems
        lastScan = Date()
    }

    func start() {
        guard !DemoMode.isOn else { return }
        // KVO rather than launch notifications: macOS doesn't post those for
        // LSUIElement apps, and most menu bar apps are one.
        // Helper processes (browser renderers, test hosts, simulators' parts)
        // come and go all the time but can't own an icon, so only apps that
        // can count, and a burst of launches makes one scan, not one each.
        owners = Self.possibleOwners(NSWorkspace.shared.runningApplications)
        appsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.appsChanged() }
        }
        // Apps also add and remove icons without launching or quitting (an
        // icon that blinks for unread messages is re-added each time). A cheap
        // window-list check notices that.
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                if MenuBarPlatform.hidesByApp {
                    // No windows to count: ask what's in view instead.
                    let count = await Task.detached { AgentBar.iconsInView().count }.value
                    if count != self.visibleCount {
                        self.visibleCount = count
                        self.refresh()
                    }
                    continue
                }
                let windows = Set(Self.statusWindows().map(\.windowID))
                if windows != self.publishedWindowIDs { self.refresh() }
            }
        }
        refresh()
    }

    @ObservationIgnored private var owners: Set<pid_t> = []
    @ObservationIgnored private var appsTask: Task<Void, Never>?
    @ObservationIgnored private var firstPendingChange: Date?

    /// Apps that can have a menu bar icon: not background-only helpers.
    nonisolated static func possibleOwners(_ apps: [NSRunningApplication]) -> Set<pid_t> {
        Set(apps.filter { $0.activationPolicy != .prohibited }.map(\.processIdentifier))
    }

    /// Waits for launches and quits to settle for 1.5 seconds, but never
    /// longer than 10 seconds in all, then scans once.
    private func appsChanged() {
        let now = Self.possibleOwners(NSWorkspace.shared.runningApplications)
        guard now != owners else { return }
        owners = now
        let first = firstPendingChange ?? Date()
        firstPendingChange = first
        appsTask?.cancel()
        let wait = Self.settleDelay(sinceFirstChange: Date().timeIntervalSince(first))
        appsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.firstPendingChange = nil
            self.refresh()
        }
    }

    nonisolated static func settleDelay(sinceFirstChange elapsed: TimeInterval, quiet: TimeInterval = 1.5,
                                        longest: TimeInterval = 10) -> TimeInterval {
        max(0, min(quiet, longest - elapsed))
    }

    /// Starts a scan, or queues one if a scan is already running.
    func refresh() {
        guard !DemoMode.isOn else { return }
        guard AccessibilityInventory.isTrusted else { return }
        if scanTask != nil {
            rescanRequested = true
            return
        }
        scanTask = Task { [weak self] in
            await self?.scan()
            guard let self else { return }
            self.scanTask = nil
            if self.rescanRequested {
                self.rescanRequested = false
                self.refresh()
            }
        }
    }

    /// Waits for a scan that's running (or starts one) and returns the result.
    func freshItems() async -> [MenuBarItem] {
        refresh()
        await scanTask?.value
        return items
    }

    /// Updates frames and sections from the window list only. Cheap, so it can
    /// run right after the dividers move. On macOS 27 the sections are
    /// brought up to date at once, and the frames by a new scan.
    func updateFrames() {
        guard !DemoMode.isOn else { return }
        guard !MenuBarPlatform.hidesByApp else {
            reclassify()
            refresh()
            return
        }
        let windows = Dictionary(Self.statusWindows().map { ($0.windowID, $0.frame) }, uniquingKeysWith: { a, _ in a })
        items = classify(items.map { item in
            var item = item
            if let frame = windows[item.windowID] { item.frame = frame }
            return item
        }).sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Reads every item's section again, after the layout changed.
    func reclassify() {
        guard !DemoMode.isOn else { return }
        items = classify(items)
    }

    /// The item's current frame according to Accessibility.
    nonisolated static func currentFrame(of element: AXElement) -> CGRect? {
        AccessibilityInventory.frame(of: element.raw)
    }

    private func scan() async {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .filter { $0.bundleURL?.pathExtension == "app" }
            .map { AppRef(pid: $0.processIdentifier, bundle: $0.bundleIdentifier, name: $0.localizedName ?? "App") }
        let entries = await Task.detached(priority: .userInitiated) {
            apps.flatMap(AccessibilityInventory.entries(for:))
        }.value
        if MenuBarPlatform.hidesByApp {
            await publish(Self.itemsWithoutWindows(entries), windows: [])
            return
        }
        // Read the windows after Accessibility, so the frames are the newest.
        // Barn Owl's own windows are left out: off screen, a divider can sit
        // where Accessibility puts another app's icon.
        let own = ownWindowFrames()
        let windows = Self.statusWindows().filter { window in
            !(window.name?.hasPrefix("BarnOwl") ?? false)
                && !own.contains { abs($0.minX - window.frame.minX) < 1 && abs($0.width - window.frame.width) < 1 }
        }
        let matched = ItemMatcher.match(windows: windows, entries: entries, frame: \.frame)
        let scanned = matched.map { window, entry in
            MenuBarItem(windowID: window.windowID, frame: window.frame, pid: entry.pid,
                        bundleIdentifier: entry.bundleIdentifier, appName: entry.appName, title: entry.title,
                        element: entry.element, windowName: window.name)
        }
        // Keys are numbered right to left, the order macOS adds items in, so
        // they don't shift when an item moves between sections.
        await publish(ItemKey.assign(scanned.sorted { $0.frame.minX > $1.frame.minX }), windows: windows)
    }

    /// macOS 27: an item for each Accessibility entry. Its ID is made from its
    /// key, as there's no window to take one from.
    nonisolated static func itemsWithoutWindows(_ entries: [AXMenuBarEntry]) -> [MenuBarItem] {
        let items = entries.map { entry in
            MenuBarItem(windowID: 0, frame: entry.frame, pid: entry.pid,
                        bundleIdentifier: entry.bundleIdentifier, appName: entry.appName, title: entry.title,
                        element: entry.element, windowName: entry.agentName)
        }
        return ItemKey.assign(items.sorted { $0.frame.minX > $1.frame.minX }).map { item in
            var item = item
            item.windowID = ItemKey.stableID(for: item.key)
            return item
        }
    }

    /// Takes a scan's items (already keyed) as the new list.
    private func publish(_ scanned: [MenuBarItem], windows: [StatusWindow]) async {
        // While the bar slides (a collapse, a move) Accessibility and the window
        // list can disagree and few items match. Keep the last list and look again.
        // After three tries it's real (an app with many icons quit), not a slide.
        if items.count >= 4, scanned.count < items.count / 2, thinScans < 3 {
            thinScans += 1
            Log.menuBar.info("Scan matched only \(scanned.count) of \(self.items.count) items; retrying")
            rescanRequested = true
            try? await Task.sleep(for: .milliseconds(500))
            return
        }
        thinScans = 0
        items = classify(scanned).sorted { $0.frame.minX < $1.frame.minX }
        publishedWindowIDs = Set(windows.map(\.windowID))
        lastScan = Date()
        onScan?()
        Log.menuBar.info("Scanned \(self.items.count) menu bar items from \(windows.count) windows")
    }

    private func classify(_ items: [MenuBarItem]) -> [MenuBarItem] {
        if MenuBarPlatform.hidesByApp {
            // macOS keeps what doesn't fit behind its own overflow button, so
            // nothing ends up behind the notch.
            return items.map { item in
                var item = item
                item.section = sectionOf(item)
                item.isBehindNotch = false
                return item
            }
        }
        // The dividers' real positions, even off screen: while collapsed the
        // always-hidden divider is entirely past the left edge.
        let separatorMinX = StatusItems.layoutFrame(of: statusItems.separator)?.minX ?? -.infinity
        let alwaysHiddenMinX = Preferences.alwaysHiddenEnabled
            ? StatusItems.layoutFrame(of: statusItems.alwaysHidden)?.minX : nil
        let notch = NotchGeometry.of(NSScreen.screens.first)
        return items.map { item in
            var item = item
            item.section = SectionClassifier.section(midX: item.frame.midX, separatorMinX: separatorMinX,
                                                     alwaysHiddenMinX: alwaysHiddenMinX)
            item.isBehindNotch = item.section == .visible && (notch?.covers(item.frame) ?? false)
            return item
        }
    }

    /// Status-level windows on the menu bar (layer 25), in top-left coordinates.
    /// Barn Owl's collapsed divider is far wider than any item; it's left out
    /// unless `includeWide`.
    nonisolated static func statusWindows(includeWide: Bool = false) -> [StatusWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == statusLevel,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 0, includeWide || frame.width < 600 else { return nil }
            return StatusWindow(windowID: id, frame: frame, name: info[kCGWindowName as String] as? String)
        }
    }
}

struct AppRef: Sendable {
    let pid: pid_t
    let bundle: String?
    let name: String
}

import AppKit
import ApplicationServices
import Observation

/// Keeps a live list of every other app's menu bar item: Accessibility says
/// which app owns what, and the window list says where each item really is.
/// A full read takes up to a second, so it runs off the main thread and the
/// panels show the last list until it finishes.
@MainActor
@Observable
final class ItemScanner {
    private(set) var items: [MenuBarItem] = []
    private(set) var lastScan: Date?

    @ObservationIgnored private let statusItems: StatusItems
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored private var appsObservation: NSKeyValueObservation?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var publishedWindowIDs: Set<CGWindowID> = []
    /// Called after each full scan.
    @ObservationIgnored var onScan: (() -> Void)?

    init(statusItems: StatusItems) {
        self.statusItems = statusItems
    }

    func start() {
        // KVO rather than launch notifications: macOS doesn't post those for
        // LSUIElement apps, and most menu bar apps are one.
        appsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                self?.refresh()
            }
        }
        // Apps also add and remove icons without launching or quitting (an
        // icon that blinks for unread messages is re-added each time). A cheap
        // window-list check notices that.
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                let windows = Set(Self.statusWindows().map(\.windowID))
                if windows != self.publishedWindowIDs { self.refresh() }
            }
        }
        refresh()
    }

    /// Starts a scan, or queues one if a scan is already running.
    func refresh() {
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
    /// run right after the dividers move.
    func updateFrames() {
        let windows = Dictionary(Self.statusWindows().map { ($0.windowID, $0.frame) }, uniquingKeysWith: { a, _ in a })
        items = classify(items.map { item in
            var item = item
            if let frame = windows[item.windowID] { item.frame = frame }
            return item
        }).sorted { $0.frame.minX < $1.frame.minX }
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
        // Read the windows after Accessibility, so the frames are the newest.
        let windows = Self.statusWindows()
        let matched = ItemMatcher.match(windows: windows, entries: entries, frame: \.frame)
        let scanned = matched.map { window, entry in
            MenuBarItem(windowID: window.windowID, frame: window.frame, pid: entry.pid,
                        bundleIdentifier: entry.bundleIdentifier, appName: entry.appName, title: entry.title,
                        element: entry.element, windowName: window.name)
        }
        // Keys are numbered right to left, the order macOS adds items in, so
        // they don't shift when an item moves between sections.
        // While the bar slides (a collapse, a move) Accessibility and the window
        // list can disagree and few items match. Keep the last list and look again.
        if items.count >= 4, scanned.count < items.count / 2 {
            Log.menuBar.info("Scan matched only \(scanned.count) of \(self.items.count) items; retrying")
            rescanRequested = true
            try? await Task.sleep(for: .milliseconds(500))
            return
        }
        let keyed = ItemKey.assign(scanned.sorted { $0.frame.minX > $1.frame.minX })
        items = classify(keyed).sorted { $0.frame.minX < $1.frame.minX }
        publishedWindowIDs = Set(windows.map(\.windowID))
        lastScan = Date()
        onScan?()
        Log.menuBar.info("Scanned \(self.items.count) menu bar items from \(windows.count) windows")
    }

    private func classify(_ items: [MenuBarItem]) -> [MenuBarItem] {
        let separatorMinX = StatusItems.frame(of: statusItems.separator)?.minX ?? -.infinity
        let alwaysHiddenMinX = Preferences.alwaysHiddenEnabled ? StatusItems.frame(of: statusItems.alwaysHidden)?.minX : nil
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
    /// Barkeep's collapsed divider is far wider than any item; it's left out
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

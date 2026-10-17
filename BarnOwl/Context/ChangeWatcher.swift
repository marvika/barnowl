import AppKit
import Network
import Observation

/// Shows a hidden icon for a while when it changes, for example when a VPN
/// drops or a sync fails.
///
/// macOS can't photograph hidden icons, so changes are detected from what can
/// be read: the icon's status text, its width, the app re-adding it, and,
/// right after the network changes or every few minutes if the user opts in,
/// a quick look (the icon slides into view for a moment to be photographed).
@MainActor
@Observable
final class ChangeWatcher {
    private(set) var watchedKeys: Set<String>
    /// Icons showing because they changed, and when they hide again.
    private(set) var surfaced: [String: Date] = [:]
    /// Called with an icon's new frame when it's brought into view.
    @ObservationIgnored var onSurface: ((CGRect) -> Void)?

    @ObservationIgnored private let scanner: ItemScanner
    @ObservationIgnored private let layout: LayoutController
    @ObservationIgnored private let mover: ItemMover
    @ObservationIgnored private let images: ItemImageCache
    @ObservationIgnored private let statusItems: StatusItems
    @ObservationIgnored private var signatures: [String: ItemSignature] = [:]
    @ObservationIgnored private var pictures: [String: PictureSignature] = [:]
    @ObservationIgnored private var lastLook = Date()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var lookRequested = false
    @ObservationIgnored private let defaultsKey = "watchedKeys"
    /// While presenting, nothing is surfaced.
    @ObservationIgnored var isPaused: () -> Bool = { false }

    init(scanner: ItemScanner, layout: LayoutController, mover: ItemMover, images: ItemImageCache,
         statusItems: StatusItems) {
        self.scanner = scanner
        self.layout = layout
        self.mover = mover
        self.images = images
        self.statusItems = statusItems
        watchedKeys = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    func isWatching(_ key: String) -> Bool { watchedKeys.contains(key) }

    func setWatching(_ key: String, _ watching: Bool) {
        if watching { watchedKeys.insert(key) } else { watchedKeys.remove(key) }
        UserDefaults.standard.set(Array(watchedKeys), forKey: defaultsKey)
        signatures[key] = nil
        pictures[key] = nil
    }

    func start() {
        // A VPN connecting or dropping changes the network path: look at the
        // watched icons right away rather than at the next periodic look.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // Only what matters for "did the VPN or connection change": the
            // status and which interfaces carry traffic. VPN agents nudge
            // their tunnels often without anything changing.
            let summary = "\(path.status)|" + path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            Task { @MainActor in self?.networkChanged(summary) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.tick()
            }
        }
    }

    @ObservationIgnored private var lastPath: String?
    @ObservationIgnored private var lastNetworkLook = Date.distantPast

    /// The first report is the current state, not a change. After that, a
    /// real change asks for a look, at most once a minute.
    private func networkChanged(_ summary: String) {
        defer { lastPath = summary }
        guard let lastPath, lastPath != summary, Date().timeIntervalSince(lastNetworkLook) > 60 else { return }
        lastNetworkLook = Date()
        Log.menuBar.info("Network changed; looking at watched icons")
        lookRequested = true
    }

    private func tick() async {
        guard !DemoMode.isOn else { return }
        guard !isPaused() else { return }
        await hideExpired()
        guard !watchedKeys.isEmpty, !layout.isBusy, !mover.isMoving else { return }
        let frames = ItemMover.frames()
        let watched = scanner.items.filter { watchedKeys.contains($0.key) }

        // Cheap signals, every few seconds.
        for item in watched {
            let signature = ItemSignature(text: AccessibilityInventory.statusText(of: item.element.raw),
                                          width: (frames[item.windowID] ?? item.frame).width,
                                          windowID: item.windowID)
            defer { signatures[item.key] = signature }
            guard let previous = signatures[item.key], previous.differs(from: signature) else { continue }
            Log.menuBar.info("\(item.key) changed (status text, size or window)")
            await surface(item)
        }

        // A look at the pictures: after a network change, or every few
        // minutes if the user asked for that.
        let interval = Preferences.changeLookInterval
        let due = interval > 0 && Date().timeIntervalSince(lastLook) > TimeInterval(interval * 60)
        if (lookRequested || due), ItemImageCache.hasPermission {
            lookRequested = false
            lastLook = Date()
            await lookAtPictures(of: watched)
        }
    }

    /// Photographs each watched icon: in place if it's showing, otherwise by
    /// sliding it into view for a moment. Surfaces the ones that look different.
    private func lookAtPictures(of items: [MenuBarItem]) async {
        guard let divider = StatusItems.windowID(of: statusItems.separator) else { return }
        for item in items where surfaced[item.key] == nil {
            // The first look compares against the last saved picture.
            if pictures[item.key] == nil, let saved = images.image(for: item) {
                pictures[item.key] = PictureSignature(saved)
            }
            let visible = item.section == .visible && !item.isBehindNotch
            if !visible {
                guard await mover.move(item.windowID, to: .rightOf(divider)) else { continue }
            }
            scanner.updateFrames()
            if let current = scanner.items.first(where: { $0.windowID == item.windowID }) {
                await images.capture([current], pruning: false)
            }
            let picture = images.image(for: item).flatMap(PictureSignature.init)
            let changed = picture.map { new in pictures[item.key].map { new.differs(from: $0) } ?? false } ?? false
            if let picture { pictures[item.key] = picture }
            if changed {
                Log.menuBar.info("\(item.key) looks different")
                surfaced[item.key] = Date().addingTimeInterval(Preferences.changeShowDuration)
                announce(item)
            } else if !visible {
                await layout.returnToRow(item.key)
            }
        }
        scanner.updateFrames()
    }

    /// Brings the icon next to the arrow for a while.
    private func surface(_ item: MenuBarItem) async {
        let until = Date().addingTimeInterval(Preferences.changeShowDuration)
        if surfaced[item.key] != nil {
            surfaced[item.key] = until
            return
        }
        guard item.section != .visible || item.isBehindNotch, item.isMovable,
              let divider = StatusItems.windowID(of: statusItems.separator) else { return }
        surfaced[item.key] = until
        await mover.move(item.windowID, to: .rightOf(divider))
        scanner.updateFrames()
        announce(item)
    }

    /// Tells the owl where the icon now is, so it can glance at it.
    private func announce(_ item: MenuBarItem) {
        if let frame = scanner.items.first(where: { $0.windowID == item.windowID })?.frame {
            onSurface?(frame)
        }
    }

    private func hideExpired() async {
        let now = Date()
        for (key, until) in surfaced where until <= now {
            // Leave it while its menu is open.
            if let item = scanner.items.first(where: { $0.key == key }), ItemOpener.hasOpenMenu(pid: item.pid) {
                continue
            }
            surfaced[key] = nil
            await layout.returnToRow(key)
        }
    }
}

/// What can be read about an icon without seeing it.
struct ItemSignature: Equatable, Sendable {
    var text: String
    var width: CGFloat
    var windowID: CGWindowID

    /// A width change of a point or less is just animation or rounding.
    func differs(from other: ItemSignature) -> Bool {
        text != other.text || abs(width - other.width) > 1 || windowID != other.windowID
    }
}

/// A tiny grayscale thumbnail, to tell whether an icon's picture changed
/// without being fooled by antialiasing.
struct PictureSignature: Equatable, Sendable {
    static let side = 12
    let pixels: [UInt8]

    init(pixels: [UInt8]) {
        self.pixels = pixels
    }

    @MainActor
    init?(_ image: NSImage) {
        let side = Self.side
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        pixels = Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: side * side),
                                           count: side * side))
    }

    /// Different when the average pixel moved by more than a small amount.
    func differs(from other: PictureSignature) -> Bool {
        guard pixels.count == other.pixels.count, !pixels.isEmpty else { return true }
        let total = zip(pixels, other.pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(pixels.count) > 6
    }
}

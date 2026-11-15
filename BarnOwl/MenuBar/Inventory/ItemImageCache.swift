import AppKit
import Observation
import ScreenCaptureKit

/// Pictures of menu bar items for the Perch and search.
///
/// macOS 26 can't capture a window that's off screen: ScreenCaptureKit refuses
/// (error -3811) and the old CGWindowList image calls return nothing. So
/// Barn Owl captures items while they're showing (at launch, and whenever the
/// hidden section is expanded) and keeps the pictures. One capture of the
/// menu bar strip, filtered to the item windows so the background is
/// transparent, is cropped into one image per item.
///
/// On macOS 27 the whole bar is one window of MenuBarAgent's. That window is
/// captured instead, and cropped to where each icon in view is.
@MainActor
@Observable
final class ItemImageCache {
    private(set) var images: [CGWindowID: NSImage] = [:]
    /// When Barn Owl last took pictures. Each capture briefly turns on macOS's
    /// screen-recording indicator, which presenter mode must not mistake for
    /// screen sharing.
    @ObservationIgnored private(set) var lastCapture = Date.distantPast
    /// Pictures from earlier runs, by item key; filled from disk on demand.
    @ObservationIgnored private var saved: [String: NSImage] = [:]

    /// ~/Library/Application Support/Barn Owl/Icons
    private static let folder: URL? = {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let folder = support.appending(path: "Barn Owl/Icons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            // The system prompt only appears once; after that, send people to the pane.
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    /// This run's capture, else the last one saved for the same icon.
    func image(for item: MenuBarItem) -> NSImage? {
        if DemoMode.isOn { return DemoMode.image(for: item) }
        if let image = images[item.windowID] { return image }
        if let image = saved[item.key] { return image }
        guard let url = Self.file(for: item.key), let image = NSImage(contentsOf: url) else { return nil }
        image.size = item.frame.size
        saved[item.key] = image
        return image
    }

    func hasFreshImage(for item: MenuBarItem) -> Bool { images[item.windowID] != nil }

    /// One file per icon and menu bar appearance (glyphs differ in light and dark).
    private static func file(for key: String) -> URL? {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return folder?.appending(path: String(safe) + (dark ? "-dark" : "-light") + ".png")
    }

    private func save(_ image: CGImage, key: String) {
        guard let url = Self.file(for: key),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Captures every item that's on screen now. Items still hidden keep
    /// their last picture. With `pruning`, `items` is the full list and
    /// pictures of windows not in it are dropped.
    func capture(_ items: [MenuBarItem], pruning: Bool = true) async {
        guard !DemoMode.isOn else { return }
        guard Self.hasPermission, let screen = NSScreen.screens.first else { return }
        lastCapture = Date()
        defer { lastCapture = Date() }
        var onScreen: [MenuBarItem] = []
        var captured: [CGWindowID: Piece] = [:]
        if MenuBarPlatform.hidesByApp {
            // Icons slide into place as the bar makes room, and say where
            // they'll end up before they get there. So the pictures are taken
            // until two in a row are the same: a picture cut from a sliding
            // icon would be kept for good.
            var last: [CGWindowID: Data] = [:]
            var steady = false
            for _ in 0..<6 where !steady {
                await LayoutController.waitForMenuBarToSettle()
                onScreen = await Self.inView(items)
                guard !onScreen.isEmpty, let pieces = await Self.capture(onScreen, screen: screen) else { return }
                let pixels = pieces.compactMapValues(\.cgImage.pixels)
                steady = !pixels.isEmpty && pixels == last
                captured = pieces
                last = pixels
                if !steady { try? await Task.sleep(for: .milliseconds(250)) }
            }
            guard steady else {
                Log.menuBar.info("The menu bar kept moving; no icon pictures taken this time")
                return
            }
        } else {
            // The clock's window runs a couple of points past the screen edge.
            onScreen = items.filter { $0.frame.minX >= screen.frame.minX && $0.frame.maxX <= screen.frame.maxX + 4 }
            guard !onScreen.isEmpty, let pieces = await Self.capture(onScreen, screen: screen) else { return }
            captured = pieces
        }
        // Drop pictures of windows that no longer exist.
        let live = Set(items.map(\.windowID))
        images = images.filter { !pruning || live.contains($0.key) }.merging(captured.mapValues(\.image)) { _, new in new }
        for item in onScreen {
            guard let piece = captured[item.windowID] else { continue }
            saved[item.key] = piece.image
            save(piece.cgImage, key: item.key)
        }
    }

    /// macOS 27: the items MenuBarAgent has in view, with the frames they have
    /// now. A hidden icon still reports the place it last had, so its own
    /// frame doesn't say it can be photographed.
    private nonisolated static func inView(_ items: [MenuBarItem]) async -> [MenuBarItem] {
        await Task.detached {
            let icons = AgentBar.iconsInView()
            return items.compactMap { item -> MenuBarItem? in
                guard let frame = AccessibilityInventory.frame(of: item.element.raw),
                      AgentBar.isShowing(pid: item.pid, frame: frame, among: icons) else { return nil }
                var item = item
                item.frame = frame
                return item
            }
        }.value
    }

    private struct Piece {
        let cgImage: CGImage
        let image: NSImage
    }

    private static func capture(_ items: [MenuBarItem], screen: NSScreen) async -> [CGWindowID: Piece]? {
        do {
            // MenuBarAgent's window says it's off screen, yet it's the one that draws the bar.
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: !MenuBarPlatform.hidesByApp)
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == screenNumber }) ?? content.displays.first
            else { return nil }
            let windows: [SCWindow]
            if MenuBarPlatform.hidesByApp {
                windows = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier == MenuBarPlatform.agentBundle
                        && $0.frame.height < 100 && $0.frame.intersects(display.frame)
                }
            } else {
                let ids = Set(items.map(\.windowID))
                windows = content.windows.filter { ids.contains($0.windowID) }
            }
            guard !windows.isEmpty else { return nil }

            let scale = screen.backingScaleFactor
            // Whole points: a strip 29.5 points tall comes back scaled to fit,
            // and every icon is then cut from a little beside where it is.
            let stripHeight = (items.map(\.frame.maxY).max() ?? 33).rounded(.up)
            let strip = CGRect(x: 0, y: 0, width: screen.frame.width, height: stripHeight)
            let config = SCStreamConfiguration()
            config.sourceRect = strip
            config.width = Int(strip.width * scale)
            config.height = Int(strip.height * scale)
            config.showsCursor = false
            config.backgroundColor = .clear
            config.captureResolution = .best
            let filter = SCContentFilter(display: display, including: windows)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            var result: [CGWindowID: Piece] = [:]
            for item in items {
                let crop = CGRect(x: (item.frame.minX - display.frame.minX) * scale, y: item.frame.minY * scale,
                                  width: item.frame.width * scale, height: item.frame.height * scale).integral
                    .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                guard let piece = image.cropping(to: crop), piece.hasVisiblePixels else { continue }
                result[item.windowID] = Piece(cgImage: piece, image: NSImage(cgImage: piece, size: item.frame.size))
            }
            return result
        } catch {
            Log.menuBar.error("Item capture failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private extension CGImage {
    /// The picture's pixels, drawn afresh (a crop shares its parent's buffer),
    /// for telling whether two pictures are the same.
    var pixels: Data? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(bytes: data, count: width * height * 4)
    }

    /// False for a fully transparent crop, e.g. an item that moved mid-capture.
    /// A crop shares its parent's pixel buffer, so it's redrawn on its own first.
    var hasVisiblePixels: Bool {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return true }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for pixel in 0..<(width * height) where bytes[pixel * 4 + 3] > 16 {
            return true
        }
        return false
    }
}

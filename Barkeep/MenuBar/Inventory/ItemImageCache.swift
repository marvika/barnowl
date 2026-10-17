import AppKit
import Observation
import ScreenCaptureKit

/// Pictures of menu bar items for the Barkeep Bar and search.
///
/// macOS 26 can't capture a window that's off screen: ScreenCaptureKit refuses
/// (error -3811) and the old CGWindowList image calls return nothing. So
/// Barkeep captures items while they're showing (at launch, and whenever the
/// hidden section is expanded) and keeps the pictures. One capture of the
/// menu bar strip, filtered to the item windows so the background is
/// transparent, is cropped into one image per item.
@MainActor
@Observable
final class ItemImageCache {
    private(set) var images: [CGWindowID: NSImage] = [:]
    /// When Barkeep last took pictures. Each capture briefly turns on macOS's
    /// screen-recording indicator, which presenter mode must not mistake for
    /// screen sharing.
    @ObservationIgnored private(set) var lastCapture = Date.distantPast
    /// Pictures from earlier runs, by item key; filled from disk on demand.
    @ObservationIgnored private var saved: [String: NSImage] = [:]

    /// ~/Library/Application Support/Barkeep/Icons
    private static let folder: URL? = {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let folder = support.appending(path: "Barkeep/Icons", directoryHint: .isDirectory)
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
        // The clock's window runs a couple of points past the screen edge.
        let onScreen = items.filter { $0.frame.minX >= screen.frame.minX && $0.frame.maxX <= screen.frame.maxX + 4 }
        guard !onScreen.isEmpty, let captured = await Self.capture(onScreen, screen: screen) else { return }
        // Drop pictures of windows that no longer exist.
        let live = Set(items.map(\.windowID))
        images = images.filter { !pruning || live.contains($0.key) }.merging(captured.mapValues(\.image)) { _, new in new }
        for item in onScreen {
            guard let piece = captured[item.windowID] else { continue }
            saved[item.key] = piece.image
            save(piece.cgImage, key: item.key)
        }
    }

    private struct Piece {
        let cgImage: CGImage
        let image: NSImage
    }

    private static func capture(_ items: [MenuBarItem], screen: NSScreen) async -> [CGWindowID: Piece]? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == screenNumber }) ?? content.displays.first
            else { return nil }
            let ids = Set(items.map(\.windowID))
            let windows = content.windows.filter { ids.contains($0.windowID) }
            guard !windows.isEmpty else { return nil }

            let scale = screen.backingScaleFactor
            let stripHeight = items.map(\.frame.maxY).max() ?? 33
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

import AppKit
import ScreenCaptureKit

/// One display, caught the moment a capture starts. Selecting happens over
/// this still picture, so menus and hover states in other apps stay put.
struct DisplaySnapshot {
    let displayID: CGDirectDisplayID
    /// The screen's frame in AppKit coordinates (origin bottom left).
    let frame: CGRect
    let scale: CGFloat
    let image: CGImage

    /// The pixels under a rect given in AppKit screen coordinates.
    func crop(_ rect: CGRect) -> CGImage? {
        let local = rect.intersection(frame).offsetBy(dx: -frame.minX, dy: -frame.minY)
        guard !local.isEmpty else { return nil }
        // Pixels run from the top down.
        let pixels = CGRect(x: local.minX * scale, y: (frame.height - local.maxY) * scale,
                            width: local.width * scale, height: local.height * scale).integral
        return image.cropping(to: pixels)
    }
}

/// What to leave out of the picture. Nothing on screen changes: the windows
/// are simply not drawn into the capture.
struct CaptureOptions {
    /// Other apps' menu bar icons, for a clean menu bar.
    var hiddenWindows: Set<CGWindowID> = []
    /// Leaves only the clock and Control Center in the menu bar: also the
    /// system's own icons and the dot that shows the screen is being captured.
    var cleanMenuBar = false
    var hidesDesktopIcons = false
    var showsPointer = false
}

/// Takes pictures of displays and windows with ScreenCaptureKit.
@MainActor
enum ScreenSnapshotter {
    /// Every display (or just `only`), without Barn Owl's own windows, except
    /// its desktop cover and pinned captures, which belong in the picture.
    static func snapshots(of only: CGDirectDisplayID? = nil, options: CaptureOptions) async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excluded = content.windows.filter { leftOut($0, options: options) }
        var result: [DisplaySnapshot] = []
        OwnCaptures.last = Date()
        defer { OwnCaptures.last = Date() }
        for display in content.displays where only == nil || display.displayID == only {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = options.showsPointer
            config.captureResolution = .best
            config.colorSpaceName = CGColorSpace.displayP3
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(DisplaySnapshot(displayID: display.displayID, frame: screen.frame, scale: scale, image: image))
        }
        return result
    }

    /// One window on its own, with its shadow on a clear background if asked.
    static func window(_ windowID: CGWindowID, shadow: Bool) async throws -> (CGImage, CGFloat)? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let info = SCShareableContent.info(for: filter)
        let scale = CGFloat(info.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(info.contentRect.width * scale)
        config.height = Int(info.contentRect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.displayP3
        config.ignoreShadowsSingleWindow = !shadow
        config.backgroundColor = .clear
        config.shouldBeOpaque = false
        OwnCaptures.last = Date()
        defer { OwnCaptures.last = Date() }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }

    private static func leftOut(_ window: SCWindow, options: CaptureOptions) -> Bool {
        if window.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier {
            return !(window.title == "BarnOwlDesktopCover" || window.title == CapturePin.windowTitle)
        }
        if options.hidesDesktopIcons, window.windowLayer == Int(CGWindowLevelForKey(.desktopIconWindow)),
           window.owningApplication?.bundleIdentifier == "com.apple.finder" {
            return true
        }
        if options.cleanMenuBar, window.windowLayer == Int(CGWindowLevelForKey(.statusWindow)),
           window.owningApplication?.bundleIdentifier == "com.apple.controlcenter",
           let title = window.title, !(title == "Clock" || title.hasPrefix("BentoBox")) {
            return true
        }
        return options.hiddenWindows.contains(window.windowID)
    }
}

/// A window you can capture on its own, under the pointer.
struct WindowTarget: Equatable {
    let windowID: CGWindowID
    /// In AppKit screen coordinates.
    let frame: CGRect
    let appName: String
}

enum WindowLocator {
    /// Ordinary windows on screen, frontmost first, without Barn Owl's own.
    static func onScreenWindows() -> [WindowTarget] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primary = NSScreen.screens.first else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != own,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                  width > 40, height > 40 else { return nil }
            // Window bounds are top-left based, from the top of the main screen.
            let frame = CGRect(x: x, y: primary.frame.maxY - y - height, width: width, height: height)
            return WindowTarget(windowID: id, frame: frame, appName: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    /// The frontmost window under a point.
    static func window(at point: CGPoint, in windows: [WindowTarget]) -> WindowTarget? {
        windows.first { $0.frame.contains(point) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

import AppKit
import ScreenCaptureKit

/// When Barn Owl itself last took a screen picture, so presenter mode doesn't
/// mistake the screen-recording indicator that lights up for a screen share.
@MainActor
enum OwnCaptures {
    static var last = Date.distantPast
    /// Barn Owl is recording the screen: the indicator stays on until it stops.
    static var isRecording = false
}

/// Hides desktop icons by covering them with a picture of the wallpaper: one
/// window per screen, just above the icons and below every other window.
/// Turning Finder's desktop off instead means restarting Finder, which closes
/// its windows and can shuffle the icons; this leaves Finder alone, so the
/// icons are exactly where they were when they come back.
@MainActor
@Observable
final class DesktopCover {
    static let shared = DesktopCover()

    private(set) var isShown = false
    @ObservationIgnored private var windows: [CGDirectDisplayID: NSWindow] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func show() {
        guard !isShown else { return }
        isShown = true
        rebuild()
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DesktopCover.shared.rebuild() }
            },
            // Each Space can have its own wallpaper.
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DesktopCover.shared.refreshPictures() }
            },
        ]
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers = []
        windows.values.forEach { $0.orderOut(nil); $0.close() }
        windows = [:]
    }

    private func rebuild() {
        windows.values.forEach { $0.orderOut(nil); $0.close() }
        windows = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            // A non-activating panel: clicking the covered desktop doesn't make
            // Barn Owl the active app and take the keyboard from yours. (It
            // still catches the click, so hidden icons can't be opened blind.)
            let window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            window.becomesKeyOnlyIfNeeded = true
            window.hidesOnDeactivate = false
            // Just above the desktop icons, far below ordinary windows.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.title = "BarnOwlDesktopCover"
            let options = NSWorkspace.shared.desktopImageOptions(for: screen)
            window.backgroundColor = options?[.fillColor] as? NSColor ?? .black
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.contentsGravity = .resizeAspectFill
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            window.orderFront(nil)
            windows[id] = window
        }
        refreshPictures()
    }

    private func refreshPictures() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let window = windows[id] else { continue }
            // The wallpaper file first, so there's never a blank moment.
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) {
                window.contentView?.layer?.contents = image
            }
            Task { await capture(screen: screen, display: id) }
        }
    }

    /// The wallpaper as it looks right now, including dynamic wallpapers that
    /// change through the day. Needs Screen Recording; without it, the
    /// wallpaper file stays.
    private func capture(screen: NSScreen, display: CGDirectDisplayID) async {
        guard CGPreflightScreenCaptureAccess() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
            guard let scDisplay = content.displays.first(where: { $0.displayID == display }),
                  let wallpaper = content.windows.first(where: {
                      $0.windowLayer == desktopLevel && $0.frame.intersects(scDisplay.frame)
                  })
            else { return }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            OwnCaptures.last = Date()
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: wallpaper), configuration: config)
            OwnCaptures.last = Date()
            guard isShown, let window = windows[display] else { return }
            window.contentView?.layer?.contents = image
        } catch {
            Log.app.error("Wallpaper capture failed: \(error.localizedDescription)")
        }
    }
}

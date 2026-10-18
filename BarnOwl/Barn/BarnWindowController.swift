import AppKit
import SwiftUI

/// The Barn's window. It's kept when closed and the owls in it stop while
/// it's hidden. The map of the disk is let go a couple of minutes after you
/// close it (it can take a hundred megabytes), unless the basket holds
/// something; open it again soon and it's still there.
@MainActor
final class BarnWindowController {
    private let barn: BarnModel
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var forgetTask: Task<Void, Never>?

    /// How long a closed Barn keeps its map of the disk.
    static let keepScanFor: Duration = .seconds(120)

    init(barn: BarnModel) {
        self.barn = barn
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: BarnView(barn: barn).tint(Brand.accent)))
            window.title = "The Barn"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 920, height: 700))
            window.setFrameAutosaveName("BarnOwlBarn")
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closed() }
            }
        } else {
            // Back again: fresh numbers, and a fresh look if the last was a while ago.
            barn.refreshSpace()
            if (barn.lastMeasured.map { Date().timeIntervalSince($0) > 300 } ?? true) { barn.measure() }
        }
        forgetTask?.cancel()
        forgetTask = nil
        OpenPanel.shared.closeAll()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func closed() {
        forgetTask?.cancel()
        forgetTask = Task { [weak self] in
            try? await Task.sleep(for: Self.keepScanFor)
            guard !Task.isCancelled, let self else { return }
            self.barn.forgetScan()
            self.forgetTask = nil
        }
    }
}

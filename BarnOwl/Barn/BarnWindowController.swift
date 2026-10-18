import AppKit
import SwiftUI

/// The Barn's window. It's kept when closed, so the last scan is still there
/// next time; the owls in it stop while it's hidden.
@MainActor
final class BarnWindowController {
    private let barn: BarnModel
    private var window: NSWindow?

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
        } else {
            // Back again: fresh numbers, and a fresh look if the last was a while ago.
            barn.refreshSpace()
            if (barn.lastMeasured.map { Date().timeIntervalSince($0) > 300 } ?? true) { barn.measure() }
        }
        OpenPanel.shared.closeAll()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

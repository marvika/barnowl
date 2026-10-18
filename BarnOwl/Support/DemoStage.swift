import AppKit
import SwiftUI

/// Demo mode only: a dusk sky over the whole desktop, under the menu bar and
/// Barn Owl's panels, so recordings and screenshots show nothing of yours.
/// Toggled with barnowl://stage.
@MainActor
enum DemoStage {
    private static var window: NSWindow?

    static func toggle() {
        guard DemoMode.isOn else { return }
        if let window {
            window.orderOut(nil)
            self.window = nil
            return
        }
        guard let screen = NSScreen.screens.first else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: DuskSky(showsMoon: false))
        // Above other apps' windows, below the menu bar and the panels.
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
    }
}

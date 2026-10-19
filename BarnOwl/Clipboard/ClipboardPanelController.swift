import AppKit
import SwiftUI

@MainActor
final class ClipboardPanelController {
    private let clipboard: ClipboardHistory
    private var panel: FloatingPanel?
    private let outsideClicks = OutsideClickMonitor()
    /// The app to paste into: whatever was in front before the panel opened.
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { panel?.isVisible ?? false }

    /// The last other app that was in front, for when the panel opens from
    /// Barn Owl's own search or Settings.
    private var lastOtherApp: NSRunningApplication?

    init(clipboard: ClipboardHistory) {
        self.clipboard = clipboard
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, app != .current { self?.lastOtherApp = app }
            }
        }
    }

    func toggle() {
        isOpen ? close() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? lastOtherApp : front
        let view = ClipboardView(clipboard: clipboard, paste: { [weak self] entry in
            guard let self else { return }
            self.close()
            self.clipboard.paste(entry, into: self.previousApp)
        }, close: { [weak self] in self?.close() })
        let panel = FloatingPanel(rootView: view)
        panel.onCancel = { [weak self] in self?.close() }
        self.panel?.dismiss()
        self.panel = panel
        NSApp.activate()
        panel.layoutIfNeeded()
        let top = (NSScreen.main?.visibleFrame.maxY ?? 800) - (NSScreen.main?.visibleFrame.height ?? 800) * 0.18
        let place = { (panel: FloatingPanel) in
            guard let screen = NSScreen.main else { return }
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: top - panel.frame.height))
        }
        panel.onResize = place
        place(panel)
        panel.makeKeyAndOrderFront(nil)
        outsideClicks.start { [weak self] in self?.close() }
        OpenPanel.shared.opening(self) { [weak self] in self?.close() }
    }

    func close() {
        outsideClicks.stop()
        OpenPanel.shared.closed(self)
        let wasOpen = panel != nil
        panel?.dismiss()
        panel = nil
        if wasOpen { FocusReturn.afterPanelCloses(to: previousApp) }
    }
}

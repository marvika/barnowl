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

    init(clipboard: ClipboardHistory) {
        self.clipboard = clipboard
    }

    func toggle() {
        isOpen ? close() : show()
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        let view = ClipboardView(clipboard: clipboard, paste: { [weak self] entry in
            guard let self else { return }
            self.close()
            self.clipboard.paste(entry, into: self.previousApp)
        }, close: { [weak self] in self?.close() })
        let panel = FloatingPanel(rootView: view)
        panel.onCancel = { [weak self] in self?.close() }
        self.panel?.orderOut(nil)
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
        panel?.orderOut(nil)
        panel = nil
    }
}

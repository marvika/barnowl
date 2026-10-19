import AppKit
import SwiftUI

@MainActor
final class SearchPanelController {
    private let model: AppModel
    private var panel: FloatingPanel?
    private let outsideClicks = OutsideClickMonitor()
    private var resizeObserver: NSObjectProtocol?
    private var top: CGFloat = 0
    /// The app the user was in, to hand the keyboard back to.
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { panel?.isVisible ?? false }

    init(model: AppModel) {
        self.model = model
    }

    func toggle() {
        isOpen ? close() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front != .current { previousApp = front }
        model.refreshPermissions()
        model.scanner.refresh()
        // A fresh view each time resets the query and focus.
        let view = SearchView(model: model, open: { [weak self] item in
            self?.close()
            self?.model.opener.open(item)
        }, run: { [weak self] command in
            self?.close()
            NSApp.deactivate()
            self?.model.perform(command)
        }, close: { [weak self] in self?.close() })
        let panel = FloatingPanel(rootView: view)
        panel.onCancel = { [weak self] in self?.close() }
        self.panel?.dismiss()
        self.panel = panel
        // Activating lets the field take typing; the panel stays non-activating
        // for clicks.
        NSApp.activate()
        panel.layoutIfNeeded()
        if let screen = NSScreen.main {
            top = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.2
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: top - size.height))
        }
        // Results grow the panel downwards, keeping the field where it was.
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                                object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: self.top - panel.frame.height))
            }
        }
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

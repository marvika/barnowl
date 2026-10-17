import AppKit
import SwiftUI

/// Shows the Barkeep Bar under Barkeep's arrow.
@MainActor
final class BarkeepBarController {
    private let model: AppModel
    private let anchor: () -> NSRect?
    private var panel: FloatingPanel?
    private let outsideClicks = OutsideClickMonitor()
    private var resizeObserver: NSObjectProtocol?

    var isOpen: Bool { panel?.isVisible ?? false }

    init(model: AppModel, anchor: @escaping () -> NSRect?) {
        self.model = model
        self.anchor = anchor
    }

    func toggle() {
        isOpen ? close() : show()
    }

    func show() {
        model.refreshPermissions()
        model.scanner.refresh()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        outsideClicks.start { [weak self] in self?.close() }
    }

    func close() {
        outsideClicks.stop()
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let view = BarkeepBarView(model: model, open: { [weak self] item in
            self?.close()
            self?.model.opener.open(item)
        }, close: { [weak self] in self?.close() })
        let panel = FloatingPanel(rootView: view)
        panel.onCancel = { [weak self] in self?.close() }
        // Keep the panel's right edge under the arrow as its content grows.
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                                object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.position(panel)
            }
        }
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let anchor = anchor(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
                ?? NSScreen.main else { return }
        let size = panel.frame.size
        // The view adds 8 pt of transparent padding for the shadow.
        var x = anchor.maxX - size.width + 8
        x = min(max(x, screen.frame.minX + 4), screen.frame.maxX - size.width - 4)
        let y = screen.visibleFrame.maxY - size.height + 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

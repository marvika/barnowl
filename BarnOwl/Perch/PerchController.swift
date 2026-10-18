import AppKit
import SwiftUI

/// Shows the Perch under Barn Owl's arrow.
@MainActor
final class PerchController {
    private let model: AppModel
    private let anchor: () -> NSRect?
    private var panel: FloatingPanel?
    private let outsideClicks = OutsideClickMonitor()

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
        OpenPanel.shared.opening(self) { [weak self] in self?.close() }
    }

    func close() {
        outsideClicks.stop()
        OpenPanel.shared.closed(self)
        panel?.dismiss()
        panel = nil
    }

    private func makePanel() -> FloatingPanel {
        let view = PerchView(model: model, open: { [weak self] item in
            self?.close()
            self?.model.opener.open(item)
        }, close: { [weak self] in self?.close() })
        let panel = FloatingPanel(rootView: view)
        panel.onCancel = { [weak self] in self?.close() }
        // Keep the panel's right edge under the arrow as its content grows.
        panel.onResize = { [weak self] panel in self?.position(panel) }
        return panel
    }

    private func position(_ panel: FloatingPanel) {
        guard let anchor = anchor() else { return }
        panel.place(under: anchor, alignRight: true)
    }
}

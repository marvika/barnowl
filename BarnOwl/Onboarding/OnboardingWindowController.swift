import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    var onFinish: () -> Void = {}

    init(model: AppModel) {
        self.model = model
    }

    func show(at step: OnboardingView.Step? = nil) {
        // A given step starts the guide afresh there.
        if step != nil, let window {
            window.delegate = nil
            window.close()
            self.window = nil
        }
        if window == nil {
            let view = OnboardingView(model: model, start: step ?? .welcome) { [weak self] in self?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        OpenPanel.shared.closeAll()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.endArranging(collapse: false)
        window = nil
        onFinish()
    }
}

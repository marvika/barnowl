import AppKit

/// Whoever opened the editor: it takes the flattened image when you copy, save, pin or finish,
/// and keeps the document so the capture can be opened again with its marks still editable.
@MainActor
protocol CaptureEditorHost: AnyObject {
    func editor(_ editor: CaptureEditor, copy image: CGImage)
    /// Saves over the capture's file, or as a new one. Returns the file, or nil if it couldn't be saved.
    func editor(_ editor: CaptureEditor, save image: CGImage) async -> URL?
    func editor(_ editor: CaptureEditor, pin image: CGImage)
    /// Done: the host copies (and saves per settings); the editor closes itself right after.
    func editor(_ editor: CaptureEditor, finish image: CGImage)
    /// The document changed; called at most about once a second, and once more on close if changed.
    func editor(_ editor: CaptureEditor, didChange document: EditorDocument)
    /// Closed. `edited` is whether anything changed since it opened.
    func editorDidClose(_ editor: CaptureEditor, edited: Bool)
}

/// The markup editor for one capture. The host keeps it until `editorDidClose`. While any
/// editor is open the host runs Barn Owl as a regular app; the editor puts up its own menus.
@MainActor
final class CaptureEditor {
    private weak var host: CaptureEditorHost?
    let model: EditorModel
    private let title: String
    private(set) var controller: EditorWindowController?
    private var closed = false
    private var menusInstalled = false
    private var activationObserver: NSObjectProtocol?
    private var reportTask: Task<Void, Never>?
    private var reported: EditorDocument
    private var lastReport = Date.distantPast
    private var askedAboutSecrets = false

    /// `image` is the captured bitmap; `scale` is pixels per point (2 on Retina); `title` names
    /// the window; `document` reopens earlier marks; `insight` is the capture's text and windows,
    /// if the scan has finished (see `update(insight:)`).
    init(image: CGImage, scale: CGFloat, title: String, document: EditorDocument? = nil, insight: CaptureInsight? = nil,
         host: CaptureEditorHost) {
        self.host = host
        self.title = title
        model = EditorModel(image: image, scale: scale, document: document, insight: insight)
        reported = model.document
        model.onAction = { [weak self] action in self?.perform(action) }
        model.onCommit = { [weak self] in self?.scheduleReport() }
    }

    /// Orders the window front and makes it key. macOS 14 and later activate apps cooperatively,
    /// so if Barn Owl isn't active yet, the window is made key again the moment it is.
    func show() {
        guard !closed else { return }
        let controller = self.controller ?? makeController()
        guard let window = controller.window else { return }
        if !menusInstalled {
            menusInstalled = true
            EditorMenus.editorOpened()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(controller.canvas)
        controller.canvas.zoomToFit()
        if !NSApp.isActive, activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            }
        }
        loadDesktopPicture(for: window.screen)
    }

    private func becameActive() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        guard !closed, let controller, let window = controller.window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.canvas)
    }

    func close() {
        if let window = controller?.window, window.isVisible {
            window.close()
        } else {
            didClose()
        }
    }

    /// The capture's text and windows, when the scan finishes after the editor opened.
    func update(insight: CaptureInsight) {
        model.update(insight: insight)
    }

    /// The current composition, flattened at full resolution in sRGB, rendered off the main thread.
    func render() async -> CGImage? {
        let renderer = model.renderer
        let document = model.document
        return await Task.detached(priority: .userInitiated) {
            renderer.render(document)
        }.value
    }

    // MARK: Window

    private func makeController() -> EditorWindowController {
        let controller = EditorWindowController(model: model, title: title)
        controller.onClose = { [weak self] in self?.didClose() }
        self.controller = controller
        model.noteOpened()
        return controller
    }

    private func loadDesktopPicture(for screen: NSScreen?) {
        guard model.renderer.desktop == nil, let screen = screen ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        let renderer = model.renderer
        Task { [weak self] in
            let picture = await Task.detached(priority: .utility) { AnnotationRenderer.loadDesktopPicture(from: url) }.value
            guard let picture else { return }
            renderer.setDesktop(picture)
            guard let self, self.model.document.frame.background == .desktop else { return }
            self.controller?.canvas.relayout()
        }
    }

    private func didClose() {
        guard !closed else { return }
        closed = true
        reportTask?.cancel()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        if model.document != reported {
            reported = model.document
            host?.editor(self, didChange: model.document)
        }
        if menusInstalled { EditorMenus.editorClosed() }
        model.onAction = nil
        model.onCommit = nil
        host?.editorDidClose(self, edited: model.isEdited)
    }

    // MARK: Autosave

    /// Tells the host about changes at most about once a second.
    private func scheduleReport() {
        guard reportTask == nil, !closed else { return }
        let wait: TimeInterval = max(0.05, 1 - Date().timeIntervalSince(lastReport))
        reportTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.reportTask = nil
            self.report()
        }
    }

    private func report() {
        guard !closed, model.document != reported else { return }
        reported = model.document
        lastReport = Date()
        host?.editor(self, didChange: model.document)
    }

    // MARK: Actions

    private func perform(_ action: EditorAction) {
        controller?.canvas.endTextEditing()
        if model.cropDraft != nil { model.applyCrop() }
        if action == .done, model.asksAboutSecretsOnDone, !askedAboutSecrets, let window = controller?.window {
            askAboutSecrets(in: window)
            return
        }
        Task { [weak self] in
            guard let self, let image = await self.render() else {
                NSSound.beep()
                return
            }
            await self.deliver(action, image)
        }
    }

    private func deliver(_ action: EditorAction, _ image: CGImage) async {
        guard !closed else { return }
        switch action {
        case .copy:
            host?.editor(self, copy: image)
            controller?.confirmCopy()
        case .save:
            let url = await host?.editor(self, save: image)
            controller?.announce(url.map { "Saved · \($0.lastPathComponent)" } ?? "Couldn't save")
        case .pin:
            host?.editor(self, pin: image)
        case .done:
            report()
            host?.editor(self, finish: image)
            close()
        }
    }

    /// Done with a key still showing: ask once.
    private func askAboutSecrets(in window: NSWindow) {
        askedAboutSecrets = true
        let alert = NSAlert()
        let several = model.visibleSecrets.count > 1
        alert.messageText = several ? "Hide the keys before copying?" : "Hide the key before copying?"
        alert.informativeText = several
            ? "Keys or tokens are visible in this capture. Anyone you share it with could use them."
            : "A key or token is visible in this capture. Anyone you share it with could use it."
        alert.addButton(withTitle: "Hide and Copy")
        alert.addButton(withTitle: "Copy Anyway")
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                if response == .alertFirstButtonReturn { self.model.hideSecrets() }
                self.model.secretBannerDismissed = true
                self.perform(.done)
            }
        }
    }
}

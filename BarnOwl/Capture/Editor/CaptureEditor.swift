import AppKit
import SwiftUI

/// Whoever opened the editor: it takes the flattened image when you copy, save, pin or finish.
@MainActor
protocol CaptureEditorHost: AnyObject {
    /// Copy the flattened image (pixels at the capture's scale).
    func editor(_ editor: CaptureEditor, copy image: CGImage)
    /// Save the flattened image (the host decides where; it overwrites the capture's own file).
    func editor(_ editor: CaptureEditor, save image: CGImage)
    /// Pin the flattened image to the screen.
    func editor(_ editor: CaptureEditor, pin image: CGImage)
    /// Done: the host copies and saves; the editor closes itself afterwards.
    func editor(_ editor: CaptureEditor, finish image: CGImage)
    func editorDidClose(_ editor: CaptureEditor)
}

/// The markup editor for one capture: a window with the image on a dark canvas, the tools along
/// the top, and the frame inspector on the right. The host keeps it until `editorDidClose`.
@MainActor
final class CaptureEditor: NSObject, NSWindowDelegate {
    private weak var host: CaptureEditorHost?
    private let title: String
    let model: EditorModel
    private let renderer: AnnotationRenderer
    private var window: NSWindow?
    private var canvas: EditorCanvas?
    /// Closing on purpose, without asking about unsaved changes.
    private var closingQuietly = false
    private var closed = false

    static let minimumSize = NSSize(width: 1020, height: 520)

    /// `image` is the captured bitmap; `scale` is pixels per point (2 on Retina), used for
    /// on-screen sizing and so strokes/text have sensible pixel sizes. `title` is the window title.
    init(image: CGImage, scale: CGFloat, title: String, host: CaptureEditorHost) {
        self.host = host
        self.title = title
        model = EditorModel(image: image, scale: scale)
        renderer = AnnotationRenderer(image: image, scale: model.scale)
        super.init()
        model.onAction = { [weak self] action in self?.perform(action) }
    }

    /// Opens the window, activates Barn Owl and makes it key.
    func show() {
        guard !closed else { return }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if let canvas { window.makeFirstResponder(canvas) }
    }

    func close() {
        closingQuietly = true
        if let window {
            window.close()
        } else {
            didClose()
        }
    }

    /// The current composition, flattened at full resolution.
    func render() -> CGImage? {
        renderer.render(model.document)
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let canvas = EditorCanvas(model: model, renderer: renderer)
        canvas.onClose = { [weak self] in self?.window?.performClose(nil) }
        self.canvas = canvas
        let content = EditorContentView(model: model, canvas: canvas)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.windowSize(canvas: canvas.frame.size, visible: visible.size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = EditorCanvas.background
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: min(Self.minimumSize.width, visible.width),
                                height: min(Self.minimumSize.height, visible.height))
        window.contentView = content
        window.initialFirstResponder = canvas
        window.delegate = self
        window.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(),
                                      y: (visible.midY - size.height / 2).rounded()))
        content.layoutSubtreeIfNeeded()
        canvas.zoomToFit()
        EditorEditMenu.editorOpened()
        return window
    }

    /// Big enough for the image at actual size and the toolbar, within 85% of the screen.
    static func windowSize(canvas: NSSize, visible: NSSize) -> NSSize {
        let maxWidth: CGFloat = (visible.width * 0.85).rounded()
        let maxHeight: CGFloat = (visible.height * 0.85).rounded()
        let wantedWidth: CGFloat = canvas.width + 2 * 40
        let wantedHeight: CGFloat = canvas.height + EditorToolbar.height + 2 * 32
        let width: CGFloat = min(max(wantedWidth, minimumSize.width), maxWidth)
        let height: CGFloat = min(max(wantedHeight, minimumSize.height), maxHeight)
        return NSSize(width: width, height: height)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas?.endTextEditing()
        guard model.isDirty, !closingQuietly else { return true }
        let alert = NSAlert()
        alert.messageText = "Save your markup?"
        alert.informativeText = "If you don't, your changes to this capture are lost."
        alert.addButton(withTitle: "Save")
        let discard = alert.addButton(withTitle: "Don't Save")
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    self.perform(.save)
                    self.close()
                case .alertSecondButtonReturn:
                    self.close()
                default:
                    break
                }
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        didClose()
    }

    private func didClose() {
        guard !closed else { return }
        closed = true
        canvas?.endTextEditing()
        if window != nil { EditorEditMenu.editorClosed() }
        window?.delegate = nil
        model.onAction = nil
        host?.editorDidClose(self)
    }

    // MARK: Actions

    private func perform(_ action: EditorAction) {
        canvas?.endTextEditing()
        if model.cropDraft != nil { model.applyCrop() }
        guard let image = render() else {
            NSSound.beep()
            return
        }
        switch action {
        case .copy:
            host?.editor(self, copy: image)
            model.confirm(.copy)
        case .save:
            host?.editor(self, save: image)
            model.markSaved()
            model.confirm(.save)
        case .pin:
            host?.editor(self, pin: image)
        case .done:
            host?.editor(self, finish: image)
            model.markSaved()
            close()
        }
    }
}

/// The window's content: the toolbar along the top, the canvas, and the frame inspector on the right.
final class EditorContentView: NSView {
    private let model: EditorModel
    private let canvas: EditorCanvas
    private let scrollView = NSScrollView()
    private let toolbar: NSHostingView<EditorToolbar>
    private let inspector: NSHostingView<FrameInspector>

    init(model: EditorModel, canvas: EditorCanvas) {
        self.model = model
        self.canvas = canvas
        toolbar = NSHostingView(rootView: EditorToolbar(model: model))
        inspector = NSHostingView(rootView: FrameInspector(model: model))
        super.init(frame: NSRect(x: 0, y: 0, width: 1020, height: 640))
        wantsLayer = true
        layer?.backgroundColor = EditorCanvas.background.cgColor

        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.drawsBackground = true
        scrollView.backgroundColor = EditorCanvas.background
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 16
        scrollView.automaticallyAdjustsContentInsets = false

        // Laid out by hand, edge to edge under the transparent title bar.
        toolbar.sizingOptions = []
        toolbar.safeAreaRegions = []
        inspector.sizingOptions = []
        inspector.safeAreaRegions = []
        addSubview(scrollView)
        addSubview(inspector)
        addSubview(toolbar)
        inspector.isHidden = !model.showsInspector
        model.onChange = { [weak canvas] in canvas?.refresh() }
        model.onInspectorChange = { [weak self] in self?.inspectorChanged() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let width: CGFloat = bounds.width
        let top: CGFloat = EditorToolbar.height
        let below: CGFloat = max(0, bounds.height - top)
        let panel: CGFloat = FrameInspector.width + 12
        let shown: CGFloat = model.showsInspector ? panel : 0
        toolbar.frame = NSRect(x: 0, y: 0, width: width, height: top)
        scrollView.frame = NSRect(x: 0, y: top, width: max(0, width - shown), height: below)
        inspector.frame = NSRect(x: width - panel, y: top - 12, width: panel, height: below + 12)
        canvas.viewportDidResize()
    }

    private func inspectorChanged() {
        inspector.isHidden = !model.showsInspector
        needsLayout = true
        layoutSubtreeIfNeeded()
        if model.showsInspector {
            inspector.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                inspector.animator().alphaValue = 1
            }
        }
    }
}

/// Barn Owl has no main menu, but typing needs Cut, Copy, Paste and Select All, which come from
/// an Edit menu. While an editor is open, this adds one if there isn't one already.
@MainActor
enum EditorEditMenu {
    private static var openEditors = 0
    private static var added: NSMenuItem?
    private static var madeMainMenu = false

    static func editorOpened() {
        openEditors += 1
        guard added == nil, !hasEditMenu else { return }
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = makeMenu()
        if let main = NSApp.mainMenu {
            main.addItem(item)
        } else {
            let main = NSMenu(title: "Main")
            // The first item is always the application menu.
            let app = NSMenuItem(title: "Barn Owl", action: nil, keyEquivalent: "")
            app.submenu = NSMenu(title: "Barn Owl")
            main.addItem(app)
            main.addItem(item)
            NSApp.mainMenu = main
            madeMainMenu = true
        }
        added = item
    }

    static func editorClosed() {
        openEditors = max(0, openEditors - 1)
        guard openEditors == 0, let added else { return }
        if madeMainMenu, NSApp.mainMenu === added.menu {
            NSApp.mainMenu = nil
        } else {
            added.menu?.removeItem(added)
        }
        self.added = nil
        madeMainMenu = false
    }

    private static var hasEditMenu: Bool {
        guard let main = NSApp.mainMenu else { return false }
        return main.items.contains { item in
            item.submenu?.items.contains { $0.action == #selector(NSText.paste(_:)) } ?? false
        }
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }
}

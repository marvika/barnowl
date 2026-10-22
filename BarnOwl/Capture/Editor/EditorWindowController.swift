import AppKit
import SwiftUI

/// The editor's window. Previews can make it draw as the key window without being on screen.
final class EditorWindow: NSWindow {
    /// For previews only: draw as active (true) or inactive (false) whatever the real state.
    var drawsAsActive: Bool?

    override var isKeyWindow: Bool { drawsAsActive ?? super.isKeyWindow }
    override var isMainWindow: Bool { drawsAsActive ?? super.isMainWindow }
}

/// The editor's window: a unified toolbar with the tools, a contextual options bar under it,
/// the canvas, and the Frame inspector at the trailing edge.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation,
    NSSharingServicePickerToolbarItemDelegate {
    let model: EditorModel
    let canvas: EditorCanvas
    let viewState = CanvasViewState()
    /// Called once the window has closed.
    var onClose: (() -> Void)?
    /// The Desktop background was chosen: its picture is wanted.
    var onNeedsDesktop: (() -> Void)?

    private let scrollView = NSScrollView()
    private let optionsLayout = OptionsBarLayout()
    private var inspectorItem: NSSplitViewItem?
    private var inspectorObservation: NSKeyValueObservation?
    private var toolGroup: NSToolbarItemGroup?
    private var modeGroup: NSToolbarItemGroup?
    private var copyItem: NSToolbarItem?
    /// Whether the shared colour panel was last opened for this editor.
    private var ownsColourPanel = false
    private var copyReset: Task<Void, Never>?
    private var recentTask: Task<Void, Never>?
    private var shortcutsSheet: NSWindow?

    /// Wide enough for every toolbar item, Done included, without the overflow menu.
    static let minimumSize = NSSize(width: 940, height: 480)
    static let sizeKey = "captureEditor.windowSize"

    private enum Item {
        static let tools = NSToolbarItem.Identifier("captureEditor.tools")
        static let modes = NSToolbarItem.Identifier("captureEditor.modes")
        static let pin = NSToolbarItem.Identifier("captureEditor.pin")
        static let share = NSToolbarItem.Identifier("captureEditor.share")
        static let copy = NSToolbarItem.Identifier("captureEditor.copy")
        static let done = NSToolbarItem.Identifier("captureEditor.done")
    }

    init(model: EditorModel, title: String) {
        self.model = model
        canvas = EditorCanvas(model: model)
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: true)
        super.init(window: window)
        window.title = title
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.backgroundColor = EditorCanvas.backdrop

        let toolbar = NSToolbar(identifier: "captureEditor.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        let options = NSTitlebarAccessoryViewController()
        options.layoutAttribute = .bottom
        let bar = NSHostingView(rootView: OptionsBar(model: model, actions: optionsActions, layout: optionsLayout))
        bar.sizingOptions = []
        bar.frame = NSRect(x: 0, y: 0, width: 1100, height: OptionsBar.height)
        options.view = bar
        window.addTitlebarAccessoryViewController(options)

        window.contentViewController = makeSplit()
        window.initialFirstResponder = canvas
        window.minSize = Self.minimumSize
        sizeWindow(window)
        wire()
        syncToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Layout

    private func makeSplit() -> NSSplitViewController {
        let split = NSSplitViewController()
        let canvasController = NSViewController()
        canvasController.view = makeCanvasContainer()
        let main = NSSplitViewItem(viewController: canvasController)
        main.minimumThickness = 420
        split.addSplitViewItem(main)
        let inspector = NSSplitViewItem(inspectorWithViewController: NSHostingController(rootView: FrameInspector(model: model)))
        inspector.minimumThickness = FrameInspector.width
        inspector.maximumThickness = FrameInspector.width
        inspector.canCollapse = true
        inspector.isCollapsed = !model.showsFrame
        split.addSplitViewItem(inspector)
        inspectorItem = inspector
        // Closed by dragging its edge: the Frame button follows.
        inspectorObservation = inspector.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            let collapsed = item.isCollapsed
            MainActor.assumeIsolated {
                guard let self, self.model.showsFrame == collapsed else { return }
                self.model.showsFrame = !collapsed
            }
        }
        return split
    }

    private func makeCanvasContainer() -> NSView {
        let container = CanvasContainerView()
        container.onLayout = { [weak self] in self?.containerDidLayout() }
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.drawsBackground = true
        scrollView.backgroundColor = EditorCanvas.backdrop
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let zoom = overlay(ZoomCapsule(state: viewState) { [weak self] request in self?.zoom(request) }, in: container)
        let readout = overlay(SizeReadout(state: viewState), in: container)
        let hint = overlay(HintStrip(model: model), in: container)
        let banner = overlay(BannerHost(model: model), in: container)
        // In a narrow window the hint gives way first, never the zoom or the size.
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            zoom.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            zoom.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            readout.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            readout.centerYAnchor.constraint(equalTo: zoom.centerYAnchor),
            hint.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: zoom.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: readout.trailingAnchor, constant: 12),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: zoom.leadingAnchor, constant: -12),
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
        return container
    }

    /// A SwiftUI overlay sized to its content, so it takes clicks only where it draws.
    private func overlay(_ view: some View, in container: NSView) -> NSView {
        let host = NSHostingView(rootView: AnyView(view))
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        return host
    }

    private func containerDidLayout() {
        canvas.viewportDidResize()
        alignOptionsBar()
    }

    /// The options bar starts where the traffic lights do.
    private func alignOptionsBar() {
        guard let window, let close = window.standardWindowButton(.closeButton) else { return }
        let frame = close.convert(close.bounds, to: nil)
        let leading: CGFloat = max(12, frame.minX.rounded())
        if abs(optionsLayout.leading - leading) > 0.5, frame.width > 0, frame.minX < window.frame.width {
            optionsLayout.leading = leading
        }
    }

    private func sizeWindow(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var size: NSSize
        if let saved = UserDefaults.standard.string(forKey: Self.sizeKey) {
            size = NSSizeFromString(saved)
        } else {
            let canvasSize = NSSize(width: canvas.frame.width, height: canvas.frame.height)
            let width: CGFloat = canvasSize.width + 2 * 48
            let height: CGFloat = canvasSize.height + 52 + OptionsBar.height + 2 * 48
            size = NSSize(width: width, height: height)
        }
        let maxWidth: CGFloat = (visible.width * 0.9).rounded()
        let maxHeight: CGFloat = (visible.height * 0.9).rounded()
        size.width = min(max(size.width, Self.minimumSize.width), maxWidth)
        size.height = min(max(size.height, Self.minimumSize.height), maxHeight)
        let x: CGFloat = (visible.midX - size.width / 2).rounded()
        let y: CGFloat = (visible.midY - size.height / 2).rounded()
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    // MARK: Wiring

    private func wire() {
        model.onDocumentChange = { [weak self] old, new in
            guard let self else { return }
            self.canvas.documentChanged(from: old, to: new)
            self.updateOutputSize()
            self.syncBadge()
            if new.frame.background == .desktop, old.frame.background != .desktop { self.onNeedsDesktop?() }
        }
        model.onChromeChange = { [weak self] in
            self?.canvas.chromeChanged()
            self?.syncBadge()
        }
        model.onToolChange = { [weak self] in
            self?.canvas.toolChanged()
            self?.syncToolbar()
        }
        model.onFrameVisibilityChange = { [weak self] in self?.syncInspector() }
        canvas.onCommand = { [weak self] id in self?.perform(id) }
        canvas.onClose = { [weak self] in self?.window?.performClose(nil) }
        canvas.onZoomChange = { [weak self] in
            guard let self else { return }
            self.viewState.zoom = self.canvas.magnification
        }
        updateOutputSize()
    }

    private func updateOutputSize() {
        viewState.outputSize = FrameLayout(document: model.document).canvasSize
    }

    private var optionsActions: OptionsBarActions {
        OptionsBarActions(
            pickColour: { [weak self] in self?.canvas.startPickingColour() },
            moreColours: { [weak self] in self?.showColourPanel() },
            showFonts: { [weak self] in self?.showFontPanel() },
            cropAspect: { [weak self] aspect in self?.canvas.applyCropAspect(aspect) },
            focusCanvas: { [weak self] in
                guard let self else { return }
                // Back to the text being typed, if there is one.
                self.window?.makeFirstResponder(self.canvas.textView ?? self.canvas)
            }
        )
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.tools, .flexibleSpace, Item.modes, .space, Item.pin, Item.share, Item.copy, .space, Item.done]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Item.tools:
            let tools = EditorTool.group
            let group = NSToolbarItemGroup(itemIdentifier: identifier, images: tools.map { Self.symbol($0.symbol, $0.title) },
                                           selectionMode: .selectOne, labels: tools.map(\.title), target: self,
                                           action: #selector(toolChosen(_:)))
            group.label = "Tools"
            group.controlRepresentation = .expanded
            for (item, tool) in zip(group.subitems, tools) {
                item.toolTip = EditorCommand.tooltip(tool)
            }
            if let index = tools.firstIndex(of: model.tool) { group.selectedIndex = index }
            toolGroup = group
            syncBadge()
            return group
        case Item.modes:
            let group = NSToolbarItemGroup(itemIdentifier: identifier,
                                           images: [Self.symbol("crop", "Crop"), Self.symbol("photo.artframe", "Frame")],
                                           selectionMode: .selectAny, labels: ["Crop", "Frame"], target: self,
                                           action: #selector(modeChosen(_:)))
            group.label = "Crop and Frame"
            group.controlRepresentation = .expanded
            group.subitems[0].toolTip = EditorCommand.tooltip(.crop)
            group.subitems[1].toolTip = "Frame: background, padding and corners (⌥⌘I)"
            group.setSelected(model.tool == .crop, at: 0)
            group.setSelected(model.showsFrame, at: 1)
            modeGroup = group
            return group
        case Item.pin:
            return button(identifier, symbol: "pin", label: "Pin", tooltip: "Pin to the screen (⌥⌘P)", action: #selector(pinPressed))
        case Item.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.delegate = self
            item.label = "Share"
            item.toolTip = "Share"
            return item
        case Item.copy:
            let item = button(identifier, symbol: "doc.on.doc", label: "Copy", tooltip: "Copy Image (⇧⌘C)", action: #selector(copyPressed))
            item.visibilityPriority = .high
            copyItem = item
            return item
        case Item.done:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Done"
            item.title = "Done"
            item.toolTip = "Copy, save and close (↩)"
            item.isBordered = true
            item.style = .prominent
            item.backgroundTintColor = EditorCanvas.accentFill
            item.target = self
            item.action = #selector(donePressed)
            // The last thing to go if the window is ever too narrow.
            item.visibilityPriority = .user
            return item
        default:
            return nil
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier, symbol: String, label: String, tooltip: String,
                        action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = Self.symbol(symbol, label)
        item.label = label
        item.toolTip = tooltip
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    static func symbol(_ name: String, _ description: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        return image?.withSymbolConfiguration(configuration) ?? NSImage()
    }

    @objc private func toolChosen(_ sender: NSToolbarItemGroup) {
        let index = sender.selectedIndex
        guard EditorTool.group.indices.contains(index) else { return }
        let tool = EditorTool.group[index]
        switch tool {
        case .arrow: model.chooseArrow(line: model.styleBook.style(for: .arrow).heads == .none)
        default: model.choose(tool)
        }
        window?.makeFirstResponder(canvas)
    }

    @objc private func modeChosen(_ sender: NSToolbarItemGroup) {
        let cropOn = sender.isSelected(at: 0)
        let frameOn = sender.isSelected(at: 1)
        if cropOn != (model.tool == .crop) {
            if cropOn { model.choose(.crop) } else { model.cancelCrop() }
        }
        if frameOn != model.showsFrame { model.showsFrame = frameOn }
        syncToolbar()
        window?.makeFirstResponder(canvas)
    }

    @objc private func pinPressed() { model.perform(.pin) }
    @objc private func copyPressed() { model.perform(.copy) }
    @objc private func donePressed() { model.perform(.done) }

    func syncToolbar() {
        if let toolGroup {
            let index = EditorTool.group.firstIndex(of: model.tool) ?? -1
            if toolGroup.selectedIndex != index {
                if index >= 0 {
                    toolGroup.selectedIndex = index
                } else {
                    for position in toolGroup.subitems.indices { toolGroup.setSelected(false, at: position) }
                }
            }
        }
        modeGroup?.setSelected(model.tool == .crop, at: 0)
        modeGroup?.setSelected(model.showsFrame, at: 1)
        syncBadge()
    }

    /// How many private things are visible, on the Redact tool.
    private func syncBadge() {
        guard let toolGroup, let index = EditorTool.group.firstIndex(of: .redact),
              toolGroup.subitems.indices.contains(index) else { return }
        let count = model.privateCount
        let item = toolGroup.subitems[index]
        item.badge = count > 0 ? .count(count) : nil
        item.toolTip = count > 0
            ? "Redact (B) — \(count) \(count == 1 ? "thing looks" : "things look") private. ⇧B to review."
            : EditorCommand.tooltip(.redact)
    }

    private func syncInspector() {
        guard let inspectorItem else { return }
        let collapsed = !model.showsFrame
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || window?.isVisible != true {
            inspectorItem.isCollapsed = collapsed
        } else {
            inspectorItem.animator().isCollapsed = collapsed
        }
        syncToolbar()
    }

    /// The Copy button shows a tick for a moment.
    func confirmCopy() {
        copyItem?.image = Self.symbol("checkmark", "Copied")
        copyReset?.cancel()
        copyReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.copyItem?.image = Self.symbol("doc.on.doc", "Copy")
        }
        announce("Copied")
    }

    func announce(_ text: String) {
        guard let window else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Sharing

    /// AppKit asks for these every time it checks the toolbar, which happens after nearly every
    /// event, so this only promises the picture: it's drawn when you actually pick a way to
    /// share, and typing in a text mark carries on undisturbed.
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        let renderer = model.renderer
        let document = model.document
        let scale = model.scale
        let provider = NSItemProvider()
        provider.registerObject(ofClass: NSImage.self, visibility: .all) { completion in
            Task.detached(priority: .userInitiated) {
                guard let image = renderer.render(document) else {
                    return completion(nil, CocoaError(.fileWriteUnknown))
                }
                let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
                completion(NSImage(cgImage: image, size: size), nil)
            }
            return nil
        }
        return [provider]
    }

    // MARK: Commands

    @objc func performEditorCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let raw = item.representedObject as? String,
              let id = EditorCommand.ID(rawValue: raw) else { return }
        perform(id)
    }

    /// The words in the capture, as much of it as the crop shows, in reading order.
    private func copyText() {
        guard let insight = model.insight, insight.textWasRead else {
            model.showHint("Still reading the text · try again in a moment")
            return
        }
        let covered = model.document.marks.filter { $0.kind == .redact }.map(\.rect)
        let words = insight.text.plainText(within: model.document.crop, excluding: covered)
        guard !words.isEmpty else {
            NSSound.beep()
            model.showHint("No text in this capture")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(words, forType: .string)
        model.showHint("Text copied")
    }

    func perform(_ id: EditorCommand.ID) {
        guard canPerform(id) else { return }
        switch id {
        case .copy: model.perform(.copy)
        case .copyMarks: canvas.copy(nil)
        case .copyText: copyText()
        case .save: model.perform(.save)
        case .pin: model.perform(.pin)
        case .done: model.perform(.done)
        case .close: window?.performClose(nil)
        case .revert: model.revertToOriginal()
        case .undo: model.undo()
        case .redo: model.redo()
        case .cut: canvas.cut(nil)
        case .paste: canvas.paste(nil)
        case .delete: model.deleteSelection()
        case .selectAll: model.selectAll()
        case .duplicate: model.duplicateSelection()
        case .actualSize: canvas.setZoom(1)
        case .zoomToFit: canvas.zoomToFit()
        case .zoomIn, .fontBigger:
            if model.isTextInHand { model.stepSize(up: true) } else { canvas.zoom(by: 1.25) }
        case .zoomOut, .fontSmaller:
            if model.isTextInHand { model.stepSize(up: false) } else { canvas.zoom(by: 0.8) }
        case .showFrame: model.showsFrame.toggle()
        case .shortcuts: showShortcuts()
        case .bringToFront: model.bringToFront()
        case .sendToBack: model.sendToBack()
        case .bringForward: model.bringForward()
        case .sendBackward: model.sendBackward()
        case .alignLeft: model.align(.left)
        case .alignCentre: model.align(.centre)
        case .alignRight: model.align(.right)
        case .alignTop: model.align(.top)
        case .alignMiddle: model.align(.middle)
        case .alignBottom: model.align(.bottom)
        case .select: model.choose(.select)
        case .arrow: model.chooseArrow(line: false)
        case .line: model.chooseArrow(line: true)
        case .rectangle: model.chooseRectangle(filled: false)
        case .filled: model.chooseRectangle(filled: true)
        case .ellipse: model.choose(.ellipse)
        case .text: model.choose(.text)
        case .counter: model.choose(.counter)
        case .highlighter: model.choose(.highlighter)
        case .pen: model.choose(.pen)
        case .redact: model.choose(.redact)
        case .review: model.beginReview()
        case .spotlight: model.choose(.spotlight)
        case .crop: model.tool == .crop ? model.applyCrop() : model.choose(.crop)
        case .colour1, .colour2, .colour3, .colour4, .colour5, .colour6, .colour7, .colour8:
            chooseColour(EditorCommand.colourKeys.firstIndex(of: id) ?? 0)
        case .smaller: model.stepSize(up: false)
        case .bigger: model.stepSize(up: true)
        case .pickColour: canvas.startPickingColour()
        case .bold: model.toggleBold()
        case .showFonts: showFontPanel()
        }
    }

    private func chooseColour(_ index: Int) {
        let palette: [MarkColour] = model.activeKind == .highlighter ? MarkColour.highlighterPalette : MarkColour.palette
        guard palette.indices.contains(index) else { return }
        model.setColour(palette[index])
    }

    /// Plain-key commands wait while you type; the rest depend on what's there to act on.
    func canPerform(_ id: EditorCommand.ID) -> Bool {
        if let command = EditorCommand.command(id), command.isBareKey {
            // Typing (a mark's text, the size field) keeps its letters; so does a counter's new label.
            guard !(window?.firstResponder is NSText), canvas.labelArmed == nil else { return false }
        }
        switch id {
        case .duplicate, .bringToFront, .sendToBack, .bringForward, .sendBackward, .delete, .cut:
            return !model.selection.isEmpty
        case .alignLeft, .alignCentre, .alignRight, .alignTop, .alignMiddle, .alignBottom:
            return !model.selection.isEmpty
        case .bold:
            return model.isTextContext
        case .review:
            return model.insight != nil
        case .revert:
            return model.canRevert
        case .copyText:
            return model.insight?.textWasRead != false
        default:
            return true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performEditorCommand(_:)),
              let raw = menuItem.representedObject as? String, let id = EditorCommand.ID(rawValue: raw) else { return true }
        menuItem.state = isChecked(id) ? .on : .off
        if id == .showFrame { menuItem.title = model.showsFrame ? "Hide Frame" : "Show Frame" }
        return canPerform(id)
    }

    private func isChecked(_ id: EditorCommand.ID) -> Bool {
        switch id {
        case .select: model.tool == .select
        case .arrow: model.tool == .arrow && model.styleBook.style(for: .arrow).heads != .none
        case .line: model.tool == .arrow && model.styleBook.style(for: .arrow).heads == .none
        case .rectangle: model.tool == .rectangle && model.styleBook.style(for: .rectangle).fill != .solid
        case .filled: model.tool == .rectangle && model.styleBook.style(for: .rectangle).fill == .solid
        case .ellipse: model.tool == .ellipse
        case .text: model.tool == .text
        case .counter: model.tool == .counter
        case .highlighter: model.tool == .highlighter
        case .pen: model.tool == .pen
        case .redact: model.tool == .redact
        case .spotlight: model.tool == .spotlight
        case .crop: model.tool == .crop
        case .bold: model.isTextContext && model.shownStyle.fontWeight == .bold
        default: false
        }
    }

    private func zoom(_ request: ZoomCapsule.ZoomRequest) {
        switch request {
        case .zoomIn: canvas.zoom(by: 1.25)
        case .zoomOut: canvas.zoom(by: 0.8)
        case .fit: canvas.zoomToFit()
        case .actual: canvas.setZoom(1)
        case .percent(let value): canvas.setZoom(value)
        }
    }

    // MARK: Panels

    private func showShortcuts() {
        guard let window, shortcutsSheet == nil else { return }
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: ShortcutsSheet { [weak self] in
            self?.closeShortcuts()
        }))
        sheet.title = "Keyboard Shortcuts"
        shortcutsSheet = sheet
        window.beginSheet(sheet)
    }

    private func closeShortcuts() {
        guard let sheet = shortcutsSheet else { return }
        window?.endSheet(sheet)
        shortcutsSheet = nil
    }

    private func showColourPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        ownsColourPanel = true
        panel.setTarget(self)
        panel.setAction(#selector(colourPanelChanged(_:)))
        panel.color = NSColor(cgColor: model.shownColour.cgColor()) ?? .systemRed
        panel.orderFront(nil)
    }

    @objc private func colourPanelChanged(_ sender: NSColorPanel) {
        guard let srgb = sender.color.usingColorSpace(.sRGB) else { return }
        let colour = MarkColour(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                                blue: Double(srgb.blueComponent))
        model.setColour(colour)
        // Remembered once you settle on it, not for every step of a drag across the wheel.
        recentTask?.cancel()
        recentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.model.noteRecent(colour)
        }
    }

    private func showFontPanel() {
        let manager = NSFontManager.shared
        manager.target = self
        let style = model.shownStyle
        let font = MarkGeometry.font(style.font, weight: style.fontWeight, size: CGFloat(style.fontSize))
        manager.setSelectedFont(font, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        let manager = NSFontManager.shared
        let style = model.shownStyle
        let current = MarkGeometry.font(style.font, weight: style.fontWeight, size: CGFloat(style.fontSize))
        let chosen = manager.convert(current)
        let size = Double(chosen.pointSize)
        let name = chosen.fontName
        model.updateStyle("Change Font") { style in
            style.font = .named(name)
            style.fontSize = size
        }
    }

    // MARK: Window

    func windowDidResize(_ notification: Notification) {
        guard let window, window.isVisible else { return }
        UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: Self.sizeKey)
    }

    func windowWillClose(_ notification: Notification) {
        canvas.endTextEditing()
        if let shortcutsSheet { window?.endSheet(shortcutsSheet) }
        releaseSharedPanels()
        onClose?()
    }

    /// The colour and font panels are shared by the whole app: once this window goes, they
    /// mustn't send their changes here, or keep it alive.
    private func releaseSharedPanels() {
        // Only if this editor last used it: another editor or Settings may have it now.
        if ownsColourPanel, NSColorPanel.sharedColorPanelExists {
            ownsColourPanel = false
            let panel = NSColorPanel.shared
            if panel.isVisible { panel.close() }
            panel.setTarget(nil)
            panel.setAction(nil)
        }
        let fonts = NSFontManager.shared
        if fonts.target === self {
            fonts.target = nil
            if NSFontPanel.sharedFontPanelExists, NSFontPanel.shared.isVisible { NSFontPanel.shared.close() }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if window?.firstResponder === window { window?.makeFirstResponder(canvas) }
    }
}

/// Holds the canvas and its overlays, and tells the canvas when its size changes.
final class CanvasContainerView: NSView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// Shows the secret banner when there's something to say.
private struct BannerHost: View {
    let model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.showsSecretBanner {
                SecretBanner(model: model).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.showsSecretBanner)
    }
}

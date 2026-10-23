import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The video editor's window, a sibling of the screenshot editor's: a unified toolbar with the
/// tools, the title in the middle and Share, Copy and Done at the end; the picture; the
/// transport and timeline under it; and the inspector at the trailing edge.
@MainActor
final class VideoEditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation,
    NSSharingServicePickerToolbarItemDelegate {
    let model: VideoEditorModel
    let stage: VideoStageView
    let timeline: VideoTimelineView
    /// Called once the window has closed.
    var onClose: (() -> Void)?
    /// Share asks for the file: make it, then call back with it (or nil).
    var onShareFile: (@MainActor (@escaping @Sendable (URL?) -> Void) -> Void)?

    private let title: String
    private let timelineScroll = NSScrollView()
    private var inspectorItem: NSSplitViewItem?
    private var inspectorObservation: NSKeyValueObservation?
    private var toolGroup: NSToolbarItemGroup?
    private var cropGroup: NSToolbarItemGroup?
    private var speedItem: NSMenuToolbarItem?
    private var copyItem: NSToolbarItem?
    private var titleField = NSTextField(labelWithString: "")
    private var copyReset: Task<Void, Never>?
    private var shortcutsSheet: NSWindow?

    static let minimumSize = NSSize(width: 960, height: 620)
    static let sizeKey = "videoEditor.windowSize"

    private enum Item {
        static let tools = NSToolbarItem.Identifier("videoEditor.tools")
        static let crop = NSToolbarItem.Identifier("videoEditor.crop")
        static let speed = NSToolbarItem.Identifier("videoEditor.speed")
        static let title = NSToolbarItem.Identifier("videoEditor.title")
        static let frame = NSToolbarItem.Identifier("videoEditor.frame")
        static let share = NSToolbarItem.Identifier("videoEditor.share")
        static let copy = NSToolbarItem.Identifier("videoEditor.copy")
        static let inspector = NSToolbarItem.Identifier("videoEditor.inspector")
        static let done = NSToolbarItem.Identifier("videoEditor.done")
    }

    init(model: VideoEditorModel, title: String) {
        self.model = model
        self.title = title
        stage = VideoStageView(model: model)
        timeline = VideoTimelineView(model: model)
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
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

        let toolbar = NSToolbar(identifier: "videoEditor.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Item.title]
        window.toolbar = toolbar

        window.contentViewController = makeSplit()
        window.initialFirstResponder = timeline
        window.minSize = Self.minimumSize
        sizeWindow(window)
        wire()
        syncToolbar()
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Layout

    private func makeSplit() -> NSSplitViewController {
        let split = NSSplitViewController()
        let mainController = NSViewController()
        mainController.view = makeMain()
        let main = NSSplitViewItem(viewController: mainController)
        main.minimumThickness = 560
        split.addSplitViewItem(main)
        let inspectorView = VideoInspector(model: model) { [weak self] in self?.model.perform(.export) }
        let inspector = NSSplitViewItem(inspectorWithViewController: NSHostingController(rootView: inspectorView))
        inspector.minimumThickness = VideoInspector.width
        inspector.maximumThickness = VideoInspector.width
        inspector.canCollapse = true
        inspector.isCollapsed = !model.showsInspector
        split.addSplitViewItem(inspector)
        inspectorItem = inspector
        inspectorObservation = inspector.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            let collapsed = item.isCollapsed
            MainActor.assumeIsolated {
                guard let self, self.model.showsInspector == collapsed else { return }
                self.model.showsInspector = !collapsed
            }
        }
        return split
    }

    private func makeMain() -> NSView {
        let container = VideoContainerView()
        container.onLayout = { [weak self] in self?.containerDidLayout() }

        stage.translatesAutoresizingMaskIntoConstraints = false
        stage.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        container.addSubview(stage)

        let panel = PanelView()
        panel.wantsLayer = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(panel)

        let transport = hosted(VideoTransportBar(model: model) { [weak self] factor in self?.zoomTimeline(factor) })
        panel.addSubview(transport)
        let headers = hosted(TimelineHeaders(model: model))
        panel.addSubview(headers)

        timeline.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        timeline.onTrimPreview = { [weak self] time in self?.stage.previewSource(time) }
        timelineScroll.documentView = timeline
        timelineScroll.drawsBackground = false
        timelineScroll.hasHorizontalScroller = true
        timelineScroll.hasVerticalScroller = false
        timelineScroll.autohidesScrollers = true
        timelineScroll.scrollerStyle = .overlay
        timelineScroll.verticalScrollElasticity = .none
        timelineScroll.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(timelineScroll)

        let lanes = VideoTimelineView.height(audioTracks: model.info.audioTracks.count)
        let panelHeight: CGFloat = VideoTransportBar.height + lanes
        NSLayoutConstraint.activate([
            stage.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stage.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            stage.bottomAnchor.constraint(equalTo: panel.topAnchor),
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            panel.heightAnchor.constraint(equalToConstant: panelHeight),
            transport.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            transport.topAnchor.constraint(equalTo: panel.topAnchor),
            transport.heightAnchor.constraint(equalToConstant: VideoTransportBar.height),
            headers.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            headers.topAnchor.constraint(equalTo: transport.bottomAnchor),
            headers.widthAnchor.constraint(equalToConstant: TimelineHeaders.width),
            headers.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            timelineScroll.leadingAnchor.constraint(equalTo: headers.trailingAnchor),
            timelineScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            timelineScroll.topAnchor.constraint(equalTo: transport.bottomAnchor),
            timelineScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        let hint = overlay(VideoHintStrip(model: model), in: container)
        let cropBar = overlay(CropBarHost(model: model), in: container)
        let progress = overlay(ExportProgressCapsule(model: model), in: container)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -6),
            cropBar.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            cropBar.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -10),
            progress.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
        ])
        return container
    }

    private func hosted(_ view: some View) -> NSView {
        let host = NSHostingView(rootView: AnyView(view))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        return host
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
        timeline.relayout()
    }

    private func sizeWindow(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var size: NSSize
        if let saved = UserDefaults.standard.string(forKey: Self.sizeKey) {
            size = NSSizeFromString(saved)
        } else {
            size = NSSize(width: 1180, height: 800)
        }
        let maxWidth: CGFloat = (visible.width * 0.92).rounded()
        let maxHeight: CGFloat = (visible.height * 0.92).rounded()
        size.width = min(max(size.width, Self.minimumSize.width), maxWidth)
        size.height = min(max(size.height, Self.minimumSize.height), maxHeight)
        let x: CGFloat = (visible.midX - size.width / 2).rounded()
        let y: CGFloat = (visible.midY - size.height / 2).rounded()
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    // MARK: Wiring

    private func wire() {
        model.onEditChange = { [weak self] old, new in self?.editChanged(from: old, to: new) }
        model.onSelectionChange = { [weak self] in self?.timeline.needsDisplay = true }
        model.onToolChange = { [weak self] in
            guard let self else { return }
            self.stage.cropChanged()
            self.syncToolbar()
            self.timeline.needsDisplay = true
        }
        model.onInspectorChange = { [weak self] in self?.syncInspector() }
        model.onZoomChange = { [weak self] in self?.timeline.relayout() }
        model.onPlayheadChange = { [weak self] in
            guard let self else { return }
            self.timeline.placePlayhead()
            if self.model.isPlaying { self.timeline.keepPlayheadVisible() }
        }
        model.onMediaChange = { [weak self] in self?.timeline.needsDisplay = true }
        model.onLiveEnd = { [weak self] old, new in self?.liveChangeEnded(from: old, to: new) }
        model.playback.onReady = { [weak self] in self?.stage.relayout() }
    }

    private func editChanged(from old: VideoEdit, to new: VideoEdit) {
        timeline.relayout()
        updateTitle()
        syncToolbar()
        let shape = old.clips != new.clips || old.crop != new.crop
        if shape {
            stage.relayout()
            // While a drag goes on, the picture shows stills; the player catches up after.
            if !model.isLiveChanging { model.playback.rebuild(new, fullFrame: model.isCropping, at: model.playhead) }
        } else if old.levels != new.levels || old.fadesSound != new.fadesSound {
            model.playback.updateMix(new)
        }
        if shape || old.levels != new.levels { model.refreshEstimate() }
    }

    /// After a drag that changed the clips: one rebuild, now.
    private func liveChangeEnded(from old: VideoEdit, to new: VideoEdit) {
        guard old.clips != new.clips || old.crop != new.crop else { return }
        model.playback.rebuild(new, fullFrame: model.isCropping, at: model.playhead, delay: .zero)
    }

    private func zoomTimeline(_ factor: CGFloat?) {
        if let factor {
            timeline.zoom(by: factor)
        } else {
            model.timelineZoom = 1
            timeline.relayout()
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.tools, Item.crop, Item.speed, .flexibleSpace, Item.title, .flexibleSpace, Item.frame, Item.share, Item.copy,
         Item.inspector, .space, Item.done]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Item.tools:
            let tools = VideoTool.allCases
            let group = NSToolbarItemGroup(itemIdentifier: identifier,
                                           images: tools.map { EditorWindowController.symbol($0.symbol, $0.title) },
                                           selectionMode: .selectOne, labels: tools.map(\.title), target: self,
                                           action: #selector(toolChosen(_:)))
            group.label = "Tools"
            group.controlRepresentation = .expanded
            group.subitems[0].toolTip = VideoCommand.tooltip(.select)
            group.subitems[1].toolTip = VideoCommand.tooltip(.blade, "Blade: click a clip to cut it")
            toolGroup = group
            return group
        case Item.crop:
            let group = NSToolbarItemGroup(itemIdentifier: identifier, images: [EditorWindowController.symbol("crop", "Crop")],
                                           selectionMode: .selectAny, labels: ["Crop"], target: self,
                                           action: #selector(cropChosen(_:)))
            group.label = "Crop"
            group.controlRepresentation = .expanded
            group.subitems[0].toolTip = VideoCommand.tooltip(.crop)
            cropGroup = group
            return group
        case Item.speed:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.image = EditorWindowController.symbol("gauge.with.dots.needle.67percent", "Speed")
            item.label = "Speed"
            item.toolTip = "Speed of the clip: slower [ or faster ]"
            item.menu = speedMenu()
            item.showsIndicator = true
            speedItem = item
            return item
        case Item.title:
            let item = NSToolbarItem(itemIdentifier: identifier)
            titleField.font = .systemFont(ofSize: 13, weight: .semibold)
            titleField.lineBreakMode = .byTruncatingMiddle
            titleField.alignment = .center
            titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            item.view = titleField
            item.label = "Title"
            item.visibilityPriority = .low
            return item
        case Item.frame:
            return button(identifier, symbol: "photo.badge.plus", label: "Edit Frame",
                          tooltip: VideoCommand.tooltip(.editFrame, "Edit this frame as a picture"),
                          action: #selector(editFramePressed))
        case Item.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.delegate = self
            item.label = "Share"
            item.toolTip = "Share"
            return item
        case Item.copy:
            let item = button(identifier, symbol: "doc.on.doc", label: "Copy", tooltip: VideoCommand.tooltip(.copy),
                              action: #selector(copyPressed))
            item.visibilityPriority = .high
            copyItem = item
            return item
        case Item.inspector:
            return button(identifier, symbol: "sidebar.right", label: "Inspector",
                          tooltip: VideoCommand.tooltip(.showInspector, "Inspector"), action: #selector(inspectorPressed))
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
            item.visibilityPriority = .user
            return item
        default:
            return nil
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier, symbol: String, label: String, tooltip: String,
                        action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = EditorWindowController.symbol(symbol, label)
        item.label = label
        item.toolTip = tooltip
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    private func speedMenu() -> NSMenu {
        let menu = NSMenu(title: "Speed")
        let current = model.targetClip?.speed ?? 1
        for speed in VideoEdit.speeds {
            let title = speed == 1 ? "Normal Speed" : VideoTimelineView.speedTitle(speed)
            menu.addItem(ClosureMenuItem(title, checked: speed == current) { [weak self] in self?.model.setSpeed(speed) })
        }
        return menu
    }

    @objc private func toolChosen(_ sender: NSToolbarItemGroup) {
        let tools = VideoTool.allCases
        guard tools.indices.contains(sender.selectedIndex) else { return }
        if model.isCropping { model.applyCrop() }
        model.tool = tools[sender.selectedIndex]
        window?.makeFirstResponder(timeline)
    }

    @objc private func cropChosen(_ sender: NSToolbarItemGroup) {
        if sender.isSelected(at: 0) { model.beginCrop() } else { model.applyCrop() }
        syncToolbar()
    }

    @objc private func editFramePressed() { perform(.editFrame) }
    @objc private func copyPressed() { perform(.copy) }
    @objc private func donePressed() { perform(.done) }
    @objc private func inspectorPressed() { model.showsInspector.toggle() }

    func syncToolbar() {
        if let toolGroup, let index = VideoTool.allCases.firstIndex(of: model.tool), toolGroup.selectedIndex != index {
            toolGroup.selectedIndex = index
        }
        cropGroup?.setSelected(model.isCropping, at: 0)
        speedItem?.menu = speedMenu()
        let speed = model.targetClip?.speed ?? 1
        speedItem?.image = EditorWindowController.symbol(speed > 1 ? "hare" : (speed < 1 ? "tortoise" : "gauge.with.dots.needle.67percent"),
                                                         "Speed")
        copyItem?.toolTip = model.edit.export.format == .gif ? "Copy GIF (⇧⌘C)" : "Copy Video (⇧⌘C)"
    }

    private func updateTitle() {
        let attributed = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ])
        attributed.append(NSAttributedString(string: "  \(VideoEdit.clock(model.duration))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        titleField.attributedStringValue = attributed
    }

    private func syncInspector() {
        guard let inspectorItem else { return }
        let collapsed = !model.showsInspector
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || window?.isVisible != true {
            inspectorItem.isCollapsed = collapsed
        } else {
            inspectorItem.animator().isCollapsed = collapsed
        }
    }

    /// The Copy button shows a tick for a moment.
    func confirmCopy() {
        copyItem?.image = EditorWindowController.symbol("checkmark", "Copied")
        copyReset?.cancel()
        copyReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.copyItem?.image = EditorWindowController.symbol("doc.on.doc", "Copy")
        }
        announce("Copied")
    }

    func announce(_ text: String) {
        guard let window else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Sharing

    /// Promises the file; it's made only when a way to share is picked.
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        let type: UTType = switch model.edit.export.format {
        case .gif: .gif
        case .mov: .quickTimeMovie
        case .mp4: .mpeg4Movie
        }
        let provider = NSItemProvider()
        let make = onShareFile
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                guard let make else { return completion(nil, false, CocoaError(.fileWriteUnknown)) }
                make { url in
                    if let url { completion(url, false, nil) } else { completion(nil, false, CocoaError(.fileWriteUnknown)) }
                }
            }
            return nil
        }
        return [provider]
    }

    // MARK: Commands

    @objc func performVideoCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let raw = item.representedObject as? String,
              let id = VideoCommand.ID(rawValue: raw) else { return }
        perform(id)
    }

    /// Keys that reach the window from a control in the inspector or the lane headers.
    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    /// ⌘C copies the movie, as Copy Video does; a text field in a sheet copies its own text.
    @objc func copy(_ sender: Any?) {
        perform(.copy)
    }

    /// Keys from the picture or the timeline.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53 {
            escape()
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76, flags.isEmpty {
            if model.isCropping { model.applyCrop() } else { perform(.done) }
            return true
        }
        guard let id = VideoCommand.command(for: event) else { return false }
        if canPerform(id) { perform(id) } else { NSSound.beep() }
        return true
    }

    /// Esc, one step back: leave crop, put the blade down, deselect.
    private func escape() {
        if model.isCropping {
            model.cancelCrop()
        } else if model.progress != nil {
            model.cancelProgress()
        } else if model.tool != .select {
            model.tool = .select
        } else if model.selection != nil {
            model.selection = nil
        } else if model.isPlaying {
            model.pause()
        }
    }

    func perform(_ id: VideoCommand.ID) {
        guard canPerform(id) else { return }
        switch id {
        case .copy: model.perform(.copy)
        case .save: model.perform(.save)
        case .export: model.perform(.export)
        case .editFrame: model.perform(.editFrame)
        case .done: model.perform(.done)
        case .close: window?.performClose(nil)
        case .revert: model.revertToOriginal()
        case .undo: model.undo()
        case .redo: model.redo()
        case .split: model.split()
        case .delete: model.deleteSelection()
        case .trimStart: model.trimStartToPlayhead()
        case .trimEnd: model.trimEndToPlayhead()
        case .deselect: model.selection = nil
        case .playPause: model.togglePlay()
        case .playBackward: model.shuttle(forward: false)
        case .stop: model.pause()
        case .playForward: model.shuttle(forward: true)
        case .previousFrame: model.step(frames: -1)
        case .nextFrame: model.step(frames: 1)
        case .backSecond: model.step(seconds: -1)
        case .forwardSecond: model.step(seconds: 1)
        case .goToStart: model.goToStart()
        case .goToEnd: model.goToEnd()
        case .loop: model.loops.toggle()
        case .select: model.tool = .select
        case .blade: model.tool = .blade
        case .crop: model.isCropping ? model.applyCrop() : model.beginCrop()
        case .slower: stepSpeed(-1)
        case .faster: stepSpeed(1)
        case .normalSpeed: model.setSpeed(1)
        case .fadeSound: model.setFades(!model.edit.fadesSound)
        case .zoomIn: timeline.zoom(by: 1.5)
        case .zoomOut: timeline.zoom(by: 1 / 1.5)
        case .zoomToFit: zoomTimeline(nil)
        case .showInspector: model.showsInspector.toggle()
        case .shortcuts: showShortcuts()
        }
    }

    private func stepSpeed(_ direction: Int) {
        let speeds = VideoEdit.speeds
        let current = model.targetClip?.speed ?? 1
        guard let index = speeds.firstIndex(of: current) else { return }
        let next = index + direction
        guard speeds.indices.contains(next) else { return NSSound.beep() }
        model.setSpeed(speeds[next])
        model.showHint("Speed \(VideoTimelineView.speedTitle(speeds[next]))")
    }

    func canPerform(_ id: VideoCommand.ID) -> Bool {
        let busy = model.progress != nil
        switch id {
        case .copy, .save, .export, .done, .editFrame:
            return !busy
        case .undo: return model.canUndo && !model.isCropping
        case .redo: return model.canRedo && !model.isCropping
        case .revert: return model.isEdited || !model.edit.isUntouched
        case .split, .trimStart, .trimEnd, .slower, .faster, .normalSpeed, .blade:
            return !model.isCropping && model.targetClip != nil
        case .delete: return !model.isCropping && model.edit.clips.count > 1
        case .deselect: return model.selection != nil
        case .playPause, .playBackward, .playForward, .stop, .previousFrame, .nextFrame, .backSecond, .forwardSecond,
             .goToStart, .goToEnd:
            return !model.isCropping
        case .fadeSound: return !model.info.audioTracks.isEmpty
        default: return true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copy(_:)) { return canPerform(.copy) }
        guard menuItem.action == #selector(performVideoCommand(_:)), let raw = menuItem.representedObject as? String,
              let id = VideoCommand.ID(rawValue: raw) else { return true }
        switch id {
        case .loop: menuItem.state = model.loops ? .on : .off
        case .select: menuItem.state = model.tool == .select ? .on : .off
        case .blade: menuItem.state = model.tool == .blade ? .on : .off
        case .crop: menuItem.state = model.isCropping ? .on : .off
        case .fadeSound: menuItem.state = model.edit.fadesSound ? .on : .off
        case .normalSpeed: menuItem.state = (model.targetClip?.speed ?? 1) == 1 ? .on : .off
        case .playPause: menuItem.title = model.isPlaying ? "Pause" : "Play"
        case .showInspector: menuItem.title = model.showsInspector ? "Hide Inspector" : "Show Inspector"
        case .copy: menuItem.title = model.edit.export.format == .gif ? "Copy GIF" : "Copy Video"
        case .undo:
            menuItem.title = model.canUndo ? "Undo \(model.undoManager.undoActionName)" : "Undo"
        case .redo:
            menuItem.title = model.canRedo ? "Redo \(model.undoManager.redoActionName)" : "Redo"
        default: break
        }
        return canPerform(id)
    }

    // MARK: Panels

    private func showShortcuts() {
        guard let window, shortcutsSheet == nil else { return }
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: VideoShortcutsSheet { [weak self] in
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

    // MARK: Window

    func windowDidResize(_ notification: Notification) {
        timeline.relayout()
        guard let window, window.isVisible else { return }
        UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: Self.sizeKey)
    }

    func windowWillClose(_ notification: Notification) {
        if let shortcutsSheet { window?.endSheet(shortcutsSheet) }
        VideoEditorMenus.uninstall()
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        VideoEditorMenus.install()
        if window?.firstResponder === window { window?.makeFirstResponder(timeline) }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Another window's menus take over; a sheet of this window keeps these.
        guard window?.attachedSheet == nil else { return }
        VideoEditorMenus.uninstall()
    }
}

/// Holds the picture, the timeline and their overlays, and says when its size changes.
final class VideoContainerView: NSView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// The timeline's panel: its own colour, with a hairline along the top.
final class PanelView: NSView {
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = VideoEditorStyle.panel.cgColor
        if separator.superlayer == nil { layer?.addSublayer(separator) }
        separator.backgroundColor = NSColor.separatorColor.cgColor
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    private let separator = CALayer()

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}

/// Shows the crop bar while cropping.
private struct CropBarHost: View {
    let model: VideoEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.isCropping { CropBar(model: model).transition(.opacity.combined(with: .move(edge: .bottom))) }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isCropping)
    }
}

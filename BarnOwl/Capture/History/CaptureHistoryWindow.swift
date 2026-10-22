import AppKit
import SwiftUI

/// What history asks of the rest of Capture; each works on a kept capture by its id.
@MainActor
protocol CaptureHistoryHost: AnyObject {
    func openEditor(_ id: UUID)
    func copy(_ id: UUID)
    func pin(_ id: UUID)
    func fileForDragging(_ id: UUID) -> URL?
}

extension CaptureCoordinator: CaptureHistoryHost {}

/// History's window. Previews can make it draw as the key window without being on screen.
final class CaptureHistoryWindow: NSWindow {
    /// For previews only: draw as active (true) or inactive (false) whatever the real state.
    var drawsAsActive: Bool?

    override var isKeyWindow: Bool { drawsAsActive ?? super.isKeyWindow }
    override var isMainWindow: Bool { drawsAsActive ?? super.isMainWindow }

    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    /// ⌘W and ⌘F, even while the menu bar shows an editor's menus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "w" {
                performClose(nil)
                return true
            }
            if key == "f", let controller = windowController as? CaptureHistoryWindowController {
                controller.focusSearch(nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Every kept capture in one window, newest first under its day: search them, edit, copy,
/// pin or drag one out, or remove it from history (Undo brings it back).
@MainActor
final class CaptureHistoryWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSSearchFieldDelegate, NSMenuItemValidation {
    let model: CaptureHistoryModel
    let grid: CaptureHistoryGrid
    /// Called once the window has closed.
    var onClose: (() -> Void)?
    private(set) var isOpen = false
    private weak var host: CaptureHistoryHost?
    private let empty: NSHostingView<HistoryEmptyState>
    /// Undo for removing from history; the window's own.
    private let removals = UndoManager()
    private var searchItem: NSSearchToolbarItem?
    private var observers: [NSObjectProtocol] = []
    private var quitObserver: NSObjectProtocol?
    private var changedIDs: Set<UUID> = []
    private var changeTask: Task<Void, Never>?

    static let frameName = "BarnOwlCaptureHistory"
    private static let searchID = NSToolbarItem.Identifier("captureHistory.search")
    /// Opening or pinning more than this at once is more likely a slip than a plan.
    private static let most = 10

    init(host: CaptureHistoryHost?, root: URL = CaptureLibrary.folder) {
        model = CaptureHistoryModel(root: root)
        grid = CaptureHistoryGrid(model: model)
        empty = NSHostingView(rootView: HistoryEmptyState(model: model))
        let window = CaptureHistoryWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                          backing: .buffered, defer: true)
        super.init(window: window)
        self.host = host
        window.title = "Capture History"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        window.minSize = NSSize(width: 560, height: 420)
        window.backgroundColor = HistoryStyle.background
        window.delegate = self
        let toolbar = NSToolbar(identifier: "captureHistory.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 940, height: 660))
        grid.frame = content.bounds
        grid.autoresizingMask = [.width, .height]
        content.addSubview(grid)
        empty.frame = content.bounds
        empty.autoresizingMask = [.width, .height]
        empty.sizingOptions = []
        empty.isHidden = true
        content.addSubview(empty)
        window.contentView = content
        window.initialFirstResponder = grid.collectionView
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        wire()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func wire() {
        empty.rootView = HistoryEmptyState(model: model) { [weak self] in self?.keepCaptures() }
        model.onChange = { [weak self] in self?.modelChanged() }
        grid.fileForDragging = { [weak self] id in self?.host?.fileForDragging(id) }
        let captures = grid.collectionView
        captures.onOpen = { [weak self] in self?.openSelection(nil) }
        captures.onRemove = { [weak self] in self?.removeFromHistory(nil) }
        captures.onEscape = { [weak self] in self?.escape() }
        captures.onType = { [weak self] text in self?.search(typing: text) }
        captures.menuProvider = { [weak self] in self?.contextMenu() }
        // Removed captures wait for Undo only while Barn Owl runs.
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                CaptureLibrary.forgetRemoved(in: self.model.root)
            }
        }
    }

    // MARK: Showing and closing

    func show() {
        guard let window else { return }
        if isOpen {
            present(window)
            return
        }
        isOpen = true
        // Anything still waiting from before Barn Owl last quit.
        CaptureLibrary.forgetRemoved(in: model.root)
        model.keepDays = CaptureLibrary.keepDays
        startObserving()
        // Opens with its captures in place, not an empty window that fills a moment later.
        model.reload { [weak self, weak window] in
            guard let self, let window, self.isOpen, !window.isVisible else { return }
            self.present(window)
        }
        Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, let window, self.isOpen, !window.isVisible else { return }
            self.present(window)
        }
    }

    private func present(_ window: NSWindow) {
        CaptureHistoryMenu.install()
        OpenPanel.shared.closeAll()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
        stopObserving()
        removals.removeAllActions()
        CaptureLibrary.forgetRemoved(in: model.root)
        searchItem?.searchField.stringValue = ""
        model.query = ""
        model.forget()
        grid.apply(animated: false)
        grid.thumbnails.clear()
        CaptureHistoryMenu.uninstall()
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        CaptureHistoryMenu.install()
        grid.refreshVisible()
        // A file may have been moved or deleted in Finder meanwhile.
        if isOpen, model.isLoaded { model.reload() }
    }

    func windowDidResignKey(_ notification: Notification) {
        grid.refreshVisible()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { removals }

    @objc func undo(_ sender: Any?) { removals.undo() }
    @objc func redo(_ sender: Any?) { removals.redo() }

    // MARK: Keeping in step

    private func startObserving() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: CaptureLibrary.didChange, object: nil, queue: .main) { [weak self] note in
                let id = note.userInfo?["id"] as? UUID
                MainActor.assumeIsolated { self?.libraryChanged(id) }
            },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settingsChanged() }
            },
            // Today becomes Yesterday at midnight.
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.reload() }
            },
        ]
    }

    private func stopObserving() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        changeTask?.cancel()
        changeTask = nil
        changedIDs = []
    }

    /// A capture was kept, changed or let go: a moment later, once its writes have settled,
    /// history reads the library again and redraws the pictures that changed.
    private func libraryChanged(_ id: UUID?) {
        if let id { changedIDs.insert(id) }
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            for id in self.changedIDs { self.grid.thumbnails.refresh(id) }
            self.changedIDs = []
            self.model.reload()
        }
    }

    private func settingsChanged() {
        let days = CaptureLibrary.keepDays
        guard days != model.keepDays else { return }
        model.keepDays = days
        model.reload()
    }

    private func modelChanged() {
        grid.apply()
        let state = model.state
        empty.isHidden = state == .grid || state == .loading
        window?.subtitle = model.subtitle
    }

    /// From the "isn't keeping captures" page.
    private func keepCaptures() {
        UserDefaults.standard.set(30, forKey: PrefKey.captureKeepDays)
    }

    // MARK: Search

    @objc func focusSearch(_ sender: Any?) {
        guard let searchItem else { return }
        searchItem.beginSearchInteraction()
        window?.makeFirstResponder(searchItem.searchField)
    }

    /// Typing in the grid searches for what you type.
    private func search(typing text: String) {
        guard let field = searchItem?.searchField else { return }
        focusSearch(nil)
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func clearSearch() {
        searchItem?.searchField.stringValue = ""
        model.query = ""
    }

    /// Esc clears a search first, then closes.
    private func escape() {
        if model.isSearching {
            clearSearch()
        } else {
            window?.performClose(nil)
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        model.query = sender.stringValue
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        model.query = field.stringValue
    }

    /// ↓ or Return go to the results; Esc clears the search, then closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertNewline(_:)):
            guard model.state == .grid else { return true }
            grid.focus()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if textView.string.isEmpty {
                window?.performClose(nil)
            } else {
                clearSearch()
            }
            return true
        default:
            return false
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.searchID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.searchID else { return nil }
        let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
        item.preferredWidthForSearchField = 200
        item.searchField.placeholderString = "Search"
        item.searchField.delegate = self
        item.searchField.target = self
        item.searchField.action = #selector(searchChanged(_:))
        item.searchField.setAccessibilityHelp("Finds captures by the words in them, their app or their day")
        item.toolTip = "Search the words in your captures, their app or their day"
        searchItem = item
        return item
    }

    // MARK: Actions

    private var selection: [CaptureHistory.Item] {
        grid.selectedIDs.compactMap { model.item($0) }
    }

    @objc func openSelection(_ sender: Any?) {
        for item in selection.prefix(Self.most) { host?.openEditor(item.id) }
    }

    @objc func copy(_ sender: Any?) {
        guard let item = selection.first, selection.count == 1 else { return NSSound.beep() }
        host?.copy(item.id)
    }

    @objc func copyText(_ sender: Any?) {
        let texts = selection.compactMap(\.text)
        guard !texts.isEmpty else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texts.joined(separator: "\n\n"), forType: .string)
    }

    @objc func showInFinder(_ sender: Any?) {
        let files = selection.compactMap(\.savedFile)
        guard !files.isEmpty else { return NSSound.beep() }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    @objc func pinSelection(_ sender: Any?) {
        for item in selection.prefix(Self.most) { host?.pin(item.id) }
    }

    @objc func removeFromHistory(_ sender: Any?) {
        remove(selection.map(\.id))
    }

    /// Takes them out of history in one step, the next one selected; Undo brings them back.
    func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let order = model.days.flatMap { $0.items.map(\.id) }
        let next = CaptureHistory.selection(afterRemoving: Set(ids), from: order)
        let removed = CaptureLibrary.remove(ids, in: model.root)
        guard !removed.isEmpty else { return NSSound.beep() }
        model.drop(Set(removed))
        grid.select(next.map { [$0] } ?? [], scroll: true)
        removals.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.restore(removed) }
        }
        removals.setActionName(removed.count == 1 ? "Remove from History" : "Remove \(removed.count) from History")
    }

    private func restore(_ ids: [UUID]) {
        let back = CaptureLibrary.restore(ids, in: model.root)
        guard !back.isEmpty else { return NSSound.beep() }
        model.reload { [weak self] in self?.grid.select(back, scroll: true) }
        removals.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.remove(back) }
        }
        removals.setActionName(back.count == 1 ? "Remove from History" : "Remove \(back.count) from History")
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let items = selection
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = removals.undoMenuItemTitle
            return removals.canUndo
        case #selector(redo(_:)):
            menuItem.title = removals.redoMenuItemTitle
            return removals.canRedo
        case #selector(copy(_:)): return items.count == 1
        case #selector(copyText(_:)): return items.contains { $0.text != nil }
        case #selector(showInFinder(_:)): return items.contains(where: \.isSaved)
        case #selector(openSelection(_:)), #selector(pinSelection(_:)): return !items.isEmpty
        // Only from the grid: ⌘⌫ in the search field deletes text there.
        case #selector(removeFromHistory(_:)): return !items.isEmpty && grid.isFocused
        default: return true
        }
    }

    /// Right-click: what can be done with the selection.
    private func contextMenu() -> NSMenu? {
        let items = selection
        guard let first = items.first else { return nil }
        let ids = items.map(\.id)
        let menu = NSMenu(title: "Capture")
        let single = items.count == 1
        menu.addItem(ClosureMenuItem(single ? "Edit" : "Edit \(items.count) Captures") { [weak self] in
            for id in ids.prefix(Self.most) { self?.host?.openEditor(id) }
        })
        menu.addItem(.separator())
        if single {
            menu.addItem(ClosureMenuItem("Copy") { [weak self] in self?.host?.copy(first.id) })
        }
        if items.contains(where: { $0.text != nil }) {
            menu.addItem(ClosureMenuItem("Copy Text") { [weak self] in self?.copyText(nil) })
        }
        if items.contains(where: \.isSaved) {
            menu.addItem(ClosureMenuItem("Show in Finder") { [weak self] in self?.showInFinder(nil) })
        }
        menu.addItem(ClosureMenuItem(single ? "Pin to Screen" : "Pin \(items.count) to Screen") { [weak self] in
            for id in ids.prefix(Self.most) { self?.host?.pin(id) }
        })
        menu.addItem(.separator())
        let remove = ClosureMenuItem(single ? "Remove from History" : "Remove \(items.count) from History") { [weak self] in
            self?.remove(ids)
        }
        remove.subtitle = Self.removalNote(items)
        menu.addItem(remove)
        return menu
    }

    /// Says what Remove from History leaves alone, or that there's nothing else.
    nonisolated static func removalNote(_ items: [CaptureHistory.Item]) -> String {
        let saved = items.filter(\.isSaved).count
        if items.count == 1 { return saved == 1 ? "The saved file stays where it is" : "It isn't saved anywhere else" }
        if saved == items.count { return "Their saved files stay where they are" }
        return saved == 0 ? "They aren't saved anywhere else" : "Saved files stay where they are"
    }
}

/// The menu bar while history is in front and no editor is open: Barn Owl, File, Edit and
/// Window. Whatever was there before comes back when history closes.
@MainActor
enum CaptureHistoryMenu {
    private static var menu: NSMenu?
    private static var window: NSMenu?
    private static var previous: NSMenu?

    static func install() {
        // An editor's menus have all of these and more.
        guard !EditorMenus.isInstalled else { return }
        let menu = self.menu ?? make()
        self.menu = menu
        guard NSApp.mainMenu !== menu else { return }
        previous = NSApp.mainMenu
        NSApp.mainMenu = menu
        NSApp.windowsMenu = window
    }

    static func uninstall() {
        guard let menu, NSApp.mainMenu === menu else { return }
        NSApp.mainMenu = previous
        previous = nil
    }

    private static func make() -> NSMenu {
        let main = NSMenu(title: "Main")
        main.addItem(submenuItem(appMenu()))
        main.addItem(submenuItem(fileMenu()))
        main.addItem(submenuItem(editMenu()))
        let window = windowMenu()
        self.window = window
        main.addItem(submenuItem(window))
        return main
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Barn Owl")
        menu.addItem(item("About Barn Owl", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",", modifiers: .command) { EditorMenus.openSettings() })
        menu.addItem(.separator())
        menu.addItem(item("Hide Barn Owl", #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Barn Owl", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        let controller = CaptureHistoryWindowController.self
        menu.addItem(item("Edit", #selector(controller.openSelection(_:)), key: "o"))
        menu.addItem(item("Pin to Screen", #selector(controller.pinSelection(_:)), key: "p", [.command, .option]))
        menu.addItem(item("Show in Finder", #selector(controller.showInFinder(_:)), key: "r", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        let controller = CaptureHistoryWindowController.self
        menu.addItem(item("Undo", #selector(controller.undo(_:)), key: "z"))
        menu.addItem(item("Redo", #selector(controller.redo(_:)), key: "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item("Copy Text", #selector(controller.copyText(_:))))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        menu.addItem(.separator())
        menu.addItem(item("Remove from History", #selector(controller.removeFromHistory(_:)), key: "\u{8}"))
        menu.addItem(.separator())
        menu.addItem(item("Find", #selector(controller.focusSearch(_:)), key: "f"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}

import AppKit
import SwiftUI

/// History's grid: tiles under day headers that stay at the top as you scroll. Arrow keys and
/// clicks select (⌘ and ⇧ for more), Return or a double-click edits, ⌘⌫ removes, and a
/// tile drags out as its file.
@MainActor
final class CaptureHistoryGrid: NSView, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    let model: CaptureHistoryModel
    let thumbnails: HistoryThumbnails
    let collectionView = HistoryCollectionView()
    let scrollView = NSScrollView()
    private var dataSource: NSCollectionViewDiffableDataSource<Date, UUID>?
    private var resting: Task<Void, Never>?

    /// The file to drag out for a capture.
    var fileForDragging: ((UUID) -> URL?)?
    /// A drag may follow (the pointer rests on a tile, or presses one): have its file ready.
    var prepareForDragging: ((UUID) -> Void)?

    init(model: CaptureHistoryModel) {
        self.model = model
        thumbnails = HistoryThumbnails(root: model.root)
        super.init(frame: NSRect(x: 0, y: 0, width: 920, height: 600))
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        let layout = HistoryGridLayout()
        layout.sectionInset = NSEdgeInsets(top: 0, left: HistoryStyle.sideInset, bottom: HistoryStyle.sectionGap,
                                           right: HistoryStyle.sideInset)
        layout.minimumInteritemSpacing = HistoryStyle.spacing
        layout.minimumLineSpacing = HistoryStyle.lineSpacing
        layout.headerReferenceSize = NSSize(width: 0, height: HistoryStyle.headerHeight)
        layout.sectionHeadersPinToVisibleBounds = true
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [HistoryStyle.background]
        collectionView.delegate = self
        collectionView.register(HistoryTileItem.self, forItemWithIdentifier: HistoryTileItem.identifier)
        collectionView.register(HistoryHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: HistoryHeaderView.identifier)
        // Out to other apps as a file; nothing to rearrange inside.
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask([], forLocal: true)
        collectionView.onFocus = { [weak self] in self?.refreshVisible() }
        collectionView.onPoint = { [weak self] path, pressed in self?.pointed(at: path, pressed: pressed) }
        collectionView.setAccessibilityLabel("Captures")

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = HistoryStyle.background
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        let dataSource = NSCollectionViewDiffableDataSource<Date, UUID>(collectionView: collectionView) {
            [weak self] collectionView, indexPath, id in
            let item = collectionView.makeItem(withIdentifier: HistoryTileItem.identifier, for: indexPath)
            self?.configure(item as? HistoryTileItem, id: id)
            return item
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: HistoryHeaderView.identifier,
                                                              for: indexPath) as? HistoryHeaderView
            self?.configure(header, section: indexPath.section)
            return header
        }
        self.dataSource = dataSource
        thumbnails.onLoad = { [weak self] id, image in self?.thumbnailArrived(id, image) }
    }

    // MARK: Showing

    /// Shows the model's days, keeping the same captures selected. One a search hides stays
    /// selected underneath, and is again when the search is cleared.
    func apply(animated: Bool = true) {
        guard let dataSource else { return }
        let selected = selectedIDs
        let wanted = selected + hiddenSelection.filter { !selected.contains($0) }
        var snapshot = NSDiffableDataSourceSnapshot<Date, UUID>()
        for day in model.days {
            snapshot.appendSections([day.start])
            snapshot.appendItems(day.items.map(\.id), toSection: day.start)
        }
        dataSource.apply(snapshot, animatingDifferences: animated && window?.isVisible == true)
        let shown = wanted.filter { dataSource.indexPath(for: $0) != nil }
        let hidden = wanted.filter { dataSource.indexPath(for: $0) == nil && model.item($0) != nil }
        if shown != selected { select(shown, scroll: false) }
        hiddenSelection = hidden
        refreshVisible()
    }

    /// Selected, but hidden by the search.
    private var hiddenSelection: [UUID] = []

    /// The selected captures, in grid order.
    var selectedIDs: [UUID] {
        guard let dataSource else { return [] }
        return collectionView.selectionIndexPaths.sorted().compactMap { dataSource.itemIdentifier(for: $0) }
    }

    func select(_ ids: [UUID], scroll: Bool) {
        guard let dataSource else { return }
        hiddenSelection = []
        let paths = Set(ids.compactMap { dataSource.indexPath(for: $0) })
        collectionView.selectionIndexPaths = paths
        if scroll, let first = paths.min() {
            collectionView.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge)
        }
    }

    /// The grid takes the keyboard, with something selected so the arrows have a start.
    func focus() {
        window?.makeFirstResponder(collectionView)
        if collectionView.selectionIndexPaths.isEmpty, let first = model.days.first?.items.first?.id {
            select([first], scroll: true)
        }
    }

    var isFocused: Bool {
        guard let window else { return false }
        return window.isKeyWindow && window.firstResponder === collectionView
    }

    /// Tiles and headers on screen show what's current: after a change, a picture or focus moving.
    func refreshVisible() {
        guard let dataSource else { return }
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            configure(collectionView.item(at: indexPath) as? HistoryTileItem, id: id)
        }
        let kind = NSCollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            configure(collectionView.supplementaryView(forElementKind: kind, at: indexPath) as? HistoryHeaderView,
                      section: indexPath.section)
        }
    }

    private func configure(_ tile: HistoryTileItem?, id: UUID) {
        guard let tile else { return }
        tile.show(model.item(id), thumbnail: thumbnails.image(id), focused: isFocused)
        tile.onPress = { [weak self] in self?.press(id) }
        tile.onShowMenu = { [weak self, weak tile] in
            guard let self, let tile else { return }
            self.showMenu(for: id, at: tile.view)
        }
        thumbnails.want(id)
    }

    /// VoiceOver's press: selects the capture and edits it.
    private func press(_ id: UUID) {
        select([id], scroll: false)
        collectionView.onOpen?()
    }

    /// VoiceOver's show menu: selects the capture, unless it's selected already, and shows
    /// what can be done with the selection, as a right-click does.
    private func showMenu(for id: UUID, at view: NSView) {
        if !selectedIDs.contains(id) { select([id], scroll: false) }
        guard let menu = collectionView.menuProvider?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
    }

    /// The pointer came to a tile, or pressed one: a drag may follow. Pressed, its file is
    /// made now; pointed at, once the pointer rests there, not for every tile it crosses.
    private func pointed(at path: IndexPath?, pressed: Bool) {
        resting?.cancel()
        guard let path, let id = dataSource?.itemIdentifier(for: path) else { return }
        guard !pressed else {
            prepareForDragging?(id)
            return
        }
        resting = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.prepareForDragging?(id)
        }
    }

    private func configure(_ header: HistoryHeaderView?, section: Int) {
        guard let header, let dataSource else { return }
        let sections = dataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(section), let day = model.days.first(where: { $0.start == sections[section] })
        else { return }
        header.show(title: day.title, count: day.items.count)
    }

    private func thumbnailArrived(_ id: UUID, _ image: NSImage) {
        guard let path = dataSource?.indexPath(for: id), let tile = collectionView.item(at: path) as? HistoryTileItem
        else { return }
        tile.show(thumbnail: image)
    }

    // MARK: NSCollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        tileSize
    }

    var tileSize: NSSize {
        let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : scrollView.contentSize.width
        let tiles = CaptureHistory.tiles(across: width - HistoryStyle.sideInset * 2, minimum: HistoryStyle.minimumTileWidth,
                                         spacing: HistoryStyle.spacing)
        return NSSize(width: tiles.width, height: HistoryStyle.tileHeight(forWidth: tiles.width))
    }

    // MARK: Choosing

    /// You chose something else: what the search hid is let go.
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        hiddenSelection = []
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        hiddenSelection = []
    }

    // MARK: Dragging out

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>,
                        with event: NSEvent) -> Bool {
        fileForDragging != nil
    }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        guard let id = dataSource?.itemIdentifier(for: indexPath), let url = fileForDragging?(id) else { return nil }
        return url as NSURL
    }
}

/// Keeps the tiles filling the width as the window resizes.
final class HistoryGridLayout: NSCollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        if let current = collectionView?.bounds, current.width != newBounds.width { return true }
        return super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}

/// The grid's own keys: Return edits, ⌘⌫ removes (a plain Delete never does, as in Finder),
/// Esc clears the search or closes, and typing a word starts searching for it.
final class HistoryCollectionView: NSCollectionView {
    var onOpen: (() -> Void)?
    var onRemove: (() -> Void)?
    var onEscape: (() -> Void)?
    var onType: ((String) -> Void)?
    /// The grid took or gave up the keyboard.
    var onFocus: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    /// The pointer moved onto a tile (or off them all), or pressed one.
    var onPoint: ((IndexPath?, _ pressed: Bool) -> Void)?
    private var pointing: IndexPath?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        let code = Int(event.keyCode)
        if (code == 36 || code == 76), modifiers.isEmpty {
            onOpen?()
        } else if (code == 51 || code == 117), modifiers == .command {
            onRemove?()
        } else if code == 53 {
            onEscape?()
        } else if modifiers.isEmpty, let text = event.characters, Self.startsSearch(text) {
            onType?(text)
        } else {
            super.keyDown(with: event)
        }
    }

    /// Letters, digits and punctuation; never arrows, Space or other function keys.
    nonisolated static func startsSearch(_ text: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols)
        return !text.isEmpty && text.unicodeScalars.allSatisfy { $0.value < 0xF700 && allowed.contains($0) }
    }

    override func mouseDown(with event: NSEvent) {
        let path = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        // Before the drag starts, inside super.
        if let path, event.clickCount == 1 { onPoint?(path, true) }
        super.mouseDown(with: event)
        if event.clickCount == 2, path != nil { onOpen?() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let path = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        guard path != pointing else { return }
        pointing = path
        onPoint?(path, false)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        pointing = nil
        onPoint?(nil, false)
    }

    /// Right-clicking a tile outside the selection selects it first, as Finder does.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        if !selectionIndexPaths.contains(path) { selectionIndexPaths = [path] }
        return menuProvider?()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        // Once the window says so, so the tiles see the change.
        if became { Task { @MainActor [weak self] in self?.onFocus?() } }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { Task { @MainActor [weak self] in self?.onFocus?() } }
        return resigned
    }
}

/// A tile, drawn by SwiftUI; the grid itself takes every click.
final class HistoryTileItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("captureHistory.tile")
    private let host = NSHostingView(rootView: HistoryTileView())
    private var item: CaptureHistory.Item?
    private var thumbnail: NSImage?
    private var focused = true
    /// Reused for another capture, and not drawn for it yet.
    private var reused = true
    /// VoiceOver's press and show menu, for the capture it shows now.
    var onPress: (() -> Void)? {
        get { (view as? PassThroughView)?.onPress }
        set { (view as? PassThroughView)?.onPress = newValue }
    }
    var onShowMenu: (() -> Void)? {
        get { (view as? PassThroughView)?.onShowMenu }
        set { (view as? PassThroughView)?.onShowMenu = newValue }
    }

    override func loadView() {
        let root = PassThroughView()
        host.sizingOptions = []
        root.addSubview(host)
        root.content = host
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.image)
        view = root
    }

    override var isSelected: Bool {
        didSet { if isSelected != oldValue { render() } }
    }

    func show(_ item: CaptureHistory.Item?, thumbnail: NSImage?, focused: Bool) {
        guard reused || item != self.item || thumbnail !== self.thumbnail || focused != self.focused else { return }
        reused = false
        self.item = item
        self.thumbnail = thumbnail
        self.focused = focused
        render()
    }

    func show(thumbnail: NSImage) {
        self.thumbnail = thumbnail
        render()
    }

    /// The grid shows the next capture straight after; drawing nothing in between keeps
    /// scrolling from flickering.
    override func prepareForReuse() {
        super.prepareForReuse()
        item = nil
        thumbnail = nil
        reused = true
    }

    private func render() {
        host.rootView = HistoryTileView(item: item, thumbnail: thumbnail, selected: isSelected, focused: focused)
        view.setAccessibilitySelected(isSelected)
        guard let item else { return }
        var words = [item.date.formatted(date: .omitted, time: .shortened), item.subtitle]
        if let duration = item.media.duration {
            words.append("\(item.media.isGIF ? "GIF" : "recording"), \(RecordingTime.text(duration))")
        }
        if item.isEdited { words.append("marked up") }
        if item.isSaved, let file = item.entry.fileURL { words.append("saved in \(file.deletingLastPathComponent().lastPathComponent)") }
        view.setAccessibilityLabel(words.joined(separator: ", "))
        view.toolTip = Self.tooltip(item)
    }

    /// "Marked up · Saved in Screenshots", or nothing.
    static func tooltip(_ item: CaptureHistory.Item) -> String? {
        var parts: [String] = []
        if item.isEdited { parts.append("Marked up") }
        if item.isSaved, let file = item.entry.fileURL {
            parts.append("Saved in \(file.deletingLastPathComponent().lastPathComponent)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Dragging shows the picture itself, where it sits on the tile.
    override var draggingImageComponents: [NSDraggingImageComponent] {
        guard let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 else { return super.draggingImageComponents }
        let box = NSRect(x: 0, y: HistoryStyle.captionHeight, width: view.bounds.width,
                         height: view.bounds.height - HistoryStyle.captionHeight).insetBy(dx: 12, dy: 12)
        let scale = min(box.width / thumbnail.size.width, box.height / thumbnail.size.height)
        let size = NSSize(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale)
        let component = NSDraggingImageComponent(key: .icon)
        component.contents = thumbnail
        component.frame = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                                 width: size.width, height: size.height)
        return [component]
    }
}

/// A day's name above its tiles.
final class HistoryHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("captureHistory.header")
    private let host = NSHostingView(rootView: HistoryDayHeaderView())

    override init(frame: NSRect) {
        super.init(frame: frame)
        host.sizingOptions = []
        addSubview(host)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(title: String, count: Int) {
        host.rootView = HistoryDayHeaderView(title: title, count: count)
        setAccessibilityLabel("\(title), \(CaptureHistoryModel.count(count))")
    }
}

/// Holds a SwiftUI view, but leaves every click to the grid underneath; VoiceOver can still
/// press it (edit) or ask for its menu.
private final class PassThroughView: NSView {
    weak var content: NSView?
    var onPress: (() -> Void)?
    var onShowMenu: (() -> Void)?

    override func layout() {
        super.layout()
        content?.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let onShowMenu else { return false }
        onShowMenu()
        return true
    }
}

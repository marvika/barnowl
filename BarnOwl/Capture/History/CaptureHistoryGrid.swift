import AppKit
import SwiftUI

/// History's grid: tiles under day headers that stay at the top as you scroll. Arrow keys and
/// clicks select (⌘ and ⇧ for more), Return or a double-click edits, Delete removes, and a
/// tile drags out as its file.
@MainActor
final class CaptureHistoryGrid: NSView, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    let model: CaptureHistoryModel
    let thumbnails: HistoryThumbnails
    let collectionView = HistoryCollectionView()
    let scrollView = NSScrollView()
    private var dataSource: NSCollectionViewDiffableDataSource<Date, UUID>?

    /// The file to drag out for a capture.
    var fileForDragging: ((UUID) -> URL?)?

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

    /// Shows the model's days, keeping the same captures selected.
    func apply(animated: Bool = true) {
        guard let dataSource else { return }
        let selected = selectedIDs
        var snapshot = NSDiffableDataSourceSnapshot<Date, UUID>()
        for day in model.days {
            snapshot.appendSections([day.start])
            snapshot.appendItems(day.items.map(\.id), toSection: day.start)
        }
        dataSource.apply(snapshot, animatingDifferences: animated && window?.isVisible == true)
        let still = selected.filter { dataSource.indexPath(for: $0) != nil }
        if still != selected { select(still, scroll: false) }
        refreshVisible()
    }

    /// The selected captures, in grid order.
    var selectedIDs: [UUID] {
        guard let dataSource else { return [] }
        return collectionView.selectionIndexPaths.sorted().compactMap { dataSource.itemIdentifier(for: $0) }
    }

    func select(_ ids: [UUID], scroll: Bool) {
        guard let dataSource else { return }
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
        thumbnails.want(id)
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

/// The grid's own keys: Return edits, Delete removes, Esc clears the search or closes, and
/// typing a word starts searching for it.
final class HistoryCollectionView: NSCollectionView {
    var onOpen: (() -> Void)?
    var onRemove: (() -> Void)?
    var onEscape: (() -> Void)?
    var onType: ((String) -> Void)?
    /// The grid took or gave up the keyboard.
    var onFocus: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        let code = Int(event.keyCode)
        if (code == 36 || code == 76), modifiers.isEmpty {
            onOpen?()
        } else if (code == 51 || code == 117), modifiers.isEmpty || modifiers == .command {
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
        super.mouseDown(with: event)
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil { onOpen?() }
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
        guard item != self.item || thumbnail !== self.thumbnail || focused != self.focused else { return }
        self.item = item
        self.thumbnail = thumbnail
        self.focused = focused
        render()
    }

    func show(thumbnail: NSImage) {
        self.thumbnail = thumbnail
        render()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        item = nil
        thumbnail = nil
        render()
    }

    private func render() {
        host.rootView = HistoryTileView(item: item, thumbnail: thumbnail, selected: isSelected, focused: focused)
        guard let item else { return }
        var words = [item.date.formatted(date: .omitted, time: .shortened), item.subtitle]
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

/// Holds a SwiftUI view, but leaves every click to the grid underneath.
private final class PassThroughView: NSView {
    weak var content: NSView?

    override func layout() {
        super.layout()
        content?.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import AppKit
import SwiftUI

/// The small cards in a corner of the screen that show what was just caught.
/// They never take the keyboard: click one to edit it, drag it into any app,
/// or point at it for Copy, Save, Pin and Edit.
@MainActor
@Observable
final class CaptureCards {
    struct Card: Identifiable {
        let id: UUID
        var thumbnail: NSImage
        /// A picture, or a recording with its length.
        var media = CaptureMedia.image
        var status: String
        /// Whether it's kept somewhere (copied or saved); otherwise the card is all there is.
        var kept: Bool
        /// Secrets found in it, offered for hiding, and what the first one is.
        var secrets = 0
        var secretTitle = ""
        var undo: (() -> Void)?
        /// A second choice beside the status, like Keep as Video while a GIF is made.
        var link: CardLink?
    }

    struct CardLink {
        let title: String
        let action: () -> Void
    }

    /// Newest last, at the bottom of the stack.
    private(set) var cards: [Card] = []
    var hovered: UUID? {
        // Pointing at a card may lead to a drag: have its file ready.
        didSet { if let hovered, hovered != oldValue { coordinator?.prepareDragFile(hovered) } }
    }
    @ObservationIgnored private weak var coordinator: CaptureCoordinator?
    @ObservationIgnored private var panel: CardPanel?
    @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]
    static let width: CGFloat = 236
    private static let shown = 3

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
    }

    var corner: CardCorner { Preferences.captureCardCorner }

    func add(_ capture: Capture, status: String, kept: Bool? = nil) {
        let small = CaptureStore.thumbnail(capture.image, width: Self.width * 2)
        let thumbnail = NSImage(cgImage: small, size: capture.pointSize)
        let kept = kept ?? (status != coordinator?.status(copied: false, saved: false))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            cards.append(Card(id: capture.id, thumbnail: thumbnail, media: capture.media, status: status, kept: kept))
        }
        while cards.count > Self.shown { remove(cards[0].id) }
        showPanel()
        scheduleClose(capture.id)
    }

    func update(_ id: UUID, status: String, kept: Bool) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let wasKept = cards[index].kept
        cards[index].status = status
        cards[index].kept = kept
        // Kept somewhere now, so it can go in its own time.
        if kept, !wasKept { scheduleClose(id) }
    }

    func has(_ id: UUID) -> Bool { cards.contains { $0.id == id } }

    func update(_ id: UUID, link: CardLink?) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].link = link
    }

    /// A new picture (after hiding secrets), with an Undo for a few seconds.
    func update(_ id: UUID, image: CGImage, status: String, undo: (() -> Void)?) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let small = CaptureStore.thumbnail(image, width: Self.width * 2)
        cards[index].thumbnail = NSImage(cgImage: small, size: cards[index].thumbnail.size)
        cards[index].status = status
        cards[index].secrets = 0
        cards[index].undo = undo
        guard undo != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let index = self.cards.firstIndex(where: { $0.id == id }) else { return }
            self.cards[index].undo = nil
        }
    }

    /// Something secret was found: the card offers to hide it.
    func offerToHide(_ id: UUID, count: Int, title: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.smooth(duration: 0.25)) {
            cards[index].secrets = count
            cards[index].secretTitle = title
        }
        place()
    }

    func remove(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = nil
        withAnimation(.smooth(duration: 0.25)) { cards.removeAll { $0.id == id } }
        if cards.isEmpty {
            Task { [weak self] in
                // Let the card slide out first.
                try? await Task.sleep(for: .milliseconds(300))
                if self?.cards.isEmpty == true { self?.panel?.orderOut(nil) }
            }
        } else {
            place()
        }
    }

    // MARK: Actions

    func copy(_ id: UUID) { coordinator?.copy(id) }
    func save(_ id: UUID) { coordinator?.save(id) }
    func edit(_ id: UUID) { coordinator?.openEditor(id) }
    func pin(_ id: UUID) {
        coordinator?.pin(id)
        remove(id)
    }
    func hide(_ id: UUID) { coordinator?.hideSecrets(id) }
    func makeGIF(_ id: UUID) { coordinator?.makeGIF(id) }
    func copyText(_ id: UUID) { coordinator?.copyText(id) }
    func hasText(_ id: UUID) -> Bool { coordinator?.hasText(id) ?? false }
    func file(_ id: UUID) -> URL? { coordinator?.fileForDragging(id) }
    func isSaved(_ id: UUID) -> Bool { coordinator?.isSaved(id) ?? false }

    // MARK: The panel

    private func showPanel() {
        if panel == nil {
            panel = CardPanel(rootView: CardStack(cards: self))
        }
        place()
        panel?.orderFrontRegardless()
    }

    /// After SwiftUI has laid out the new stack.
    private func place() {
        Task { @MainActor [weak self] in self?.placeNow() }
    }

    private func placeNow() {
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let size = panel.contentView?.fittingSize ?? .zero
        let visible = screen.visibleFrame
        let x = corner == .bottomLeft ? visible.minX + 4 : visible.maxX - size.width - 4
        panel.setFrame(CGRect(x: x, y: visible.minY + 4, width: size.width, height: size.height), display: true)
    }

    /// Closes the card after a while, but never while you're pointing at it,
    /// and never one that's neither saved nor copied.
    private func scheduleClose(_ id: UUID) {
        let seconds = Preferences.captureCardSeconds
        guard seconds > 0 else { return }
        timers[id]?.cancel()
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            while let self, !Task.isCancelled {
                // A card offering to hide a secret waits for your answer.
                let card = self.cards.first { $0.id == id }
                guard self.hovered == id || (card?.secrets ?? 0) > 0 else {
                    if card?.kept == true { self.remove(id) }
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Floats in a corner and never takes the keyboard from the app you're in.
final class CardPanel: NSPanel {
    init<Content: View>(rootView: Content) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = FirstMouseHostingView(rootView: rootView)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
}

/// Buttons answer the first click, even though the panel is never key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CardStack: View {
    let cards: CaptureCards

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cards.cards) { card in
                CaptureCardView(card: card, cards: cards)
                    .transition(.asymmetric(insertion: .move(edge: cards.corner == .bottomLeft ? .leading : .trailing)
                                                .combined(with: .scale(scale: 0.92)).combined(with: .opacity),
                                            removal: .move(edge: cards.corner == .bottomLeft ? .leading : .trailing)
                                                .combined(with: .opacity)))
            }
        }
        .padding(16)
        .frame(width: CaptureCards.width + 32)
    }
}

struct CaptureCardView: View {
    let card: CaptureCards.Card
    let cards: CaptureCards
    @State private var hovering: Bool

    /// `hovering`: drawn as if pointed at, for previews.
    init(card: CaptureCards.Card, cards: CaptureCards, hovering: Bool = false) {
        self.card = card
        self.cards = cards
        _hovering = State(initialValue: hovering)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            statusRow
            if card.secrets > 0 { secretsRow }
        }
        .padding(8)
        .frame(width: CaptureCards.width)
        .background {
            // The material alone turns grey over a white window; some of the window's own
            // colour keeps the text crisp on anything.
            RoundedRectangle(cornerRadius: 16).fill(.thickMaterial)
                .overlay { RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor).opacity(0.6)) }
        }
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .overlay(alignment: .topLeading) {
            if hovering {
                Button { cards.remove(card.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.black.opacity(0.55), in: .circle)
                        .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5) }
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .help("Close")
                .accessibilityLabel("Close")
                .transition(.opacity)
            }
        }
        .onHover { inside in
            withAnimation(.smooth(duration: 0.15)) { hovering = inside }
            cards.hovered = inside ? card.id : (cards.hovered == card.id ? nil : cards.hovered)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.media.isMovie ? "Recording" : "Capture"). \(card.status)")
        .accessibilityAction(named: "Edit") { cards.edit(card.id) }
        .accessibilityAction(named: "Copy") { cards.copy(card.id) }
    }

    private var thumbnail: some View {
        Image(nsImage: card.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 140)
            .clipShape(.rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
            .overlay {
                if hovering {
                    RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.2)).allowsHitTesting(false)
                }
            }
            .overlay {
                // Click to edit; drag to take the file anywhere.
                CardDragArea(url: { cards.file(card.id) }, image: card.thumbnail,
                             click: { cards.edit(card.id) }, dropped: { cards.remove(card.id) })
            }
            .overlay(alignment: .topTrailing) {
                if card.media.isMovie && !hovering { MovieBadge(media: card.media).padding(6).transition(.opacity) }
            }
            .overlay(alignment: .bottom) {
                if hovering { actions.transition(.opacity) }
            }
            .help("Click to edit · drag into any app")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if card.media.isMovie { movieActions } else { pictureActions }
        }
        .padding(.bottom, 8)
    }

    /// A recording: copy or save the file, make a GIF of it, or edit it.
    @ViewBuilder private var movieActions: some View {
        IconButton(symbol: "doc.on.doc", label: "Copy") { cards.copy(card.id) }
        IconButton(symbol: cards.isSaved(card.id) ? "folder" : "square.and.arrow.down",
                   label: cards.isSaved(card.id) ? "Show in Finder" : "Save") { cards.save(card.id) }
        if !card.media.isGIF {
            IconButton(symbol: "photo.stack", label: "Make GIF") { cards.makeGIF(card.id) }
        }
        IconButton(symbol: "pencil", label: "Edit", prominent: true) { cards.edit(card.id) }
    }

    @ViewBuilder private var pictureActions: some View {
            IconButton(symbol: "doc.on.doc", label: "Copy") { cards.copy(card.id) }
            if cards.hasText(card.id) {
                IconButton(symbol: "text.viewfinder", label: "Copy Text") { cards.copyText(card.id) }
            }
            IconButton(symbol: cards.isSaved(card.id) ? "folder" : "square.and.arrow.down",
                       label: cards.isSaved(card.id) ? "Show in Finder" : "Save") { cards.save(card.id) }
            IconButton(symbol: "pin", label: "Pin") { cards.pin(card.id) }
            IconButton(symbol: "pencil", label: "Edit", prominent: true) { cards.edit(card.id) }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if card.status.hasSuffix("…") {
                // Still working: saving, making a GIF, reading the text.
                ProgressView().controlSize(.mini).frame(width: 11, height: 11)
            } else {
                Image(systemName: card.kept ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(card.kept ? Color.green : Color.orange)
                    .font(.system(size: 11))
            }
            Text(card.status).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let undo = card.undo {
                Button("Undo", action: undo).buttonStyle(.link).font(.caption.weight(.semibold))
            }
            if let link = card.link {
                Button(link.title, action: link.action).buttonStyle(.link).font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 4)
    }

    private var secretsRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.trianglebadge.exclamationmark").foregroundStyle(Brand.amber).font(.system(size: 11))
            Text("\(card.secretTitle) visible")
                .font(.system(size: 11, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { cards.hide(card.id) } label: {
                Text("Hide").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.indigoDeep)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Brand.amber, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            .help("Hide them in the copy and the saved file")
        }
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// A round button with a symbol, for the card's hover row.
private struct IconButton: View {
    let symbol: String
    let label: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(prominent ? AnyShapeStyle(Brand.lavenderFill) : AnyShapeStyle(.black.opacity(hovering ? 0.6 : 0.45)),
                            in: .circle)
                .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
                .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The thumbnail's click and drag: a click opens the editor, a drag carries
/// the file and closes the card once it's dropped somewhere.
private struct CardDragArea: NSViewRepresentable {
    let url: () -> URL?
    let image: NSImage
    let click: () -> Void
    let dropped: () -> Void

    func makeNSView(context: Context) -> CardDragView {
        CardDragView(url: url, image: image, click: click, dropped: dropped)
    }

    func updateNSView(_ view: CardDragView, context: Context) {
        view.url = url
        view.image = image
        view.click = click
        view.dropped = dropped
    }
}

final class CardDragView: NSView, NSDraggingSource {
    var url: () -> URL?
    var image: NSImage
    var click: () -> Void
    var dropped: () -> Void
    private var downEvent: NSEvent?
    private var dragging = false

    init(url: @escaping () -> URL?, image: NSImage, click: @escaping () -> Void, dropped: @escaping () -> Void) {
        self.url = url
        self.image = image
        self.click = click
        self.dropped = dropped
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, !dragging else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 4, let file = url() else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let width = min(bounds.width, 160)
        let size = NSSize(width: width, height: width * image.size.height / max(image.size.width, 1))
        let origin = convert(start, from: nil)
        item.setDraggingFrame(CGRect(x: origin.x - size.width / 2, y: origin.y - size.height / 2,
                                     width: size.width, height: size.height), contents: image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downEvent = nil }
        if !dragging { click() }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        if operation != [] { dropped() }
    }
}

import AppKit
import SwiftUI

/// The small cards in a corner of the screen that show what was just caught.
@MainActor
@Observable
final class CaptureCards {
    struct Card: Identifiable {
        let id: UUID
        let thumbnail: NSImage
        var status: String
    }

    /// Newest last, at the bottom of the stack.
    private(set) var cards: [Card] = []
    var hovered: UUID?
    @ObservationIgnored private weak var coordinator: CaptureCoordinator?
    @ObservationIgnored private var panel: CardPanel?
    @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]
    static let width: CGFloat = 228
    private static let shown = 3

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
    }

    func add(_ capture: Capture, status: String) {
        let thumbnail = NSImage(cgImage: capture.image, size: capture.pointSize)
        cards.append(Card(id: capture.id, thumbnail: thumbnail, status: status))
        while cards.count > Self.shown { remove(cards[0].id) }
        showPanel()
        scheduleClose(capture.id)
    }

    func update(_ id: UUID, status: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].status = status
    }

    func remove(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = nil
        withAnimation(.smooth(duration: 0.25)) { cards.removeAll { $0.id == id } }
        if cards.isEmpty {
            panel?.orderOut(nil)
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
    func file(_ id: UUID) -> URL? { coordinator?.fileForDragging(id) }
    func isSaved(_ id: UUID) -> Bool { coordinator?.capture(id)?.fileURL != nil }

    /// Keys act on the newest card, without having to point at it.
    func handleKey(_ event: NSEvent) -> Bool {
        guard let newest = cards.last?.id else { return false }
        let command = event.modifierFlags.contains(.command)
        switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased(), command) {
        case (53, _, _), (51, _, _): remove(newest)
        case (36, _, _), (76, _, _): edit(newest)
        case (_, "c", true): copy(newest)
        case (_, "s", true): save(newest)
        case (_, "p", false): pin(newest)
        default: return false
        }
        return true
    }

    // MARK: The panel

    private func showPanel() {
        if panel == nil {
            let panel = CardPanel(rootView: CardStack(cards: self))
            panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
            self.panel = panel
        }
        place()
        panel?.orderFrontRegardless()
        // The keys work straight away; clicking anywhere else gives them back.
        panel?.makeKey()
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
        let x = Preferences.captureCardCorner == .bottomLeft ? visible.minX + 8 : visible.maxX - size.width - 8
        panel.setFrame(CGRect(x: x, y: visible.minY + 8, width: size.width, height: size.height), display: true)
    }

    /// Closes the card after a while, but never while you're pointing at it,
    /// and never one that's neither saved nor copied.
    private func scheduleClose(_ id: UUID) {
        let seconds = Preferences.captureCardSeconds
        guard seconds > 0 else { return }
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            while let self, !Task.isCancelled {
                guard self.hovered == id else {
                    let kept = self.isSaved(id) || Preferences.captureCopies
                    if kept { self.remove(id) }
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// The panel holding the cards: floats, takes keys, never activates Barn Owl.
final class CardPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    init<Content: View>(rootView: Content) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKey?(event) == true || super.performKeyEquivalent(with: event)
    }
}

private struct CardStack: View {
    let cards: CaptureCards

    var body: some View {
        VStack(spacing: 8) {
            ForEach(cards.cards) { card in
                CaptureCardView(card: card, cards: cards)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(width: CaptureCards.width + 24)
        .animation(.smooth(duration: 0.3), value: cards.cards.map(\.id))
    }
}

private struct CaptureCardView: View {
    let card: CaptureCards.Card
    let cards: CaptureCards
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(card.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .frame(width: CaptureCards.width)
        // Tinted like Barn Owl's panels, so text behind doesn't show through.
        .glassEffect(.regular.tint(Brand.indigoDeep.opacity(0.62)), in: .rect(cornerRadius: 16))
        .opacity(hovering ? 1 : 0.96)
        .overlay(alignment: .topLeading) {
            if hovering {
                Button { cards.remove(card.id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .help("Close (Esc)")
                .accessibilityLabel("Close")
            }
        }
        .onHover { inside in
            withAnimation(.smooth(duration: 0.15)) { hovering = inside }
            cards.hovered = inside ? card.id : (cards.hovered == card.id ? nil : cards.hovered)
        }
        .onDrag {
            guard let url = cards.file(card.id) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture. \(card.status)")
    }

    private var thumbnail: some View {
        Image(nsImage: card.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 132)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                if hovering { actions.transition(.opacity) }
            }
            .onTapGesture(count: 2) { cards.edit(card.id) }
    }

    private var actions: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.45))
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    CardButton(title: "Copy", key: "⌘C") { cards.copy(card.id) }
                    CardButton(title: cards.isSaved(card.id) ? "Show" : "Save", key: "⌘S") { cards.save(card.id) }
                }
                GridRow {
                    CardButton(title: "Edit", key: "↩", prominent: true) { cards.edit(card.id) }
                    CardButton(title: "Pin", key: "P") { cards.pin(card.id) }
                }
            }
            .padding(10)
        }
    }
}

private struct CardButton: View {
    let title: String
    let key: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(key).font(.system(size: 10, weight: .semibold, design: .monospaced)).opacity(0.65)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Color(red: 0.16, green: 0.09, blue: 0.02) : .white)
            .background(prominent ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.white.opacity(0.16)),
                        in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .help("\(title) (\(key))")
    }
}

import AppKit

/// A capture pinned above your windows, for comparing or copying from.
/// Drag it anywhere, scroll to zoom, double-click to edit.
@MainActor
final class CapturePin {
    /// Pins belong in captures; Barn Owl's other windows are left out by this title.
    static let windowTitle = "BarnOwlPin"

    var onEdit: (() -> Void)?
    var onClose: (() -> Void)?
    private let image: CGImage
    private let scale: CGFloat
    private let panel: PinPanel
    private var zoom: CGFloat = 1

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        panel = PinPanel()
        panel.title = Self.windowTitle
        let view = PinView(image: image)
        view.pin = self
        panel.contentView = view
    }

    func show() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        // As big as it was on screen, but never more than most of the screen.
        let natural = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, visible.width * 0.6 / natural.width, visible.height * 0.6 / natural.height)
        zoom = fit
        let size = CGSize(width: natural.width * fit, height: natural.height * fit)
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
        onClose?()
    }

    func edit() { onEdit?() }

    func copy() { CaptureStore.copy(image, scale: scale) }

    func setOpacity(_ value: CGFloat) { panel.alphaValue = value }

    /// Zooms around the pointer, between a quarter and four times its size.
    func zoom(by delta: CGFloat, around point: CGPoint) {
        let natural = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let next = min(4, max(0.25, zoom * (1 + delta)))
        guard next != zoom else { return }
        let frame = panel.frame
        let size = CGSize(width: natural.width * next, height: natural.height * next)
        let ratioX = (point.x - frame.minX) / frame.width, ratioY = (point.y - frame.minY) / frame.height
        let origin = CGPoint(x: point.x - size.width * ratioX, y: point.y - size.height * ratioY)
        zoom = next
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

private final class PinPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

private final class PinView: NSView {
    weak var pin: CapturePin?
    private let closeButton: NSButton

    init(image: CGImage) {
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
                               target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(closePin)
        closeButton.isHidden = true
        closeButton.toolTip = "Close (Esc)"
        addSubview(closeButton)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        setAccessibilityLabel("Pinned capture")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        closeButton.frame = CGRect(x: 6, y: bounds.height - 26, width: 20, height: 20)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { pin?.edit() } else { window?.performDrag(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = (event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20)
        pin?.zoom(by: delta, around: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        pin?.zoom(by: event.magnification, around: NSEvent.mouseLocation)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { closePin() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" else {
            return super.performKeyEquivalent(with: event)
        }
        pin?.copy()
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyPin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Edit…", action: #selector(editPin), keyEquivalent: "").target = self
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for percent in [100, 80, 60, 40] {
            let item = choices.addItem(withTitle: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.state = Int((window?.alphaValue ?? 1) * 100 + 0.5) == percent ? .on : .off
        }
        opacity.submenu = choices
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "").target = self
        return menu
    }

    @objc private func closePin() { pin?.close() }
    @objc private func copyPin() { pin?.copy() }
    @objc private func editPin() { pin?.edit() }
    @objc private func setOpacity(_ sender: NSMenuItem) { pin?.setOpacity(CGFloat(sender.tag) / 100) }
}

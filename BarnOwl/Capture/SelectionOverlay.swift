import AppKit
import SwiftUI

enum CaptureMode: String, CaseIterable, Identifiable {
    case area, window, screen

    var id: String { rawValue }
    var title: String {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .screen: "Screen"
        }
    }
    var key: String {
        switch self {
        case .area: "A"
        case .window: "W"
        case .screen: "F"
        }
    }
    var hint: String {
        switch self {
        case .area: "Drag to capture · click a window · Space for windows · ⇧ square · ⌥ from the centre · Esc cancels"
        case .window: "Click a window · Space to drag an area · Esc cancels"
        case .screen: "Click a screen · Esc cancels"
        }
    }
}

enum SelectionResult {
    /// A rect in AppKit screen coordinates, on one display.
    case area(CGRect, DisplaySnapshot)
    case window(WindowTarget, DisplaySnapshot)
    case screen(DisplaySnapshot)
    case cancelled
}

/// The frozen screens you select on: one window per display, each showing
/// the picture taken when you pressed the shortcut.
@MainActor
final class SelectionOverlay {
    private var windows: [OverlayWindow] = []
    private var mode: CaptureMode
    private let completion: (SelectionResult) -> Void
    private var finished = false
    private var previousApp: NSRunningApplication?

    init(snapshots: [DisplaySnapshot], targets: [WindowTarget], mode: CaptureMode,
         completion: @escaping (SelectionResult) -> Void) {
        self.mode = mode
        self.completion = completion
        for snapshot in snapshots {
            let window = OverlayWindow(snapshot: snapshot, targets: targets, mode: mode)
            window.selection.onResult = { [weak self] in self?.finish($0) }
            window.selection.onMode = { [weak self] in self?.setMode($0) }
            windows.append(window)
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        // Keys and the crosshair only reach an active app.
        NSApp.activate()
        let pointer = NSEvent.mouseLocation
        for window in windows {
            window.orderFrontRegardless()
            if window.frame.contains(pointer) { window.makeKey() }
        }
        if !windows.contains(where: \.isKeyWindow) { windows.first?.makeKey() }
        windows.forEach { $0.selection.pointerMoved(to: pointer) }
    }

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
        windows.forEach { $0.selection.mode = mode }
    }

    func finish(_ result: SelectionResult) {
        guard !finished else { return }
        finished = true
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = []
        // Back to the app you were in, unless the capture opens the editor.
        if case .cancelled = result { previousApp?.activate() } else if !Preferences.captureOpensEditor { previousApp?.activate() }
        completion(result)
    }
}

final class OverlayWindow: NSPanel {
    let selection: SelectionView

    init(snapshot: DisplaySnapshot, targets: [WindowTarget], mode: CaptureMode) {
        selection = SelectionView(snapshot: snapshot, targets: targets, mode: mode)
        super.init(contentRect: snapshot.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false
        // Over the menu bar and the Dock.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        acceptsMouseMovedEvents = true
        contentView = selection
        setFrame(snapshot.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// Draws the frozen screen, the dimming, the selection and the loupe, and
/// turns mouse and keys into a result.
final class SelectionView: NSView {
    var onResult: ((SelectionResult) -> Void)?
    var onMode: ((CaptureMode) -> Void)?
    var mode: CaptureMode {
        didSet { modeChanged() }
    }

    private let snapshot: DisplaySnapshot
    private let targets: [WindowTarget]
    private let dim = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let label = CATextLayer()
    private let labelBackground = CALayer()
    private let loupe = Loupe()
    private var bar: NSHostingView<CaptureModeBar>?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var lastPoint: CGPoint = .zero
    private var spaceHeld = false
    private var selection: CGRect?
    private var hovered: WindowTarget?

    init(snapshot: DisplaySnapshot, targets: [WindowTarget], mode: CaptureMode) {
        self.snapshot = snapshot
        self.targets = targets
        self.mode = mode
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        wantsLayer = true
        guard let layer else { return }
        layer.contents = snapshot.image
        layer.contentsGravity = .resize
        dim.fillRule = .evenOdd
        dim.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        outline.fillColor = nil
        outline.strokeColor = NSColor.white.cgColor
        outline.lineWidth = 1
        labelBackground.backgroundColor = NSColor(white: 0.08, alpha: 0.72).cgColor
        labelBackground.cornerRadius = 7
        label.fontSize = 12
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.foregroundColor = NSColor.white.cgColor
        label.alignmentMode = .center
        label.contentsScale = snapshot.scale
        labelBackground.addSublayer(label)
        for sublayer in [dim, outline, labelBackground, loupe.layer] { layer.addSublayer(sublayer) }
        loupe.setImage(snapshot.image, scale: snapshot.scale)
        let bar = NSHostingView(rootView: CaptureModeBar(mode: mode) { [weak self] in self?.onMode?($0) })
        addSubview(bar)
        self.bar = bar
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate,
                                                              .mouseEnteredAndExited],
                                       owner: self))
    }

    override func layout() {
        super.layout()
        guard let bar else { return }
        let size = bar.fittingSize
        bar.frame = CGRect(x: (bounds.width - size.width) / 2, y: 28, width: size.width, height: size.height)
    }

    override func cursorUpdate(with event: NSEvent) {
        (mode == .area ? NSCursor.crosshair : NSCursor.arrow).set()
    }

    // MARK: Pointer

    /// The pointer's place in this view, from a global position.
    private func local(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - snapshot.frame.minX, y: global.y - snapshot.frame.minY)
    }

    func pointerMoved(to global: CGPoint) {
        lastPoint = local(global)
        hovered = mode == .window ? WindowLocator.window(at: global, in: targets) : nil
        update()
    }

    override func mouseEntered(with event: NSEvent) {
        // The display under the pointer takes the keys.
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: NSEvent.mouseLocation)
        cursorUpdate(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastPoint = point
        switch mode {
        case .area:
            dragStart = point
            dragCurrent = point
            selection = nil
        case .window:
            if let hovered { onResult?(.window(hovered, snapshot)) }
        case .screen:
            onResult?(.screen(snapshot))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area, let start = dragStart, let current = dragCurrent else { return }
        let point = convert(event.locationInWindow, from: nil)
        if spaceHeld {
            // Space moves the selection instead of resizing it.
            let dx = point.x - current.x, dy = point.y - current.y
            dragStart = CGPoint(x: start.x + dx, y: start.y + dy)
        }
        dragCurrent = point
        lastPoint = point
        selection = Self.rect(from: dragStart ?? start, to: point, flags: event.modifierFlags)
            .intersection(bounds)
        update()
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area else { return }
        defer { dragStart = nil; dragCurrent = nil }
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            // A click without a drag takes the window under the pointer.
            selection = nil
            let global = CGPoint(x: lastPoint.x + snapshot.frame.minX, y: lastPoint.y + snapshot.frame.minY)
            if let target = WindowLocator.window(at: global, in: targets) {
                onResult?(.window(target, snapshot))
            } else {
                update()
            }
            return
        }
        onResult?(.area(selection.offsetBy(dx: snapshot.frame.minX, dy: snapshot.frame.minY), snapshot))
    }

    override func flagsChanged(with event: NSEvent) {
        guard let start = dragStart, let current = dragCurrent else { return }
        selection = Self.rect(from: start, to: current, flags: event.modifierFlags).intersection(bounds)
        update()
    }

    /// The rect a drag makes: ⇧ keeps it square, ⌥ grows it from the start point.
    static func rect(from start: CGPoint, to end: CGPoint, flags: NSEvent.ModifierFlags) -> CGRect {
        var dx = end.x - start.x
        var dy = end.y - start.y
        if flags.contains(.shift) {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if flags.contains(.option) {
            return CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        }
        return CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onResult?(.cancelled)
        case 49: // Space
            if dragStart != nil { spaceHeld = true } else { onMode?(mode == .window ? .area : .window) }
        case 36, 76: // Return
            if mode == .screen { onResult?(.screen(snapshot)) }
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": onMode?(.area)
            case "w": onMode?(.window)
            case "f": onMode?(.screen)
            default: super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }

    private func modeChanged() {
        dragStart = nil
        dragCurrent = nil
        selection = nil
        hovered = mode == .window ? WindowLocator.window(at: NSEvent.mouseLocation, in: targets) : nil
        bar?.rootView = CaptureModeBar(mode: mode) { [weak self] in self?.onMode?($0) }
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        update()
    }

    // MARK: Drawing

    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let pointerHere = bounds.contains(lastPoint) && (window?.frame.contains(NSEvent.mouseLocation) ?? false)
        // What stays bright: the selection, the window under the pointer, or the whole screen.
        var focus: CGRect?
        switch mode {
        case .area: focus = selection
        case .window: focus = hovered.map { $0.frame.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY) }
        case .screen: focus = pointerHere ? bounds : nil
        }
        let path = CGMutablePath()
        path.addRect(bounds)
        if let focus { path.addRect(focus) }
        dim.frame = bounds
        dim.path = path
        // Lighter before you start, so you can still read the screen.
        dim.fillColor = NSColor.black.withAlphaComponent(focus == nil ? 0.22 : 0.45).cgColor
        outline.frame = bounds
        outline.path = focus.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }
        outline.strokeColor = (mode == .area ? NSColor.white : NSColor(Brand.lavender)).cgColor
        outline.lineWidth = mode == .area ? 1 : 3

        if let focus, mode != .screen {
            label.string = mode == .window
                ? "\(hovered?.appName ?? "")  \(Int(focus.width)) × \(Int(focus.height))"
                : "\(Int(focus.width)) × \(Int(focus.height))"
            let text = (label.string as? String) ?? ""
            let width = (text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]).width + 18
            let above = focus.maxY + 30 < bounds.maxY
            labelBackground.frame = CGRect(x: max(4, min(focus.minX, bounds.maxX - width - 4)),
                                           y: above ? focus.maxY + 8 : focus.maxY - 30, width: width, height: 22)
            label.frame = labelBackground.bounds.insetBy(dx: 0, dy: 3)
            labelBackground.isHidden = false
        } else {
            labelBackground.isHidden = true
        }

        loupe.layer.isHidden = mode != .area || !pointerHere
        if !loupe.layer.isHidden { loupe.show(at: lastPoint, in: bounds, snapshot: snapshot) }
    }
}

/// A magnified look at the pixels under the pointer, with their position and colour.
@MainActor
private final class Loupe {
    let layer = CALayer()
    private let lens = CALayer()
    private let grid = CAShapeLayer()
    private let centre = CAShapeLayer()
    private let caption = CATextLayer()
    private let captionBackground = CALayer()
    /// Pixels across the lens.
    private let pixels: CGFloat = 15
    private let size: CGFloat = 120
    private var imageSize = CGSize.zero

    init() {
        lens.frame = CGRect(x: 0, y: 26, width: size, height: size)
        lens.cornerRadius = size / 2
        lens.masksToBounds = true
        lens.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        lens.borderWidth = 2
        lens.magnificationFilter = .nearest
        lens.contentsGravity = .resize
        let cell = size / pixels
        let path = CGMutablePath()
        for index in 1..<Int(pixels) {
            let offset = CGFloat(index) * cell
            path.move(to: CGPoint(x: offset, y: 0)); path.addLine(to: CGPoint(x: offset, y: size))
            path.move(to: CGPoint(x: 0, y: offset)); path.addLine(to: CGPoint(x: size, y: offset))
        }
        grid.path = path
        grid.strokeColor = NSColor.black.withAlphaComponent(0.12).cgColor
        grid.lineWidth = 0.5
        grid.frame = lens.bounds
        let middle = (pixels - 1) / 2 * cell
        centre.path = CGPath(rect: CGRect(x: middle, y: middle, width: cell, height: cell), transform: nil)
        centre.strokeColor = NSColor.systemRed.cgColor
        centre.fillColor = nil
        centre.lineWidth = 1.5
        centre.frame = lens.bounds
        lens.addSublayer(grid)
        lens.addSublayer(centre)
        captionBackground.backgroundColor = NSColor(white: 0.08, alpha: 0.72).cgColor
        captionBackground.cornerRadius = 6
        caption.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        caption.fontSize = 11
        caption.foregroundColor = NSColor.white.cgColor
        caption.alignmentMode = .center
        captionBackground.addSublayer(caption)
        layer.addSublayer(lens)
        layer.addSublayer(captionBackground)
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: -4)
    }

    func setImage(_ image: CGImage, scale: CGFloat) {
        lens.contents = image
        imageSize = CGSize(width: image.width, height: image.height)
        caption.contentsScale = scale
    }

    func show(at point: CGPoint, in bounds: CGRect, snapshot: DisplaySnapshot) {
        // The lens sits below right of the pointer, and flips at the edges.
        var origin = CGPoint(x: point.x + 22, y: point.y - size - 48)
        if origin.x + size > bounds.maxX { origin.x = point.x - size - 22 }
        if origin.y < bounds.minY { origin.y = point.y + 22 }
        layer.frame = CGRect(x: origin.x, y: origin.y, width: size, height: size + 26)
        let width = imageSize.width, height = imageSize.height
        guard width > 0, height > 0 else { return }
        let pixelX = point.x * snapshot.scale, pixelY = point.y * snapshot.scale
        let half = pixels / 2
        lens.contentsRect = CGRect(x: (pixelX - half) / width, y: (pixelY - half) / height,
                                   width: pixels / width, height: pixels / height)
        // Points from the top left, the way the screen is usually measured.
        let x = Int(point.x), y = Int(bounds.height - point.y)
        var text = "\(x), \(y)"
        if let hex = Self.hexColour(in: snapshot.image, x: Int(pixelX), y: Int(CGFloat(snapshot.image.height) - pixelY)) {
            text += " · \(hex)"
        }
        caption.string = text
        let textWidth = (text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]).width + 14
        captionBackground.frame = CGRect(x: (size - textWidth) / 2, y: 0, width: textWidth, height: 20)
        caption.frame = captionBackground.bounds.insetBy(dx: 0, dy: 3)
    }

    /// The colour of one pixel (counted from the top left), as #RRGGBB in sRGB.
    static func hexColour(in image: CGImage, x: Int, y: Int) -> String? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

/// The glass bar at the bottom: which kind of capture, and how.
struct CaptureModeBar: View {
    let mode: CaptureMode
    let select: (CaptureMode) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(CaptureMode.allCases) { item in
                    Button { select(item) } label: {
                        HStack(spacing: 6) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.key)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.white.opacity(0.1), in: .rect(cornerRadius: 4))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(item == mode ? AnyShapeStyle(.white.opacity(0.16)) : AnyShapeStyle(.clear),
                                    in: .rect(cornerRadius: 10))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("\(item.title) (\(item.key))")
                }
            }
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            Text(mode.hint)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .shadow(color: .black.opacity(0.6), radius: 3)
        }
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

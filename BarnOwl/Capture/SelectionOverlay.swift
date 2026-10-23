import AppKit
import KeyboardShortcuts
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
    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .screen: "display"
        }
    }
    var hint: String {
        switch self {
        case .area: "Drag an area or click a window · L for the last area · ? for keys"
        case .window: "Click a window · Space to drag an area · ? for keys"
        case .screen: "Click a screen · ? for keys"
        }
    }
    /// The hint while selecting something to record.
    var recordHint: String {
        switch self {
        case .area: "Drag an area or click a window to record · L for the last area"
        case .window: "Click a window to record · Space to drag an area"
        case .screen: "Click a screen to record"
        }
    }
    /// The hint while selecting something for a scrolling capture.
    var scrollHint: String {
        switch self {
        case .area: "Drag over the part that scrolls · L for the last area"
        case .window: "Click a window to scroll through · Space to drag an area"
        case .screen: "Click a screen to scroll through"
        }
    }
}

/// What to do with what you've selected.
enum CaptureAction {
    /// Copy and save, as Settings › Capture says.
    case primary
    case edit, pin, copy, save
    /// The words in it, not the picture.
    case copyText
    /// Record it, as a video or as a GIF.
    case record, recordGIF
    /// A scrolling capture of it.
    case scroll

    /// Records or scrolls: needs more than a sliver to work with.
    var needsRoom: Bool { self == .record || self == .recordGIF || self == .scroll }

    /// What Return does, as the overlay was started: copy the words, record, scroll, or
    /// copy and save as usual.
    static func onReturn(copiesText: Bool = false, recording: RecordingSetup? = nil, scrolls: Bool = false) -> Self {
        if copiesText { return .copyText }
        if let recording { return recording.makesGIF ? .recordGIF : .record }
        return scrolls ? .scroll : .primary
    }
}

/// What the record bar offers, when the overlay is up to record.
struct RecordingSetup {
    var makesGIF = false
    var microphones: [Microphone] = []
    var micStatus = MicrophoneStatus.notAsked
    var allowMicrophone: () -> Void = {}
}

/// What you've selected.
enum CaptureTarget {
    /// A rect in AppKit screen coordinates, on one display.
    case area(CGRect, DisplaySnapshot)
    /// A window, captured on its own with its shadow.
    case window(WindowTarget, DisplaySnapshot)
    case screen(DisplaySnapshot)
}

enum SelectionResult {
    case done(CaptureTarget, CaptureAction)
    case cancelled
}

/// The frozen screens you select on: one window per display, each showing
/// the picture taken when you pressed the shortcut. After you let go, the
/// selection stays adjustable, with a small bar of what to do with it.
@MainActor
final class SelectionOverlay {
    private var windows: [OverlayWindow] = []
    private var mode: CaptureMode
    private let completion: (SelectionResult) -> Void
    private var finished = false
    private var observers: [NSObjectProtocol] = []
    private var pointerMonitor: Any?
    /// Asks for new pictures when an option that changes them is switched.
    var onOptionsChanged: (() -> Void)?

    /// `copiesText`: started to copy text, so Return copies the words in the selection.
    /// `recording`: started to record, so the selection gets the record bar and Return records.
    /// `scrolls`: started for a scrolling capture, so Return starts one.
    init(snapshots: [DisplaySnapshot], targets: [WindowTarget], mode: CaptureMode, copiesText: Bool = false,
         recording: RecordingSetup? = nil, scrolls: Bool = false, completion: @escaping (SelectionResult) -> Void) {
        self.mode = mode
        self.completion = completion
        let hints = Preferences.captureHintCount < 10
        for snapshot in snapshots {
            let window = OverlayWindow(snapshot: snapshot, targets: targets, mode: mode, showsHints: hints)
            window.selection.copiesText = copiesText
            window.selection.recording = recording
            window.selection.scrolls = scrolls
            window.selection.onResult = { [weak self] in self?.finish($0) }
            window.selection.onMode = { [weak self] in self?.setMode($0) }
            window.selection.onSelect = { [weak self, weak window] in self?.selectionStarted(in: window) }
            window.selection.onOptions = { [weak self] in self?.onOptionsChanged?() }
            windows.append(window)
        }
    }

    func show() {
        Preferences.captureHintCount += 1
        // Keys and the crosshair only reach an active app.
        NSApp.activate()
        let pointer = NSEvent.mouseLocation
        for window in windows {
            if window.frame.contains(pointer) { window.makeKeyAndOrderFront(nil) } else { window.orderFrontRegardless() }
        }
        pointerMoved()
        // Activation finishes a moment later; claim the keys again then.
        DispatchQueue.main.async { [weak self] in self?.pointerMoved() }
        // A display, Space or sleep change leaves the frozen pictures wrong.
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(.cancelled) }
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(.cancelled) }
            },
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(.cancelled) }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            },
            // Switching to another app (⌘Tab) ends the capture; it never leaves a frozen screen behind.
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(.cancelled) }
            },
        ]
        // Which display has the bars and the keys follows the pointer.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.pointerMoved()
            return event
        }
    }

    /// New pictures, after an option changed what's left out of them.
    func replace(_ snapshots: [DisplaySnapshot]) {
        for window in windows {
            if let snapshot = snapshots.first(where: { $0.displayID == window.selection.displayID }) {
                window.selection.replace(snapshot)
            }
        }
    }

    private func pointerMoved() {
        let pointer = NSEvent.mouseLocation
        let active = windows.first { $0.frame.contains(pointer) } ?? windows.first
        for window in windows {
            window.selection.isActiveDisplay = window === active
            window.selection.pointerMoved(to: pointer)
        }
        // Keys go to the display under the pointer, always to its selection view.
        if let active {
            if !active.isKeyWindow { active.makeKey() }
            if active.firstResponder !== active.selection { active.makeFirstResponder(active.selection) }
        }
    }

    private func selectionStarted(in window: OverlayWindow?) {
        // One selection at a time, across displays.
        for other in windows where other !== window { other.selection.clearSelection() }
    }

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
        windows.forEach { $0.selection.mode = mode }
    }

    func finish(_ result: SelectionResult) {
        guard !finished else { return }
        finished = true
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers = []
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        let windows = self.windows
        self.windows = []
        completion(result)
        // After the result is handled (the editor may already be in front),
        // and after the click that ended it has finished with these windows.
        DispatchQueue.main.async {
            windows.forEach { $0.orderOut(nil); $0.close() }
        }
    }
}

final class OverlayWindow: NSPanel {
    let selection: SelectionView

    init(snapshot: DisplaySnapshot, targets: [WindowTarget], mode: CaptureMode, showsHints: Bool) {
        selection = SelectionView(snapshot: snapshot, targets: targets, mode: mode, showsHints: showsHints)
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

/// Draws one frozen display with the dimming, the selection, its handles,
/// the bars and the loupe, and turns mouse and keys into a result.
final class SelectionView: NSView {
    var onResult: ((SelectionResult) -> Void)?
    var onMode: ((CaptureMode) -> Void)?
    var onSelect: (() -> Void)?
    var onOptions: (() -> Void)?
    var mode: CaptureMode {
        didSet { modeChanged() }
    }
    /// The display under the pointer shows the bars.
    var isActiveDisplay = false {
        didSet { if isActiveDisplay != oldValue { update() } }
    }
    var displayID: CGDirectDisplayID { snapshot.displayID }

    private enum Gesture {
        case drawing(start: CGPoint)
        case moving(offset: CGSize)
        case resizing(handle: Handle, from: CGRect)
    }

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private var snapshot: DisplaySnapshot
    /// A mostly dark screen needs a deeper dim for the selection to stand out.
    private var darkScreen: Bool
    private let targets: [WindowTarget]
    private let showsHints: Bool
    private let dim = CAShapeLayer()
    private let edgeOuter = CAShapeLayer()
    private let edgeInner = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let handles = CAShapeLayer()
    private let label = CATextLayer()
    private let labelBackground = CALayer()
    private let loupe = Loupe()
    private var modeBar: NSHostingView<CaptureModeBar>?
    private var actionBar: NSHostingView<CaptureActionBar>?
    private var recordBar: NSHostingView<RecordBar>?
    private var keysSheet: NSHostingView<CaptureKeysSheet>?

    private var gesture: Gesture?
    /// The selection before a move or resize, for Esc.
    private var beforeGesture: (selection: CGRect, window: WindowTarget?, screen: Bool)?
    private var spaceHeld = false
    private var lastPoint: CGPoint = .zero
    /// The selection, in this view's coordinates.
    private var selection: CGRect?
    /// Set while the selection is exactly a window you clicked.
    private var selectedWindow: WindowTarget?
    private var selectedScreen = false
    private var hovered: WindowTarget?
    /// Started to copy text: Return copies the words in the selection, not the picture.
    var copiesText = false {
        didSet { modeBar?.rootView = modeBarView }
    }
    /// Started to record: the record bar instead of the action bar, and Return records.
    var recording: RecordingSetup? {
        didSet { modeBar?.rootView = modeBarView }
    }
    /// Started for a scrolling capture: Return starts one.
    var scrolls = false {
        didSet { modeBar?.rootView = modeBarView }
    }

    init(snapshot: DisplaySnapshot, targets: [WindowTarget], mode: CaptureMode, showsHints: Bool) {
        self.snapshot = snapshot
        darkScreen = Self.isDark(snapshot.image)
        self.targets = targets
        self.mode = mode
        self.showsHints = showsHints
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        wantsLayer = true
        guard let layer else { return }
        layer.contents = snapshot.image
        layer.contentsGravity = .resize
        dim.fillRule = .evenOdd
        edgeOuter.fillColor = nil
        edgeOuter.strokeColor = NSColor.black.withAlphaComponent(0.4).cgColor
        edgeOuter.lineWidth = 1
        edgeInner.fillColor = nil
        edgeInner.strokeColor = NSColor.white.cgColor
        edgeInner.lineWidth = 1
        highlight.fillColor = NSColor(Brand.lavender).withAlphaComponent(0.18).cgColor
        highlight.strokeColor = NSColor(Brand.lavender).cgColor
        highlight.lineWidth = 1.5
        handles.fillColor = NSColor.white.cgColor
        handles.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        handles.lineWidth = 0.75
        handles.shadowOpacity = 0.3
        handles.shadowRadius = 2
        handles.shadowOffset = CGSize(width: 0, height: -1)
        labelBackground.backgroundColor = NSColor(white: 0.08, alpha: 0.72).cgColor
        labelBackground.cornerRadius = 7
        label.alignmentMode = .center
        label.contentsScale = snapshot.scale
        labelBackground.addSublayer(label)
        for sublayer in [dim, highlight, edgeOuter, edgeInner, handles, labelBackground, loupe.layer] {
            layer.addSublayer(sublayer)
        }
        loupe.setImage(snapshot.image, scale: snapshot.scale)
        let modeBar = NSHostingView(rootView: modeBarView)
        addSubview(modeBar)
        self.modeBar = modeBar
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The picture is the layer's content; a redraw must put it back, not wipe it.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = snapshot.image }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    func replace(_ snapshot: DisplaySnapshot) {
        self.snapshot = snapshot
        darkScreen = Self.isDark(snapshot.image)
        layer?.contents = snapshot.image
        loupe.setImage(snapshot.image, scale: snapshot.scale)
    }

    func clearSelection() {
        guard selection != nil || gesture != nil else { return }
        selection = nil
        selectedWindow = nil
        selectedScreen = false
        gesture = nil
        update()
    }

    private var modeBarView: CaptureModeBar {
        CaptureModeBar(mode: mode, showsHints: showsHints, copiesText: copiesText, records: recording != nil,
                       scrolls: scrolls,
                       select: { [weak self] in self?.onMode?($0) },
                       options: { [weak self] in self?.onOptions?() },
                       cancel: { [weak self] in self?.onResult?(.cancelled) })
    }

    // MARK: Pointer

    func pointerMoved(to global: CGPoint) {
        let point = CGPoint(x: global.x - snapshot.frame.minX, y: global.y - snapshot.frame.minY)
        guard gesture == nil else { return }
        lastPoint = point
        hovered = selection == nil && mode != .screen ? WindowLocator.window(at: global, in: targets) : nil
        updateCursor()
        update()
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: NSEvent.mouseLocation)
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    private func updateCursor() {
        if let selection {
            if let handle = handle(at: lastPoint, in: selection) {
                cursor(for: handle).set()
            } else if selection.contains(lastPoint) {
                NSCursor.openHand.set()
            } else {
                (mode == .area ? NSCursor.crosshair : NSCursor.arrow).set()
            }
        } else {
            (mode == .area ? NSCursor.crosshair : NSCursor.arrow).set()
        }
    }

    private func cursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .top, .bottom: .resizeUpDown
        case .left, .right: .resizeLeftRight
        case .topLeft, .bottomRight: .frameResize(position: .topLeft, directions: .all)
        case .topRight, .bottomLeft: .frameResize(position: .topRight, directions: .all)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastPoint = point
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
        if let selection {
            if let handle = handle(at: point, in: selection) {
                beforeGesture = (selection, selectedWindow, selectedScreen)
                gesture = .resizing(handle: handle, from: selection)
                return
            }
            if selection.contains(point) {
                if event.clickCount == 2 { return act(.primary) }
                beforeGesture = (selection, selectedWindow, selectedScreen)
                gesture = .moving(offset: CGSize(width: point.x - selection.minX, height: point.y - selection.minY))
                NSCursor.closedHand.set()
                return
            }
        }
        // A new selection, here.
        selection = nil
        selectedWindow = nil
        selectedScreen = false
        onSelect?()
        gesture = .drawing(start: point)
        update()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { lastPoint = point; update() }
        switch gesture {
        case .drawing(let start):
            var origin = start
            if spaceHeld {
                // Space moves the selection being drawn.
                origin = CGPoint(x: start.x + point.x - lastPoint.x, y: start.y + point.y - lastPoint.y)
                gesture = .drawing(start: origin)
            }
            selection = Self.rect(from: origin, to: point, flags: event.modifierFlags).intersection(bounds)
            hovered = nil
        case .moving(let offset):
            guard let current = selection else { return }
            let x = min(max(point.x - offset.width, 0), bounds.width - current.width)
            let y = min(max(point.y - offset.height, 0), bounds.height - current.height)
            selection = CGRect(x: x, y: y, width: current.width, height: current.height)
            selectedWindow = nil
            selectedScreen = false
        case .resizing(let handle, let from):
            selection = Self.resize(from, handle: handle, to: point).intersection(bounds)
            selectedWindow = nil
            selectedScreen = false
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastPoint = point
        let ended = gesture
        gesture = nil
        defer { updateCursor(); update() }
        guard case .drawing = ended else { return }
        if let selection, selection.width >= 4, selection.height >= 4 {
            if !Preferences.captureAdjusts { act(.primary) }
            return
        }
        // A click: the window under it, or the whole display.
        selection = nil
        let global = CGPoint(x: point.x + snapshot.frame.minX, y: point.y + snapshot.frame.minY)
        if mode != .screen, let target = WindowLocator.window(at: global, in: targets) {
            selectedWindow = target
            selection = target.frame.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY).intersection(bounds)
        } else if mode == .screen || Preferences.captureAdjusts {
            selectedScreen = true
            selection = bounds
        }
        if selection != nil, !Preferences.captureAdjusts { act(.primary) }
    }

    override func flagsChanged(with event: NSEvent) {
        guard case .drawing(let start) = gesture else { return }
        selection = Self.rect(from: start, to: lastPoint, flags: event.modifierFlags).intersection(bounds)
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

    /// A rect with one handle dragged to `point`; the opposite edges stay put.
    static func resize(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = point.x; maxY = point.y
        case .top: maxY = point.y
        case .topRight: maxX = point.x; maxY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; minY = point.y
        case .bottom: minY = point.y
        case .bottomLeft: minX = point.x; minY = point.y
        case .left: minX = point.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// Handle points, AppKit-style: top is the larger y.
    /// Whether a picture is mostly dark: its average brightness under a quarter.
    static func isDark(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: 64)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard drawn else { return false }
        return Double(pixels.reduce(0) { $0 + Int($1) }) / 64 / 255 < 0.25
    }

    static func handlePoints(of rect: CGRect) -> [(Handle, CGPoint)] {
        [(.topLeft, CGPoint(x: rect.minX, y: rect.maxY)), (.top, CGPoint(x: rect.midX, y: rect.maxY)),
         (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)), (.right, CGPoint(x: rect.maxX, y: rect.midY)),
         (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)), (.bottom, CGPoint(x: rect.midX, y: rect.minY)),
         (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)), (.left, CGPoint(x: rect.minX, y: rect.midY))]
    }

    /// The handles, kept whole on screen when the selection reaches an edge.
    private func visibleHandles(of rect: CGRect) -> [(Handle, CGPoint)] {
        let inside = bounds.insetBy(dx: 6, dy: 6)
        return Self.handlePoints(of: rect).map { handle, centre in
            (handle, CGPoint(x: min(max(centre.x, inside.minX), inside.maxX), y: min(max(centre.y, inside.minY), inside.maxY)))
        }
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> Handle? {
        // Small selections keep only the corners, so the middle stays draggable.
        let corners: Set<Handle> = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        let small = rect.width < 60 || rect.height < 60
        return visibleHandles(of: rect).first { handle, centre in
            (!small || corners.contains(handle)) && hypot(point.x - centre.x, point.y - centre.y) <= 8
        }?.0
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let key = Self.letter(for: event)
        switch event.keyCode {
        case 53: // Esc steps back: the gesture, then the selection, then the overlay.
            if gesture != nil {
                // A move or resize goes back to where it started; a new selection goes.
                if case .drawing = gesture {
                    selection = nil
                } else if let beforeGesture {
                    // A window stays a window, with its shadow.
                    (selection, selectedWindow, selectedScreen) = beforeGesture
                }
                gesture = nil
                update()
            } else if keysSheet != nil {
                toggleKeys()
            } else if selection != nil {
                clearSelection()
            } else {
                onResult?(.cancelled)
            }
            return
        case 36, 76: // Return: the selection, or the window or screen you're pointing at.
            if selection == nil, mode == .screen { selectedScreen = true; selection = bounds }
            if selection == nil, let hovered {
                selectedWindow = hovered
                selection = hovered.frame.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY).intersection(bounds)
            }
            if selection != nil { act(.primary) }
            return
        case 49: // Space
            if case .drawing = gesture { spaceHeld = true } else if selection == nil { onMode?(mode == .window ? .area : .window) }
            return
        case 123, 124, 125, 126: // Arrows nudge; ⇧ by 10; ⌥ resizes
            guard let current = selection else { return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy: CGFloat = event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0
            if event.modifierFlags.contains(.option) {
                // The top left stays; the right and bottom edges follow the arrows.
                let width = max(4, current.width + dx), height = max(4, current.height - dy)
                selection = CGRect(x: current.minX, y: current.maxY - height, width: width, height: height).intersection(bounds)
            } else {
                // Stops at the edge rather than shrinking.
                let x = min(max(current.minX + dx, 0), bounds.width - current.width)
                let y = min(max(current.minY + dy, 0), bounds.height - current.height)
                selection = CGRect(x: x, y: y, width: current.width, height: current.height)
            }
            selectedWindow = nil
            selectedScreen = false
            update()
            return
        default:
            break
        }
        // Recording, the picture's own actions are left out, so a stray key never takes one.
        let picture = recording == nil
        switch (key, command) {
        case ("c", true): if selection != nil, picture { act(.copy) }
        case ("s", true): if selection != nil, picture { act(.save) }
        case ("e", false): if selection != nil, picture { act(.edit) }
        case ("p", false): if selection != nil, picture { act(.pin) }
        case ("t", false): if selection != nil, picture { act(.copyText) }
        case ("r", false): if selection != nil { act(.record) }
        case ("g", false): if selection != nil { act(.recordGIF) }
        case ("s", false): if selection != nil, picture { act(.scroll) }
        case ("a", false): onMode?(.area)
        case ("w", false): onMode?(.window)
        case ("f", false): onMode?(.screen)
        case ("l", false): restoreLastArea()
        default:
            // "?" is a different key on every layout: go by what it types.
            if event.characters == "?" || key == "?" { toggleKeys() } else { super.keyDown(with: event) }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }

    /// The letter typed, from the layout; from the key's place when an event
    /// carries no characters (some automation tools send those).
    static func letter(for event: NSEvent) -> String {
        if let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty { return characters }
        let byKey: [UInt16: String] = [0: "a", 1: "s", 3: "f", 5: "g", 8: "c", 13: "w", 14: "e", 15: "r", 17: "t", 35: "p",
                                       37: "l"]
        return byKey[event.keyCode] ?? ""
    }

    /// Brings back the area you captured last, if it's on this display.
    private func restoreLastArea() {
        guard let area = Preferences.captureLastArea, snapshot.frame.intersects(area) else { return NSSound.beep() }
        onSelect?()
        selection = area.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY).intersection(bounds)
        selectedWindow = nil
        selectedScreen = false
        if Preferences.captureAdjusts { update() } else { act(.primary) }
    }

    private func act(_ action: CaptureAction) {
        guard let selection else { return }
        var action = action
        if action == .primary { action = .onReturn(copiesText: copiesText, recording: recording, scrolls: scrolls) }
        guard selection.width >= 1, selection.height >= 1 else { return NSSound.beep() }
        // A recording or a scroll needs something to see.
        if action.needsRoom, selection.width < 32 || selection.height < 32 { return NSSound.beep() }
        if selectedScreen, selection == bounds {
            onResult?(.done(.screen(snapshot), action))
        } else if let selectedWindow {
            onResult?(.done(.window(selectedWindow, snapshot), action))
        } else {
            onResult?(.done(.area(selection.offsetBy(dx: snapshot.frame.minX, dy: snapshot.frame.minY), snapshot), action))
        }
    }

    private func modeChanged() {
        gesture = nil
        selection = nil
        selectedWindow = nil
        selectedScreen = false
        hovered = mode == .window ? WindowLocator.window(at: NSEvent.mouseLocation, in: targets) : nil
        modeBar?.rootView = modeBarView
        updateCursor()
        update()
    }

    private func toggleKeys() {
        if let keysSheet {
            keysSheet.removeFromSuperview()
            self.keysSheet = nil
        } else {
            let sheet = NSHostingView(rootView: CaptureKeysSheet())
            addSubview(sheet)
            let size = sheet.fittingSize
            sheet.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                 width: size.width, height: size.height)
            keysSheet = sheet
        }
    }

    // MARK: Drawing

    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let drawing: Bool = { if case .drawing = gesture { return true } else { return false } }()
        let resizing: Bool = { if case .resizing = gesture { return true } else { return false } }()
        // What stays bright: the selection, or the window or screen you'd get by clicking.
        var focus = selection
        if focus == nil, isActiveDisplay {
            if let hovered, mode != .screen {
                focus = hovered.frame.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY)
            } else if mode == .screen {
                focus = bounds
            }
        }
        let path = CGMutablePath()
        path.addRect(bounds)
        if let focus { path.addRect(focus) }
        dim.frame = bounds
        dim.path = path
        // Lighter before you start, so the screen stays readable.
        dim.fillColor = NSColor.black.withAlphaComponent(focus == nil ? 0.2 : darkScreen ? 0.62 : 0.5).cgColor

        // A window (hovered or clicked) gets a lavender wash; an area gets a crisp edge.
        let windowLike = selection == nil ? focus != nil && mode != .area || hovered != nil : selectedWindow != nil
        highlight.frame = bounds
        highlight.path = windowLike ? focus.map { CGPath(roundedRect: $0.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 10, cornerHeight: 10, transform: nil) } : nil
        let edge = !windowLike ? (selection ?? (drawing ? selection : nil)) : nil
        edgeOuter.frame = bounds
        edgeInner.frame = bounds
        edgeOuter.path = edge.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }
        edgeInner.path = edge.map { CGPath(rect: $0.insetBy(dx: 0.5, dy: 0.5), transform: nil) }

        // Handles once you've let go.
        handles.frame = bounds
        // A window is taken whole, so it shows none; dragging where they'd be still resizes.
        if let selection, gesture == nil || resizing, !selectedScreen, selectedWindow == nil {
            let corners: Set<Handle> = [.topLeft, .topRight, .bottomRight, .bottomLeft]
            let small = selection.width < 60 || selection.height < 60
            let dots = CGMutablePath()
            for (handle, centre) in visibleHandles(of: selection) where !small || corners.contains(handle) {
                dots.addEllipse(in: CGRect(x: centre.x - 4.5, y: centre.y - 4.5, width: 9, height: 9))
            }
            handles.path = dots
        } else {
            handles.path = nil
        }

        updateLabel(focus: focus)
        loupe.layer.isHidden = !(drawing || resizing)
        if !loupe.layer.isHidden { loupe.show(at: lastPoint, in: bounds, snapshot: snapshot) }
        updateBars(drawing: drawing || resizing)
    }

    private func updateLabel(focus: CGRect?) {
        guard let focus, isActiveDisplay || selection != nil, !(selectedScreen && gesture == nil && selection == nil) else {
            labelBackground.isHidden = true
            return
        }
        let size = "\(Int(focus.width.rounded())) × \(Int(focus.height.rounded()))"
        let name = selectedWindow?.appName ?? (selection == nil ? hovered?.appName : nil)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let text = NSMutableAttributedString()
        if let name {
            text.append(NSAttributedString(string: "\(name) · ", attributes: [.font: font, .foregroundColor: NSColor.white]))
        }
        text.append(NSAttributedString(string: size, attributes: [
            .font: font, .foregroundColor: NSColor.white.withAlphaComponent(name == nil ? 1 : 0.7),
        ]))
        label.string = text
        let width = text.size().width + 18
        let above = focus.maxY + 30 < bounds.maxY
        labelBackground.frame = CGRect(x: max(4, min(focus.minX, bounds.maxX - width - 4)),
                                       y: above ? focus.maxY + 8 : focus.maxY - 30, width: width, height: 22)
        label.frame = labelBackground.bounds.insetBy(dx: 0, dy: 3)
        labelBackground.isHidden = false
    }

    private func updateBars(drawing: Bool) {
        // The mode bar until there's a selection; then the action bar under it.
        let showsModeBar = isActiveDisplay && selection == nil && !drawing
        if let modeBar {
            modeBar.isHidden = !showsModeBar
            if showsModeBar {
                let size = modeBar.fittingSize
                modeBar.frame = CGRect(x: (bounds.width - size.width) / 2, y: 28, width: size.width, height: size.height)
            }
        }
        guard let selection, gesture == nil else {
            actionBar?.isHidden = true
            recordBar?.isHidden = true
            return
        }
        let bar: NSView
        if recording != nil {
            let host = recordBar ?? {
                let host = NSHostingView(rootView: recordBarView)
                addSubview(host)
                recordBar = host
                return host
            }()
            host.rootView = recordBarView
            bar = host
        } else {
            let host = actionBar ?? {
                let host = NSHostingView(rootView: actionBarView)
                addSubview(host)
                actionBar = host
                return host
            }()
            host.rootView = actionBarView
            bar = host
        }
        let size = bar.fittingSize
        var y = selection.minY - size.height - 10
        if y < 12 { y = selection.maxY + 10 }
        if y + size.height > bounds.maxY - 12 { y = selection.minY + 12 }
        let x = min(max(selection.midX - size.width / 2, 12), bounds.width - size.width - 12)
        bar.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        bar.isHidden = false
    }

    private var recordBarView: RecordBar {
        let setup = recording ?? RecordingSetup()
        return RecordBar(microphones: setup.microphones, micStatus: setup.micStatus, makesGIF: setup.makesGIF,
                         showsHint: showsHints,
                         setGIF: { [weak self] gif in
                             self?.recording?.makesGIF = gif
                             self?.update()
                         },
                         record: { [weak self] in self?.act(.primary) },
                         allowMicrophone: { [weak self] in self?.recording?.allowMicrophone() },
                         cancel: { [weak self] in self?.clearSelection() })
    }

    private var actionBarView: CaptureActionBar {
        CaptureActionBar(primary: copiesText ? "Copy Text" : scrolls ? "Start Capture" : Self.primaryTitle,
                         copiesText: copiesText, scrolls: scrolls, showsHint: showsHints) { [weak self] action in
            if let action { self?.act(action) } else { self?.clearSelection() }
        }
    }

    /// "Copy & Save", "Copy" or "Save", as Settings › Capture says.
    static var primaryTitle: String {
        switch (Preferences.captureCopies, Preferences.captureSaves) {
        case (true, true): "Copy & Save"
        case (true, false): "Copy"
        case (false, true): "Save"
        case (false, false): "Capture"
        }
    }
}

/// A magnified look at the pixels under the pointer, with their position and colour.
@MainActor
private final class Loupe {
    let layer = CALayer()
    private let lens = CALayer()
    private let grid = CAShapeLayer()
    private let centre = CAShapeLayer()
    private let centreDark = CAShapeLayer()
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
        // The pixel you're on: white and black hairlines, visible on anything.
        let middle = (pixels - 1) / 2 * cell
        let square = CGRect(x: middle, y: middle, width: cell, height: cell)
        centreDark.path = CGPath(rect: square.insetBy(dx: -1, dy: -1), transform: nil)
        centreDark.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        centreDark.fillColor = nil
        centreDark.lineWidth = 1
        centre.path = CGPath(rect: square, transform: nil)
        centre.strokeColor = NSColor.white.cgColor
        centre.fillColor = nil
        centre.lineWidth = 1
        for sublayer in [grid, centreDark, centre] {
            sublayer.frame = lens.bounds
            lens.addSublayer(sublayer)
        }
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
        // Below right of the pointer, flipping at the edges.
        var origin = CGPoint(x: point.x + 22, y: point.y - size - 48)
        if origin.x + size > bounds.maxX { origin.x = point.x - size - 22 }
        if origin.y < bounds.minY { origin.y = point.y + 22 }
        layer.frame = CGRect(x: origin.x, y: origin.y, width: size, height: size + 26)
        let width = imageSize.width, height = imageSize.height
        guard width > 0, height > 0 else { return }
        // The pixel under the pointer, counted from the bottom like the view.
        let pixelX = (point.x * snapshot.scale).rounded(.down)
        let pixelY = (point.y * snapshot.scale).rounded(.down)
        let half = (pixels - 1) / 2
        lens.contentsRect = CGRect(x: (pixelX - half) / width, y: (pixelY - half) / height,
                                   width: pixels / width, height: pixels / height)
        // Points from the top left, the way the screen is usually measured.
        let x = Int(point.x), y = Int(bounds.height - point.y)
        var text = "\(x), \(y)"
        let row = Int(height) - 1 - Int(pixelY)
        if let hex = Self.hexColour(in: snapshot.image, x: Int(pixelX), y: row) { text += " · \(hex)" }
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

/// The glass bar at the bottom: which kind of capture, and what's left out of it.
struct CaptureModeBar: View {
    let mode: CaptureMode
    let showsHints: Bool
    var copiesText = false
    /// Selecting something to record.
    var records = false
    /// Selecting something for a scrolling capture.
    var scrolls = false
    let select: (CaptureMode) -> Void
    let options: () -> Void
    let cancel: () -> Void
    @AppStorage(PrefKey.captureCleanMenuBar) private var cleanMenuBar = true
    @AppStorage(PrefKey.captureHidesDesktopIcons) private var hidesDesktopIcons = true
    @AppStorage(PrefKey.captureShowsPointer) private var showsPointer = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                if records {
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: 8, height: 8)
                        Text("Record").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 10).padding(.trailing, 6)
                    .accessibilityElement(children: .combine)
                    Divider().frame(height: 18).padding(.horizontal, 4)
                } else if scrolls {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.expand.vertical").font(.system(size: 13, weight: .medium))
                        Text("Scrolling Capture").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 10).padding(.trailing, 6)
                    .accessibilityElement(children: .combine)
                    Divider().frame(height: 18).padding(.horizontal, 4)
                }
                ForEach(CaptureMode.allCases) { item in
                    Button { select(item) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium))
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            KeyCap(item.key)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(item == mode ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.clear),
                                    in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help("\(item.title) (\(item.key))")
                    .accessibilityAddTraits(item == mode ? .isSelected : [])
                }
                Divider().frame(height: 18).padding(.horizontal, 4)
                Menu {
                    Toggle("Clean Menu Bar", isOn: binding($cleanMenuBar))
                    Toggle("Hide Desktop Icons", isOn: binding($hidesDesktopIcons))
                    Toggle("Show the Pointer", isOn: binding($showsPointer))
                } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("What to leave out of the picture")
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
                .accessibilityLabel("Cancel")
            }
            if showsHints || copiesText || records || scrolls {
                Text(copiesText ? "Drag over text to copy it · click a window for all of its text"
                                : records ? mode.recordHint : scrolls ? mode.scrollHint : mode.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 2)
            }
        }
        .padding(6)
        .captureGlass(in: .rect(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    /// Changing what's left out takes new pictures.
    private func binding(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; options() })
    }
}

/// What to do with the selection: the main action on Return, and the others with a letter each.
struct CaptureActionBar: View {
    let primary: String
    /// Copying text: the main action copies the words, so there's no separate Text button.
    var copiesText = false
    /// For a scrolling capture: the main action starts it, and nothing else is offered.
    var scrolls = false
    let showsHint: Bool
    /// nil closes the selection.
    let act: (CaptureAction?) -> Void

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                if !scrolls {
                    BarButton(title: "Edit", symbol: "pencil", key: "E") { act(.edit) }
                    BarButton(title: "Pin", symbol: "pin", key: "P") { act(.pin) }
                }
                if !copiesText && !scrolls {
                    BarButton(title: "Text", symbol: "text.viewfinder", key: "T") { act(.copyText) }
                    Divider().frame(height: 18).padding(.horizontal, 2)
                    BarButton(title: "Record", symbol: "record.circle", key: "R", compact: true) { act(.record) }
                    BarButton(title: "Record a GIF", glyph: "GIF", key: "G", compact: true) { act(.recordGIF) }
                    BarButton(title: "Scrolling Capture", symbol: "rectangle.expand.vertical", key: "S",
                              compact: true) { act(.scroll) }
                    Divider().frame(height: 18).padding(.horizontal, 2)
                }
                BarButton(title: primary, symbol: primarySymbol, key: "↩", prominent: true) { act(.primary) }
                Button { act(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Start over (Esc)")
                .accessibilityLabel("Start over")
            }
            if showsHint {
                // A scrolling capture's first time: what happens after Return.
                Text(scrolls ? "Return to start, then scroll down slowly · Esc to start over"
                             : "Drag the edges to adjust · drag inside to move · Esc to start over")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(5)
        .captureGlass(in: .rect(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private var primarySymbol: String {
        copiesText ? "text.viewfinder" : scrolls ? "rectangle.expand.vertical" : "arrow.down.doc"
    }

    struct BarButton: View {
        let title: String
        var symbol = ""
        /// A few letters in place of a symbol, like GIF.
        var glyph = ""
        let key: String
        var prominent = false
        /// Just the symbol and its key; the title shows on hover.
        var compact = false
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    if glyph.isEmpty {
                        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    } else {
                        Text(glyph).font(.system(size: 9, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 2.5).padding(.vertical, 1)
                            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 1.2) }
                    }
                    if !compact { Text(title).font(.system(size: 13, weight: .semibold)) }
                    KeyCap(key, onAccent: prominent)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 9 : 11).padding(.vertical, 6)
                .background(background, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(PressableStyle())
            .onHover { hovering = $0 }
            .help("\(title) (\(key))")
            .accessibilityLabel(title)
        }

        private var background: AnyShapeStyle {
            if prominent { return AnyShapeStyle(Brand.lavenderFill.opacity(hovering ? 1 : 0.94)) }
            return AnyShapeStyle(.white.opacity(hovering ? 0.22 : 0.12))
        }
    }
}

/// A key's letter in a small rounded box.
struct KeyCap: View {
    let key: String
    var onAccent = false
    /// The keys sheet's size, beside 12 pt text.
    var large = false

    init(_ key: String, onAccent: Bool = false, large: Bool = false) {
        self.key = key
        self.onAccent = onAccent
        self.large = large
    }

    var body: some View {
        Text(key)
            .font(.system(size: large ? 11.5 : 10.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, large ? 5 : 4).padding(.vertical, large ? 2 : 1)
            .frame(minWidth: large ? 20 : 0)
            .background(.white.opacity(onAccent ? 0.22 : large ? 0.14 : 0.1), in: .rect(cornerRadius: large ? 5 : 4))
            .foregroundStyle(.white.opacity(large ? 0.92 : 0.8))
    }
}

/// Every key, on "?". Keys written in [brackets] are drawn as key caps, as on the bars.
struct CaptureKeysSheet: View {
    private let groups: [(String, [(String, String)])] = [
        ("Choose", [("Drag", "an area"), ("Click", "a window, or the screen"), ("[A] [W] [F]", "area, window, screen"),
                    ("[Space]", "switch area and window"), ("[L]", "the last area again")]),
        ("Shape It", [("[⇧] drag", "square"), ("[⌥] drag", "from the centre"), ("[Space]", "move it while dragging"),
                      ("[←] [→] [↑] [↓]", "nudge (⇧ 10 pt)"), ("[⌥] arrows", "resize")]),
        ("Then", [("[↩]", SelectionView.primaryTitle.lowercased()), ("[E]", "edit"), ("[P]", "pin"), ("[T]", "copy its text"),
                  ("[⌘C] [⌘S]", "copy only · save only"), ("[R] [G]", "record a video · a GIF"), ("[S]", "scrolling capture"),
                  ("[Esc]", "start over, then cancel")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 32) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        header(group.0)
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                            ForEach(group.1, id: \.0) { row in
                                GridRow {
                                    Self.keys(row.0).frame(minHeight: 20)
                                    Text(row.1).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                                        .fixedSize()
                                }
                            }
                        }
                    }
                }
            }
            Rectangle().fill(.white.opacity(0.14)).frame(height: 0.5)
            HStack(spacing: 22) {
                if !anywhere.isEmpty {
                    header("Anywhere")
                    ForEach(anywhere, id: \.0) { item in
                        HStack(spacing: 8) {
                            Self.keys("[\(item.0)]")
                            Text(item.1).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Self.keys("[?]")
                    Text("shows or hides these").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(22)
        .captureGlass(in: .rect(cornerRadius: 22), tint: 0.6)
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    /// The shortcuts that work from any app, as you've set them.
    private var anywhere: [(String, String)] {
        var items: [(String, String)] = []
        if let keys = KeyboardShortcuts.Name.recordScreen.keys { items.append((keys, "record, and again to stop")) }
        if let keys = KeyboardShortcuts.Name.captureScrolling.keys { items.append((keys, "scrolling capture")) }
        return items
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.6))
    }

    /// "[⇧] drag": a ⇧ key cap, then "drag".
    static func keys(_ text: String) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(tokens(text).enumerated()), id: \.offset) { _, token in
                if token.isKey {
                    KeyCap(token.text, large: true)
                } else {
                    Text(token.text).font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .foregroundStyle(.white)
    }

    /// Splits "[⌥] arrows" into its key caps and words.
    nonisolated static func tokens(_ text: String) -> [(text: String, isKey: Bool)] {
        var tokens: [(text: String, isKey: Bool)] = []
        var current = ""
        var inKey = false
        for character in text {
            guard (character == "[" && !inKey) || (character == "]" && inKey) else {
                current.append(character)
                continue
            }
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { tokens.append((trimmed, inKey)) }
            current = ""
            inKey.toggle()
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { tokens.append((rest, false)) }
        return tokens
    }
}

import AppKit
import KeyboardShortcuts

/// Runs a capture from the shortcut to the card: takes the frozen picture,
/// lets you select, then saves, copies and shows what was caught.
@MainActor
@Observable
final class CaptureCoordinator {
    @ObservationIgnored private let scanner: ItemScanner
    /// Barn Owl's own menu bar items (the arrow, dividers, the owl), left out of a clean menu bar too.
    @ObservationIgnored var ownStatusWindows: () -> Set<CGWindowID> = { [] }
    @ObservationIgnored private var overlay: SelectionOverlay?
    @ObservationIgnored private lazy var cards = CaptureCards(coordinator: self)
    @ObservationIgnored private var editors: [ObjectIdentifier: (editor: CaptureEditor, captureID: UUID)] = [:]
    @ObservationIgnored private var pins: [CapturePin] = []
    /// Recent captures, for the cards and the editor.
    @ObservationIgnored private var captures: [UUID: Capture] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var lastAppleKeys: Bool?
    @ObservationIgnored private lazy var shutter = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true)
    private(set) var isCapturing = false

    init(scanner: ItemScanner) {
        self.scanner = scanner
        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in self?.start(.area) }
        KeyboardShortcuts.onKeyUp(for: .captureScreen) { [weak self] in self?.captureScreen() }
        KeyboardShortcuts.onKeyUp(for: .captureSameArea) { [weak self] in self?.captureSameArea() }
        KeyboardShortcuts.onKeyUp(for: .captureAreaApple) { [weak self] in self?.start(.area) }
        KeyboardShortcuts.onKeyUp(for: .captureScreenApple) { [weak self] in self?.captureScreen() }
        applySettings()
    }

    /// Turns the shortcuts on or off with the setting, and takes ⌘⇧3 and ⌘⇧4
    /// only while you've asked for them and macOS's own are off.
    func applySettings() {
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureScreen, .captureSameArea]
        if Preferences.captureEnabled { KeyboardShortcuts.enable(names) } else { KeyboardShortcuts.disable(names) }
        let apple = Preferences.captureEnabled && Preferences.captureAppleKeys && !SystemScreenshotShortcuts.anyEnabled
        // Setting a shortcut writes to the defaults, which calls this again: only on a change.
        guard apple != lastAppleKeys else { return }
        lastAppleKeys = apple
        let area = KeyboardShortcuts.Shortcut(.four, modifiers: [.command, .shift])
        let screen = KeyboardShortcuts.Shortcut(.three, modifiers: [.command, .shift])
        if KeyboardShortcuts.getShortcut(for: .captureAreaApple) != (apple ? area : nil) {
            KeyboardShortcuts.setShortcut(apple ? area : nil, for: .captureAreaApple)
        }
        if KeyboardShortcuts.getShortcut(for: .captureScreenApple) != (apple ? screen : nil) {
            KeyboardShortcuts.setShortcut(apple ? screen : nil, for: .captureScreenApple)
        }
    }

    // MARK: Capturing

    /// Freezes the screens and lets you pick an area, a window or a screen.
    func start(_ mode: CaptureMode = .area) {
        guard Preferences.captureEnabled, !isCapturing, Self.hasPermission() else { return }
        isCapturing = true
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        Task {
            do {
                let snapshots = try await ScreenSnapshotter.snapshots(options: options)
                guard !snapshots.isEmpty else { isCapturing = false; return }
                let overlay = SelectionOverlay(snapshots: snapshots, targets: WindowLocator.onScreenWindows(),
                                               mode: mode) { [weak self] result in
                    guard let self else { return }
                    self.overlay = nil
                    Task { await self.finish(result, appName: appName) }
                }
                self.overlay = overlay
                overlay.show()
            } catch {
                isCapturing = false
                Log.app.error("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    /// The whole screen under the pointer, straight away.
    func captureScreen() {
        guard Preferences.captureEnabled, !isCapturing, Self.hasPermission() else { return }
        isCapturing = true
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let pointer = NSEvent.mouseLocation
        let display = NSScreen.screens.first { $0.frame.contains(pointer) }?.displayID
        Task {
            defer { isCapturing = false }
            guard let snapshot = try? await ScreenSnapshotter.snapshots(of: display, options: options).first else { return }
            deliver(Capture(image: snapshot.image, scale: snapshot.scale, kind: .screen, date: Date(), appName: appName))
        }
    }

    /// The area you captured last, without selecting again.
    func captureSameArea() {
        guard Preferences.captureEnabled, !isCapturing else { return }
        guard let area = Preferences.captureLastArea,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: area.midX, y: area.midY)) })
        else { return start(.area) }
        guard Self.hasPermission() else { return }
        isCapturing = true
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        Task {
            defer { isCapturing = false }
            guard let snapshot = try? await ScreenSnapshotter.snapshots(of: screen.displayID, options: options).first,
                  let image = snapshot.crop(area) else { return }
            deliver(Capture(image: image, scale: snapshot.scale, kind: .area, date: Date(), appName: appName))
        }
    }

    private var options: CaptureOptions {
        var hidden: Set<CGWindowID> = []
        if Preferences.captureCleanMenuBar {
            // Only the icons go; the clock and Control Center stay.
            hidden = Set(scanner.items.filter(\.isMovable).map(\.windowID)).union(ownStatusWindows())
        }
        return CaptureOptions(hiddenWindows: hidden, hidesDesktopIcons: Preferences.captureHidesDesktopIcons,
                              showsPointer: Preferences.captureShowsPointer)
    }

    private func finish(_ result: SelectionResult, appName: String?) async {
        defer { isCapturing = false }
        switch result {
        case .cancelled:
            return
        case .area(let rect, let snapshot):
            guard let image = snapshot.crop(rect) else { return }
            Preferences.captureLastArea = rect
            deliver(Capture(image: image, scale: snapshot.scale, kind: .area, date: Date(), appName: appName))
        case .window(let target, let snapshot):
            // The window on its own, with its shadow; the frozen pixels if that fails.
            if let window = try? await ScreenSnapshotter.window(target.windowID, shadow: Preferences.captureWindowShadow) {
                deliver(Capture(image: window.0, scale: window.1, kind: .window, date: Date(), appName: target.appName))
            } else if let image = snapshot.crop(target.frame) {
                deliver(Capture(image: image, scale: snapshot.scale, kind: .window, date: Date(), appName: target.appName))
            }
        case .screen(let snapshot):
            deliver(Capture(image: snapshot.image, scale: snapshot.scale, kind: .screen, date: Date(), appName: appName))
        }
    }

    /// Saves, copies and shows a capture, as Settings › Capture says.
    private func deliver(_ capture: Capture) {
        var capture = capture
        if Preferences.captureSound { shutter?.stop(); shutter?.play() }
        if Preferences.captureSaves {
            do {
                capture.fileURL = try CaptureStore.save(capture)
            } catch {
                Log.app.error("Saving a capture failed: \(error.localizedDescription)")
            }
        }
        if Preferences.captureCopies { CaptureStore.copy(capture.image, scale: capture.scale) }
        remember(capture)
        if Preferences.captureOpensEditor {
            openEditor(capture.id)
        } else if Preferences.captureShowsCard || capture.fileURL == nil && !Preferences.captureCopies {
            // With nothing else kept, the card is the only place it lives.
            cards.add(capture, status: status(of: capture))
        }
    }

    private func remember(_ capture: Capture) {
        captures[capture.id] = capture
        order.removeAll { $0 == capture.id }
        order.append(capture.id)
        // Keep the last few in memory; open editors keep their own.
        let open = Set(editors.values.map(\.captureID))
        while order.count > 12, let oldest = order.first(where: { !open.contains($0) }) {
            order.removeAll { $0 == oldest }
            captures[oldest] = nil
        }
    }

    func status(of capture: Capture) -> String {
        switch (capture.fileURL != nil, Preferences.captureCopies) {
        case (true, true): "Copied and saved"
        case (true, false): "Saved"
        case (false, true): "Copied"
        case (false, false): "Not saved yet"
        }
    }

    private static func hasPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // macOS asks once; after that only System Settings can allow it.
        if !CGRequestScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "Barn Owl needs Screen Recording to capture"
            alert.informativeText = "Turn on Barn Owl in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch Barn Owl."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

    // MARK: What cards and pins ask for

    func capture(_ id: UUID) -> Capture? { captures[id] }

    func copy(_ id: UUID) {
        guard let capture = captures[id] else { return }
        CaptureStore.copy(capture.image, scale: capture.scale)
        cards.update(id, status: capture.fileURL == nil ? "Copied" : "Copied and saved")
    }

    /// Saves it, or shows it in Finder if it's saved already.
    func save(_ id: UUID) {
        guard var capture = captures[id] else { return }
        if let url = capture.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        do {
            capture.fileURL = try CaptureStore.save(capture)
            captures[id] = capture
            cards.update(id, status: "Saved")
        } catch {
            Log.app.error("Saving a capture failed: \(error.localizedDescription)")
        }
    }

    /// A file to drag: the saved one, or a temporary copy.
    func fileForDragging(_ id: UUID) -> URL? {
        guard let capture = captures[id] else { return nil }
        return capture.fileURL ?? CaptureStore.temporaryFile(for: capture)
    }

    func pin(_ id: UUID) {
        guard let capture = captures[id] else { return }
        pin(capture.image, scale: capture.scale, captureID: id)
    }

    func pin(_ image: CGImage, scale: CGFloat, captureID: UUID?) {
        let pin = CapturePin(image: image, scale: scale)
        pin.onEdit = { [weak self] in
            guard let self else { return }
            // A pin of an edited capture opens what the pin shows.
            let capture = Capture(image: image, scale: scale, kind: .area, date: Date(), appName: nil,
                                  fileURL: captureID.flatMap { self.captures[$0]?.fileURL })
            self.remember(capture)
            self.openEditor(capture.id)
        }
        pin.onClose = { [weak self, weak pin] in self?.pins.removeAll { $0 === pin } }
        pins.append(pin)
        pin.show()
    }

    func openEditor(_ id: UUID) {
        guard let capture = captures[id] else { return }
        cards.remove(id)
        let title = capture.fileURL?.deletingPathExtension().lastPathComponent
            ?? CaptureStore.baseName(prefix: Preferences.captureNamePrefix, date: capture.date, appName: nil)
        let editor = CaptureEditor(image: capture.image, scale: capture.scale, title: title, host: self)
        editors[ObjectIdentifier(editor)] = (editor, id)
        editor.show()
    }
}

extension CaptureCoordinator: CaptureEditorHost {
    private func captureID(for editor: CaptureEditor) -> UUID? { editors[ObjectIdentifier(editor)]?.captureID }

    func editor(_ editor: CaptureEditor, copy image: CGImage) {
        guard let id = captureID(for: editor), let capture = captures[id] else { return }
        CaptureStore.copy(image, scale: capture.scale)
    }

    func editor(_ editor: CaptureEditor, save image: CGImage) {
        guard let id = captureID(for: editor), var capture = captures[id] else { return }
        do {
            capture.fileURL = try CaptureStore.save(capture, image: image)
            captures[id] = capture
        } catch {
            Log.app.error("Saving an edited capture failed: \(error.localizedDescription)")
        }
    }

    func editor(_ editor: CaptureEditor, pin image: CGImage) {
        guard let id = captureID(for: editor), let capture = captures[id] else { return }
        pin(image, scale: capture.scale, captureID: id)
    }

    func editor(_ editor: CaptureEditor, finish image: CGImage) {
        guard let id = captureID(for: editor), let capture = captures[id] else { return }
        CaptureStore.copy(image, scale: capture.scale)
        // Saved over its file if it has one; saved anew only if saving is on.
        if capture.fileURL != nil || Preferences.captureSaves { self.editor(editor, save: image) }
    }

    func editorDidClose(_ editor: CaptureEditor) {
        editors[ObjectIdentifier(editor)] = nil
    }
}

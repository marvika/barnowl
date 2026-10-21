import AppKit
import KeyboardShortcuts

/// Runs a capture from the shortcut to the card: takes the frozen picture,
/// lets you select, then saves, copies and shows what was caught, gives the
/// keyboard back to the app you were in, and keeps every capture editable.
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
    /// The last few captures, in memory; older ones come back from the library.
    @ObservationIgnored private var captures: [UUID: Capture] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private(set) var insights: [UUID: CaptureInsight] = [:]
    @ObservationIgnored private var scans: [UUID: Task<Void, Never>] = [:]
    /// The app you were in when the capture started, to give the keyboard back to.
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var targets: [WindowTarget] = []
    @ObservationIgnored private var lastAppleKeys: Bool?
    @ObservationIgnored private lazy var shutter = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true)
    private(set) var isCapturing = false
    /// The newest capture, for Edit Last Capture.
    private(set) var lastCaptureID: UUID?

    init(scanner: ItemScanner) {
        self.scanner = scanner
        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in self?.start(.area) }
        KeyboardShortcuts.onKeyUp(for: .captureScreen) { [weak self] in self?.captureScreen() }
        KeyboardShortcuts.onKeyUp(for: .captureSameArea) { [weak self] in self?.captureSameArea() }
        KeyboardShortcuts.onKeyUp(for: .captureAreaApple) { [weak self] in self?.start(.area) }
        KeyboardShortcuts.onKeyUp(for: .captureScreenApple) { [weak self] in self?.captureScreen() }
        KeyboardShortcuts.onKeyUp(for: .editLastCapture) { [weak self] in self?.editLastCapture() }
        applySettings()
        Task.detached(priority: .background) { CaptureLibrary.prune() }
    }

    /// Turns the shortcuts on or off with the setting, and takes ⌘⇧3 and ⌘⇧4
    /// only while you've asked for them and macOS's own are off.
    func applySettings() {
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureScreen, .captureSameArea, .editLastCapture]
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
        rememberFrontApp()
        let appName = previousApp?.localizedName
        Task {
            do {
                let snapshots = try await ScreenSnapshotter.snapshots(options: options)
                guard !snapshots.isEmpty else { isCapturing = false; return }
                targets = WindowLocator.onScreenWindows()
                let overlay = SelectionOverlay(snapshots: snapshots, targets: targets, mode: mode) { [weak self] result in
                    guard let self else { return }
                    self.overlay = nil
                    Task { await self.finish(result, appName: appName) }
                }
                overlay.onOptionsChanged = { [weak self, weak overlay] in
                    guard let self else { return }
                    // New pictures with the new choices; Barn Owl's overlay isn't in them.
                    Task {
                        if let fresh = try? await ScreenSnapshotter.snapshots(options: self.options) { overlay?.replace(fresh) }
                    }
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
        rememberFrontApp()
        let appName = previousApp?.localizedName
        let pointer = NSEvent.mouseLocation
        let display = NSScreen.screens.first { $0.frame.contains(pointer) }?.displayID
        targets = WindowLocator.onScreenWindows()
        Task {
            defer { isCapturing = false }
            guard let snapshot = try? await ScreenSnapshotter.snapshots(of: display, options: options).first else { return }
            deliver(Capture(image: snapshot.image, scale: snapshot.scale, kind: .screen, date: Date(), appName: appName),
                    action: .primary, windows: windowRects(in: snapshot.frame, scale: snapshot.scale))
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
        rememberFrontApp()
        let appName = previousApp?.localizedName
        targets = WindowLocator.onScreenWindows()
        Task {
            defer { isCapturing = false }
            guard let snapshot = try? await ScreenSnapshotter.snapshots(of: screen.displayID, options: options).first,
                  let image = snapshot.crop(area) else { return }
            deliver(Capture(image: image, scale: snapshot.scale, kind: .area, date: Date(), appName: appName),
                    action: .primary, windows: windowRects(in: area, scale: snapshot.scale))
        }
    }

    private var options: CaptureOptions {
        var hidden: Set<CGWindowID> = []
        if Preferences.captureCleanMenuBar {
            // Only the icons go; the clock and Control Center stay.
            hidden = Set(scanner.items.filter(\.isMovable).map(\.windowID)).union(ownStatusWindows())
        }
        return CaptureOptions(hiddenWindows: hidden, cleanMenuBar: Preferences.captureCleanMenuBar,
                              hidesDesktopIcons: Preferences.captureHidesDesktopIcons,
                              showsPointer: Preferences.captureShowsPointer)
    }

    private func rememberFrontApp() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? previousApp : front
    }

    private func finish(_ result: SelectionResult, appName: String?) async {
        defer { isCapturing = false }
        guard case .done(let target, let action) = result else {
            giveFocusBack()
            return
        }
        switch target {
        case .area(let rect, let snapshot):
            guard let image = snapshot.crop(rect) else { return giveFocusBack() }
            Preferences.captureLastArea = rect
            deliver(Capture(image: image, scale: snapshot.scale, kind: .area, date: Date(), appName: appName),
                    action: action, windows: windowRects(in: rect, scale: snapshot.scale))
        case .window(let window, let snapshot):
            // The window on its own, with its shadow; the frozen pixels if that fails.
            if let picture = try? await ScreenSnapshotter.window(window.windowID, shadow: Preferences.captureWindowShadow) {
                let whole = [CGRect(x: 0, y: 0, width: picture.0.width, height: picture.0.height)]
                deliver(Capture(image: picture.0, scale: picture.1, kind: .window, date: Date(), appName: window.appName),
                        action: action, windows: whole)
            } else if let image = snapshot.crop(window.frame) {
                deliver(Capture(image: image, scale: snapshot.scale, kind: .window, date: Date(), appName: window.appName),
                        action: action, windows: windowRects(in: window.frame, scale: snapshot.scale))
            }
        case .screen(let snapshot):
            deliver(Capture(image: snapshot.image, scale: snapshot.scale, kind: .screen, date: Date(), appName: appName),
                    action: action, windows: windowRects(in: snapshot.frame, scale: snapshot.scale))
        }
    }

    /// The windows inside a captured rect, in the capture's pixels from the top left.
    private func windowRects(in rect: CGRect, scale: CGFloat) -> [CGRect] {
        targets.compactMap { target in
            let inside = target.frame.intersection(rect)
            guard !inside.isEmpty else { return nil }
            return CGRect(x: (inside.minX - rect.minX) * scale, y: (rect.maxY - inside.maxY) * scale,
                          width: inside.width * scale, height: inside.height * scale)
        }
    }

    /// Saves, copies and shows a capture, as the action and Settings › Capture say.
    private func deliver(_ capture: Capture, action: CaptureAction, windows: [CGRect]) {
        var capture = capture
        let copies: Bool, saves: Bool
        switch action {
        case .primary: copies = Preferences.captureCopies; saves = Preferences.captureSaves
        case .copy: copies = true; saves = false
        case .save: copies = false; saves = true
        case .edit, .pin: copies = false; saves = false
        }
        if Preferences.captureSound { shutter?.stop(); shutter?.play() }
        if saves { capture.fileURL = CaptureStore.reserveURL(for: capture) }
        remember(capture)
        lastCaptureID = capture.id
        writeInBackground(capture, copies: copies, saves: saves)
        scanInBackground(capture, windows: windows)

        switch action {
        case .edit:
            openEditor(capture.id)
        case .pin:
            pin(capture.id)
            giveFocusBack()
        default:
            switch Preferences.captureThen {
            case .editor: openEditor(capture.id)
            case .card: cards.add(capture, status: status(copied: copies, saved: saves)); giveFocusBack()
            case .nothing:
                // With nothing else kept, the card is the only place it lives.
                if !copies && !saves { cards.add(capture, status: status(copied: false, saved: false)) }
                giveFocusBack()
            }
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: status(copied: copies, saved: saves),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// One PNG, made off the main thread, for the clipboard, the file and the library.
    private func writeInBackground(_ capture: Capture, copies: Bool, saves: Bool) {
        let image = capture.image, scale = capture.scale, id = capture.id
        let entry = CaptureLibrary.Entry(id: id, date: capture.date, scale: Double(scale), kind: capture.kind.rawValue,
                                         appName: capture.appName, fileURL: saves ? capture.fileURL : nil, edited: false)
        let fileURL = saves ? capture.fileURL : nil
        let atOneX = Preferences.captureAtOneX
        let kind = capture.kind
        Task {
            let png: Data? = try? await Task.detached(priority: .userInitiated) {
                try CaptureStore.encode(image, scale: scale, as: .png, atOneX: false)
            }.value
            if copies, let png { CaptureStore.copy(png: png) }
            let saved: Bool = await Task.detached(priority: .userInitiated) {
                try? CaptureLibrary.store(image, entry: entry)
                guard let fileURL else { return false }
                do {
                    let format = CaptureStore.format(of: fileURL)
                    let data: Data
                    if format == .png, !atOneX, let png {
                        data = png
                    } else {
                        data = try CaptureStore.encode(image, scale: scale, as: format, atOneX: atOneX)
                    }
                    try data.write(to: fileURL, options: .atomic)
                    CaptureStore.markAsScreenshot(fileURL, kind: kind)
                    CaptureLibrary.tag(fileURL, id: id)
                    return true
                } catch {
                    return false
                }
            }.value
            if fileURL != nil, !saved {
                Log.app.error("Saving a capture failed")
                captures[id]?.fileURL = nil
                cards.update(id, status: "Couldn't save · drag or copy it", kept: copies)
            }
        }
    }

    private func scanInBackground(_ capture: Capture, windows: [CGRect]) {
        let image = capture.image, id = capture.id
        guard Preferences.capturePrivateInfo else {
            insights[id] = CaptureInsight(windowRects: windows)
            return
        }
        scans[id] = Task {
            let insight = await Task.detached(priority: .utility) {
                await CaptureInsight.make(image: image, windowRects: windows)
            }.value
            guard !Task.isCancelled else { return }
            insights[id] = insight
            scans[id] = nil
            let secrets = insight.text.findings.filter { $0.kind.tier == .secret }
            if !secrets.isEmpty { cards.offerToHide(id, count: secrets.count) }
        }
    }

    private func remember(_ capture: Capture) {
        captures[capture.id] = capture
        order.removeAll { $0 == capture.id }
        order.append(capture.id)
        // Three in memory; the library has the rest. Open editors keep theirs.
        let open = Set(editors.values.map(\.captureID))
        while order.count > 3, let oldest = order.first(where: { !open.contains($0) }) {
            order.removeAll { $0 == oldest }
            captures[oldest] = nil
            insights[oldest] = nil
            scans[oldest]?.cancel()
            scans[oldest] = nil
        }
    }

    /// A capture by id: from memory, or back from the library.
    func capture(_ id: UUID) -> Capture? {
        if let capture = captures[id] { return capture }
        guard let entry = CaptureLibrary.entry(id), let image = CaptureLibrary.original(id) else { return nil }
        let capture = Capture(id: id, image: image, scale: entry.scale, kind: Capture.Kind(rawValue: entry.kind) ?? .area,
                              date: entry.date, appName: entry.appName, fileURL: entry.fileURL)
        remember(capture)
        return capture
    }

    func status(copied: Bool, saved: Bool) -> String {
        switch (saved, copied) {
        case (true, true): "Copied and saved"
        case (true, false): "Saved"
        case (false, true): "Copied"
        case (false, false): "Not saved · drag or copy it"
        }
    }

    /// Back to the app you were in, unless one of Barn Owl's own windows is in front.
    private func giveFocusBack() {
        FocusReturn.afterPanelCloses(to: previousApp)
    }

    /// One dialog at a time: Barn Owl's own explanation first, then macOS's.
    private static func hasPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let alert = NSAlert()
        let askedBefore = UserDefaults.standard.bool(forKey: "captureAskedPermission")
        if askedBefore {
            alert.messageText = "Screen Recording is off for Barn Owl"
            alert.informativeText = "Turn on Barn Owl in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch Barn Owl."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.messageText = "Let Barn Owl see your screen"
            alert.informativeText = "macOS asks you to allow Screen Recording before Barn Owl can capture. Nothing leaves your Mac."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Not Now")
        }
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        if askedBefore {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else {
            UserDefaults.standard.set(true, forKey: "captureAskedPermission")
            _ = CGRequestScreenCaptureAccess()
        }
        return false
    }

    // MARK: What cards and pins ask for

    func copy(_ id: UUID) {
        guard let capture = capture(id) else { return }
        Task {
            await CaptureStore.copy(capture.image, scale: capture.scale)
            cards.update(id, status: capture.fileURL == nil ? "Copied" : "Copied and saved", kept: true)
        }
    }

    /// Saves it, or shows it in Finder if it's saved already.
    func save(_ id: UUID) {
        guard var capture = capture(id) else { return }
        if let url = capture.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        do {
            let url = try CaptureStore.save(capture)
            capture.fileURL = url
            captures[id] = capture
            CaptureLibrary.setFile(url, for: id)
            cards.update(id, status: "Saved", kept: true)
        } catch {
            Log.app.error("Saving a capture failed: \(error.localizedDescription)")
        }
    }

    /// A file to drag: the saved one, or a temporary copy.
    func fileForDragging(_ id: UUID) -> URL? {
        guard let capture = capture(id) else { return nil }
        return capture.fileURL ?? CaptureStore.temporaryFile(for: capture)
    }

    func isSaved(_ id: UUID) -> Bool { capture(id)?.fileURL != nil }

    func pin(_ id: UUID) {
        guard let capture = capture(id) else { return }
        pin(capture.image, scale: capture.scale, captureID: id)
    }

    func pin(_ image: CGImage, scale: CGFloat, captureID: UUID?) {
        let pin = CapturePin(image: image, scale: scale)
        pin.onEdit = { [weak self] in
            guard let self, let captureID else { return }
            self.openEditor(captureID)
        }
        pin.onClose = { [weak self, weak pin] in self?.pins.removeAll { $0 === pin } }
        pins.append(pin)
        pin.show()
    }

    /// Covers what looks secret with solid bars, in the clipboard and the file.
    /// The library keeps the original, so Undo can bring it back.
    func hideSecrets(_ id: UUID) {
        guard var capture = capture(id), let insight = insights[id] else { return }
        let rects = insight.text.findings.filter { $0.kind.tier == .secret }.map(\.rect)
        guard let covered = Redactor.cover(capture.image, rects: rects) else { return }
        let original = capture.image
        capture.image = covered
        captures[id] = capture
        rewrite(capture)
        cards.update(id, image: covered, status: "Hidden", undo: { [weak self] in
            guard let self, var restored = self.capture(id) else { return }
            restored.image = original
            self.captures[id] = restored
            self.rewrite(restored)
            let status = self.status(copied: Preferences.captureCopies, saved: restored.fileURL != nil)
            self.cards.update(id, image: original, status: status, undo: nil)
        })
    }

    /// Puts a changed capture back on the clipboard and over its file.
    private func rewrite(_ capture: Capture) {
        Task {
            await CaptureStore.copy(capture.image, scale: capture.scale)
            if capture.fileURL != nil { _ = try? CaptureStore.save(capture) }
        }
    }

    // MARK: The editor

    func editLastCapture() {
        guard Preferences.captureEnabled else { return }
        rememberFrontApp()
        guard let id = lastCaptureID ?? CaptureLibrary.latest()?.id else { return }
        openEditor(id)
    }

    func openEditor(_ id: UUID) {
        guard let capture = capture(id) else { return }
        cards.remove(id)
        if let open = editors.values.first(where: { $0.captureID == id }) {
            open.editor.show()
            return
        }
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
        guard let id = captureID(for: editor), let capture = capture(id) else { return }
        Task { await CaptureStore.copy(image, scale: capture.scale) }
    }

    func editor(_ editor: CaptureEditor, save image: CGImage) {
        guard let id = captureID(for: editor), var capture = capture(id) else { return }
        do {
            let url = try CaptureStore.save(capture, image: image)
            capture.fileURL = url
            captures[id] = capture
            CaptureLibrary.setFile(url, for: id)
        } catch {
            Log.app.error("Saving an edited capture failed: \(error.localizedDescription)")
        }
    }

    func editor(_ editor: CaptureEditor, pin image: CGImage) {
        guard let id = captureID(for: editor), let capture = capture(id) else { return }
        pin(image, scale: capture.scale, captureID: id)
    }

    func editor(_ editor: CaptureEditor, finish image: CGImage) {
        guard let id = captureID(for: editor), let capture = capture(id) else { return }
        Task { await CaptureStore.copy(image, scale: capture.scale) }
        // Saved over its file if it has one; saved anew only if saving is on.
        if capture.fileURL != nil || Preferences.captureSaves { self.editor(editor, save: image) }
    }

    func editorDidClose(_ editor: CaptureEditor) {
        editors[ObjectIdentifier(editor)] = nil
        if editors.isEmpty { giveFocusBack() }
    }
}

/// Solid bars over parts of an image, the colour of the text they cover.
enum Redactor {
    static func cover(_ image: CGImage, rects: [CGRect]) -> CGImage? {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for rect in rects {
            // Rects are from the top left; the context draws from the bottom.
            let flipped = CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
            let corner = min(4, rect.height / 4)
            context.setFillColor(barColour(in: image, rect: rect))
            context.addPath(CGPath(roundedRect: flipped, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
        }
        return context.makeImage()
    }

    /// Dark bars on light backgrounds, light bars on dark ones, so they read as covered.
    static func barColour(in image: CGImage, rect: CGRect) -> CGColor {
        let light = averageLuminance(in: image, rect: rect) > 0.5
        return light ? CGColor(red: 0.086, green: 0.082, blue: 0.122, alpha: 1) : CGColor(gray: 0.94, alpha: 1)
    }

    static func averageLuminance(in image: CGImage, rect: CGRect) -> CGFloat {
        guard let crop = image.cropping(to: rect.integral),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.interpolationQuality = .medium
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return 1 }
        let red = CGFloat(data[0]) * 0.2126
        let green = CGFloat(data[1]) * 0.7152
        let blue = CGFloat(data[2]) * 0.0722
        return (red + green + blue) / 255
    }
}

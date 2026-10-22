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
    /// Editors closed with Done, so their close isn't mistaken for leaving.
    @ObservationIgnored private var finished: Set<UUID> = []
    /// Captures that went to the clipboard.
    @ObservationIgnored private var copied: Set<UUID> = []
    /// The last few captures, in memory; older ones come back from the library.
    @ObservationIgnored private var captures: [UUID: Capture] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private(set) var insights: [UUID: CaptureInsight] = [:]
    @ObservationIgnored private var scans: [UUID: Task<Void, Never>] = [:]
    /// The app you were in when the capture started, to give the keyboard back to.
    @ObservationIgnored private var previousApp: NSRunningApplication?
    /// The last app other than Barn Owl you were in, for when Barn Owl is in front.
    @ObservationIgnored private var lastOtherApp: NSRunningApplication?
    /// Each capture's file, clipboard and library writes, one after another.
    @ObservationIgnored private var writes: [UUID: Task<Void, Never>] = [:]
    /// The capture Barn Owl last put on the clipboard, and the clipboard's count right after.
    @ObservationIgnored private var onClipboard: (id: UUID, changeCount: Int)?
    /// Copies made ahead of a drag, so pulling a card out never waits on an encode.
    @ObservationIgnored private var dragFiles: [UUID: (image: CGImage, url: URL)] = [:]
    /// Pictures opened with Barn Owl, so opening one again finds its editor.
    @ObservationIgnored private var openedFiles: [URL: UUID] = [:]
    /// What each editor's Save last wrote, so closing right after doesn't count as unsaved.
    @ObservationIgnored private var savedDocuments: [UUID: EditorDocument] = [:]
    @ObservationIgnored private var lastKeepDays: Int?
    @ObservationIgnored private var targets: [WindowTarget] = []
    @ObservationIgnored private var lastAppleKeys: Bool?
    /// Capture History's window, once it's been opened.
    @ObservationIgnored private var history: CaptureHistoryWindowController?
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
        KeyboardShortcuts.onKeyUp(for: .captureText) { [weak self] in self?.captureText() }
        KeyboardShortcuts.onKeyUp(for: .captureHistory) { [weak self] in self?.showHistory() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                // Only apps with windows: Spotlight or Raycast have nowhere to type.
                guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      app.activationPolicy == .regular else { return }
                self?.lastOtherApp = app
            }
        }
        applySettings()
        Task.detached(priority: .background) { CaptureStore.tidyTemporaryFiles() }
    }

    /// Turns the shortcuts on or off with the setting, and takes ⇧⌘3 and ⇧⌘4
    /// only while you've asked for them and macOS's own are off.
    func applySettings() {
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureScreen, .captureSameArea, .editLastCapture,
                                               .captureText, .captureHistory]
        if Preferences.captureEnabled { KeyboardShortcuts.enable(names) } else { KeyboardShortcuts.disable(names) }
        // At launch, and whenever you keep captures for less time.
        if CaptureLibrary.keepDays != lastKeepDays {
            lastKeepDays = CaptureLibrary.keepDays
            let days = CaptureLibrary.keepDays
            Task.detached(priority: .background) { CaptureLibrary.prune(days: days) }
        }
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
    /// `copiesText`: Return copies the words in what you select instead of the picture.
    func start(_ mode: CaptureMode = .area, copiesText: Bool = false) {
        guard Preferences.captureEnabled, !isCapturing, Self.hasPermission() else { return }
        isCapturing = true
        rememberFrontApp()
        let appName = previousApp?.localizedName
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshots = try await ScreenSnapshotter.snapshots(options: options)
                guard !snapshots.isEmpty else { isCapturing = false; return NSSound.beep() }
                targets = WindowLocator.onScreenWindows()
                let overlay = SelectionOverlay(snapshots: snapshots, targets: targets, mode: mode,
                                               copiesText: copiesText) { [weak self] result in
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
                NSSound.beep()
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
        // NSMouseInRect counts the top and right edges too, where the pointer can rest.
        let display = (NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main)?.displayID
        targets = WindowLocator.onScreenWindows()
        Task {
            defer { isCapturing = false }
            guard let snapshot = try? await ScreenSnapshotter.snapshots(of: display, options: options).first else {
                return NSSound.beep()
            }
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
                  let image = snapshot.crop(area) else { return NSSound.beep() }
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
        previousApp = front == nil || front == .current ? lastOtherApp ?? previousApp : front
    }

    private func finish(_ result: SelectionResult, appName: String?) async {
        defer { isCapturing = false }
        guard case .done(let target, let action) = result else {
            giveFocusBack()
            return
        }
        switch target {
        case .area(let rect, let snapshot):
            guard let image = snapshot.crop(rect) else {
                NSSound.beep()
                return giveFocusBack()
            }
            Preferences.captureLastArea = rect
            deliver(Capture(image: image, scale: snapshot.scale, kind: .area, date: Date(), appName: appName),
                    action: action, windows: windowRects(in: rect, scale: snapshot.scale))
        case .window(let window, let snapshot):
            Preferences.captureLastArea = window.frame
            // The window on its own, with its shadow; the frozen pixels if that fails.
            if let picture = try? await ScreenSnapshotter.window(window.windowID, shadow: Preferences.captureWindowShadow) {
                let whole = [CGRect(x: 0, y: 0, width: picture.0.width, height: picture.0.height)]
                deliver(Capture(image: picture.0, scale: picture.1, kind: .window, date: Date(), appName: window.appName),
                        action: action, windows: whole)
            } else if let image = snapshot.crop(window.frame) {
                deliver(Capture(image: image, scale: snapshot.scale, kind: .window, date: Date(), appName: window.appName),
                        action: action, windows: windowRects(in: window.frame, scale: snapshot.scale))
            } else {
                NSSound.beep()
                giveFocusBack()
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
        case .edit, .pin, .copyText: copies = false; saves = false
        }
        if Preferences.captureSound { shutter?.stop(); shutter?.play() }
        if saves { capture.fileURL = CaptureStore.reserveURL(for: capture) }
        if copies { copied.insert(capture.id) }
        remember(capture)
        lastCaptureID = capture.id
        writeInBackground(capture, copies: copies, saves: saves, windows: windows)
        scanInBackground(capture, windows: windows)

        switch action {
        case .edit:
            openEditor(capture.id)
        case .pin:
            pin(capture.id)
            giveFocusBack()
        case .copyText:
            // The card says how it went; the picture is still there to copy or save.
            cards.add(capture, status: "Reading the text…", kept: true)
            giveFocusBack()
            copyText(capture.id)
            return
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
    private func writeInBackground(_ capture: Capture, copies: Bool, saves: Bool, windows: [CGRect]) {
        let image = capture.image, scale = capture.scale, id = capture.id
        let entry = CaptureLibrary.Entry(id: id, date: capture.date, scale: Double(scale), kind: capture.kind.rawValue,
                                         appName: capture.appName, fileURL: saves ? capture.fileURL : nil, edited: false,
                                         windows: windows)
        let fileURL = saves ? capture.fileURL : nil
        let atOneX = Preferences.captureAtOneX
        let kind = capture.kind
        inOrder(id) { [self] in
            let png: Data? = try? await Task.detached(priority: .userInitiated) {
                try CaptureStore.encode(image, scale: scale, as: .png, atOneX: false)
            }.value
            if copies, let png {
                CaptureStore.copy(png: png)
                onClipboard = (id, NSPasteboard.general.changeCount)
            }
            // The file first, since the card already offers it; then the library.
            let saved: Bool = await Task.detached(priority: .userInitiated) {
                var kept = entry
                defer {
                    try? CaptureLibrary.store(image, png: png, entry: kept)
                    CaptureLibrary.storeThumbnail(image, for: id)
                }
                guard let fileURL else { return false }
                defer { CaptureStore.release(fileURL) }
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
                    kept.fileStamp = CaptureLibrary.FileStamp(of: fileURL)
                    return true
                } catch {
                    return false
                }
            }.value
            if fileURL != nil, !saved {
                Log.app.error("Saving a capture failed")
                captures[id]?.fileURL = nil
                couldNotSave(id, kept: copies)
            }
        }
    }

    /// Says so on the card, or with a card if there's none any more.
    private func couldNotSave(_ id: UUID, kept: Bool) {
        if cards.has(id) {
            cards.update(id, status: "Couldn't save · drag or copy it", kept: kept)
        } else if let capture = capture(id) {
            cards.add(capture, status: "Couldn't save · drag or copy it", kept: kept)
        } else {
            NSSound.beep()
        }
    }

    /// Keeps history's thumbnail in step with how the capture looks now.
    private func storeThumbnail(_ image: CGImage, for id: UUID) {
        inOrder(id) {
            await Task.detached(priority: .utility) { CaptureLibrary.storeThumbnail(image, for: id) }.value
        }
    }

    /// Puts a capture on the clipboard once its earlier writes are done.
    @discardableResult
    private func copyInOrder(_ id: UUID, image: CGImage, scale: CGFloat) -> Task<Void, Never> {
        copied.insert(id)
        return inOrder(id) { [self] in
            await CaptureStore.copy(image, scale: scale)
            onClipboard = (id, NSPasteboard.general.changeCount)
        }
    }

    /// Whether the clipboard still holds this capture, not something copied since.
    private func clipboardHolds(_ id: UUID) -> Bool {
        onClipboard?.id == id && onClipboard?.changeCount == NSPasteboard.general.changeCount
    }

    /// Runs a capture's writes in the order they were asked for, so a quick
    /// Hide or edit never loses to the first save still encoding.
    @discardableResult
    private func inOrder<T: Sendable>(_ id: UUID, _ work: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = writes[id]
        let task = Task { @MainActor in
            await previous?.value
            return await work()
        }
        writes[id] = Task { _ = await task.value }
        return task
    }

    /// Writes over the capture's file, or a new one in the capture folder, off the main thread.
    @discardableResult
    private func saveFile(_ id: UUID, image: CGImage? = nil) -> Task<URL?, Never> {
        inOrder(id) { [self] in
            guard var capture = capture(id) else { return nil }
            let picture = image ?? capture.image
            let url = capture.fileURL ?? CaptureStore.reserveURL(for: capture)
            let scale = capture.scale, kind = capture.kind, atOneX = Preferences.captureAtOneX
            let saved = await Task.detached(priority: .userInitiated) {
                defer { CaptureStore.release(url) }
                do {
                    let data = try CaptureStore.encode(picture, scale: scale, as: CaptureStore.format(of: url), atOneX: atOneX)
                    try data.write(to: url, options: .atomic)
                    CaptureStore.markAsScreenshot(url, kind: kind)
                    return true
                } catch {
                    return false
                }
            }.value
            guard saved else {
                Log.app.error("Saving a capture failed")
                return nil
            }
            capture = self.capture(id) ?? capture
            capture.fileURL = url
            // Unless the picture changed again while this one was being written.
            if capture.image === picture { capture.unsavedEdits = false }
            captures[id] = capture
            CaptureLibrary.setFile(url, for: id)
            return url
        }
    }

    /// Reads the capture's text on the Mac, for smart marks, Copy Text and history search;
    /// private info is only looked for, and offered, when Settings › Capture says so.
    private func scanInBackground(_ capture: Capture, windows: [CGRect]) {
        let image = capture.image, id = capture.id
        let looksForPrivateInfo = Preferences.capturePrivateInfo
        scans[id] = Task {
            var insight = await Task.detached(priority: .utility) {
                await CaptureInsight.make(image: image, windowRects: windows)
            }.value
            if !looksForPrivateInfo {
                insight.text.findings = []
                insight.lookedForPrivateInfo = false
            }
            guard !Task.isCancelled else { return }
            insights[id] = insight
            scans[id] = nil
            // Kept with the capture, for searching history and Copy Text later.
            let words = insight.text.plainText()
            if !words.isEmpty { inOrder(id) { CaptureLibrary.update(id) { $0.text = words } } }
            editors.values.first { $0.captureID == id }?.editor.update(insight: insight)
            // Only secrets interrupt; once offered, Hide covers everything private.
            // Secrets named first, as the editor's banner does.
            let findings = insight.text.findings.filter(\.kind.isDefault).sorted { $0.kind.tier > $1.kind.tier }
            if findings.contains(where: { $0.kind.tier == .secret }) {
                cards.offerToHide(id, count: findings.count, title: Self.describe(findings))
            }
        }
    }

    private func remember(_ capture: Capture) {
        captures[capture.id] = capture
        order.removeAll { $0 == capture.id }
        order.append(capture.id)
        // Three in memory; the library has the rest. Open editors and cards keep theirs.
        let open = Set(editors.values.map(\.captureID))
        while order.count > 3, let oldest = order.first(where: { !open.contains($0) && !cards.has($0) && $0 != capture.id }) {
            order.removeAll { $0 == oldest }
            captures[oldest] = nil
            if let file = dragFiles.removeValue(forKey: oldest) { try? FileManager.default.removeItem(at: file.url) }
            insights[oldest] = nil
            scans[oldest]?.cancel()
            scans[oldest] = nil
        }
    }

    /// A capture by id: from memory, or back from the library.
    func capture(_ id: UUID) -> Capture? {
        if let capture = captures[id] { return capture }
        guard let capture = keptCapture(id, rendered: true) else { return nil }
        remember(capture)
        return capture
    }

    /// A capture back from the library. `rendered`: as it looks now, its marks drawn on, so
    /// copying, pinning or dragging it from history gives what the thumbnail shows; without,
    /// just the original (the editor draws the marks itself).
    private func keptCapture(_ id: UUID, rendered: Bool) -> Capture? {
        guard let entry = CaptureLibrary.entry(id), let original = CaptureLibrary.original(id) else { return nil }
        let document = rendered && entry.edited ? storedDocument(id) : nil
        let image = document.flatMap { renderer(for: original, scale: entry.scale, document: $0).render($0) } ?? original
        var capture = Capture(id: id, image: image, scale: entry.scale, kind: Capture.Kind(rawValue: entry.kind) ?? .area,
                              date: entry.date, appName: entry.appName, fileURL: entry.fileURL)
        if let file = entry.fileURL, let stamp = entry.fileStamp {
            if !stamp.matches(CaptureLibrary.FileStamp(of: file)) {
                // Changed elsewhere, or gone: not this capture's to write over any more.
                capture.fileURL = nil
            } else if entry.edited, CaptureLibrary.documentIsNewer(than: stamp, for: id) {
                // Marks changed after the file was written: dragging or saving uses the new look.
                capture.unsavedEdits = true
            }
        }
        return capture
    }

    /// Draws marks over `image`, with the desktop picture when the frame asks for it.
    private func renderer(for image: CGImage, scale: CGFloat, document: EditorDocument) -> AnnotationRenderer {
        let renderer = AnnotationRenderer(image: image, scale: scale)
        if document.frame.background == .desktop, let screen = NSScreen.main ?? NSScreen.screens.first,
           let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            renderer.setDesktop(AnnotationRenderer.loadDesktopPicture(from: url))
        }
        return renderer
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
            alert.informativeText = "Turn on Barn Owl in System Settings › Privacy & Security › Screen & System Audio Recording, then choose Relaunch. Barn Owl can't capture until it restarts."
            alert.addButton(withTitle: "Relaunch Barn Owl")
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.messageText = "Let Barn Owl see your screen"
            alert.informativeText = "macOS asks you to allow Screen Recording before Barn Owl can capture. Nothing leaves your Mac. Once it's allowed, relaunch Barn Owl and press the shortcut again."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Not Now")
        }
        NSApp.activate()
        let answer = alert.runModal()
        if askedBefore {
            if answer == .alertFirstButtonReturn {
                Relaunch.now()
            } else if answer == .alertSecondButtonReturn,
                      let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return false
        }
        guard answer == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: "captureAskedPermission")
        _ = CGRequestScreenCaptureAccess()
        return false
    }

    // MARK: Text

    /// A shortcut of its own: select something, and its words go to the clipboard.
    func captureText() {
        start(.area, copiesText: true)
    }

    /// Without a kept copy, the edited picture is all there is, cropped and framed: its
    /// text is read again when it's next wanted, so places in it line up.
    private func forgetTextIfNotKept(_ id: UUID) {
        guard CaptureLibrary.entry(id) == nil else { return }
        insights[id] = nil
    }

    /// The words you can see: inside its crop, and not under a redaction.
    private func visibleText(_ text: CaptureText, of id: UUID) -> String {
        guard let document = storedDocument(id) else { return text.plainText() }
        let covered = document.marks.filter { $0.kind == .redact }.map(\.rect)
        return text.plainText(within: document.crop, excluding: covered)
    }

    /// Whether there's text worth copying, as far as is known yet.
    func hasText(_ id: UUID) -> Bool {
        if let insight = insights[id], insight.textWasRead { return !visibleText(insight.text, of: id).isEmpty }
        return CaptureLibrary.entry(id)?.text?.isEmpty == false
    }

    /// Puts the capture's words on the clipboard, in reading order, and says how it went.
    /// Read again carefully, with words corrected, from the original when it's kept.
    func copyText(_ id: UUID) {
        guard let capture = capture(id) else { return NSSound.beep() }
        let image = storedDocument(id) != nil ? (CaptureLibrary.original(id) ?? capture.image) : capture.image
        Task {
            let read = try? await Task.detached(priority: .userInitiated) {
                try await SensitiveTextFinder.scan(image, forReading: true)
            }.value
            let words = read.map { visibleText($0, of: id) } ?? ""
            let status: String
            if read == nil {
                status = "Couldn't read the text"
                NSSound.beep()
            } else if words.isEmpty {
                status = "No text found"
                NSSound.beep()
            } else {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(words, forType: .string)
                // The clipboard has words now, not this capture's picture.
                onClipboard = nil
                copied.remove(id)
                let lines = words.components(separatedBy: "\n").count
                status = lines == 1 ? "Text copied" : "Text copied · \(lines) lines"
            }
            cards.update(id, status: status, kept: true)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: status, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    // MARK: What cards and pins ask for

    func copy(_ id: UUID) {
        guard let capture = capture(id) else { return }
        let copying = copyInOrder(id, image: capture.image, scale: capture.scale)
        Task {
            await copying.value
            cards.update(id, status: status(copied: true, saved: isSaved(id)), kept: true)
        }
    }

    /// Saves it, or shows it in Finder if it's saved already.
    func save(_ id: UUID) {
        guard let capture = capture(id) else { return }
        if isSaved(id), let url = capture.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        let saving = saveFile(id)
        Task {
            let saved = await saving.value != nil
            let copies = copied.contains(id)
            if saved {
                cards.update(id, status: status(copied: copies, saved: true), kept: true)
            } else {
                couldNotSave(id, kept: copies)
            }
        }
    }

    /// A file to drag: the saved one, or a temporary copy of what the card shows.
    func fileForDragging(_ id: UUID) -> URL? {
        guard let capture = capture(id) else { return nil }
        if isSaved(id), let url = capture.fileURL { return url }
        if let ready = dragFiles[id], ready.image === capture.image { return ready.url }
        return CaptureStore.temporaryFile(for: capture)
    }

    /// Makes the copy a drag would need, off the main thread, while you point at the card.
    func prepareDragFile(_ id: UUID) {
        guard !isSaved(id), let capture = capture(id), dragFiles[id]?.image !== capture.image else { return }
        let image = capture.image
        Task {
            let url = await Task.detached(priority: .userInitiated) { CaptureStore.temporaryFile(for: capture) }.value
            guard let url, self.captures[id]?.image === image else { return }
            dragFiles[id] = (image, url)
        }
    }

    /// Saved, and the file on disk is what the card shows: not still being
    /// written, moved away, or behind later edits. Never decodes a picture.
    func isSaved(_ id: UUID) -> Bool {
        let url = captures[id].map { $0.unsavedEdits ? nil : $0.fileURL } ?? CaptureLibrary.entry(id)?.fileURL
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

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

    /// Hides what looks secret, in the clipboard and the file, with a light blur (or the
    /// Redact style you chose). They're ordinary redaction marks, so the editor can take them off
    /// again; the library keeps the original.
    func hideSecrets(_ id: UUID) {
        guard let capture = capture(id), let insight = insights[id] else { return }
        let findings = insight.text.findings.filter(\.kind.isDefault)
        let before = CaptureLibrary.document(id)
        var document = storedDocument(id) ?? EditorDocument(imageSize: CGSize(width: capture.image.width, height: capture.image.height),
                                                             scale: capture.scale)
        // What it looks like now, for Undo; marks are drawn again over the original, never twice.
        let original = capture.image
        let base = storedDocument(id) != nil ? (CaptureLibrary.original(id) ?? original) : original
        let book = EditorModel.savedStyleBook()
        let style = book.hideStyle
        for finding in findings {
            let solid = style.redact == .solid && !book.redactColourChosen
            let colour = solid ? ImageSampler.redactionColour(in: base, rect: finding.rect) : book.redactColour
            var mark = Mark(kind: .redact, colour: colour, style: style,
                            start: finding.rect.origin, end: CGPoint(x: finding.rect.maxX, y: finding.rect.maxY))
            mark.origin = MarkOrigin(source: .privateInfo, category: finding.kind.rawValue)
            document.marks.append(mark)
        }
        let renderer = renderer(for: base, scale: capture.scale, document: document)
        let covering = document
        // Nothing secret to paste while the covered copy is being made.
        if clipboardHolds(id) { NSPasteboard.general.clearContents() }
        cards.update(id, status: "Hiding…", kept: false)
        Task {
            guard let covered = await Task.detached(priority: .userInitiated, operation: { renderer.render(covering) }).value,
                  var capture = self.capture(id), capture.image === original else { return NSSound.beep() }
            store(covering, for: id)
            capture.image = covered
            capture.unsavedEdits = capture.fileURL != nil
            captures[id] = capture
            storeThumbnail(covered, for: id)
            cards.update(id, image: covered, status: "Hiding…", undo: nil)
            // "Hidden" only once the file and the clipboard are covered too.
            await rewrite(capture).value
            let kept = isSaved(id) || clipboardHolds(id)
            cards.update(id, status: "Hidden", kept: kept)
            cards.update(id, image: covered, status: "Hidden", undo: { [weak self] in
                guard let self, var restored = self.capture(id), restored.image === covered else { return }
                restored.image = original
                restored.unsavedEdits = restored.fileURL != nil
                self.captures[id] = restored
                self.storeThumbnail(original, for: id)
                let data = before ?? Data()
                self.inOrder(id) { try? CaptureLibrary.storeDocument(data, for: id) }
                let restoring = self.rewrite(restored)
                Task {
                    await restoring.value
                    let status = self.status(copied: self.clipboardHolds(id), saved: self.isSaved(id))
                    self.cards.update(id, image: original, status: status, undo: nil)
                }
            })
        }
    }

    /// "A key or token", "A card number and an email address", "4 private details".
    static func describe(_ findings: [SensitiveTextFinder.Finding]) -> String {
        var kinds: [SensitiveTextFinder.Kind] = []
        for finding in findings where !kinds.contains(finding.kind) { kinds.append(finding.kind) }
        let name: String
        switch kinds.count {
        case 1 where findings.count == 1: name = kinds[0].phrase
        case 2 where findings.count == 2: name = "\(kinds[0].phrase) and \(kinds[1].phrase)"
        default: return "\(findings.count) private details"
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private func storedDocument(_ id: UUID) -> EditorDocument? {
        guard let data = CaptureLibrary.document(id), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(EditorDocument.self, from: data)
    }

    private func store(_ document: EditorDocument, for id: UUID) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        inOrder(id) { try? CaptureLibrary.storeDocument(data, for: id) }
    }

    /// Puts a changed capture back on the clipboard, if it's still there, and over its file.
    /// The task finishes once both are done.
    @discardableResult
    private func rewrite(_ capture: Capture) -> Task<Void, Never> {
        let id = capture.id, image = capture.image, scale = capture.scale
        // Decided when its turn comes, after the first copy has landed.
        inOrder(id) { [self] in
            guard clipboardHolds(id) else { return }
            await CaptureStore.copy(image, scale: scale)
            onClipboard = (id, NSPasteboard.general.changeCount)
        }
        if capture.fileURL != nil { saveFile(id, image: image) }
        return inOrder(id) {}
    }

    /// Quitting: every open editor's marks are kept straight away.
    func keepOpenEditors() {
        for (editor, id) in editors.values where editor.model.isEdited {
            guard let data = try? JSONEncoder().encode(editor.model.document) else { continue }
            try? CaptureLibrary.storeDocument(data, for: id)
        }
    }

    // MARK: The editor

    func editLastCapture() {
        guard Preferences.captureEnabled else { return }
        // Never under a frozen screen.
        overlay?.finish(.cancelled)
        rememberFrontApp()
        guard let id = lastCaptureID ?? CaptureLibrary.latest()?.id else { return NSSound.beep() }
        openEditor(id)
    }

    /// Opens a picture in the editor. One Barn Owl saved, unchanged since, comes back with
    /// its marks still movable, from wherever it is now; any other picture (a copy, one
    /// edited elsewhere, anyone else's) opens as a new capture, and Done saves a copy rather
    /// than writing over it.
    func open(_ file: URL) {
        if let id = CaptureLibrary.id(of: file), let entry = CaptureLibrary.entry(id), CaptureLibrary.isOwn(file, entry: entry),
           var capture = capture(id) {
            if capture.fileURL?.standardizedFileURL != file.standardizedFileURL {
                // Moved or renamed since: Done saves over it where it is now.
                capture.fileURL = file
                captures[id] = capture
                CaptureLibrary.setFile(file, for: id)
            }
            rememberFrontApp()
            return openEditor(id)
        }
        // Opened already: the same editor, not a second copy.
        if let id = openedFiles[file.standardizedFileURL], captures[id] != nil || CaptureLibrary.entry(id) != nil {
            rememberFrontApp()
            return openEditor(id)
        }
        guard let picture = Self.picture(at: file) else {
            let alert = NSAlert()
            alert.messageText = "Barn Owl can't open “\(file.lastPathComponent)”"
            alert.informativeText = "It isn't a picture Barn Owl can read. Barn Owl opens PNG, JPEG and HEIC files."
            NSApp.activate()
            alert.runModal()
            return
        }
        var capture = Capture(image: picture.image, scale: picture.scale, kind: .area, date: Date(), appName: nil)
        capture.openedFrom = file.deletingPathExtension().lastPathComponent
        openedFiles[file.standardizedFileURL] = capture.id
        remember(capture)
        lastCaptureID = capture.id
        writeInBackground(capture, copies: false, saves: false, windows: [])
        scanInBackground(capture, windows: [])
        rememberFrontApp()
        openEditor(capture.id)
    }

    /// A picture file's pixels the right way up (a portrait photo turned as it was taken),
    /// and its scale: 144 dpi is a Retina screenshot, two pixels to a point.
    static func picture(at file: URL) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double) ?? 72
        // Print resolutions (300 dpi) aren't screen scales.
        return (CaptureStore.ownBitmap(image), min(2, max(1, (dpi / 72).rounded())))
    }

    func openEditor(_ id: UUID) {
        // The editor draws the marks itself: no need to render them here.
        guard let capture = captures[id] ?? keptCapture(id, rendered: false) else { return }
        if editors.isEmpty { rememberFrontApp() }
        cards.remove(id)
        if let open = editors.values.first(where: { $0.captureID == id }) {
            open.editor.show()
            return
        }
        let title = capture.openedFrom ?? capture.fileURL?.deletingPathExtension().lastPathComponent
            ?? CaptureStore.baseName(prefix: Preferences.captureNamePrefix, date: capture.date, appName: nil)
        // The marks stay editable: the original pixels plus the stored document.
        let document = storedDocument(id)
        let image = document != nil ? (CaptureLibrary.original(id) ?? capture.image) : capture.image
        let editor = CaptureEditor(image: image, scale: capture.scale, title: title, document: document,
                                   insight: insights[id], host: self)
        editors[ObjectIdentifier(editor)] = (editor, id)
        // Reopened after Barn Owl restarted: read its text again, so private info is still
        // offered and Done still asks about a key.
        if insights[id] == nil, scans[id] == nil {
            var original = capture
            original.image = image
            scanInBackground(original, windows: CaptureLibrary.entry(id)?.windows ?? [])
        }
        // A real app while you edit: in the Dock and ⌘Tab, with its menus, so
        // the editor never gets lost behind other windows.
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        editor.show()
    }

    // MARK: History

    /// Every kept capture, in a window of its own; Barn Owl is a real app while it's open.
    func showHistory() {
        overlay?.finish(.cancelled)
        if editors.isEmpty, history?.isOpen != true { rememberFrontApp() }
        let history = self.history ?? CaptureHistoryWindowController(host: self)
        history.onClose = { [weak self] in self?.becomeAccessoryWhenDone() }
        self.history = history
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        history.show()
    }

    /// A menu bar app again once no editor and no history window is open.
    private func becomeAccessoryWhenDone() {
        guard editors.isEmpty, history?.isOpen != true else { return }
        // Once the window has really gone, or Barn Owl still counts it as open.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard editors.isEmpty, history?.isOpen != true else { return }
            NSApp.setActivationPolicy(.accessory)
            giveFocusBack()
        }
    }
}

extension CaptureCoordinator: CaptureEditorHost {
    private func captureID(for editor: CaptureEditor) -> UUID? { editors[ObjectIdentifier(editor)]?.captureID }

    func editor(_ editor: CaptureEditor, copy image: CGImage) {
        guard let id = captureID(for: editor), let capture = capture(id) else { return }
        copyInOrder(id, image: image, scale: capture.scale)
    }

    func editor(_ editor: CaptureEditor, save image: CGImage) async -> URL? {
        guard let id = captureID(for: editor) else { return nil }
        let document = editor.model.document
        let url = await saveFile(id, image: image).value
        if url != nil { savedDocuments[id] = document }
        return url
    }

    func editor(_ editor: CaptureEditor, pin image: CGImage) {
        guard let id = captureID(for: editor), let capture = capture(id) else { return }
        pin(image, scale: capture.scale, captureID: id)
    }

    func editor(_ editor: CaptureEditor, finish image: CGImage) {
        guard let id = captureID(for: editor), var capture = capture(id) else { return }
        finished.insert(id)
        copyInOrder(id, image: image, scale: capture.scale)
        // The card comes back with what you made; saved over its file if it
        // has one, saved anew only if saving is on.
        let saves = capture.fileURL != nil || Preferences.captureSaves
        capture.image = image
        capture.unsavedEdits = capture.fileURL != nil
        captures[id] = capture
        forgetTextIfNotKept(id)
        storeThumbnail(image, for: id)
        let showsCard = Preferences.captureThen != .nothing
        if showsCard { cards.add(capture, status: saves ? "Edited · copied, saving…" : "Edited · copied") }
        guard saves else { return }
        let saving = saveFile(id, image: image)
        Task {
            let saved = await saving.value != nil
            if showsCard {
                cards.update(id, status: saved ? "Edited · copied and saved" : "Edited · copied · couldn't save", kept: true)
            } else if !saved {
                NSSound.beep()
            }
        }
    }

    func editor(_ editor: CaptureEditor, didChange document: EditorDocument) {
        guard let id = captureID(for: editor) else { return }
        store(document, for: id)
    }

    func editorDidClose(_ editor: CaptureEditor, edited: Bool) {
        let id = captureID(for: editor)
        // Closed without Done: the edits are kept, and the card offers the rest.
        if let id, edited, !finished.contains(id) {
            // Saved from the editor just now, with nothing changed since.
            let savedAsIs = savedDocuments[id] == editor.model.document
            Task {
                guard let image = await editor.render(), var capture = self.capture(id) else { return }
                capture.image = image
                // Its file and the clipboard still have the old picture; dragging,
                // copying or saving uses the new one.
                capture.unsavedEdits = capture.fileURL != nil && !savedAsIs
                self.captures[id] = capture
                self.forgetTextIfNotKept(id)
                self.storeThumbnail(image, for: id)
                self.copied.remove(id)
                self.cards.add(capture, status: savedAsIs ? "Edited · saved, not copied yet" : "Edited · not copied yet",
                               kept: savedAsIs)
            }
        }
        // Opened with E and closed untouched: unless it was copied or saved, the
        // card is the only place it lives.
        if let id, !edited, !finished.contains(id), !isSaved(id), !copied.contains(id), let capture = capture(id),
           capture.openedFrom == nil {
            cards.add(capture, status: capture.unsavedEdits ? "Edited · not copied yet" : status(copied: false, saved: false),
                      kept: false)
        }
        if let id {
            finished.remove(id)
            savedDocuments[id] = nil
        }
        editors[ObjectIdentifier(editor)] = nil
        becomeAccessoryWhenDone()
    }
}

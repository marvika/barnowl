import AppKit
import AVFoundation

/// Runs a recording from the selection to the card: the countdown, the stream, the controls
/// beside the area and in the menu bar, then the saved file, its card and its place in
/// history. Owned by `CaptureCoordinator`, which shows the result like any capture.
@MainActor
final class RecordingCoordinator {
    /// One recording, from the countdown to the file.
    private struct Take {
        let id: UUID
        let target: RecordingTarget
        /// What's recorded, in AppKit screen points: where the controls go.
        let area: CGRect
        /// The display it's on.
        let screen: CGRect
        let kind: Capture.Kind
        let appName: String?
        let options: RecordingOptions
        /// Where this attempt is written; a restart writes a new one.
        var master: URL
        var date = Date()
        /// Said on the card when the mic you chose couldn't be used.
        var note: String?
        /// Left behind by a quit or crash, and found at the next launch.
        var recovered = false
    }

    let model = RecordingModel()
    var microphoneAccess: any MicrophoneAccess = SystemMicrophoneAccess()
    private weak var host: CaptureCoordinator?
    private var machine = RecordingStateMachine()
    private var take: Take?
    private var recorder: ScreenRecorder?
    private var clock = RecordingClock()
    private var silence = MicrophoneSilence()
    private var countdown: RecordingCountdown?
    private var pill: RecordingPanel?
    private var border: RecordingBorder?
    private var statusItem: RecordingStatusItem?
    private var ticker: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var keyMonitor: Any?
    private var discardReset: Task<Void, Never>?
    /// Why the stream stopped by itself, for the card.
    private var stoppedEarly: String?
    /// Movies of recent recordings, before (or instead of) the library keeping them.
    private var movies: [UUID: URL] = [:]
    /// GIFs being made, so Keep as Video can stop one.
    private var gifs: [UUID: Task<URL?, Never>] = [:]
    /// Recordings being saved after they stopped: their file, GIF or mix is still being written.
    private var saving: Set<UUID> = []
    /// Barn Owl is quitting: recordings are saved as they are, without GIFs or the editor.
    private var quitting = false
    private lazy var stopSound = NSSound(named: "Pop")

    init(host: CaptureCoordinator) {
        self.host = host
    }

    /// From the countdown until the file is written.
    var isActive: Bool { machine.phase != .idle }

    /// Recording, or saving a recording: quitting now would lose it.
    var hasWorkToFinish: Bool { machine.phase != .idle || !saving.isEmpty }

    /// Long enough that losing it would hurt: Restart and the menu bar's Discard ask first.
    static let worthKeeping: TimeInterval = 5

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Starting and stopping

    /// Records what was selected in the overlay.
    func begin(_ target: CaptureTarget, makesGIF: Bool, appName: String?) {
        guard machine.phase == .idle, let host else { return NSSound.beep() }
        let snapshot = target.snapshot
        let centre = CGPoint(x: target.rect.midX, y: target.rect.midY)
        if let free = RecordingStore.freeSpace(), free < RecordingStore.roomToStart {
            host.giveFocusBack()
            return RecordingToast.show("Not enough free space to record", at: centre)
        }
        let settings = RecordingSettings.current
        let micStatus = microphoneAccess.status
        var options = RecordingOptions(settings: settings, makesGIF: makesGIF, microphoneAllowed: micStatus == .allowed)
        var note: String?
        if !makesGIF, settings.microphoneID != nil {
            if micStatus != .allowed {
                note = "No mic: not allowed"
            } else if let chosen = options.microphoneID, !microphoneAccess.devices().contains(where: { $0.id == chosen }) {
                // Unplugged since you chose it.
                options.microphoneID = nil
                note = "No mic: not connected"
            }
        }
        let id = UUID()
        let recorded: RecordingTarget
        let kind: Capture.Kind
        var name = appName
        switch target {
        case .area(let rect, _):
            recorded = .display(snapshot.displayID, frame: snapshot.frame, scale: snapshot.scale, area: rect)
            kind = .area
        case .window(let window, _):
            recorded = .window(window.windowID)
            kind = .window
            name = window.appName
        case .screen:
            recorded = .display(snapshot.displayID, frame: snapshot.frame, scale: snapshot.scale, area: nil)
            kind = .screen
        }
        take = Take(id: id, target: recorded, area: target.rect, screen: snapshot.frame, kind: kind, appName: name,
                    options: options, master: RecordingStore.masterURL(for: id), note: note)
        send(.begin(countdown: settings.countdown))
    }

    /// ⌃⌥⌘5: select something to record, or stop the recording that's going.
    func shortcutPressed() {
        switch machine.phase {
        case .idle: host?.startRecording()
        case .countingDown:
            // A restart may not have put its countdown up yet.
            if let countdown { countdown.cancel() } else { send(.cancel) }
        case .starting, .recording, .paused: send(.stop)
        case .finishing: break
        }
    }

    func stop() { send(.stop) }

    func togglePause() { send(model.isPaused ? .resume : .pause) }

    /// Once the take is worth keeping, the first click asks and the second starts again.
    func restart() {
        guard model.confirmingRestart || !isWorthKeeping else {
            return askAgain { $0.confirmingRestart = true }
        }
        send(.restart(countdown: RecordingSettings.current.countdown))
    }

    /// The first click asks, the second throws the recording away.
    func discard() {
        guard model.confirmingDiscard else { return askAgain { $0.confirmingDiscard = true } }
        send(.discard)
    }

    /// One button at a time turns into its question, for three seconds.
    private func askAgain(_ question: (RecordingModel) -> Void) {
        model.confirmingDiscard = false
        model.confirmingRestart = false
        question(model)
        discardReset?.cancel()
        discardReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.model.confirmingDiscard = false
            self.model.confirmingRestart = false
        }
    }

    private var isWorthKeeping: Bool { clock.elapsed(at: Self.now) >= Self.worthKeeping }

    /// The menu bar's Restart: a small alert asks first once the take is worth keeping.
    private func restartFromMenu() {
        confirm(title: "Restart this recording?", then: ", and recording starts again", button: "Restart") { [weak self] in
            self?.send(.restart(countdown: RecordingSettings.current.countdown))
        }
    }

    /// The menu bar's Discard: a small alert asks first once the take is worth keeping.
    private func discardFromMenu() {
        confirm(title: "Discard this recording?", then: "", button: "Discard") { [weak self] in
            self?.send(.discard)
        }
    }

    private func confirm(title: String, then after: String, button: String, act: @escaping () -> Void) {
        guard machine.phase.isLive else { return }
        guard isWorthKeeping else { return act() }
        // After the menu has closed.
        Task { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = title
            let length = RecordingTime.text(self.clock.elapsed(at: Self.now))
            alert.informativeText = "The \(length) recorded so far will be lost\(after)."
            alert.addButton(withTitle: button).hasDestructiveAction = true
            alert.addButton(withTitle: "Keep Recording")
            NSApp.activate()
            let answer = alert.runModal()
            self.host?.giveFocusBack()
            // Stopped meanwhile? Then there's nothing left to throw away.
            guard answer == .alertFirstButtonReturn, self.machine.phase.isLive else { return }
            act()
        }
    }

    // MARK: Quitting

    /// Quitting, logging out or relaunching: stops the recording and saves it, then waits for
    /// every save under way, for up to `limit`. Whatever isn't saved by then is recovered at
    /// the next launch, or kept in history.
    func finishBeforeQuitting(within limit: Duration) async {
        quitting = true
        switch machine.phase {
        case .countingDown:
            if let countdown { countdown.cancel() } else { send(.cancel) }
        case .starting, .recording, .paused:
            send(.stop)
        case .idle, .finishing:
            break
        }
        // A GIF takes too long: the recording is saved as a movie instead.
        for making in gifs.values { making.cancel() }
        let deadline = ContinuousClock.now + limit
        while hasWorkToFinish, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Runs `action` once nothing is being recorded or saved: an update waits for that before
    /// it relaunches Barn Owl.
    func whenDone(_ action: @escaping @MainActor () -> Void) {
        Task { [weak self] in
            while self?.hasWorkToFinish == true {
                try? await Task.sleep(for: .milliseconds(500))
            }
            action()
        }
    }

    // MARK: The state machine's effects

    private func send(_ event: RecordingEvent) {
        let effects = machine.handle(event)
        model.phase = machine.phase
        border?.setPaused(machine.phase == .paused)
        statusItem?.update(elapsed: clock.elapsed(at: Self.now), paused: machine.phase == .paused)
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: RecordingEffect) {
        switch effect {
        case .showCountdown:
            showCountdown()
        case .startCapture:
            startCapture()
        case .abortStart:
            hideControls()
            if let take {
                RecordingToast.show("Too short to keep", symbol: "timer", at: CGPoint(x: take.area.midX, y: take.area.midY))
            }
            let recorder = self.recorder
            Task {
                // The start, cut short, tears its stream down itself; nothing waits on it.
                await recorder?.cancel()
                send(.finished)
            }
        case .pauseCapture:
            recorder?.pause()
            clock.pause(at: Self.now)
        case .resumeCapture:
            recorder?.resume()
            clock.resume(at: Self.now)
        case .finishCapture(let keep):
            finishCapture(keep: keep)
        case .restartCapture(let countdown):
            restartCapture(countdown: countdown)
        case .tearDown:
            tearDown()
        }
    }

    private func showCountdown() {
        guard let take else { return }
        let countdown = RecordingCountdown()
        self.countdown = countdown
        countdown.start(at: CGPoint(x: take.area.midX, y: take.area.midY), onFinish: { [weak self] in
            self?.countdown = nil
            self?.send(.countdownEnded)
        }, onCancel: { [weak self] in
            self?.countdown = nil
            self?.send(.cancel)
            self?.host?.giveFocusBack()
        })
    }

    private func startCapture() {
        guard let take, let host else { return send(.failed) }
        // Your app gets the keyboard back before the first frame.
        host.giveFocusBack()
        let request = ScreenRecorder.Request(target: take.target, options: take.options, leftOut: host.leftOut,
                                             atOneX: Preferences.captureAtOneX, url: take.master)
        let recorder = ScreenRecorder(request: request)
        recorder.onStopped = { [weak self, weak recorder] error in
            guard let self, let recorder, self.recorder === recorder else { return }
            Log.app.error("Recording stopped: \(error.localizedDescription)")
            self.stoppedEarly = "Stopped early"
            self.send(.failed)
        }
        recorder.onLevel = { [weak self] level in self?.heard(level) }
        self.recorder = recorder
        OwnCaptures.isRecording = true
        // Up before the stream, so its filter already knows them.
        showControls()
        Task {
            do {
                try await recorder.start()
                guard self.recorder === recorder else { return }
                clock.start(at: Self.now)
                silence = MicrophoneSilence()
                startTicking()
                send(.started)
            } catch {
                // The stream, the writer and its file, whatever got going before it failed.
                await recorder.cancel()
                guard self.recorder === recorder else { return }
                if machine.phase == .starting {
                    Log.app.error("Recording couldn't start: \(error.localizedDescription)")
                    RecordingToast.show("Couldn't start recording", at: CGPoint(x: take.area.midX, y: take.area.midY))
                    try? FileManager.default.removeItem(at: take.master.deletingLastPathComponent())
                }
                send(.failed)
            }
        }
    }

    private func finishCapture(keep: Bool) {
        guard let recorder, let take else { return send(.finished) }
        hideControls()
        ticker?.cancel()
        let reason = stoppedEarly
        if keep, Preferences.captureSound { stopSound?.stop(); stopSound?.play() }
        Task {
            guard keep else {
                await recorder.cancel()
                try? FileManager.default.removeItem(at: take.master.deletingLastPathComponent())
                return send(.finished)
            }
            // Until it's saved, quitting waits for it.
            saving.insert(take.id)
            defer { saving.remove(take.id) }
            do {
                let output = try await recorder.stop()
                send(.finished)
                await deliver(output, take: take, reason: reason)
            } catch {
                send(.finished)
                Log.app.error("Recording couldn't be finished: \(error.localizedDescription)")
                RecordingToast.show("The recording couldn't be saved", at: CGPoint(x: take.area.midX, y: take.area.midY))
            }
        }
    }

    private func restartCapture(countdown: Bool) {
        let old = recorder
        recorder = nil
        hideControls()
        ticker?.cancel()
        clock = RecordingClock()
        model.elapsed = 0
        take?.date = Date()
        // A new file: the old one is still being let go.
        if let id = take?.id { take?.master = RecordingStore.masterURL(for: id) }
        Task {
            await old?.cancel()
            guard machine.phase == .countingDown || machine.phase == .starting else { return }
            if countdown { showCountdown() } else { startCapture() }
        }
    }

    private func tearDown() {
        countdown?.close()
        countdown = nil
        hideControls()
        ticker?.cancel()
        ticker = nil
        recorder = nil
        take = nil
        stoppedEarly = nil
        clock = RecordingClock()
        OwnCaptures.isRecording = false
        OwnCaptures.last = Date()
        model.reset()
    }

    // MARK: The controls

    private func showControls() {
        guard let take else { return }
        model.hasMicrophone = take.options.microphoneID != nil
        model.hasSystemAudio = take.options.systemAudio
        model.makesGIF = take.options.makesGIF
        model.elapsed = 0
        if case .display(_, _, _, let area) = take.target, area != nil {
            let border = RecordingBorder(around: take.area)
            border.show()
            self.border = border
        }
        let pill = RecordingPanel(rootView: RecordingPill(model: model, stop: { [weak self] in self?.stop() },
                                                          togglePause: { [weak self] in self?.togglePause() },
                                                          restart: { [weak self] in self?.restart() },
                                                          discard: { [weak self] in self?.discard() }))
        place(pill, for: take)
        pill.orderFrontRegardless()
        self.pill = pill
        let item = RecordingStatusItem()
        item.onStop = { [weak self] in self?.stop() }
        item.onTogglePause = { [weak self] in self?.togglePause() }
        item.onRestart = { [weak self] in self?.restartFromMenu() }
        item.onDiscard = { [weak self] in self?.discardFromMenu() }
        statusItem = item
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                          reason: "Recording the screen")
        // Esc stops only while Barn Owl has the keyboard: it never takes Esc from the app you're
        // recording, nor from Barn Owl's own windows (Settings, an editor), which use it themselves.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.machine.phase.isLive,
                  Self.escStops(keyWindow: NSApp.keyWindow) else { return event }
            self.stop()
            return nil
        }
    }

    /// Esc stops when the recording's own controls have the keyboard, or no window does.
    static func escStops(keyWindow: NSWindow?) -> Bool {
        keyWindow == nil || keyWindow is RecordingPanel
    }

    /// Just below the area, or above it, or inside its bottom edge when it fills the screen.
    private func place(_ pill: RecordingPanel, for take: Take) {
        let size = pill.fittingSize
        let screen = NSScreen.screens.first { $0.frame == take.screen }?.visibleFrame ?? take.screen
        let x = min(max(take.area.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let gap: CGFloat = 12 + RecordingBorder.inset
        var y = take.area.minY - size.height - gap
        if y < screen.minY + 8 { y = take.area.maxY + gap }
        if y + size.height > screen.maxY - 8 { y = max(take.area.minY, screen.minY) + 24 }
        pill.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    private func hideControls() {
        pill?.orderOut(nil)
        pill = nil
        border?.close()
        border = nil
        statusItem?.remove()
        statusItem = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        discardReset?.cancel()
        model.confirmingDiscard = false
        model.confirmingRestart = false
    }

    /// The time, four times a second; the free space, every ten seconds.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var ticks = 0
            var shown = -1
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = self.clock.elapsed(at: Self.now)
                // Only when the second changes: the pill and the menu bar redraw no more than they must.
                if Int(elapsed) != shown {
                    shown = Int(elapsed)
                    self.model.elapsed = elapsed
                    self.statusItem?.update(elapsed: elapsed, paused: self.model.isPaused)
                }
                ticks += 1
                if ticks % 40 == 0, let free = RecordingStore.freeSpace(), free < RecordingStore.roomToGoOn {
                    self.stoppedEarly = "Disk nearly full"
                    self.send(.stop)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func heard(_ level: Float) {
        guard machine.phase == .recording else { return }
        model.micLevel = level
        silence.hear(level, at: Self.now)
        if silence.isSilent != model.micSilent { model.micSilent = silence.isSilent }
    }

    // MARK: The result

    private func deliver(_ output: RecordingWriter.Output, take: Take, reason: String?) async {
        let centre = CGPoint(x: take.area.midX, y: take.area.midY)
        let folder = take.master.deletingLastPathComponent()
        guard output.duration >= 1 else {
            try? FileManager.default.removeItem(at: folder)
            return RecordingToast.show("Too short to keep", symbol: "timer", at: centre)
        }
        guard let host else { return }
        let poster = await RecordingStore.poster(of: take.master) ?? Self.blank
        // Pixels per point of the poster, which is smaller than the movie: only its shape matters.
        let scale = max(0.1, CGFloat(poster.width) / max(1, take.area.width))
        var capture = Capture(id: take.id, image: poster, scale: scale, kind: take.kind, date: take.date, appName: take.appName)
        let makesGIF = take.options.makesGIF && !quitting
        capture.media = makesGIF ? .gif(duration: output.duration) : .video(duration: output.duration)

        // History keeps the movie with its separate tracks, for the video editor. It goes there
        // first, so Edit or Make GIF on the card finds it where it stays.
        let movie = await keep(take.master, poster: poster, capture: capture)
        movies[take.id] = movie
        let first = makesGIF ? "Making GIF…" : "Saving…"
        host.showRecording(capture, status: take.recovered ? "Recovered a recording · \(first)" : first,
                           onACard: take.recovered)

        var saved: URL?
        var label = "Saved"
        if makesGIF {
            host.cards.update(take.id, link: CaptureCards.CardLink(title: "Keep as Video") { [weak self] in
                self?.gifs[take.id]?.cancel()
            })
            let making = Task { await host.makeGIF(from: movie, for: take.id) }
            gifs[take.id] = making
            let gif = await making.value
            gifs[take.id] = nil
            host.cards.update(take.id, link: nil)
            if let gif, !making.isCancelled, let url = await Self.place(gif, date: take.date, appName: take.appName) {
                saved = url
                label = "GIF"
            } else {
                capture.media = .video(duration: output.duration)
                label = making.isCancelled ? "Kept as video" : "Saved as video"
            }
        }
        if saved == nil { saved = await Self.saveVideo(movie, mixing: RecordingMixer.needsMixing(output), take: take) }
        let kind = capture.media.libraryKind ?? "video"
        CaptureLibrary.update(take.id) { $0.kind = kind }
        if let saved {
            CaptureLibrary.setFile(saved, for: take.id)
            // History didn't keep the movie: now that it's saved, the next launch lets it go.
            if movie == take.master { RecordingStore.markSaved(folder) }
        }
        host.recordingSaved(take.id, file: saved, media: capture.media)

        let bytes = saved.flatMap(CaptureLibrary.size(of:))
        var status = saved == nil ? "Couldn't save · drag it from here" : RecordingTime.status(label, bytes: bytes)
        let micCutOut = output.cutShort.contains(.microphone) ? "Mic stopped partway" : nil
        if take.recovered {
            status = "Recovered a recording · \(status)"
        } else if let note = reason ?? take.note ?? micCutOut {
            status = "\(note) · \(status)"
        }
        host.cards.update(take.id, status: status, kept: saved != nil)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: saved == nil ? "Recording couldn't be saved" : "Recording saved",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        if Preferences.captureThen == .editor, !take.recovered, !quitting { host.openVideoEditor(take.id) }
    }

    /// Moves a take's movie into history and says where it is now: there, or where it was
    /// recorded while history is off. Making room never lets go of a recording open in the
    /// editor or being made into a GIF.
    private func keep(_ master: URL, poster: CGImage, capture: Capture) async -> URL {
        let entry = CaptureLibrary.Entry(id: capture.id, date: capture.date, scale: Double(capture.scale),
                                         kind: capture.media.libraryKind ?? "video", appName: capture.appName, fileURL: nil,
                                         edited: false, duration: capture.media.duration)
        let keeping = (host?.editingCaptures ?? []).union(gifs.keys)
        let kept = await Task.detached(priority: .userInitiated) { () -> URL? in
            do {
                try CaptureLibrary.storeMovie(master, poster: poster, entry: entry, keeping: keeping)
            } catch {
                Log.app.error("Keeping a recording in history failed: \(error.localizedDescription)")
            }
            return CaptureLibrary.movie(entry.id)
        }.value
        guard let kept else { return master }
        // Its folder among the temporary copies is empty now.
        try? FileManager.default.removeItem(at: master.deletingLastPathComponent())
        return kept
    }

    /// The movie you're handed: the sounds mixed into one track, or the movie as it is.
    private static func saveVideo(_ movie: URL, mixing: Bool, take: Take) async -> URL? {
        let url = RecordingStore.reserveURL(date: take.date, appName: take.appName, fileExtension: "mov")
        defer { CaptureStore.release(url) }
        do {
            if mixing {
                try await RecordingMixer.mix(movie, to: url)
            } else {
                try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: movie, to: url) }.value
            }
            return url
        } catch {
            Log.app.error("Saving a recording failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Moves a GIF into the recordings folder under the recording's name.
    private static func place(_ gif: URL, date: Date, appName: String?) async -> URL? {
        let url = RecordingStore.reserveURL(date: date, appName: appName, fileExtension: "gif")
        defer { CaptureStore.release(url) }
        let moved = await Task.detached(priority: .userInitiated) { () -> Bool in
            (try? FileManager.default.moveItem(at: gif, to: url)) != nil
                || (try? FileManager.default.copyItem(at: gif, to: url)) != nil
        }.value
        return moved ? url : nil
    }

    private static let blank: CGImage = {
        let context = CGContext(data: nil, width: 16, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 10))
        return context.makeImage()!
    }()

    // MARK: What cards and history ask of a recording

    /// The movie with its separate tracks: kept in history, or still where it was recorded.
    func movie(for id: UUID) -> URL? {
        if let url = movies[id], FileManager.default.fileExists(atPath: url.path) { return url }
        return CaptureLibrary.movie(id)
    }

    /// A recording's file on the clipboard.
    func copy(_ id: UUID, file: URL?) {
        guard let file = file ?? movie(for: id) else { return NSSound.beep() }
        RecordingStore.copy(file)
        host?.cards.update(id, status: host?.isSaved(id) == true ? "Copied and saved" : "Copied", kept: true)
    }

    /// Saves a recording again whose file has gone: from the kept movie, mixed as before.
    func saveAgain(_ id: UUID, capture: Capture) {
        guard let movie = movie(for: id) else { return NSSound.beep() }
        Task {
            let url = RecordingStore.reserveURL(date: capture.date, appName: capture.appName, fileExtension: "mov")
            saving.insert(id)
            defer {
                CaptureStore.release(url)
                saving.remove(id)
            }
            let tracks = (try? await AVURLAsset(url: movie).loadTracks(withMediaType: .audio).count) ?? 0
            do {
                if tracks > 1 {
                    try await RecordingMixer.mix(movie, to: url)
                } else {
                    try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: movie, to: url) }.value
                }
            } catch {
                host?.cards.update(id, status: "Couldn't save · drag it from here", kept: false)
                return
            }
            CaptureLibrary.setFile(url, for: id)
            host?.recordingSaved(id, file: url, media: .video(duration: capture.media.duration ?? 0))
            host?.cards.update(id, status: RecordingTime.status("Saved", bytes: CaptureLibrary.size(of: url)), kept: true)
        }
    }

    /// Make GIF on a video's card: saved beside the video and put on the clipboard.
    func makeGIF(_ id: UUID, capture: Capture) {
        guard let movie = movie(for: id), gifs[id] == nil, let host else { return NSSound.beep() }
        host.cards.update(id, status: "Making GIF…", kept: true)
        let making = Task { await host.makeGIF(from: movie, for: id) }
        gifs[id] = making
        Task {
            let gif = await making.value
            gifs[id] = nil
            guard let gif, let url = await Self.place(gif, date: capture.date, appName: capture.appName) else {
                host.cards.update(id, status: "Couldn't make a GIF", kept: true)
                return NSSound.beep()
            }
            RecordingStore.copy(url)
            host.cards.update(id, status: RecordingTime.status("GIF copied and saved", bytes: CaptureLibrary.size(of: url)),
                              kept: true)
        }
    }

    // MARK: Recovering

    /// Recordings a quit, crash or power cut left among the temporary copies: each is kept and
    /// saved like any other, on a card that says it was recovered. Call once, at launch.
    func recoverLeftovers() async {
        let masters = await Task.detached(priority: .utility) { RecordingStore.leftovers() }.value
        for master in masters { await recover(master) }
    }

    private func recover(_ master: URL) async {
        let folder = master.deletingLastPathComponent()
        let asset = AVURLAsset(url: master)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let audio = (try? await asset.loadTracks(withMediaType: .audio).count) ?? 0
        guard duration >= 1, let video = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await video.load(.naturalSize), size.width > 0, size.height > 0 else {
            // Too short, or nothing was written that can be played.
            try? FileManager.default.removeItem(at: folder)
            return
        }
        let values = try? master.resourceValues(forKeys: [.creationDateKey])
        // The take's own id, unless history has it already.
        let named = UUID(uuidString: folder.lastPathComponent)
        let id = named.flatMap { CaptureLibrary.entry($0) == nil ? $0 : nil } ?? UUID()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let area = CGRect(x: 0, y: 0, width: size.width / scale, height: size.height / scale)
        let options = RecordingOptions(settings: .current, makesGIF: false, microphoneAllowed: false)
        let take = Take(id: id, target: .display(0, frame: area, scale: scale, area: nil), area: area, screen: area,
                        kind: .area, appName: nil, options: options, master: master,
                        date: values?.creationDate ?? Date(), recovered: true)
        let sources = Array(RecordingWriter.Source.allCases.prefix(audio))
        let output = RecordingWriter.Output(url: master, duration: duration, frames: 0, audio: sources)
        saving.insert(id)
        defer { saving.remove(id) }
        await deliver(output, take: take, reason: nil)
    }
}

extension CaptureTarget {
    /// What was selected, in AppKit screen points.
    var rect: CGRect {
        switch self {
        case .area(let rect, _): rect
        case .window(let window, _): window.frame
        case .screen(let snapshot): snapshot.frame
        }
    }

    var snapshot: DisplaySnapshot {
        switch self {
        case .area(_, let snapshot), .window(_, let snapshot), .screen(let snapshot): snapshot
        }
    }
}

import AppKit

/// Recording and GIFs, as Capture starts and hands them on.
extension CaptureCoordinator {
    /// ⌃⌥⌘5, search and barnowl://capture?mode=record: select an area, a window or a screen to record.
    func startRecording(gif: Bool = false) {
        let access = recording.microphoneAccess
        let status = access.status
        let setup = RecordingSetup(makesGIF: gif, microphones: status == .allowed ? access.devices() : [], micStatus: status,
                                   allowMicrophone: { [weak self] in
                                       // Asked about in Settings, never over a frozen screen.
                                       self?.cancelSelection()
                                       if status == .denied {
                                           NSWorkspace.shared.open(SystemMicrophoneAccess.settingsURL)
                                       } else {
                                           self?.showCaptureSettings()
                                       }
                                   })
        start(.area, recording: setup)
    }

    /// Opens a recording in the video editor, with its cuts from last time still editable: the
    /// kept movie (computer audio and the mic on separate tracks), or failing that its saved file.
    /// One editor per recording; opening it again brings that one forward.
    func openVideoEditor(_ id: UUID) {
        if let open = videoEditors.values.first(where: { $0.captureID == id }) {
            cards.remove(id)
            return open.editor.show()
        }
        guard !openingVideos.contains(id) else { return }
        guard let capture = capture(id),
              let movie = recording.movie(for: id) ?? (isSaved(id) ? capture.fileURL : nil) else { return NSSound.beep() }
        let title = capture.fileURL?.deletingPathExtension().lastPathComponent
            ?? RecordingStore.baseName(prefix: Preferences.captureNamePrefix, date: capture.date, appName: nil)
        let edit = CaptureLibrary.videoEdit(id)
        if editingCaptures.isEmpty { rememberFrontApp() }
        openingVideos.insert(id)
        Task {
            defer { openingVideos.remove(id) }
            let editor: VideoEditor
            do {
                editor = try await VideoEditor.load(movie: movie, title: title, scale: capture.scale, edit: edit, host: self)
            } catch {
                Log.app.error("Opening a recording to edit failed: \(error.localizedDescription)")
                return NSSound.beep()
            }
            videoEditors[ObjectIdentifier(editor)] = VideoEditing(editor: editor, captureID: id)
            cards.remove(id)
            // A real app while you edit, as for pictures.
            if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
            editor.show()
        }
    }

    /// Make GIF on a video's card.
    func makeGIF(_ id: UUID) {
        guard let capture = capture(id), capture.media.isMovie else { return NSSound.beep() }
        recording.makeGIF(id, capture: capture)
    }

    /// Makes a GIF of a recording and returns where it wrote it (the caller moves it into place),
    /// or nil if it couldn't. Cancelling the task means Keep as Video.
    func makeGIF(from movie: URL, for id: UUID) async -> URL? {
        let gif = FileManager.default.temporaryDirectory.appending(path: "\(id.uuidString).gif")
        do {
            _ = try await GIFMaker.make(from: movie, range: nil, options: .standard, to: gif, progress: { _ in })
            return gif
        } catch {
            if !(error is CancellationError) { Log.app.error("Making a GIF failed: \(error.localizedDescription)") }
            try? FileManager.default.removeItem(at: gif)
            return nil
        }
    }
}

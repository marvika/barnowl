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

    /// Opens a recording to edit. Until the video editor lands, QuickTime Player plays the
    /// kept movie (computer audio and the mic on separate tracks), or the saved file.
    func openVideoEditor(_ id: UUID) {
        guard let movie = recording.movie(for: id) ?? capture(id)?.fileURL else { return NSSound.beep() }
        cards.remove(id)
        let player = URL(fileURLWithPath: "/System/Applications/QuickTime Player.app")
        NSWorkspace.shared.open([movie], withApplicationAt: player, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Make GIF on a video's card.
    func makeGIF(_ id: UUID) {
        guard let capture = capture(id), capture.media.isMovie else { return NSSound.beep() }
        recording.makeGIF(id, capture: capture)
    }

    /// Makes a GIF of a recording and returns where it wrote it (the caller moves it into place),
    /// or nil if it couldn't. Cancelling the task means Keep as Video.
    func makeGIF(from movie: URL, for id: UUID) async -> URL? {
        // GIFMaker isn't here yet.
        nil
    }
}

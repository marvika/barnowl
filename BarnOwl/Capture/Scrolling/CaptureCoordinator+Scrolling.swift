import AppKit

/// What's under way, and so what may start. A frozen screen never goes up over a scrolling
/// capture, which takes Return and Esc for itself; a recording and a scrolling capture never
/// run at once; and there's only ever one of each.
struct CaptureActivity: Equatable {
    var recording = false
    var scrolling = false

    /// The frozen screen, to take a picture, or to record (`records`) or scroll (`scrolls`)
    /// what you select. Pictures can still be taken while you record.
    func canSelect(records: Bool = false, scrolls: Bool = false) -> Bool {
        guard !scrolling else { return false }
        return !recording || !(records || scrolls)
    }

    /// A scrolling capture of what you've just selected.
    var canScroll: Bool { !scrolling && !recording }
}

/// Scrolling capture, as Capture starts it and hands on the tall picture it stitches.
extension CaptureCoordinator {
    var activity: CaptureActivity {
        CaptureActivity(recording: recording.isActive, scrolling: scrollingSession != nil)
    }

    /// ⌃⌥⌘S, search and barnowl://capture?mode=scroll: select what to scroll through, or,
    /// while a scrolling capture is going, finish it as Done would.
    func scrollingCapture() {
        if let scrollingSession { return scrollingSession.finish() }
        start(.area, scrolls: true)
    }

    /// S in the overlay, or Return after ⌃⌥⌘S: scrolls through what you selected, then delivers
    /// the picture like any screenshot, to the card, the clipboard, the file and history.
    func startScrollingCapture(_ target: CaptureTarget, appName: String?) {
        guard activity.canScroll else {
            NSSound.beep()
            return giveFocusBack()
        }
        var name = appName
        switch target {
        case .area(let rect, _):
            Preferences.captureLastArea = rect
        case .window(let window, _):
            Preferences.captureLastArea = window.frame
            name = window.appName
        case .screen:
            break
        }
        let rect = target.rect
        let session = ScrollingCaptureSession(rect: rect, display: target.snapshot.displayID)
        scrollingSession = session
        Task {
            let shot = await session.run()
            scrollingSession = nil
            guard let shot else {
                // Cancelled says nothing; one that couldn't start says why.
                if let failure = session.failure {
                    RecordingToast.show(failure, at: CGPoint(x: rect.midX, y: rect.midY))
                }
                return giveFocusBack()
            }
            deliver(Capture(image: shot.image, scale: shot.scale, kind: .area, date: Date(), appName: name),
                    action: .primary, windows: [])
        }
    }
}

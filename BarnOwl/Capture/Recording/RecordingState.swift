import Foundation

/// Where a recording is, from the countdown to the file.
enum RecordingPhase: Equatable, Sendable {
    case idle
    case countingDown
    /// The stream is being set up; nothing is being written yet.
    case starting
    case recording
    case paused
    /// Stopped, discarded or restarted: the file is being finished or let go.
    case finishing

    /// The controls are up and the clock is running (or paused).
    var isLive: Bool { self == .recording || self == .paused }
}

/// What happens to a recording, from you or from the stream.
enum RecordingEvent: Equatable, Sendable {
    case begin(countdown: Bool)
    case countdownEnded
    /// Esc during the countdown.
    case cancel
    /// The first frame arrived.
    case started
    /// Couldn't start, or the stream stopped by itself.
    case failed
    case pause, resume, stop, discard
    /// Throw this take away and record again.
    case restart(countdown: Bool)
    /// The file is written, or let go.
    case finished
}

/// What the coordinator does for an event.
enum RecordingEffect: Equatable, Sendable {
    case showCountdown
    case startCapture
    /// Stopped while still starting: tear the stream down as soon as it's up, keep nothing.
    case abortStart
    case pauseCapture
    case resumeCapture
    /// `keep`: write the file; otherwise let it go.
    case finishCapture(keep: Bool)
    /// Let this take go, then count down (or start) again.
    case restartCapture(countdown: Bool)
    /// Everything on screen goes: countdown, controls, border, menu bar item.
    case tearDown
}

/// The rules of a recording, apart from any window or stream, so they're tested alone.
/// Stopping right after starting never leaves a stream or the microphone running.
struct RecordingStateMachine: Sendable {
    private(set) var phase = RecordingPhase.idle

    mutating func handle(_ event: RecordingEvent) -> [RecordingEffect] {
        switch (phase, event) {
        case (.idle, .begin(let countdown)):
            phase = countdown ? .countingDown : .starting
            return [countdown ? .showCountdown : .startCapture]

        case (.countingDown, .countdownEnded):
            phase = .starting
            return [.startCapture]
        case (.countingDown, .cancel), (.countingDown, .stop), (.countingDown, .discard):
            phase = .idle
            return [.tearDown]

        case (.starting, .started):
            phase = .recording
            return []
        case (.starting, .failed):
            phase = .idle
            return [.tearDown]
        case (.starting, .stop), (.starting, .discard), (.starting, .cancel):
            // Too soon to have anything worth keeping.
            phase = .finishing
            return [.abortStart]

        case (.recording, .pause):
            phase = .paused
            return [.pauseCapture]
        case (.paused, .resume):
            phase = .recording
            return [.resumeCapture]
        case (.recording, .stop), (.paused, .stop):
            phase = .finishing
            return [.finishCapture(keep: true)]
        case (.recording, .failed), (.paused, .failed):
            // The display changed or the window closed: keep what was recorded.
            phase = .finishing
            return [.finishCapture(keep: true)]
        case (.recording, .discard), (.paused, .discard):
            phase = .finishing
            return [.finishCapture(keep: false)]
        case (.recording, .restart(let countdown)), (.paused, .restart(let countdown)):
            phase = countdown ? .countingDown : .starting
            return [.restartCapture(countdown: countdown)]

        case (.finishing, .finished), (.finishing, .failed):
            phase = .idle
            return [.tearDown]

        default:
            // A second stop, a pause before the first frame, and so on: nothing to do.
            return []
        }
    }
}

/// The recording's running time, without the pauses. Times are seconds on any steady clock.
struct RecordingClock: Equatable, Sendable {
    private var startedAt: TimeInterval?
    private var pausedAt: TimeInterval?
    private var paused: TimeInterval = 0

    mutating func start(at now: TimeInterval) {
        startedAt = now
        pausedAt = nil
        paused = 0
    }

    mutating func pause(at now: TimeInterval) {
        guard startedAt != nil, pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: TimeInterval) {
        guard let pausedAt else { return }
        paused += max(0, now - pausedAt)
        self.pausedAt = nil
    }

    func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? now) - startedAt - paused)
    }
}

/// Notices a microphone that hears nothing: quieter than about −60 dB for three seconds.
struct MicrophoneSilence: Equatable, Sendable {
    static let threshold: Float = 0.001
    static let seconds: TimeInterval = 3
    private var quietSince: TimeInterval?
    private(set) var isSilent = false

    mutating func hear(_ level: Float, at now: TimeInterval) {
        if level > Self.threshold {
            quietSince = nil
            isSilent = false
        } else {
            let since = quietSince ?? now
            quietSince = since
            isSilent = now - since >= Self.seconds
        }
    }
}

import AppKit
import KeyboardShortcuts
import SwiftUI

/// What the controls show while recording.
@MainActor
@Observable
final class RecordingModel {
    var phase = RecordingPhase.idle
    var elapsed: TimeInterval = 0
    /// The microphone's level, 0 to 1.
    var micLevel: Float = 0
    var micSilent = false
    var hasMicrophone = false
    var hasSystemAudio = false
    var makesGIF = false
    /// The bin was clicked once: a second click discards.
    var confirmingDiscard = false

    var isPaused: Bool { phase == .paused }

    func reset() {
        phase = .idle
        elapsed = 0
        micLevel = 0
        micSilent = false
        confirmingDiscard = false
    }
}

/// A panel of Barn Owl's that floats over everything. It's never in a recording, and it takes
/// the keyboard only when asked (the countdown, for Return and Esc).
final class RecordingPanel: NSPanel {
    private let takesKeys: Bool

    init<Content: View>(rootView: Content, level: NSWindow.Level = .statusBar, takesKeys: Bool = false) {
        self.takesKeys = takesKeys
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = !takesKeys
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = FirstClickHostingView(rootView: rootView)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { takesKeys }

    var fittingSize: CGSize { contentView?.fittingSize ?? .zero }
}

/// Buttons answer the first click, though the panel is never key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: The pill

/// The controls beside what's recorded: stop, the time, pause, restart, discard, and what's heard.
struct RecordingPill: View {
    let model: RecordingModel
    let stop: () -> Void
    let togglePause: () -> Void
    let restart: () -> Void
    let discard: () -> Void

    /// Clear room around the pill in its panel, for its shadow.
    static let margin: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            stopButton
            time
            Divider().frame(height: 18).padding(.horizontal, 5)
            PillButton(symbol: model.isPaused ? "play.fill" : "pause.fill",
                       label: model.isPaused ? "Resume" : "Pause",
                       help: model.isPaused ? "Resume recording" : "Pause recording", action: togglePause)
            PillButton(symbol: "arrow.counterclockwise", label: "Restart", help: "Restart from the beginning", action: restart)
            discardButton
            if hears {
                Divider().frame(height: 18).padding(.horizontal, 5)
                hearing
            }
        }
        // Round buttons at the ends sit concentric with the pill's ends.
        .padding(.leading, 5).padding(.trailing, hears ? 10 : 5).padding(.vertical, 5)
        .captureGlass(in: .capsule, floating: true)
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .animation(.smooth(duration: 0.2), value: model.confirmingDiscard)
        .animation(.smooth(duration: 0.2), value: model.micSilent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording controls")
    }

    private var hears: Bool { model.makesGIF || model.hasMicrophone || model.hasSystemAudio }

    /// "Stop and save (⌃⌥⌘5)", with the shortcut you've set.
    static var stopHelp: String {
        KeyboardShortcuts.Name.recordScreen.keys.map { "Stop and save (\($0))" } ?? "Stop and save"
    }

    private var stopButton: some View {
        Button(action: stop) {
            ZStack {
                Circle().fill(Color(red: 1, green: 0.27, blue: 0.23))
                RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)
            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
            .contentShape(.circle)
        }
        .buttonStyle(PressableStyle())
        .help(Self.stopHelp)
        .accessibilityLabel("Stop and save")
    }

    private var time: some View {
        HStack(spacing: 6) {
            RecordingDot(paused: model.isPaused)
            Text(RecordingTime.text(model.elapsed))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(model.isPaused ? 0.6 : 1))
                .contentTransition(.numericText())
            if model.isPaused {
                Text("Paused").font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.amber)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.isPaused ? "Paused at \(RecordingTime.text(model.elapsed))"
                                           : "Recording, \(RecordingTime.text(model.elapsed))")
    }

    private var discardButton: some View {
        Group {
            if model.confirmingDiscard {
                Button(action: discard) {
                    Text("Discard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color(red: 1, green: 0.27, blue: 0.23), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(PressableStyle())
                .help("Click again to throw this recording away")
                .accessibilityLabel("Confirm discard")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                PillButton(symbol: "trash", label: "Discard", help: "Discard this recording", action: discard)
            }
        }
    }

    /// The microphone's level, computer audio, or the GIF it'll become.
    private var hearing: some View {
        HStack(spacing: 8) {
            if model.makesGIF {
                Text("GIF")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: 4))
                    .help("Saved as a GIF when you stop")
                    .accessibilityLabel("Saved as a GIF when you stop")
            }
            if model.hasSystemAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .help("Recording computer audio")
                    .accessibilityLabel("Recording computer audio")
            }
            if model.hasMicrophone {
                MicLevel(level: model.micLevel, silent: model.micSilent)
                if model.micSilent {
                    Text("Mic is silent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Brand.amber)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// A round, quiet button for the pill.
private struct PillButton: View {
    let symbol: String
    let label: String
    /// The tooltip; the label when there's nothing more to say.
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: 28, height: 28)
                .background(.white.opacity(hovering ? 0.16 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

/// Red and softly breathing while recording; amber and still while paused.
private struct RecordingDot: View {
    let paused: Bool
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(paused ? Brand.amber : Color(red: 1, green: 0.27, blue: 0.23))
            .frame(width: 7, height: 7)
            .opacity(dim && !paused ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// The microphone with a ring that swells with your voice.
private struct MicLevel: View {
    let level: Float
    let silent: Bool

    var body: some View {
        // Speech sits around −30 dB: scale so it fills the ring.
        let loudness = CGFloat(min(1, max(0, (20 * log10(max(level, 0.00001)) + 60) / 45)))
        ZStack {
            Circle()
                .fill(Brand.lavender.opacity(0.35))
                .frame(width: 14 + 12 * loudness, height: 14 + 12 * loudness)
                .animation(.easeOut(duration: 0.12), value: loudness)
            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(silent ? Brand.amber : .white)
        }
        .frame(width: 26, height: 26)
        .help(silent ? "The microphone hears nothing. Is it muted?" : "Recording the microphone")
        .accessibilityLabel(silent ? "Microphone is silent" : "Recording the microphone")
    }
}

// MARK: Countdown

@MainActor
@Observable
final class CountdownModel {
    var number = 3
}

/// 3, 2, 1 in the middle of what's about to be recorded. A click starts at once.
struct RecordingCountdownView: View {
    let model: CountdownModel
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("\(model.number)")
                .font(.system(size: 68, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .frame(width: 128, height: 128)
                .captureGlass(in: .circle, tint: 0.55, floating: true)
            Text("Click to start now · Esc to cancel")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .captureGlass(in: .capsule, tint: 0.55, floating: true)
        }
        .padding(16)
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .contentShape(.rect)
        .onTapGesture(perform: skip)
        .animation(.smooth(duration: 0.3), value: model.number)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording starts in \(model.number)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Counts down, ticking once a second, then hands over. Return or a click skips it; Esc cancels.
@MainActor
final class RecordingCountdown {
    private let model = CountdownModel()
    private var panel: RecordingPanel?
    private var task: Task<Void, Never>?
    private var monitor: Any?
    private var onFinish: (() -> Void)?
    private var onCancel: (() -> Void)?
    private lazy var tick = NSSound(named: "Tink")

    func start(at centre: CGPoint, seconds: Int = 3, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        model.number = seconds
        // Above the overlay that's just closing.
        let panel = RecordingPanel(rootView: RecordingCountdownView(model: model) { [weak self] in self?.finish() },
                                   level: .screenSaver, takesKeys: true)
        let size = panel.fittingSize
        panel.setFrame(CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height),
                       display: false)
        // Return and Esc reach it; after a restart, your app had the keyboard back.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53: self?.cancel()
            case 36, 76, 49: self?.finish()
            default: return event
            }
            return nil
        }
        task = Task { [weak self] in
            for number in stride(from: seconds, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.model.number = number
                if Preferences.captureSound { self.tick?.stop(); self.tick?.volume = 0.35; self.tick?.play() }
                try? await Task.sleep(for: .seconds(1))
            }
            self?.finish()
        }
    }

    func finish() {
        let done = onFinish
        close()
        done?()
    }

    func cancel() {
        let cancelled = onCancel
        close()
        cancelled?()
    }

    func close() {
        task?.cancel()
        task = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onFinish = nil
        onCancel = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: Border

/// A thin ring just outside the recorded area, which never catches a click. Dashed while paused.
@MainActor
final class RecordingBorder {
    static let inset: CGFloat = 4
    private let panel: NSPanel
    private let ring = CAShapeLayer()
    private let shade = CAShapeLayer()

    init(around area: CGRect) {
        let frame = area.insetBy(dx: -Self.inset, dy: -Self.inset)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        // The ring's inside edge sits a point outside the area, so it's never in the picture.
        let path = CGPath(rect: view.bounds.insetBy(dx: Self.inset - 1.75, dy: Self.inset - 1.75), transform: nil)
        for (layer, colour, width) in [(shade, NSColor.black.withAlphaComponent(0.28), CGFloat(3.5)),
                                       (ring, NSColor(Brand.lavender), CGFloat(1.5))] {
            layer.path = path
            layer.fillColor = nil
            layer.strokeColor = colour.cgColor
            layer.lineWidth = width
            layer.frame = view.bounds
            view.layer?.addSublayer(layer)
        }
        panel.contentView = view
    }

    func show() { panel.orderFrontRegardless() }

    func setPaused(_ paused: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.lineDashPattern = paused ? [6, 4] : nil
        shade.lineDashPattern = paused ? [6, 4] : nil
        CATransaction.commit()
    }

    func close() { panel.orderOut(nil) }
}

// MARK: Toast

/// A short word on glass, where the recording was: "Too short to keep".
struct RecordingToastView: View {
    let symbol: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.amber)
            Text(message).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .captureGlass(in: .capsule, tint: 0.55, floating: true)
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .padding(14)
    }
}

@MainActor
enum RecordingToast {
    private static var current: RecordingPanel?

    static func show(_ message: String, symbol: String = "exclamationmark.circle.fill", at centre: CGPoint) {
        current?.orderOut(nil)
        let panel = RecordingPanel(rootView: RecordingToastView(symbol: symbol, message: message))
        let size = panel.fittingSize
        panel.setFrame(CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height),
                       display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        current = panel
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                Task { @MainActor in
                    panel.orderOut(nil)
                    if current === panel { current = nil }
                }
            }
        }
    }
}

// MARK: Badge

/// A recording's sign on its picture: a play glyph (or GIF) and how long it runs.
struct MovieBadge: View {
    let media: CaptureMedia
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if media.isGIF {
                Text("GIF").font(.system(size: compact ? 9.5 : 10, weight: .heavy, design: .rounded))
            } else {
                Image(systemName: "play.fill").font(.system(size: compact ? 8 : 9, weight: .bold))
            }
            if let duration = media.duration {
                Text(RecordingTime.text(duration)).font(.system(size: compact ? 10.5 : 11, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 7).padding(.vertical, compact ? 2.5 : 3)
        .background(.black.opacity(0.55), in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(media.isGIF ? "GIF, \(RecordingTime.text(media.duration ?? 0))"
                                        : "Recording, \(RecordingTime.text(media.duration ?? 0))")
    }
}

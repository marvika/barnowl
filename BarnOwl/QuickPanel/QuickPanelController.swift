import AppKit
import SwiftUI

/// Shows the quick panel under the owl or the arrow, and owns the owl in the
/// menu bar, whose eyes are open while your Mac is kept awake.
@MainActor
final class QuickPanelController: NSObject {
    private let model: AppModel
    private var panel: FloatingPanel?
    private let outsideClicks = OutsideClickMonitor()
    private(set) var owlItem: NSStatusItem?
    private var countdownTask: Task<Void, Never>?
    private var eyesTask: Task<Void, Never>?
    private var blinkTask: Task<Void, Never>?
    /// How open the owl's eyes are right now, 0 (shut) to 1.
    private var openness: CGFloat = 0
    /// Where its eyes look, -1 (left) to 1 (right).
    private var look: CGFloat = 0
    private var winking = false
    private var glanceTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    var isOpen: Bool { panel?.isVisible ?? false }

    init(model: AppModel) {
        self.model = model
    }

    /// Adds or removes the owl to match the setting, and updates it: eyes
    /// open while keeping awake, plus the time left in a timed session.
    func syncOwlIcon() {
        guard Preferences.showKeepAwakeIcon else {
            if let owlItem { NSStatusBar.system.removeStatusItem(owlItem) }
            owlItem = nil
            blinkTask?.cancel()
            return
        }
        let item = owlItem ?? makeOwlItem()
        owlItem = item
        let awake = model.keepAwake.isActive
        // In a timed session's last minute, the eyes start to droop.
        let lastMinute = (model.keepAwake.endDate?.timeIntervalSinceNow ?? .infinity) < 60
        animateEyes(to: awake ? (lastMinute ? 0.45 : 1) : 0)
        awake && Preferences.owlMoves ? startBlinking() : stopBlinking()
        render()
        item.button?.setAccessibilityLabel(awake ? "Barn Owl, keeping your Mac awake" : "Barn Owl")
        item.button?.toolTip = "Keep Awake: \(KeepAwakeFormatter.status(of: model.keepAwake))"
        // Time left next to the owl, like Amphetamine.
        if Preferences.keepAwakeCountdown, let end = model.keepAwake.endDate {
            item.button?.title = " " + KeepAwakeFormatter.countdown(end.timeIntervalSinceNow)
            item.button?.imagePosition = .imageLeading
            item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            startCountdown()
        } else {
            item.button?.title = ""
            item.button?.imagePosition = .imageOnly
            countdownTask?.cancel()
            countdownTask = nil
        }
    }

    private func setEyes(_ value: CGFloat) {
        openness = value
        render()
    }

    private func render() {
        owlItem?.button?.image = MenuBarOwl.image(openness: openness, look: look, winkRight: winking,
                                                  shades: model.presenter.isPresenting)
    }

    /// Glances toward an icon that just popped into view (show on change).
    func glance(toward frame: CGRect) {
        guard let owl = owlItem?.button?.window?.frame, Preferences.owlMoves else { return }
        glanceTask?.cancel()
        look = frame.midX < owl.midX ? -1 : 1
        render()
        glanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, !Task.isCancelled else { return }
            self.look = 0
            self.render()
        }
    }

    /// One sleepy double blink, after the Mac wakes up.
    private func wakeBlink() {
        guard Preferences.owlMoves, owlItem != nil else { return }
        let target = openness
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            for value in [0.1, 0.6, 0.1, target] as [CGFloat] {
                self?.setEyes(value)
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }

    // The eyes follow the pointer across the owl, by a point.
    //
    // The tracking area calls these by their AppKit names (mouseMoved: and so
    // on). This isn't an NSResponder, so Swift's names (mouseMovedWith:) would
    // not match: AppKit then threw an exception on every pointer movement over
    // the owl, which could leave its animation state broken and crash later.
    @objc(mouseMoved:) func mouseMoved(with event: NSEvent) {
        guard let button = owlItem?.button, Preferences.owlMoves else { return }
        let x = button.convert(event.locationInWindow, from: nil).x
        let imageWidth = button.image?.size.width ?? button.bounds.width
        guard imageWidth > 0, x.isFinite else { return }
        look = max(-1, min(1, (x - imageWidth / 2) / (imageWidth / 2)))
        render()
    }

    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        guard look != 0, glanceTask == nil || glanceTask?.isCancelled == true else { return }
        look = 0
        render()
    }

    /// Waking up, the eyes pop wide open and settle. Dozing off, they droop
    /// halfway, hang there sleepily, then close.
    private func animateEyes(to target: CGFloat) {
        guard target != openness || owlItem?.button?.image == nil else { return }
        eyesTask?.cancel()
        guard Preferences.owlMoves else { return setEyes(target) }
        let frames: [(CGFloat, Int)] = target > openness
            ? [(0.3, 35), (0.75, 35), (1.2, 35), (1.35, 70), (1.15, 45), (1.0, 0)]
            : [(0.7, 60), (0.45, 60), (0.42, 260), (0.5, 120), (0.3, 70), (0.15, 70), (0, 0)]
        eyesTask = Task { [weak self] in
            for (value, pause) in frames {
                guard !Task.isCancelled else { return }
                self?.setEyes(value)
                try? await Task.sleep(for: .milliseconds(pause))
            }
        }
    }

    /// While awake, the owl blinks every half a minute or so.
    private func startBlinking() {
        guard blinkTask == nil else { return }
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 20...45)))
                guard let self, !Task.isCancelled, self.openness > 0.9 else { continue }
                for value in [0.4, 0.1, 0.5, 1.0] as [CGFloat] {
                    self.setEyes(value)
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
        }
    }

    private func stopBlinking() {
        blinkTask?.cancel()
        blinkTask = nil
    }

    /// Refreshes the countdown every few seconds while a timed session runs.
    private func startCountdown() {
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.countdownTask = nil
                self.syncOwlIcon()
                return
            }
        }
    }

    private func makeOwlItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BarnOwlKeepAwake"
        item.button?.target = self
        item.button?.action = #selector(owlClicked)
        item.button?.image = MenuBarOwl.image(openness: 0)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let button = item.button {
            button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved,
                                                                         .activeAlways, .inVisibleRect],
                                                  owner: self))
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wakeBlink() }
        }
        // A new status item appears at the far left, in a hidden section. Put
        // it next to the arrow once; after that macOS remembers its place.
        let placedKey = "placedKeepAwakeIcon"
        if !UserDefaults.standard.bool(forKey: placedKey) {
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                if let window = StatusItems.windowID(of: item),
                   let divider = StatusItems.windowID(of: model.sections.items.separator),
                   await model.mover.move(window, to: .rightOf(divider)) {
                    UserDefaults.standard.set(true, forKey: placedKey)
                }
            }
        }
        return item
    }

    @objc private func owlClicked() {
        // Option-click starts or stops keep awake without opening the panel.
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            if model.keepAwake.session != nil {
                model.keepAwake.stop()
            } else {
                model.keepAwake.start(minutes: Preferences.keepAwakeHotkeyMinutes)
            }
            wink()
            return
        }
        toggle(under: owlItem?.button?.window?.frame)
    }

    /// A wink, for the Option-click shortcut.
    private func wink() {
        guard Preferences.owlMoves else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.winking = true
            self?.render()
            try? await Task.sleep(for: .milliseconds(300))
            self?.winking = false
            self?.render()
        }
    }

    func toggle(under anchor: NSRect?) {
        isOpen ? close() : show(under: anchor)
    }

    func show(under anchor: NSRect?) {
        close()
        let panel = FloatingPanel(rootView: QuickPanelView(model: model) { [weak self] in self?.close() })
        panel.onCancel = { [weak self] in self?.close() }
        if let anchor {
            panel.onResize = { $0.place(under: anchor, alignRight: true) }
            panel.layoutIfNeeded()
            panel.place(under: anchor, alignRight: true)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
        outsideClicks.start { [weak self] in self?.close() }
        OpenPanel.shared.opening(self) { [weak self] in self?.close() }
    }

    func close() {
        outsideClicks.stop()
        OpenPanel.shared.closed(self)
        panel?.dismiss()
        panel = nil
    }
}

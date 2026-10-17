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
        animateEyes(to: awake ? 1 : 0)
        awake ? startBlinking() : stopBlinking()
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
        owlItem?.button?.image = MenuBarOwl.image(openness: value)
    }

    /// Waking up, the eyes pop wide open and settle. Dozing off, they droop
    /// halfway, hang there sleepily, then close.
    private func animateEyes(to target: CGFloat) {
        guard target != openness || owlItem?.button?.image == nil else { return }
        eyesTask?.cancel()
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
            return
        }
        toggle(under: owlItem?.button?.window?.frame)
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
    }

    func close() {
        outsideClicks.stop()
        panel?.orderOut(nil)
        panel = nil
    }
}

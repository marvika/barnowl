import AppKit

/// A stop button with the time in the menu bar, only while recording. Click stops; a right
/// click (or ⌃-click) offers Pause, Restart and Discard. Placed beside Barn Owl's arrow, never
/// in the hidden section or behind the notch; Barn Owl's arranger leaves its own items alone.
@MainActor
final class RecordingStatusItem: NSObject, NSMenuDelegate {
    static let name = "BarnOwlRecording"
    var onStop: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onRestart: () -> Void = {}
    var onDiscard: () -> Void = {}
    private let item: NSStatusItem
    private var paused = false

    override init() {
        StatusItems.seedVisiblePosition(for: Self.name)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = Self.name
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        update(elapsed: 0, paused: false)
    }

    func update(elapsed: TimeInterval, paused: Bool) {
        self.paused = paused
        guard let button = item.button else { return }
        let symbol = paused ? "pause.circle.fill" : "stop.circle.fill"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        button.image?.isTemplate = true
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.attributedTitle = NSAttributedString(string: " " + RecordingTime.text(elapsed), attributes: [.font: font])
        button.toolTip = paused ? "Recording paused · click to stop and save" : "Recording · click to stop and save"
        button.setAccessibilityLabel(paused ? "Recording paused, \(RecordingTime.text(elapsed)). Stop recording"
                                            : "Recording, \(RecordingTime.text(elapsed)). Stop recording")
    }

    func remove() {
        item.menu = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard wantsMenu else { return onStop() }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(ClosureMenuItem("Stop and Save") { [weak self] in self?.onStop() })
        menu.addItem(ClosureMenuItem(paused ? "Resume" : "Pause") { [weak self] in self?.onTogglePause() })
        menu.addItem(ClosureMenuItem("Restart") { [weak self] in self?.onRestart() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Discard") { [weak self] in self?.onDiscard() })
        item.menu = menu
        sender.performClick(nil)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated { item.menu = nil }
    }
}

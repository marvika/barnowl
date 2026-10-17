import AppKit
import SwiftUI

/// Shows the quick panel under the cup icon or the arrow, and owns the
/// optional cup icon itself.
@MainActor
final class QuickPanelController: NSObject {
    private let model: AppModel
    private var panel: FloatingPanel?
    private let outsideClicks = OutsideClickMonitor()
    private(set) var cupItem: NSStatusItem?

    var isOpen: Bool { panel?.isVisible ?? false }

    init(model: AppModel) {
        self.model = model
    }

    /// Adds or removes the cup icon to match the setting, and updates its look.
    func syncCupIcon() {
        if Preferences.showKeepAwakeIcon {
            let item = cupItem ?? makeCupItem()
            cupItem = item
            let active = model.keepAwake.isActive
            item.button?.image = NSImage(systemSymbolName: active ? "cup.and.heat.waves.fill" : "cup.and.saucer",
                                         accessibilityDescription: active ? "Keep awake on" : "Keep awake off")?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            item.button?.toolTip = "Keep Awake: \(KeepAwakeFormatter.status(of: model.keepAwake))"
        } else if let cupItem {
            NSStatusBar.system.removeStatusItem(cupItem)
            self.cupItem = nil
        }
    }

    private func makeCupItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BarkeepKeepAwake"
        item.button?.target = self
        item.button?.action = #selector(cupClicked)
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

    @objc private func cupClicked() {
        // Option-click starts or stops keep awake without opening the panel.
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            if model.keepAwake.session != nil {
                model.keepAwake.stop()
            } else {
                model.keepAwake.start(minutes: Preferences.keepAwakeHotkeyMinutes)
            }
            return
        }
        toggle(under: cupItem?.button?.window?.frame)
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

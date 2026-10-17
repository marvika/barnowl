import AppKit

/// Decides which section is showing: handles toggling, auto-rehide and
/// arrangement checks, and hands the mechanics to a HidingEngine.
@MainActor
final class SectionController {
    let items: StatusItems
    let engine: HidingEngine
    private(set) var state: SectionState = .expanded
    var onStateChange: ((SectionState) -> Void)?
    /// Displays were connected, disconnected or rearranged.
    var onScreensChanged: (() -> Void)?

    /// Keeps hidden icons showing, e.g. while setup or Settings asks the user
    /// to arrange them. Clearing it starts the auto-rehide timer again.
    var holdOpen = false {
        didSet {
            guard holdOpen != oldValue else { return }
            rehideTask?.cancel()
            if !holdOpen && state != .collapsed { scheduleRehide() }
        }
    }

    private var rehideTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?

    init(items: StatusItems, engine: HidingEngine) {
        self.items = items
        self.engine = engine
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.invalidateLayout()
                self.set(self.state)
                self.onScreensChanged?()
            }
        }
    }

    func toggle() {
        set(state == .collapsed ? .expanded : .collapsed)
    }

    func showAll() {
        set(.expandedAll)
    }

    func collapse() {
        set(.collapsed)
    }

    /// Re-applies the current state, e.g. after a settings change.
    func refresh() {
        set(state)
    }

    func set(_ requested: SectionState) {
        rehideTask?.cancel()
        if requested == .collapsed, let problem = arrangementProblem() {
            Log.menuBar.error("Not collapsing: \(problem)")
            showArrangementAlert(problem)
            return
        }
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            guard let self else { return }
            let ok = await self.engine.apply(requested, alwaysHiddenEnabled: Preferences.alwaysHiddenEnabled)
            guard !Task.isCancelled else { return }
            self.state = ok ? requested : .expandedAll
            self.onStateChange?(self.state)
            if self.state != .collapsed { self.scheduleRehide() }
        }
    }

    /// If the "|" divider ends up right of the toggle, collapsing would hide the
    /// toggle too and leave only the hotkey to bring it back.
    func arrangementProblem() -> String? {
        guard let toggle = StatusItems.frame(of: items.toggle),
              let separator = StatusItems.frame(of: items.separator) else { return nil }
        if separator.minX > toggle.minX {
            return "The | divider is to the right of Barn Owl's arrow. ⌘-drag it back to the left of the arrow."
        }
        if Preferences.alwaysHiddenEnabled,
           let alwaysHidden = StatusItems.frame(of: items.alwaysHidden),
           alwaysHidden.minX > separator.minX {
            return "The ⋮ divider is to the right of the | divider. ⌘-drag it further left."
        }
        return nil
    }

    private func scheduleRehide() {
        guard Preferences.autoRehide, !holdOpen else { return }
        let delay = Preferences.autoRehideDelay
        rehideTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                // Wait while the pointer is in the menu bar: the user is probably
                // about to click one of the revealed items.
                if self.isPointerInMenuBar() { continue }
                self.collapse()
                return
            }
        }
    }

    private func isPointerInMenuBar() -> Bool {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else { return false }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return location.y >= screen.frame.maxY - max(menuBarHeight, 24)
    }

    private func showArrangementAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Barn Owl can't hide icons yet"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}

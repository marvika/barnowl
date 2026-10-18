import AppKit

/// Optional ways to show hidden icons without clicking: rest the pointer on
/// the arrow, or scroll over the menu bar (down shows, up hides).
@MainActor
final class RevealGestures {
    private let statusItems: StatusItems
    private let isCollapsed: () -> Bool
    private let reveal: () -> Void
    private let hide: () -> Void
    private var hoverMonitor: Any?
    private var scrollMonitor: Any?
    private var settingsObserver: NSObjectProtocol?
    private var hoverTask: Task<Void, Never>?
    private var lastScrollAction = Date.distantPast

    init(statusItems: StatusItems, isCollapsed: @escaping () -> Bool, reveal: @escaping () -> Void,
         hide: @escaping () -> Void) {
        self.statusItems = statusItems
        self.isCollapsed = isCollapsed
        self.reveal = reveal
        self.hide = hide
    }

    func start() {
        update()
        // Turned on or off in Settings: listen, or stop listening, right away.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Listens only for the gestures that are on. Every pointer movement on
    /// the Mac would otherwise be sent to Barn Owl, for nothing.
    private func update() {
        // Global monitors see events going to other apps, which is where the
        // pointer is when it's over the menu bar.
        if Preferences.revealOnHover, hoverMonitor == nil {
            hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            }
        } else if !Preferences.revealOnHover, let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
            hoverMonitor = nil
            hoverTask?.cancel()
            hoverTask = nil
        }
        if Preferences.revealOnScroll, scrollMonitor == nil {
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let delta = event.scrollingDeltaY
                MainActor.assumeIsolated { self?.scrolled(delta) }
            }
        } else if !Preferences.revealOnScroll, let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    /// Whether anything is listening to the pointer, for tests.
    var isListening: (hover: Bool, scroll: Bool) { (hoverMonitor != nil, scrollMonitor != nil) }

    private func pointerMoved() {
        guard Preferences.revealOnHover, isCollapsed(), let arrow = StatusItems.frame(of: statusItems.toggle) else {
            hoverTask?.cancel()
            hoverTask = nil
            return
        }
        guard arrow.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else {
            hoverTask?.cancel()
            hoverTask = nil
            return
        }
        guard hoverTask == nil else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            if let arrow = StatusItems.frame(of: self.statusItems.toggle),
               arrow.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation), self.isCollapsed() {
                self.reveal()
            }
        }
    }

    private func scrolled(_ delta: CGFloat) {
        guard Preferences.revealOnScroll, abs(delta) > 2, Date().timeIntervalSince(lastScrollAction) > 0.6,
              Self.isPointerInMenuBar() else { return }
        lastScrollAction = Date()
        // With natural scrolling, two fingers moving down give a positive delta.
        if delta > 0, isCollapsed() {
            reveal()
        } else if delta < 0, !isCollapsed() {
            hide()
        }
    }

    static func isPointerInMenuBar() -> Bool {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else { return false }
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return location.y >= screen.frame.maxY - height
    }
}

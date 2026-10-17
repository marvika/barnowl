import AppKit

/// Optional ways to show hidden icons without clicking: rest the pointer on
/// the arrow, or scroll over the menu bar (down shows, up hides).
@MainActor
final class RevealGestures {
    private let statusItems: StatusItems
    private let isCollapsed: () -> Bool
    private let reveal: () -> Void
    private let hide: () -> Void
    private var monitors: [Any] = []
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
        // Global monitors see events going to other apps, which is where the
        // pointer is when it's over the menu bar.
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(moved) }
        if let scrolled = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let delta = event.scrollingDeltaY
            MainActor.assumeIsolated { self?.scrolled(delta) }
        }) { monitors.append(scrolled) }
    }

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

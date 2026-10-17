import AppKit
import ApplicationServices

/// Opens another app's menu bar item from the Barkeep Bar or search.
///
/// A hidden item ignores presses (its menu would open off screen), so the
/// item's section is revealed first, the item is pressed through
/// Accessibility, and the section hides again once the item's menu closes.
@MainActor
final class ItemOpener {
    private let sections: SectionController
    private let scanner: ItemScanner
    private var openTask: Task<Void, Never>?

    init(sections: SectionController, scanner: ItemScanner) {
        self.sections = sections
        self.scanner = scanner
    }

    func open(_ item: MenuBarItem) {
        openTask?.cancel()
        openTask = Task { await self.perform(item) }
    }

    private func perform(_ item: MenuBarItem) async {
        let needsReveal = item.section != .visible
        if needsReveal {
            sections.holdOpen = true
            sections.set(item.section == .alwaysHidden ? .expandedAll : .expanded)
            await waitUntilOnScreen(item)
        }
        defer {
            if needsReveal {
                sections.holdOpen = false
                sections.collapse()
            }
        }

        let pressed = AXUIElementPerformAction(item.element.raw, kAXPressAction as CFString) == .success
        // Some apps (often Electron ones) accept the press but show nothing;
        // a real click works for those.
        let opened = pressed ? await menuAppears(for: item.pid) : false
        if !opened {
            Log.menuBar.info("Press didn't open \(item.appName); clicking instead")
            let frame = ItemScanner.currentFrame(of: item.element) ?? item.frame
            Self.click(at: CGPoint(x: frame.midX, y: frame.midY))
            _ = await menuAppears(for: item.pid)
        }
        if needsReveal {
            await waitForMenuToClose(pid: item.pid)
        }
    }

    private func waitUntilOnScreen(_ item: MenuBarItem) async {
        for _ in 0..<25 {
            if let frame = ItemScanner.currentFrame(of: item.element), frame.minX >= 0 { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private func menuAppears(for pid: pid_t) async -> Bool {
        for _ in 0..<10 {
            if Self.hasOpenMenu(pid: pid) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Keeps the section revealed while the item's menu or popover is open,
    /// so it doesn't jump away from under the menu.
    private func waitForMenuToClose(pid: pid_t) async {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline, !Task.isCancelled, Self.hasOpenMenu(pid: pid) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Whether the app (or Control Center, which draws many system menus) has a
    /// menu or popover window up: anything above normal windows that isn't a
    /// menu bar item.
    private static func hasOpenMenu(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return list.contains { info in
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let owner = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            return owner == pid && layer > 0 && layer != statusLevel
        }
    }

    /// A left click at a screen point (top-left coordinates). The pointer is
    /// put back where it was.
    private static func click(at point: CGPoint) {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        if let original { CGWarpMouseCursorPosition(original) }
    }
}

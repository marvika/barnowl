import AppKit
import ApplicationServices

/// Opens another app's menu bar item from the Perch, a group or search.
///
/// A hidden item ignores presses (its menu would open off screen). So the
/// item is moved next to the icon that was clicked (the arrow or a group),
/// pressed there so its menu opens in the right place, and moved back once
/// the menu closes. If moving fails, the item's whole section is revealed
/// instead.
@MainActor
final class ItemOpener {
    private let sections: SectionController
    private let mover: ItemMover
    private var openTask: Task<Void, Never>?

    init(sections: SectionController, mover: ItemMover) {
        self.sections = sections
        self.mover = mover
    }

    /// `anchor` is the window to open the item next to (a group or custom
    /// icon); if nil, the item opens at the start of the visible section.
    /// Right of the anchor, because "left of" an icon that slides while the
    /// item is lifted lands one slot off.
    func open(_ item: MenuBarItem, near anchor: CGWindowID? = nil) {
        guard !DemoMode.isOn else { return }
        openTask?.cancel()
        openTask = Task { await self.perform(item, anchor: anchor) }
    }

    private func perform(_ item: MenuBarItem, anchor: CGWindowID?) async {
        if item.section == .visible && !item.isBehindNotch {
            await press(item)
            return
        }
        let destination: MoveDestination? = anchor.map { .rightOf($0) }
            ?? StatusItems.windowID(of: sections.items.separator).map { .rightOf($0) }
        if item.isMovable, let destination, await openMovedOut(item, to: destination) {
            return
        }
        await openRevealed(item)
    }

    private func openMovedOut(_ item: MenuBarItem, to destination: MoveDestination) async -> Bool {
        // Where it goes back to: left of whatever was right of it.
        let frames = ItemMover.frames()
        let start = frames[item.windowID] ?? item.frame
        let neighbor = frames.filter { $0.key != item.windowID && $0.value.minX >= start.maxX - 1 }
            .min { $0.value.minX < $1.value.minX }?.key
        guard await mover.move(item.windowID, to: destination) else { return false }
        await press(item)
        await waitForMenuToClose(pid: item.pid)
        // Back where it was, once the user pauses: the menu has just closed and
        // they're likely still moving the pointer. If they don't pause, the
        // layout keeper puts it back later.
        if let neighbor, !Task.isCancelled {
            await mover.move(item.windowID, to: .leftOf(neighbor), whenIdle: true)
        }
        return true
    }

    private func openRevealed(_ item: MenuBarItem) async {
        sections.holdOpen = true
        sections.set(item.section == .alwaysHidden ? .expandedAll : .expanded)
        await waitUntilOnScreen(item)
        await press(item)
        await waitForMenuToClose(pid: item.pid)
        // Another icon is being opened instead: leave the bar to that one.
        guard !Task.isCancelled else { return }
        sections.holdOpen = false
        sections.collapse()
    }

    /// Presses through Accessibility; some apps (often Electron ones) accept
    /// the press but show nothing, and a real click works for those.
    private func press(_ item: MenuBarItem) async {
        // An app running its menu often can't answer in time and reports
        // "cannot complete" although the menu opened. Keep the wait short and
        // look for the menu either way; clicking now would close it again.
        AXUIElementSetMessagingTimeout(item.element.raw, 0.25)
        let result = AXUIElementPerformAction(item.element.raw, kAXPressAction as CFString)
        let mayHaveOpened = result == .success || result == .cannotComplete
        if mayHaveOpened, await menuAppears(for: item.pid) { return }
        Log.menuBar.info("Press didn't open \(item.appName); clicking instead")
        let frame = ItemMover.frames()[item.windowID] ?? item.frame
        Self.click(at: CGPoint(x: frame.midX, y: frame.midY))
        _ = await menuAppears(for: item.pid)
    }

    private func waitUntilOnScreen(_ item: MenuBarItem) async {
        for _ in 0..<25 {
            if let frame = ItemMover.frames()[item.windowID], frame.minX >= 0 { return }
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

    /// Keeps the item in place while its menu or popover is open.
    private func waitForMenuToClose(pid: pid_t) async {
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline, !Task.isCancelled, Self.hasOpenMenu(pid: pid) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// Whether the app has a menu or popover up: a window above normal ones
    /// that isn't a menu bar item.
    static func hasOpenMenu(pid: pid_t) -> Bool {
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
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            SyntheticEvents.mark(event)
            event?.post(tap: .cghidEventTap)
        }
        if let original { CGWarpMouseCursorPosition(original) }
    }
}

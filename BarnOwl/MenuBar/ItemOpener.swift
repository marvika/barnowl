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
    /// Icons moved out to be opened, until they're back: the layout keeper
    /// mustn't learn their place from them.
    private(set) var movedOutKeys: Set<String> = []
    /// An icon that couldn't be moved back: the layout keeper takes it back.
    var onLeftOut: (String) -> Void = { _ in }
    /// Which openRevealed holds the bar open now.
    private var revealToken = 0

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
        // While presenting, every icon is behind the curtain left of the arrow:
        // it comes out between the two, and goes back after. Battery sits
        // right of the arrow, out of the curtain's reach.
        let curtain = StatusItems.windowID(of: sections.items.curtain)
        if item.section == .visible && !item.isBehindNotch && (curtain == nil || item.alwaysShows) {
            await press(item)
            return
        }
        let destination: MoveDestination? = (curtain ?? anchor).map { .rightOf($0) }
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
        movedOutKeys.insert(item.key)
        defer { movedOutKeys.remove(item.key) }
        guard await mover.move(item.windowID, to: destination) else { return false }
        await press(item)
        await waitForMenuToClose(pid: item.pid)
        // Back where it was, once the user pauses: the menu has just closed and
        // they're likely still moving the pointer. If they don't pause, or another
        // icon is opened meanwhile, the layout keeper puts it back later. So does
        // it for macOS's own icons, which it moves with every row showing.
        if let neighbor, !Task.isCancelled, !item.isSystem,
           await mover.move(item.windowID, to: .leftOf(neighbor), whenIdle: true) {
            return true
        }
        onLeftOut(item.key)
        return true
    }

    private func openRevealed(_ item: MenuBarItem) async {
        revealToken += 1
        let token = revealToken
        sections.holdOpen = true
        sections.set(item.section == .alwaysHidden ? .expandedAll : .expanded)
        await waitUntilOnScreen(item)
        await press(item)
        await waitForMenuToClose(pid: item.pid)
        // Another icon is being opened instead: leave the bar to that one. If it
        // isn't being opened this way, the bar is no longer held, so it can hide.
        guard !Task.isCancelled else {
            if token == revealToken { sections.holdOpen = false }
            return
        }
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

    /// Whether the app has a menu or popover hanging from the menu bar. A
    /// floating window elsewhere (a timer, a call's controls) isn't one.
    static func hasOpenMenu(pid: pid_t) -> Bool {
        anyMenuOpen(ownedBy: [pid])
    }

    /// Whether one of `owners` (the apps whose icons are hidden) has a menu or
    /// popover hanging from the menu bar.
    static func anyMenuOpen(ownedBy owners: Set<pid_t>) -> Bool {
        guard !owners.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        // Window bounds are top-left based, from the top of the main screen.
        let tops = NSScreen.screens.map { primary.frame.maxY - $0.frame.maxY }
        return list.contains { isMenu($0, ownedBy: owners, screenTops: tops) }
    }

    /// A window above normal ones whose top meets the top of a screen. The
    /// menu bar itself is one too, always there, so only the icons' own apps
    /// count: anything else would keep the icons showing for good.
    nonisolated static func isMenu(_ info: [String: Any], ownedBy owners: Set<pid_t>,
                                   screenTops: [CGFloat]) -> Bool {
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        let owner = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
        let barLevels = [CGWindowLevelForKey(.mainMenuWindow), CGWindowLevelForKey(.statusWindow)].map(Int.init)
        guard owners.contains(owner), layer > 0, !barLevels.contains(layer),
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat], let y = bounds["Y"] else { return false }
        return screenTops.contains { y >= $0 && y <= $0 + 60 }
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
        if let original { SyntheticEvents.restorePointer(to: original, after: point) }
    }
}

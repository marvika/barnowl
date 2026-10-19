import AppKit

/// Where to put a menu bar item, relative to another status window.
enum MoveDestination: Equatable, Sendable {
    case leftOf(CGWindowID)
    case rightOf(CGWindowID)

    var targetWindowID: CGWindowID {
        switch self {
        case .leftOf(let id), .rightOf(let id): id
        }
    }

    /// Where the mouse-up goes, against the target's frame. Off-screen targets
    /// (in a hidden section) are fine: the system places by raw coordinates.
    func dropPoint(targetFrame: CGRect) -> CGPoint {
        switch self {
        case .leftOf: CGPoint(x: targetFrame.minX + 1, y: targetFrame.midY)
        case .rightOf: CGPoint(x: targetFrame.maxX - 1, y: targetFrame.midY)
        }
    }

    /// Whether the item already sits there: next to the target on the right
    /// side, with no other window in between.
    func isSatisfied(itemID: CGWindowID, frames: [CGWindowID: CGRect]) -> Bool {
        guard let item = frames[itemID], let target = frames[targetWindowID] else { return false }
        let others = frames.filter { $0.key != itemID && $0.key != targetWindowID }.values
        switch self {
        case .leftOf:
            guard item.maxX <= target.minX + 2 else { return false }
            return !others.contains { $0.midX > item.maxX && $0.midX < target.minX }
        case .rightOf:
            guard item.minX >= target.maxX - 2 else { return false }
            return !others.contains { $0.midX > target.maxX && $0.midX < item.minX }
        }
    }
}

/// Moves menu bar items, other apps' and Barn Owl's own, with a synthetic ⌘-drag.
///
/// macOS 26 routes a mouse event by the window ID in event field 0x33 rather
/// than by position, so the mouse-down lands on Barn Owl's own arrow (always
/// visible, always ours) while the system lifts the target item, even an
/// off-screen one. The mouse-up then goes next to the destination. Nothing is
/// ever clicked on another app's icon. Measured on 26.6: the item lifts after
/// 20–60 ms; the mouse-up must wait for that or the move is ignored.
/// Technique from Ice and Frost (MIT; see THIRD_PARTY_NOTICES.md).
@MainActor
final class ItemMover {
    private let statusItems: StatusItems
    private var tail: Task<Bool, Never>?

    /// True while a move is in progress.
    private(set) var isMoving = false

    init(statusItems: StatusItems) {
        self.statusItems = statusItems
    }

    /// Moves are queued: one ⌘-drag at a time. A ⌘-drag borrows the pointer
    /// for a moment, so moves Barn Owl makes on its own (`whenIdle`) wait
    /// until the user has stopped using the mouse and keyboard, and are
    /// skipped if they don't within half a minute.
    @discardableResult
    func move(_ windowID: CGWindowID, to destination: MoveDestination, whenIdle: Bool = false) async -> Bool {
        // Waiting for a pause happens before joining the queue, so a move the
        // user asks for meanwhile (opening an icon) goes first.
        if whenIdle, !(await UserActivity.waitUntilIdle(timeout: 30)) {
            Log.menuBar.info("Move of \(windowID) skipped: you were busy")
            return false
        }
        let previous = tail
        let task = Task { [weak self] () -> Bool in
            _ = await previous?.value
            guard let self else { return false }
            // Still paused after waiting its turn? Otherwise try again another time.
            if whenIdle, !UserActivity.isIdle { return false }
            return await self.perform(windowID, destination)
        }
        tail = task
        return await task.value
    }

    private func perform(_ itemID: CGWindowID, _ destination: MoveDestination) async -> Bool {
        isMoving = true
        // The drag's mouse-down lands on the arrow; without this its tooltip
        // pops up after every move.
        let toolTip = statusItems.toggle.button?.toolTip
        statusItems.toggle.button?.toolTip = nil
        defer {
            isMoving = false
            Task { @MainActor [statusItems] in
                try? await Task.sleep(for: .seconds(2))
                if statusItems.toggle.button?.toolTip == nil { statusItems.toggle.button?.toolTip = toolTip }
            }
        }
        for attempt in 1...3 {
            await Self.waitForMouseButtonsReleased()
            let frames = Self.frames()
            if destination.isSatisfied(itemID: itemID, frames: frames) { return true }
            guard let itemFrame = frames[itemID], frames[destination.targetWindowID] != nil,
                  let arrow = StatusItems.cgFrame(of: statusItems.toggle) else {
                Log.menuBar.error("Move of \(itemID) skipped: item, target or arrow not found")
                return false
            }
            // Near the arrow's right edge: while presenting the arrow is very
            // wide and its middle is off screen.
            let down = CGPoint(x: arrow.maxX - min(12, arrow.width / 2), y: arrow.midY)
            let posted = await Task.detached {
                Self.postCommandDrag(itemID: itemID, originalFrame: itemFrame, mouseDown: down,
                                     destination: destination)
            }.value
            if await settle(itemID, destination) {
                Log.menuBar.info("Moved \(itemID) to \(String(describing: destination)) (attempt \(attempt))")
                return true
            }
            Log.menuBar.info("Move of \(itemID) attempt \(attempt) didn't land (lifted: \(posted))")
        }
        return false
    }

    /// Waits for the menu bar to stop sliding and checks the result.
    private func settle(_ itemID: CGWindowID, _ destination: MoveDestination) async -> Bool {
        var previous: [CGWindowID: CGRect] = [:]
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(50))
            let frames = Self.frames()
            if frames == previous { return destination.isSatisfied(itemID: itemID, frames: frames) }
            previous = frames
        }
        return destination.isSatisfied(itemID: itemID, frames: Self.frames())
    }

    nonisolated static func frames() -> [CGWindowID: CGRect] {
        Dictionary(ItemScanner.statusWindows(includeWide: true).map { ($0.windowID, $0.frame) },
                   uniquingKeysWith: { a, _ in a })
    }

    private static func waitForMouseButtonsReleased() async {
        for _ in 0..<100 where isAnyMouseButtonHeld {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    nonisolated static var isAnyMouseButtonHeld: Bool {
        [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
    }

    nonisolated private static let windowIDField = CGEventField(rawValue: 0x33)!

    /// Posts the ⌘-drag and returns whether the item was seen lifting. Runs
    /// off the main thread because it sleeps between events.
    nonisolated private static func postCommandDrag(itemID: CGWindowID, originalFrame: CGRect, mouseDown: CGPoint,
                                                    destination: MoveDestination) -> Bool {
        guard !isAnyMouseButtonHeld else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        // Don't block the user's own input while the synthetic events go out.
        if let session = CGEventSource(stateID: .combinedSessionState) {
            let permit: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents,
                                             .permitSystemDefinedEvents]
            session.setLocalEventsFilterDuringSuppressionState(permit, state: .eventSuppressionStateRemoteMouseDrag)
            session.setLocalEventsFilterDuringSuppressionState(permit,
                                                               state: .eventSuppressionStateSuppressionInterval)
            session.localEventsSuppressionInterval = 0
        }
        func event(_ type: CGEventType, _ point: CGPoint) -> CGEvent? {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                mouseButton: .left)
            event?.flags = .maskCommand
            event?.setIntegerValueField(windowIDField, value: Int64(itemID))
            SyntheticEvents.mark(event)
            return event
        }
        let savedCursor = CGEvent(source: nil)?.location
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            if let savedCursor { CGWarpMouseCursorPosition(savedCursor) }
            CGDisplayShowCursor(CGMainDisplayID())
        }

        event(.leftMouseDown, mouseDown)?.post(tap: .cgSessionEventTap)
        // Wait until the item has lifted out of its slot (its frame changes)
        // and been seen lifted a few times, at most 600 ms.
        var liftedSnapshots = 0
        var frames = Self.frames()
        for _ in 0..<60 {
            usleep(10_000)
            frames = Self.frames()
            if let frame = frames[itemID], frame != originalFrame { liftedSnapshots += 1 }
            if liftedSnapshots >= 3 { break }
        }
        // Aim at where the target is now: the others slide while the item is lifted.
        // No target any more: drop where the drag started rather than at (0, 0),
        // the top-left hot corner.
        let target = frames[destination.targetWindowID] ?? originalFrame
        event(.leftMouseUp, destination.dropPoint(targetFrame: target))?.post(tap: .cgSessionEventTap)
        usleep(20_000)
        return liftedSnapshots >= 3
    }
}

/// Marks the mouse events Barn Owl posts itself, so its own monitors can tell
/// them apart from real clicks.
enum SyntheticEvents {
    nonisolated static let tag: Int64 = 0x0B4E_0A71

    nonisolated static func mark(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: tag)
    }

    nonisolated static func isMarked(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == tag
    }
}

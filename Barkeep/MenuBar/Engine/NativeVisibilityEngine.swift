import AppKit

/// macOS 27: ask macOS to show only an allow-list of apps, through the private
/// restriction behind exam (assessment) mode. macOS hides the rest and reflows
/// the bar itself. Adapted from Hidden Bar's engine (see THIRD_PARTY_NOTICES.md).
///
/// Limits of what macOS 27 exposes:
/// - Hiding is per app: an app with several icons hides or shows them all.
/// - System items (clock, Wi-Fi, Control Center…) always stay visible.
/// - Sections can only be read while nothing is hidden, so an app launched
///   while collapsed stays where macOS puts it until the next collapse.
///
/// Experimental: written against Hidden Bar's findings and not yet tested on
/// macOS 27 hardware.
@MainActor
final class NativeVisibilityEngine: HidingEngine {
    let displayName = "Native visibility (macOS 27)"
    let needsAccessibility = true

    /// System item IDs to keep. Unknown IDs are ignored, so a generous range
    /// covers items a given Mac doesn't have.
    private static let systemItemsToKeep = (0..<64).map { NSNumber(value: $0) }

    private let items: StatusItems
    private var assertion: AnyObject?
    private var layout: SectionLayout?
    /// Bumped by every apply, so a slow activation can't win over a newer one.
    private var generation = 0

    init(items: StatusItems) {
        self.items = items
    }

    func apply(_ state: SectionState, alwaysHiddenEnabled: Bool) async -> Bool {
        generation += 1
        let generation = self.generation
        let alwaysHidden = alwaysHiddenEnabled ? items.ensureAlwaysHiddenItem() : items.alwaysHidden
        alwaysHidden?.length = alwaysHiddenEnabled ? StatusItems.dividerLength : 0

        if state == .expandedAll || (state == .expanded && !alwaysHiddenEnabled) {
            release()
            items.setDividerVisible(items.separator, true)
            return true
        }
        guard BKNativeVisibilityIsAvailable() else {
            Log.menuBar.error("Native visibility API is not available on this macOS")
            return false
        }
        guard AccessibilityInventory.isTrusted else {
            AccessibilityInventory.requestTrust()
            Log.menuBar.error("Accessibility permission is needed to read the menu bar sections")
            return false
        }
        guard let layout = await currentLayout(alwaysHiddenEnabled: alwaysHiddenEnabled),
              generation == self.generation else { return false }

        let sections: Set<MenuBarSection> = state == .collapsed ? [.visible] : [.visible, .hidden]
        let allowed = [Bundle.main.bundleIdentifier].compactMap { $0 } + layout.bundles(in: sections)
        let ok = await activate(allowing: allowed, generation: generation)
        if ok {
            items.setDividerVisible(items.separator, state != .collapsed)
        }
        return ok
    }

    func invalidateLayout() {
        if assertion == nil { layout = nil }
    }

    /// Only Barkeep's own items (and the system's) stay.
    func setPresenting(_ presenting: Bool) async -> Bool {
        generation += 1
        let generation = self.generation
        if presenting {
            return await activate(allowing: [Bundle.main.bundleIdentifier].compactMap { $0 }, generation: generation)
        }
        release()
        return true
    }

    /// Fresh from an unrestricted bar; while a restriction is active, hidden
    /// items report stale positions, so the cached layout stands in.
    private func currentLayout(alwaysHiddenEnabled: Bool) async -> SectionLayout? {
        if assertion != nil, let layout { return layout }
        guard let separatorFrame = StatusItems.frame(of: items.separator) else { return nil }
        let alwaysHiddenFrame = alwaysHiddenEnabled ? StatusItems.frame(of: items.alwaysHidden) : nil
        let inventory = await AccessibilityInventory.snapshot()
        let resolved = SectionLayoutResolver.resolve(items: inventory,
                                                     separatorFrame: separatorFrame,
                                                     alwaysHiddenFrame: alwaysHiddenFrame,
                                                     excluding: Bundle.main.bundleIdentifier)
        Log.menuBar.info("Sections: visible \(resolved.bundles(in: [.visible])), hidden \(resolved.bundles(in: [.hidden])), always hidden \(resolved.bundles(in: [.alwaysHidden]))")
        layout = resolved
        return resolved
    }

    /// Activates the new restriction before dropping the old one, so switching
    /// states never flashes the whole bar.
    private func activate(allowing bundles: [String], generation: Int) async -> Bool {
        // The completion always runs on the main queue, so handing the
        // assertion back to this main-actor engine is safe.
        let result: ActivationResult = await withCheckedContinuation { continuation in
            BKNativeVisibilityActivate(Self.systemItemsToKeep, bundles) { assertion, error in
                continuation.resume(returning: ActivationResult(assertion: assertion as AnyObject?,
                                                                error: error?.localizedDescription))
            }
        }
        guard generation == self.generation else {
            if let stale = result.assertion { BKNativeVisibilityInvalidate(stale) }
            return false
        }
        guard let newAssertion = result.assertion else {
            // Fail open: never leave icons hidden after an error.
            Log.menuBar.error("Native visibility activation failed: \(result.error ?? "unknown error")")
            release()
            return false
        }
        let old = assertion
        assertion = newAssertion
        if let old { BKNativeVisibilityInvalidate(old) }
        return true
    }

    private func release() {
        if let assertion { BKNativeVisibilityInvalidate(assertion) }
        assertion = nil
    }
}

private struct ActivationResult: @unchecked Sendable {
    var assertion: AnyObject?
    var error: String?
}

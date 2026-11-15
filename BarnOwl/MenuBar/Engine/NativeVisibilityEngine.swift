import AppKit

/// macOS 27: tell macOS which apps may show their icons, through the private
/// restriction behind exam (assessment) mode. macOS hides the rest and reflows
/// the bar itself. The technique comes from Hidden Bar (see
/// THIRD_PARTY_NOTICES.md); which apps to let through comes from Barn Owl's
/// own table (`AppRows`), not from where icons sit.
///
/// What macOS 27.0 allows, measured on a Mac running it:
/// - Hiding is per app: an app with several icons hides or shows them all.
/// - macOS's own Sound, Battery, Wi‑Fi, Control Center and clock always show,
///   whatever the restriction lists. Now Playing hides whenever anything does.
/// - Several restrictions add up: macOS shows what any of them allows. Barn
///   Owl holds one at a time, and swaps it for a new one without a gap.
/// - The restriction ends by itself when Barn Owl quits or crashes, so icons
///   are never left hidden.
@MainActor
final class NativeVisibilityEngine: HidingEngine {
    let displayName = "Per app (macOS 27)"
    let needsAccessibility = true

    /// The system-item list the restriction takes. It changes nothing on
    /// macOS 27.0; the full range is passed in case a later release reads it.
    private static let systemItems = (0..<64).map { NSNumber(value: $0) }

    /// Which apps may show in a state, or nil when that state hides nothing.
    /// The layout sets this once it exists.
    var allowedApps: (SectionState) -> Set<String>? = { _ in nil }

    private var assertion: AnyObject?
    /// What the restriction in force allows.
    private var active: [String]?
    private var state = SectionState.expandedAll
    private var presenting = false
    private var revealed: Set<String> = []
    /// Bumped by every change, so a slow activation can't win over a newer one.
    private var generation = 0

    func apply(_ state: SectionState, alwaysHiddenEnabled: Bool) async -> Bool {
        self.state = state
        return await update()
    }

    func refresh() async {
        _ = await update()
    }

    func invalidateLayout() {
        // Nothing here depends on the displays.
    }

    /// Only Barn Owl's own icons (and macOS's) stay.
    func setPresenting(_ presenting: Bool) async -> Bool {
        self.presenting = presenting
        return await update()
    }

    func reveal(_ apps: Set<String>) async -> Bool {
        revealed = apps
        return await update()
    }

    /// The apps to let through now, or nil for all of them.
    private var wanted: [String]? {
        let own = Bundle.main.bundleIdentifier.map { [$0] } ?? []
        if presenting { return Set(own).union(revealed).sorted() }
        guard state != .expandedAll, let allowed = allowedApps(state) else { return nil }
        return allowed.union(revealed).union(own).sorted()
    }

    private func update() async -> Bool {
        generation += 1
        let generation = self.generation
        guard let wanted else {
            release()
            return true
        }
        if assertion != nil, wanted == active { return true }
        guard BKNativeVisibilityIsAvailable() else {
            Log.menuBar.error("The menu bar restriction isn't available on this macOS")
            release()
            return false
        }
        return await activate(allowing: wanted, generation: generation)
    }

    /// Activates the new restriction before dropping the old one, so switching
    /// states never flashes the whole bar.
    private func activate(allowing bundles: [String], generation: Int) async -> Bool {
        // The completion always runs on the main queue, so handing the
        // assertion back to this main-actor engine is safe.
        let result: ActivationResult = await withCheckedContinuation { continuation in
            // The private API's callback could come twice (an error after a
            // result); resuming a continuation twice crashes.
            let once = OnceFlag()
            BKNativeVisibilityActivate(Self.systemItems, bundles) { assertion, error in
                guard once.claim() else { return }
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
            Log.menuBar.error("Hiding icons failed: \(result.error ?? "unknown error", privacy: .public)")
            release()
            return false
        }
        let old = assertion
        assertion = newAssertion
        active = bundles
        if let old { BKNativeVisibilityInvalidate(old) }
        Log.menuBar.info("Showing \(bundles.count) apps' icons, hiding the rest")
        return true
    }

    private func release() {
        if let assertion { BKNativeVisibilityInvalidate(assertion) }
        assertion = nil
        active = nil
    }
}

private struct ActivationResult: @unchecked Sendable {
    var assertion: AnyObject?
    var error: String?
}

/// True the first time it's claimed, false after: for callbacks that must act once.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

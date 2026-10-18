import AppKit
import ApplicationServices
import Observation

/// Hides every menu bar icon while you share or record your screen, so
/// nothing private shows up in a meeting.
@MainActor
@Observable
final class PresenterMode {
    private(set) var isPresenting = false
    /// True while icons are being moved in or out for presenting; the
    /// background arranger must not mistake those moves for the user's.
    private(set) var isChanging = false
    /// True when the current session started because screen sharing began.
    private(set) var startedAutomatically = false
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    @ObservationIgnored private let sections: SectionController
    @ObservationIgnored private let keepAwake: KeepAwakeController
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var hidDesktopIcons = false
    @ObservationIgnored private let images: ItemImageCache
    @ObservationIgnored private let scanner: ItemScanner
    @ObservationIgnored private let mover: ItemMover
    @ObservationIgnored private let layout: LayoutController
    @ObservationIgnored private var sharingChecks = 0
    /// Set when presenting is turned off by hand during a share.
    @ObservationIgnored private var stoppedDuringShare = false
    /// Icons moved out of view for presenting, to put back afterwards.
    @ObservationIgnored private(set) var movedKeys: [String] = []

    init(sections: SectionController, keepAwake: KeepAwakeController, images: ItemImageCache, scanner: ItemScanner,
         mover: ItemMover, layout: LayoutController) {
        self.sections = sections
        self.keepAwake = keepAwake
        self.images = images
        self.scanner = scanner
        self.mover = mover
        self.layout = layout
    }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.checkSharing()
            }
        }
    }

    func toggle() async {
        await set(!isPresenting, automatically: false)
    }

    func set(_ presenting: Bool, automatically: Bool) async {
        guard presenting != isPresenting, !isChanging else { return }
        isChanging = true
        isPresenting = presenting
        startedAutomatically = presenting && automatically
        // Turned off by hand during a share: stay off until that share ends.
        if !presenting, !automatically, sharingChecks >= 2 { stoppedDuringShare = true }
        Log.app.info("Presenter mode \(presenting ? "on" : "off")\(automatically ? " (screen sharing)" : "")")
        onChange?(presenting)
        sections.collapse()
        if !(await sections.engine.setPresenting(presenting)) {
            presenting ? await hideVisibleIcons() : await restoreIcons()
        }
        keepAwake.setPresenting(presenting && Preferences.presenterKeepAwake)
        let switchesDesktop = Self.switchesDesktopIcons(presenting: presenting,
                                                        enabled: Preferences.presenterHideDesktopIcons,
                                                        hidden: QuickToggles.desktopIconsHidden,
                                                        hidThem: hidDesktopIcons)
        if switchesDesktop { QuickToggles.toggleDesktopIcons() }
        hidDesktopIcons = presenting && switchesDesktop
        await finishChange(presenting)
    }

    /// Hides the desktop icons as presenting starts, if they're showing. At
    /// the end, shows them again only if Barn Owl hid them and they're still
    /// hidden: you may have shown them by hand meanwhile.
    nonisolated static func switchesDesktopIcons(presenting: Bool, enabled: Bool, hidden: Bool,
                                                 hidThem: Bool) -> Bool {
        presenting ? enabled && !hidden : hidThem && hidden
    }

    /// Moves every other app's visible icon into the hidden section, without
    /// changing the saved layout. The clock and Control Center stay; macOS
    /// won't move them.
    private func hideVisibleIcons() async {
        guard let divider = StatusItems.windowID(of: sections.items.separator) else { return }
        scanner.updateFrames()
        for item in scanner.items where item.section == .visible && item.isMovable {
            // Recorded first, so it's restored even if the move reports failure.
            // `scanner.items` runs left to right.
            movedKeys.append(item.key)
            await mover.move(item.windowID, to: .leftOf(divider))
        }
        scanner.updateFrames()
    }

    /// Each icon returns to the start of the visible section, so going from
    /// the rightmost to the leftmost keeps their order.
    private func restoreIcons() async {
        for key in movedKeys.reversed() { await layout.returnToRow(key) }
        movedKeys = []
    }

    /// Called at the end of every switch.
    private func finishChange(_ presenting: Bool) async {
        isChanging = false
        // Back from presenting: catch up on anything apps changed meanwhile.
        if !presenting { await layout.reconcile() }
    }

    /// Starts when screen sharing starts, and stops when it stops, unless
    /// the user started presenting by hand.
    private func checkSharing() async {
        guard !DemoMode.isOn else { return }
        guard Preferences.presenterAutomatic else { return }
        // Barn Owl's own icon pictures light up the same indicator for a few
        // seconds; ignore it then, and require it to stay on for two checks.
        let ownCaptureRecently = Date().timeIntervalSince(max(images.lastCapture, OwnCaptures.last)) < 10
        let indicator = !ownCaptureRecently && Self.isScreenBeingShared
        sharingChecks = indicator ? sharingChecks + 1 : 0
        if !indicator && !ownCaptureRecently { stoppedDuringShare = false }
        let sharing = sharingChecks >= 2
        if sharing && !isPresenting && !stoppedDuringShare {
            await set(true, automatically: true)
        } else if !indicator && !ownCaptureRecently && isPresenting && startedAutomatically {
            await set(false, automatically: true)
        }
    }

    /// While the screen is shared or recorded, Control Center says so in its
    /// menu bar item's description ("Control Center, Screen Recording is in
    /// use"); macOS's own indicator, readable without extra permission.
    nonisolated static var isScreenBeingShared: Bool {
        guard let controlCenter = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.controlcenter").first else { return false }
        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar
        else { return false }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement]) ?? [] {
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier)
            guard (identifier as? String) == "com.apple.menuextra.controlcenter" else { continue }
            var description: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &description)
            return describesSharing(description as? String ?? "")
        }
        return false
    }

    /// "Control Center, Screen Recording is in use" (and "Screen Sharing" variants).
    nonisolated static func describesSharing(_ description: String) -> Bool {
        let lowered = description.lowercased()
        return lowered.contains("screen") && (lowered.contains("in use") || lowered.contains("sharing"))
    }
}

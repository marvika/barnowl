import AppKit
import ApplicationServices

/// macOS 27: what MenuBarAgent, which draws the menu bar, has in view.
///
/// A hidden icon still answers Accessibility, with the frame it last had on
/// screen, and another icon may since have taken that place. So an icon's own
/// frame can't say whether it's showing. MenuBarAgent's window can: it holds
/// one element per icon it has laid out, each with the icon inside it, which
/// belongs to the icon's own app and sits where the icon really is.
enum AgentBar {
    /// An icon in view: the process it belongs to (MenuBarAgent itself for
    /// macOS's own icons) and where it is, with a top-left origin.
    struct Icon: Equatable, Sendable {
        let pid: pid_t
        let frame: CGRect
    }

    /// Every icon in view. Empty if MenuBarAgent can't be read, as on macOS 26.
    nonisolated static func iconsInView() -> [Icon] {
        guard let agent = NSRunningApplication.runningApplications(
            withBundleIdentifier: MenuBarPlatform.agentBundle).first else { return [] }
        let app = timed(AXUIElementCreateApplication(agent.processIdentifier))
        var laidOut: [(slot: CGRect, icon: Icon)] = []
        for window in elements(app, kAXWindowsAttribute) {
            for slot in elements(timed(window), kAXChildrenAttribute) {
                guard let slotFrame = AccessibilityInventory.frame(of: timed(slot)),
                      let inner = elements(slot, kAXChildrenAttribute).first,
                      let frame = AccessibilityInventory.frame(of: timed(inner)) else { continue }
                var pid: pid_t = 0
                AXUIElementGetPid(inner, &pid)
                laidOut.append((slotFrame, Icon(pid: pid, frame: frame)))
            }
        }
        let overflow = overflowButtons(of: app)
        return laidOut.filter { !isTuckedAway($0.slot, under: overflow) }.map(\.icon)
    }

    /// macOS keeps the icons that don't fit beside the notch behind a button
    /// of its own ("«"). They're laid out all the same, stacked under that
    /// button with their right edges on its right edge, where they can't be
    /// seen or clicked.
    nonisolated static func isTuckedAway(_ slot: CGRect, under overflowButtons: [CGRect]) -> Bool {
        overflowButtons.contains { abs($0.maxX - slot.maxX) <= 2 && abs($0.midY - slot.midY) <= 12 }
    }

    /// Whether an icon of process `pid` reporting `frame` is one of the icons
    /// in view: same process, same place and width. (Height and y differ for
    /// macOS's own icons, which are listed by the view that holds them.)
    nonisolated static func isShowing(pid: pid_t, frame: CGRect, among icons: [Icon]) -> Bool {
        icons.contains { $0.pid == pid && abs($0.frame.minX - frame.minX) <= 1 && abs($0.frame.width - frame.width) <= 1 }
    }

    /// The overflow buttons: the only things in MenuBarAgent's own list of
    /// icons that aren't in a hosting view.
    private nonisolated static func overflowButtons(of app: AXUIElement) -> [CGRect] {
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        return elements(timed(bar as! AXUIElement), kAXChildrenAttribute).compactMap { child in
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(timed(child), kAXRoleAttribute as CFString, &role)
            guard (role as? String) == kAXButtonRole else { return nil }
            return AccessibilityInventory.frame(of: child)
        }
    }

    private nonisolated static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    /// One hung read mustn't hold Barn Owl up.
    private nonisolated static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, 0.2)
        return element
    }
}

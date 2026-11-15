import AppKit
import ApplicationServices

/// Lists other apps' menu bar items through Accessibility.
///
/// On macOS 26 every item window is owned by Control Center, so the window
/// list can't say which app an item belongs to. Each app's AXExtrasMenuBar
/// children can. On macOS 27 there are no item windows at all, and this is
/// the only list there is.
enum AccessibilityInventory {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt; the global itself isn't concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Every menu bar item of one app, with what's needed to name and press it.
    nonisolated static func entries(for app: AppRef) -> [AXMenuBarEntry] {
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let bar: AXUIElement = attribute(element, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(timed(bar), kAXChildrenAttribute) else { return [] }
        if app.bundle == MenuBarPlatform.agentBundle { return agentEntries(children, app: app) }
        return children.compactMap { child in
            guard let frame = frame(of: timed(child)) else { return nil }
            return AXMenuBarEntry(pid: app.pid, bundleIdentifier: app.bundle, appName: app.name,
                                  title: name(of: child), frame: frame, element: AXElement(raw: child))
        }
    }

    /// macOS 27: macOS's own icons (Sound, Battery, Wi‑Fi, Control Center, the
    /// clock…) belong to MenuBarAgent. Each sits one level down, in a hosting
    /// view, and says which it is in its identifier
    /// ("com.apple.menuextra.sound"). Anything else there, such as the button
    /// for macOS's own overflow, isn't an icon.
    private nonisolated static func agentEntries(_ hosts: [AXUIElement], app: AppRef) -> [AXMenuBarEntry] {
        hosts.flatMap { host -> [AXMenuBarEntry] in
            let items: [AXUIElement] = attribute(timed(host), kAXChildrenAttribute) ?? []
            return items.compactMap { item in
                guard let identifier: String = attribute(timed(item), kAXIdentifierAttribute),
                      let agentName = agentName(fromIdentifier: identifier),
                      let frame = frame(of: item) else { return nil }
                return AXMenuBarEntry(pid: app.pid, bundleIdentifier: app.bundle, appName: app.name,
                                      title: name(of: item), frame: frame, element: AXElement(raw: item),
                                      agentName: agentName)
            }
        }
    }

    /// "sound" from "com.apple.menuextra.sound"; nil for anything that isn't
    /// one of macOS's menu extras.
    nonisolated static func agentName(fromIdentifier identifier: String) -> String? {
        let prefix = "com.apple.menuextra."
        guard identifier.hasPrefix(prefix), identifier.count > prefix.count else { return nil }
        return String(identifier.dropFirst(prefix.count))
    }

    private nonisolated static func name(of element: AXUIElement) -> String? {
        let title: String? = attribute(element, kAXTitleAttribute)
        let description: String? = attribute(element, kAXDescriptionAttribute)
        return [title, description].compactMap { $0 }.first { !$0.isEmpty }.map(cleaned)
    }

    /// The item's current status text: its title, description or help (tooltip),
    /// whichever it has. Many apps put their state there ("Syncing…").
    nonisolated static func statusText(of element: AXUIElement) -> String {
        AXUIElementSetMessagingTimeout(element, 0.1)
        return [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            .compactMap { (attribute(element, $0) as String?) }
            .joined(separator: "|")
    }

    /// The timeout belongs to each element, not to the app: a bar or item
    /// fetched from a hung app would otherwise wait the default seconds.
    private nonisolated static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }

    /// Accessibility titles sometimes span lines ("OneDrive\nBacked up and synced").
    private nonisolated static func cleaned(_ title: String) -> String {
        title.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private nonisolated static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Accessibility uses a top-left origin and AppKit a bottom-left one; only
    /// x is used for sections and it's the same in both.
    nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

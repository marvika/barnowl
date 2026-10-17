import AppKit
import ApplicationServices

/// Lists other apps' menu bar items through Accessibility.
///
/// On macOS 26 every item window is owned by Control Center, so the window
/// list can't say which app an item belongs to. Each app's AXExtrasMenuBar
/// children can.
enum AccessibilityInventory {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt; the global itself isn't concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Walks every running app off the main thread. Takes about a second in
    /// total, because each app has to answer an Accessibility round trip.
    static func snapshot() async -> [InventoryItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Only app bundles own status items; skipping helpers and XPC services
        // avoids sitting out their timeouts.
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .map { (pid: $0.processIdentifier, bundle: $0.bundleIdentifier) }
        return await Task.detached(priority: .userInitiated) {
            apps.flatMap { items(pid: $0.pid, bundle: $0.bundle) }
        }.value
    }

    private nonisolated static func items(pid: pid_t, bundle: String?) -> [InventoryItem] {
        let app = AXUIElementCreateApplication(pid)
        // The default timeout is seconds per app; one hung app would stall everything.
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let bar: AXUIElement = attribute(app, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }
        return children.compactMap { child in
            frame(of: child).map { InventoryItem(bundleIdentifier: bundle, frame: $0) }
        }
    }

    /// Every menu bar item of one app, with what's needed to name and press it.
    nonisolated static func entries(for app: AppRef) -> [AXMenuBarEntry] {
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let bar: AXUIElement = attribute(element, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }
        return children.compactMap { child in
            guard let frame = frame(of: child) else { return nil }
            let title: String? = attribute(child, kAXTitleAttribute)
            let description: String? = attribute(child, kAXDescriptionAttribute)
            let name = [title, description].compactMap { $0 }.first { !$0.isEmpty }
            return AXMenuBarEntry(pid: app.pid, bundleIdentifier: app.bundle, appName: app.name,
                                  title: name.map(cleaned), frame: frame, element: AXElement(raw: child))
        }
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

import AppKit

/// A made-up menu bar for screenshots and demos: generic icons, clipboard
/// entries and shelf files instead of the real ones. Started with
/// `Scripts/demo.sh`, which runs a separate copy of Barn Owl with its own
/// settings, so nothing real is read, moved or saved.
enum DemoMode {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "BarnOwlDemo") }

    struct Icon {
        let name: String
        let symbol: String
        let section: MenuBarSection
        var title: String?
        var text: String?
    }

    /// Left to right, as they'd sit in the menu bar.
    static let icons: [Icon] = [
        Icon(name: "Passwords", symbol: "key.fill", section: .alwaysHidden),
        Icon(name: "Backup", symbol: "externaldrive.fill.badge.timemachine", section: .alwaysHidden),
        Icon(name: "VPN", symbol: "lock.shield.fill", section: .alwaysHidden, title: "Connected"),
        Icon(name: "Mail", symbol: "envelope.fill", section: .alwaysHidden),
        Icon(name: "Chat", symbol: "bubble.left.and.bubble.right.fill", section: .alwaysHidden),
        Icon(name: "Cloud Drive", symbol: "icloud.fill", section: .hidden, title: "Up to date"),
        Icon(name: "Containers", symbol: "shippingbox.fill", section: .hidden),
        Icon(name: "Screenshots", symbol: "camera.viewfinder", section: .hidden),
        Icon(name: "Window Switcher", symbol: "rectangle.on.rectangle", section: .hidden),
        Icon(name: "Translator", symbol: "character.bubble.fill", section: .hidden),
        Icon(name: "Notes", symbol: "note.text", section: .hidden),
        Icon(name: "Timer", symbol: "timer", section: .hidden, text: "25:00"),
        Icon(name: "Spotlight", symbol: "magnifyingglass", section: .hidden),
        Icon(name: "Weather", symbol: "cloud.sun.fill", section: .visible, text: "18°"),
        Icon(name: "Music", symbol: "music.note", section: .visible),
        Icon(name: "Wi‑Fi", symbol: "wifi", section: .visible, title: "connected"),
        Icon(name: "Battery", symbol: "battery.75percent", section: .visible),
    ]

    /// Icons in the demo "Work" group (set up by `Scripts/demo.sh`).
    static let workGroup = ["VPN", "Mail", "Chat"]

    static func key(for icon: Icon) -> String { "demo/\(icon.name)" }

    @MainActor
    static func items() -> [MenuBarItem] {
        let placeholder = AXElement(raw: AXUIElementCreateSystemWide())
        var x: CGFloat = -1200
        return icons.enumerated().map { index, icon in
            let width = icon.text == nil ? 32 : 70.0
            defer { x += width }
            var item = MenuBarItem(windowID: CGWindowID(900_000 + index),
                                   frame: CGRect(x: icon.section == .visible ? 1300 + x / 10 : x, y: 0,
                                                 width: width, height: 33),
                                   pid: 0, bundleIdentifier: icon.name == "Wi‑Fi" || icon.name == "Battery"
                                       ? "com.apple.controlcenter" : "demo.\(icon.name.lowercased())",
                                   appName: icon.name == "Wi‑Fi" || icon.name == "Battery" ? "Control Center" : icon.name,
                                   title: icon.name == "Wi‑Fi" || icon.name == "Battery"
                                       ? [icon.name, icon.title].compactMap { $0 }.joined(separator: ", ") : icon.title,
                                   element: placeholder)
            item.key = key(for: icon)
            item.section = icon.section
            return item
        }
    }

    /// Menu-bar-style picture: a white symbol, plus text for some.
    @MainActor
    static func image(for item: MenuBarItem) -> NSImage? {
        guard let icon = icons.first(where: { key(for: $0) == item.key }) else { return nil }
        let size = NSSize(width: item.frame.width, height: 24)
        let symbol = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: icon.name)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium).applying(.init(paletteColors: [.white])))
        return NSImage(size: size, flipped: false) { rect in
            guard let symbol else { return true }
            let symbolX = icon.text == nil ? (rect.width - symbol.size.width) / 2 : 6
            symbol.draw(at: NSPoint(x: symbolX, y: (rect.height - symbol.size.height) / 2), from: .zero,
                        operation: .sourceOver, fraction: 1)
            if let text = icon.text {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: NSPoint(x: symbolX + symbol.size.width + 4,
                                        y: (rect.height - string.size().height) / 2))
            }
            return true
        }
    }

    static func clipEntries() -> [ClipEntry] {
        let now = Date()
        return [
            ClipEntry(kind: .text, text: "https://github.com/marvika/barnowl", date: now.addingTimeInterval(-20),
                      sourceApp: "Safari"),
            ClipEntry(kind: .text, text: "Let's move the weekly sync to Thursday at 10:00.", date: now.addingTimeInterval(-160),
                      sourceApp: "Mail"),
            ClipEntry(kind: .text, text: "git log --oneline --graph --decorate", date: now.addingTimeInterval(-600),
                      sourceApp: "Terminal", isPinned: true),
            ClipEntry(kind: .files, files: [URL(fileURLWithPath: "/tmp/Barn Owl Demo/Project Brief.pdf")],
                      date: now.addingTimeInterval(-1800), sourceApp: "Finder"),
            ClipEntry(kind: .text, text: "Barn Owl keeps your menu bar tidy and your Mac awake.",
                      date: now.addingTimeInterval(-3600), sourceApp: "Notes"),
        ]
    }

    /// Files for the demo shelf; `Scripts/demo.sh` creates them.
    static let shelfFiles = ["Project Brief.pdf", "Roadmap.key", "Screenshot.png"]
        .map { URL(fileURLWithPath: "/tmp/Barn Owl Demo/\($0)") }
}

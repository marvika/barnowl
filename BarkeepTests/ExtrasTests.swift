import Foundation
import Testing
@testable import Barkeep

struct GroupCompatibilityTests {
    @Test func groupsSavedBeforeCustomIconsStillLoad() throws {
        let old = #"[{"id":"92F94C27-5CC7-4492-B028-40FFB4505AF7","name":"Work","symbol":"briefcase.fill","memberKeys":["com.zscaler.zscaler/Item-0"]}]"#
        let groups = try JSONDecoder().decode([MenuBarGroup].self, from: Data(old.utf8))
        #expect(groups.first?.name == "Work")
        #expect(groups.first?.label == nil)
        #expect(groups.first?.opensDirectly == false)
    }

    @Test func customIconsRoundTrip() throws {
        let icon = MenuBarGroup(name: "Zscaler", symbol: "star.fill", memberKeys: ["z"], label: "VPN", opensDirectly: true)
        let decoded = try JSONDecoder().decode(MenuBarGroup.self, from: JSONEncoder().encode(icon))
        #expect(decoded == icon)
    }
}

struct MenuBarStyleTests {
    @Test func tintIsOffByDefault() {
        #expect(!MenuBarStyle().isEnabled)
    }

    @Test func styleRoundTrips() throws {
        var style = MenuBarStyle()
        style.isEnabled = true
        style.shape = .split
        style.tint = StoredColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let decoded = try JSONDecoder().decode(MenuBarStyle.self, from: JSONEncoder().encode(style))
        #expect(decoded == style)
    }
}

@MainActor
struct ClipEntryTests {
    @Test func previewsAndSymbols() {
        let link = ClipEntry(kind: .text, text: "  https://example.com \n")
        #expect(link.preview == "https://example.com")
        #expect(ClipEntry(kind: .text, text: "https://x").symbol == "link")
        let files = ClipEntry(kind: .files, files: [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.png")])
        #expect(files.preview == "a.pdf, b.png")
    }

    @Test func imagesAreNeverWrittenToDisk() throws {
        // `image` isn't in the coding keys, so a saved entry has no picture data.
        let entry = ClipEntry(kind: .image, image: Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(ClipEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded.image == nil)
    }

    @Test func passwordManagerCopiesAreSkipped() {
        #expect(ClipboardHistory.privateTypes.contains("org.nspasteboard.ConcealedType"))
        #expect(ClipboardHistory.privateApps.contains("com.1password.1password"))
    }
}

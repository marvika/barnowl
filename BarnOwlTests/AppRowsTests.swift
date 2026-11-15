import AppKit
import ApplicationServices
import Testing
@testable import BarnOwl

/// macOS 27's layout: a table of apps rather than of icons.
struct AppRowsTests {
    @Test func anAppTakesItsMostVisibleIconsRow() {
        // Keys from different times: with and without window names.
        let rows = AppRows(itemRows: [
            "com.microsoft.OneDrive/Item-0": .alwaysHidden,
            "com.microsoft.OneDrive/item": .hidden,
            "com.cyberark.CyberArkEPM/Item-0": .alwaysHidden,
            "com.example.shown/item": .visible,
            "com.example.shown/Item-0": .hidden,
        ])
        #expect(rows.rows == [
            "com.microsoft.OneDrive": .hidden,
            "com.cyberark.CyberArkEPM": .alwaysHidden,
            "com.example.shown": .visible,
        ])
    }

    @Test func groupedIconsAreLeftToTheirGroup() {
        let rows = AppRows(itemRows: ["com.example.vpn/item": .group(UUID()), "com.example.other/item": .hidden])
        #expect(rows.rows == ["com.example.other": .hidden])
    }

    @Test func theAppIsTheKeyUpToTheFirstSlash() {
        #expect(AppRows.app(ofKey: "com.example.app/Item-0") == "com.example.app")
        // Titles can hold slashes of their own.
        #expect(AppRows.app(ofKey: "com.microsoft.Outlook/10m: Stand-up / planning") == "com.microsoft.Outlook")
        #expect(AppRows.app(ofKey: "com.example.app") == "com.example.app")
    }

    @Test func anUnlistedAppGoesWhereNewIconsGo() {
        let rows = AppRows(rows: ["com.example.known": .visible])
        #expect(rows.section(of: "com.example.new", newIcons: .hidden, alwaysHiddenEnabled: true) == .hidden)
        #expect(rows.section(of: "com.example.new", newIcons: .visible, alwaysHiddenEnabled: true) == .visible)
        #expect(rows.section(of: "com.example.known", newIcons: .hidden, alwaysHiddenEnabled: true) == .visible)
    }

    @Test func withoutTheAlwaysHiddenRowItsAppsAreJustHidden() {
        let rows = AppRows(rows: ["com.example.deep": .alwaysHidden])
        #expect(rows.section(of: "com.example.deep", newIcons: .hidden, alwaysHiddenEnabled: true) == .alwaysHidden)
        #expect(rows.section(of: "com.example.deep", newIcons: .hidden, alwaysHiddenEnabled: false) == .hidden)
    }

    private let table = AppRows(rows: [
        "com.example.shown": .visible, "com.example.hidden": .hidden, "com.example.deep": .alwaysHidden,
    ])

    private func allowed(_ showing: Set<MenuBarSection>, running: Set<String> = [], grouped: Set<String> = [],
                         newIcons: NewIconPlacement = .hidden, alwaysHidden: Bool = true) -> Set<String>? {
        table.allowed(showing: showing, running: running, grouped: grouped, newIcons: newIcons,
                      alwaysHiddenEnabled: alwaysHidden)
    }

    @Test func collapsedLetsOnlyTheMenuBarRowThrough() {
        #expect(allowed([.visible]) == ["com.example.shown"])
    }

    @Test func expandedAddsTheHiddenRow() {
        #expect(allowed([.visible, .hidden]) == ["com.example.shown", "com.example.hidden"])
    }

    @Test func nothingToHideMeansNoRestriction() {
        #expect(allowed([.visible, .hidden, .alwaysHidden]) == nil)
        // The always-hidden row is off: expanding shows everything.
        #expect(allowed([.visible, .hidden], alwaysHidden: false) == nil)
    }

    @Test func aRunningAppNotInTheTableFollowsNewIcons() {
        #expect(allowed([.visible], running: ["com.example.new"]) == ["com.example.shown"])
        #expect(allowed([.visible], running: ["com.example.new"], newIcons: .visible)
            == ["com.example.shown", "com.example.new"])
    }

    @Test func groupedAppsOnlyComeOutWhenEverythingShows() {
        #expect(allowed([.visible, .hidden], grouped: ["com.example.hidden"]) == ["com.example.shown"])
        // Even an app the table has in the menu bar row.
        #expect(allowed([.visible], grouped: ["com.example.shown"]) == [])
        // And even with every row showing, a restriction stays to keep them back.
        #expect(allowed([.visible, .hidden, .alwaysHidden], grouped: ["com.example.vpn"])
            == ["com.example.shown", "com.example.hidden", "com.example.deep"])
    }

    @Test func savesAndLoads() {
        let saved = table.storage
        #expect(saved == ["com.example.shown": "visible", "com.example.hidden": "hidden",
                          "com.example.deep": "alwaysHidden"])
        #expect(AppRows(storage: saved) == table)
        // Anything unreadable is dropped rather than guessed at.
        #expect(AppRows(storage: ["com.example.odd": "sideways"]).rows.isEmpty)
    }

    @Test func eachDisplayProfileHasItsOwnTable() {
        #expect(DisplayProfile.single.appRowsKey == "appRows")
        #expect(DisplayProfile.desk.appRowsKey == "appRows.desk")
    }
}

/// macOS 27: icons without windows.
struct AgentBarItemTests {
    private func entry(_ bundle: String?, app: String, title: String?, x: CGFloat, agentName: String? = nil)
        -> AXMenuBarEntry {
        AXMenuBarEntry(pid: 1, bundleIdentifier: bundle, appName: app, title: title,
                       frame: CGRect(x: x, y: 4.5, width: 30, height: 24),
                       element: AXElement(raw: AXUIElementCreateSystemWide()), agentName: agentName)
    }

    @Test func itemsGetAnIDFromTheirKey() {
        let items = ItemScanner.itemsWithoutWindows([
            entry("com.example.one", app: "One", title: nil, x: 100),
            entry("com.example.two", app: "Two", title: "Two — syncing", x: 140),
        ])
        #expect(Set(items.map(\.key)) == ["com.example.one/item", "com.example.two/item"])
        #expect(items.allSatisfy { $0.windowID == ItemKey.stableID(for: $0.key) })
        #expect(Set(items.map(\.windowID)).count == 2)
    }

    @Test func theIDStaysTheSameAndClearOfRealWindows() {
        #expect(ItemKey.stableID(for: "com.example.one/item") == ItemKey.stableID(for: "com.example.one/item"))
        #expect(ItemKey.stableID(for: "com.example.one/item") != ItemKey.stableID(for: "com.example.two/item"))
        #expect(ItemKey.stableID(for: "") >= 0x8000_0000)
    }

    @Test func macOSOwnIconsAreNamedAndStayPut() throws {
        let items = ItemScanner.itemsWithoutWindows([
            entry(MenuBarPlatform.agentBundle, app: "MenuBarAgent", title: "Wi‑Fi, Personal Hotspot", x: 200,
                  agentName: "wifi"),
            entry(MenuBarPlatform.agentBundle, app: "MenuBarAgent", title: "Battery", x: 240, agentName: "battery"),
        ])
        let wifi = try #require(items.first { $0.key == "com.apple.MenuBarAgent/wifi" })
        #expect(wifi.name == "Wi‑Fi")
        #expect(wifi.detail == "Personal Hotspot")
        #expect(wifi.isSystem)
        #expect(wifi.alwaysShows)
        #expect(!wifi.isMovable)
        #expect(items.contains { $0.key == "com.apple.MenuBarAgent/battery" })
    }

    @Test func otherAppsIconsCanChangeRows() throws {
        let item = try #require(ItemScanner.itemsWithoutWindows([
            entry("com.example.one", app: "One", title: nil, x: 100),
        ]).first)
        #expect(item.isMovable)
        #expect(!item.alwaysShows)
    }

    @Test func onlyMenuExtrasCountAsMacOSIcons() {
        #expect(AccessibilityInventory.agentName(fromIdentifier: "com.apple.menuextra.sound") == "sound")
        #expect(AccessibilityInventory.agentName(fromIdentifier: "com.apple.menuextra.now-playing") == "now-playing")
        #expect(AccessibilityInventory.agentName(fromIdentifier: "com.apple.menuextra.") == nil)
        #expect(AccessibilityInventory.agentName(fromIdentifier: "Show Hidden Menu Bar Items") == nil)
    }

    @Test func anIconIsInViewWhenItsOwnAppHasOneThere() {
        let icons = [
            AgentBar.Icon(pid: 10, frame: CGRect(x: 1476, y: 4.5, width: 38, height: 24)),
            // One of macOS's own, listed by the view that holds it.
            AgentBar.Icon(pid: 1, frame: CGRect(x: 1447, y: 0, width: 22, height: 33)),
        ]
        #expect(AgentBar.isShowing(pid: 10, frame: CGRect(x: 1476, y: 4.5, width: 38, height: 24), among: icons))
        #expect(AgentBar.isShowing(pid: 1, frame: CGRect(x: 1447, y: 5.5, width: 22, height: 22), among: icons))
        // A hidden icon still reports where it last was, and another app's
        // icon may have taken that place since.
        #expect(!AgentBar.isShowing(pid: 20, frame: CGRect(x: 1444, y: 4.5, width: 34, height: 24), among: icons))
        #expect(!AgentBar.isShowing(pid: 20, frame: CGRect(x: 1476, y: 4.5, width: 38, height: 24), among: icons))
        #expect(!AgentBar.isShowing(pid: 10, frame: CGRect(x: 1476, y: 4.5, width: 38, height: 24), among: []))
    }

    @Test func iconsUnderTheOverflowButtonAreNotInView() {
        // Measured on macOS 27.0: the button, and two icons macOS tucked under it.
        let button = [CGRect(x: 1042, y: 1, width: 17.5, height: 30)]
        #expect(AgentBar.isTuckedAway(CGRect(x: 982, y: 0, width: 77, height: 33), under: button))
        #expect(AgentBar.isTuckedAway(CGRect(x: 1019, y: 0, width: 40, height: 33), under: button))
        // The first icon right of the button shows.
        #expect(!AgentBar.isTuckedAway(CGRect(x: 1067, y: 0, width: 32, height: 33), under: button))
        #expect(!AgentBar.isTuckedAway(CGRect(x: 982, y: 0, width: 77, height: 33), under: []))
    }

    @Test func anIconTakesMoreRoomThanItsWidth() throws {
        let items = ItemScanner.itemsWithoutWindows([
            entry("com.example.small", app: "Small", title: nil, x: 100),
            entry(MenuBarPlatform.agentBundle, app: "MenuBarAgent", title: "Battery", x: 240, agentName: "battery"),
        ])
        let small = try #require(items.first { $0.bundleIdentifier == "com.example.small" })
        let battery = try #require(items.first { $0.bundleIdentifier == MenuBarPlatform.agentBundle })
        // Both are 30 points wide here.
        #expect(AppModel.slotWidth(of: small) == 30)
        #expect(AppModel.slotWidth(of: battery) == 46)
    }

    @Test func aGroupHoldsTheAppsOfItsIcons() {
        let group = MenuBarGroup(name: "Work", symbol: "briefcase.fill",
                                 memberKeys: ["com.example.vpn/Item-0", "com.example.vpn/item", "com.example.chat/item"])
        #expect(group.memberApps == ["com.example.vpn", "com.example.chat"])
    }
}

import AppKit
import Testing
@testable import BarnOwl

struct ItemMatcherTests {
    private struct Entry { let name: String; let frame: CGRect }

    private func window(_ id: CGWindowID, x: CGFloat, width: CGFloat = 30) -> StatusWindow {
        StatusWindow(windowID: id, frame: CGRect(x: x, y: 0, width: width, height: 33))
    }

    private func entry(_ name: String, x: CGFloat, width: CGFloat = 30) -> Entry {
        Entry(name: name, frame: CGRect(x: x, y: 4.5, width: width, height: 24))
    }

    @Test func matchesByHorizontalCentre() {
        let pairs = ItemMatcher.match(windows: [window(1, x: 100), window(2, x: 140)],
                                      entries: [entry("b", x: 141), entry("a", x: 100)], frame: \.frame)
        #expect(pairs.map { "\($0.0.windowID)=\($0.1.name)" } == ["1=a", "2=b"])
    }

    @Test func dropsWindowsWithoutAnEntry() {
        // Stale windows of apps that quit have no Accessibility entry.
        let pairs = ItemMatcher.match(windows: [window(1, x: 100), window(2, x: -900)],
                                      entries: [entry("a", x: 100)], frame: \.frame)
        #expect(pairs.map(\.0.windowID) == [1])
    }

    @Test func usesEachEntryOnce() {
        let pairs = ItemMatcher.match(windows: [window(1, x: 100), window(2, x: 101)],
                                      entries: [entry("a", x: 100)], frame: \.frame)
        #expect(pairs.count == 1)
    }

    @Test func rejectsEntriesTooFarAway() {
        let pairs = ItemMatcher.match(windows: [window(1, x: 100)], entries: [entry("a", x: 110)], frame: \.frame)
        #expect(pairs.isEmpty)
    }

    @Test func matchesOffScreenHiddenItems() {
        let pairs = ItemMatcher.match(windows: [window(1, x: -563, width: 31)],
                                      entries: [entry("hidden", x: -563, width: 31)], frame: \.frame)
        #expect(pairs.count == 1)
    }
}

struct SectionClassifierTests {
    @Test func classifiesAgainstDividers() {
        #expect(SectionClassifier.section(midX: 1600, separatorMinX: 1500, alwaysHiddenMinX: 1000) == .visible)
        #expect(SectionClassifier.section(midX: 1200, separatorMinX: 1500, alwaysHiddenMinX: 1000) == .hidden)
        #expect(SectionClassifier.section(midX: 900, separatorMinX: 1500, alwaysHiddenMinX: 1000) == .alwaysHidden)
        #expect(SectionClassifier.section(midX: 900, separatorMinX: 1500, alwaysHiddenMinX: nil) == .hidden)
    }

    @Test func collapsedSeparatorReachesOffScreen() {
        // Collapsed, the divider spans from far off screen up to the arrow.
        #expect(SectionClassifier.section(midX: -548, separatorMinX: -418, alwaysHiddenMinX: nil) == .hidden)
    }
}

struct NotchGeometryTests {
    // A 16-inch MacBook Pro: 1728 pt wide, notch between 771 and 956.
    private let notch = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                      leftArea: CGRect(x: 0, y: 1085, width: 771, height: 32),
                                      rightArea: CGRect(x: 956, y: 1085, width: 772, height: 32))

    @Test func readsTheNotchFromTheAuxiliaryAreas() {
        #expect(notch == NotchGeometry(minX: 771, maxX: 956))
    }

    @Test func noNotchWithoutAuxiliaryAreas() {
        #expect(NotchGeometry(screenFrame: .zero, leftArea: nil, rightArea: nil) == nil)
    }

    @Test func coversItemsMostlyUnderTheNotch() throws {
        let notch = try #require(notch)
        #expect(notch.covers(CGRect(x: 800, y: 0, width: 30, height: 24)))
        #expect(notch.covers(CGRect(x: 940, y: 0, width: 30, height: 24)))  // 16 of 30 pt under
        #expect(!notch.covers(CGRect(x: 950, y: 0, width: 30, height: 24)))  // 6 of 30 pt under
        #expect(!notch.covers(CGRect(x: 1000, y: 0, width: 30, height: 24)))
    }
}

struct HiddenIconsDisplayTests {
    @Test func automaticUsesTheBarOnlyWhenIconsWouldNotFit() {
        #expect(!HiddenIconsDisplay.usesBar(.automatic, visibleWidth: 300, hiddenWidth: 200, availableWidth: 772))
        #expect(HiddenIconsDisplay.usesBar(.automatic, visibleWidth: 300, hiddenWidth: 600, availableWidth: 772))
    }

    @Test func explicitSettingsWin() {
        #expect(HiddenIconsDisplay.usesBar(.perch, visibleWidth: 0, hiddenWidth: 0, availableWidth: 772))
        #expect(!HiddenIconsDisplay.usesBar(.menuBar, visibleWidth: 900, hiddenWidth: 900, availableWidth: 772))
    }
}

@MainActor
struct ItemSearchTests {
    private func item(_ name: String, title: String? = nil, x: CGFloat, bundle: String? = nil) -> MenuBarItem {
        MenuBarItem(windowID: CGWindowID(x + 1000), frame: CGRect(x: x, y: 0, width: 30, height: 24), pid: 1,
                    bundleIdentifier: bundle ?? "com.example.\(name.lowercased())", appName: name, title: title,
                    element: AXElement(raw: AXUIElementCreateSystemWide()))
    }

    @Test func doesNotMatchBundleIDs() {
        let items = [item("Docker Desktop", x: 10, bundle: "com.electron.dockerdesktop")]
        #expect(ItemSearch.filter(items, query: "on").isEmpty)
    }

    @Test func systemItemsGoByTheirTitle() {
        let wifi = item("Control Center", title: "Wi‑Fi, connected, 3 bars", x: 10, bundle: "com.apple.controlcenter")
        #expect(wifi.name == "Wi‑Fi")
        #expect(wifi.detail == "connected, 3 bars")
        #expect(ItemSearch.filter([wifi], query: "wi").count == 1)
        let oneDrive = item("OneDrive", title: "OneDrive — Contoso", x: 20)
        #expect(oneDrive.name == "OneDrive")
        #expect(oneDrive.displayName == "OneDrive — Contoso")
    }

    @Test func matchesEveryWordAcrossNameAndTitle() {
        let items = [item("OneDrive", title: "Backed up and synced", x: 10), item("Zscaler", x: 20)]
        #expect(ItemSearch.filter(items, query: "one synced").map(\.appName) == ["OneDrive"])
        #expect(ItemSearch.filter(items, query: "ZSC").map(\.appName) == ["Zscaler"])
        #expect(ItemSearch.filter(items, query: "").count == 2)
    }

    @Test func appNamePrefixMatchesRankFirst() {
        let items = [item("Docker", title: "Claude helper", x: 10), item("Claude", x: 20)]
        #expect(ItemSearch.filter(items, query: "cla").map(\.appName) == ["Claude", "Docker"])
    }
}

struct MoveDestinationTests {
    private let frames: [CGWindowID: CGRect] = [
        1: CGRect(x: 100, y: 0, width: 30, height: 33),
        2: CGRect(x: 130, y: 0, width: 30, height: 33),
        3: CGRect(x: 160, y: 0, width: 30, height: 33),
    ]

    @Test func leftOfIsSatisfiedOnlyWhenAdjacent() {
        #expect(MoveDestination.leftOf(2).isSatisfied(itemID: 1, frames: frames))
        #expect(!MoveDestination.leftOf(3).isSatisfied(itemID: 1, frames: frames))  // 2 is in between
        #expect(!MoveDestination.leftOf(1).isSatisfied(itemID: 3, frames: frames))  // wrong side
    }

    @Test func rightOfIsSatisfiedOnlyWhenAdjacent() {
        #expect(MoveDestination.rightOf(2).isSatisfied(itemID: 3, frames: frames))
        #expect(!MoveDestination.rightOf(1).isSatisfied(itemID: 3, frames: frames))
    }

    @Test func dropPointsLandInsideTheTargetEdge() {
        let target = CGRect(x: -449, y: 0, width: 1944, height: 33)
        #expect(MoveDestination.leftOf(9).dropPoint(targetFrame: target) == CGPoint(x: -448, y: 16.5))
        #expect(MoveDestination.rightOf(9).dropPoint(targetFrame: target) == CGPoint(x: 1494, y: 16.5))
    }
}

@MainActor
struct ItemKeyTests {
    private func item(_ bundle: String, window: String?, title: String? = nil, x: CGFloat) -> MenuBarItem {
        MenuBarItem(windowID: CGWindowID(x + 5000), frame: CGRect(x: x, y: 0, width: 30, height: 24), pid: 1,
                    bundleIdentifier: bundle, appName: bundle, title: title,
                    element: AXElement(raw: AXUIElementCreateSystemWide()), windowName: window)
    }

    @Test func keysUseBundleAndWindowNameAndNumberRepeats() {
        let keyed = ItemKey.assign([item("a", window: "Item-0", x: 1), item("a", window: "Item-0", x: 2),
                                    item("b", window: nil, title: "Status", x: 3)])
        #expect(keyed.map(\.key) == ["a/Item-0", "a/Item-0#2", "b/item"])
    }

    /// Without Screen Recording there's no window name. An icon whose title
    /// changes with its state must keep its key, or it reads as a new icon
    /// and gets moved.
    @Test func keysWithoutWindowNamesSurviveStatusChanges() {
        let before = ItemKey.assign([
            item("com.apple.controlcenter", window: nil, title: "Wi-Fi, connected", x: 1),
            item("com.apple.controlcenter", window: nil, title: "Battery, 80 percent", x: 2),
            item("com.microsoft.OneDrive", window: nil, title: "OneDrive · Backed up", x: 3),
        ])
        let after = ItemKey.assign([
            item("com.apple.controlcenter", window: nil, title: "Wi-Fi, not connected", x: 1),
            item("com.apple.controlcenter", window: nil, title: "Battery, 79 percent", x: 2),
            item("com.microsoft.OneDrive", window: nil, title: "OneDrive · Syncing 3 files", x: 3),
        ])
        #expect(before.map(\.key) == after.map(\.key))
        #expect(before.map(\.key) == ["com.apple.controlcenter/Wi-Fi", "com.apple.controlcenter/Battery",
                                      "com.microsoft.OneDrive/item"])
    }

    @Test func clockAndControlCenterCantMove() {
        #expect(!item("com.apple.controlcenter", window: "Clock", x: 1).isMovable)
        #expect(!item("com.apple.controlcenter", window: "BentoBox-0", x: 1).isMovable)
        #expect(item("com.apple.controlcenter", window: "WiFi", x: 1).isMovable)
        #expect(item("com.example", window: "Item-0", x: 1).isMovable)
    }
}

@MainActor
struct GroupStoreTests {
    @Test func addingMovesAnItemBetweenGroups() {
        let defaults = UserDefaults(suiteName: "BarnOwlTests-\(UUID().uuidString)")!
        let store = GroupStore(defaults: defaults)
        let work = store.create(name: "Work", symbol: "briefcase.fill")
        let dev = store.create(name: "Dev", symbol: "hammer.fill")
        store.add("zscaler", to: work.id)
        store.add("docker", to: work.id)
        store.add("claude", to: work.id, before: "docker")
        #expect(store.groups[0].memberKeys == ["zscaler", "claude", "docker"])
        store.add("docker", to: dev.id)
        #expect(store.group(containing: "docker")?.id == dev.id)
        #expect(store.groups[0].memberKeys == ["zscaler", "claude"])
        store.removeFromGroups("zscaler")
        #expect(store.allMemberKeys == ["claude", "docker"])
        #expect(GroupStore(defaults: defaults).groups.count == 2)  // saved
    }
}

struct LayoutKeeperTests {
    private typealias Item = (key: String, windowID: CGWindowID, row: LayoutRow, movable: Bool)
    private let work = UUID()

    private func run(_ items: [Item], remembered: [String: LayoutRow] = [:], last: [String: CGWindowID] = [:],
                     baseline: Bool = true, newIcons: NewIconPlacement = .hidden,
                     groups: [String: UUID] = [:]) -> (moves: [LayoutKeeper.Decision], remembered: [String: LayoutRow]) {
        LayoutKeeper.reconcile(items: items, groupOf: { groups[$0] }, remembered: remembered, lastWindowIDs: last,
                               hasBaseline: baseline, newIcons: newIcons)
    }

    @Test func firstScanOnlyRecords() {
        let result = run([("a", 1, .visible, true), ("b", 2, .hidden, true)], baseline: false)
        #expect(result.moves.isEmpty)
        #expect(result.remembered == ["a": .visible, "b": .hidden])
    }

    @Test func relaunchedIconGoesBackToItsRow() {
        // Same key, new window, wrong row: the app re-added it.
        let result = run([("a", 7, .visible, true)], remembered: ["a": .hidden], last: ["a": 1])
        #expect(result.moves == [.init(key: "a", row: .hidden)])
    }

    @Test func userDragIsRespected() {
        // Same window, different row: the user moved it with ⌘-drag.
        let result = run([("a", 1, .visible, true)], remembered: ["a": .hidden], last: ["a": 1])
        #expect(result.moves.isEmpty)
        #expect(result.remembered["a"] == .visible)
    }

    @Test func newIconsFollowThePreference() {
        #expect(run([("new", 9, .visible, true)]).moves == [.init(key: "new", row: .hidden)])
        #expect(run([("new", 9, .visible, true)], newIcons: .visible).moves.isEmpty)
    }

    @Test func groupMembersStayAlwaysHidden() {
        let result = run([("z", 3, .visible, true)], groups: ["z": work])
        #expect(result.moves == [.init(key: "z", row: .group(work))])
        #expect(run([("z", 3, .alwaysHidden, true)], groups: ["z": work]).moves.isEmpty)
    }

    @Test func immovableIconsAreLeftAlone() {
        #expect(run([("clock", 5, .visible, false)]).moves.isEmpty)
    }

    @Test func rowsRoundTripThroughStorage() {
        for row in [LayoutRow.visible, .hidden, .alwaysHidden, .group(work)] {
            #expect(LayoutRow(storageValue: row.storageValue) == row)
        }
    }
}

/// NSTrackingArea calls its owner by AppKit's selector names. A Swift method
/// named mouseMoved(with:) on a class that isn't an NSResponder gets the
/// selector mouseMovedWith:, and AppKit then throws on every pointer move.
@MainActor
struct TrackingSelectorTests {
    @Test(arguments: ["mouseMoved:", "mouseEntered:", "mouseExited:"])
    func theOwlAnswersTrackingAreaCalls(selector: String) {
        #expect(QuickPanelController.instancesRespond(to: NSSelectorFromString(selector)))
    }
}

struct OpenMenuTests {
    private func window(pid: pid_t, layer: Int, y: CGFloat, width: CGFloat = 240) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowBounds as String: ["X": CGFloat(800), "Y": y, "Width": width, "Height": CGFloat(300)]]
    }

    private let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

    @Test func theMenuBarItselfIsNoMenu() {
        // Window Server's "Menubar" is always on screen at the top: counting it
        // kept hidden icons showing for good.
        let menuBar = window(pid: 418, layer: Int(CGWindowLevelForKey(.mainMenuWindow)), y: 0, width: 1728)
        #expect(!ItemOpener.isMenu(menuBar, ownedBy: [418, 42], screenTops: [0]))
        #expect(!ItemOpener.isMenu(menuBar, ownedBy: [42], screenTops: [0]))
    }

    @Test func aHiddenIconsMenuUnderTheBarCounts() {
        #expect(ItemOpener.isMenu(window(pid: 42, layer: menuLevel, y: 33), ownedBy: [42], screenTops: [0]))
        // On a second display above the main one.
        #expect(ItemOpener.isMenu(window(pid: 42, layer: menuLevel, y: -1047), ownedBy: [42], screenTops: [0, -1080]))
    }

    @Test func otherAppsAndOtherPlacesDontCount() {
        #expect(!ItemOpener.isMenu(window(pid: 7, layer: menuLevel, y: 33), ownedBy: [42], screenTops: [0]))
        #expect(!ItemOpener.isMenu(window(pid: 42, layer: menuLevel, y: 400), ownedBy: [42], screenTops: [0]))
        #expect(!ItemOpener.isMenu(window(pid: 42, layer: 0, y: 33), ownedBy: [42], screenTops: [0]))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        #expect(!ItemOpener.isMenu(window(pid: 42, layer: statusLevel, y: 0), ownedBy: [42], screenTops: [0]))
    }
}

@MainActor
struct PresenterFallbackTests {
    private func item(_ bundle: String, title: String? = nil, section: MenuBarSection = .visible) -> MenuBarItem {
        var item = MenuBarItem(windowID: 1, frame: CGRect(x: 0, y: 0, width: 30, height: 24), pid: 1,
                               bundleIdentifier: bundle, appName: "App", title: title,
                               element: AXElement(raw: AXUIElementCreateSystemWide()))
        item.section = section
        return item
    }

    @Test func movesOtherAppsVisibleIcons() {
        #expect(PresenterMode.hidesForPresenting(item("com.microsoft.teams2")))
        #expect(!PresenterMode.hidesForPresenting(item("com.microsoft.teams2", section: .hidden)))
    }

    @Test func leavesMacOSItemsAlone() {
        #expect(!PresenterMode.hidesForPresenting(item("com.apple.controlcenter", title: "Battery, 80 percent")))
        #expect(!PresenterMode.hidesForPresenting(item("com.apple.controlcenter", title: "Wi‑Fi, connected")))
        #expect(!PresenterMode.hidesForPresenting(item("com.apple.Spotlight")))
    }
}

@MainActor
struct AlwaysShownTests {
    private func item(title: String?, windowName: String? = nil,
                      bundle: String = "com.apple.controlcenter") -> MenuBarItem {
        MenuBarItem(windowID: 1, frame: CGRect(x: 0, y: 0, width: 30, height: 24), pid: 1,
                    bundleIdentifier: bundle, appName: "Control Center", title: title,
                    element: AXElement(raw: AXUIElementCreateSystemWide()), windowName: windowName)
    }

    @Test func batteryAlwaysShowsAndIsNeverMovedByBarnOwl() {
        for battery in [item(title: "Battery, 80 percent"), item(title: nil, windowName: "Battery")] {
            #expect(battery.alwaysShows)
            #expect(!battery.isMovable)
            #expect(!PresenterMode.hidesForPresenting(battery))
        }
    }

    @Test func otherIconsDont() {
        let wifi = item(title: "Wi‑Fi, connected", windowName: "WiFi")
        #expect(!wifi.alwaysShows)
        #expect(wifi.isMovable)
        #expect(!item(title: "Battery", bundle: "com.example.batterybar").alwaysShows)
    }
}

/// Where the presenting curtain may land.
struct PresenterCurtainTests {
    private let arrow = CGRect(x: 1488, y: 0, width: 27, height: 33)
    private let owl = CGRect(x: 1440, y: 0, width: 48, height: 33)

    @Test func besideTheOwlLeavesItsMenuInReach() {
        let curtain = CGRect(x: -2560, y: 0, width: 4000, height: 33)
        #expect(StatusItems.isBeside(owl, arrow))
        #expect(StatusItems.curtainLanded(curtain, arrow: arrow, owl: owl))
    }

    @Test func besideTheOwlButWithAnotherIconBetweenDoesntCount() {
        // Landed one icon further left: that icon would show on the shared screen.
        let curtain = CGRect(x: -2590, y: 0, width: 4000, height: 33)
        #expect(!StatusItems.curtainLanded(curtain, arrow: arrow, owl: owl))
        // The owl moved away from the arrow meanwhile.
        let movedOwl = owl.offsetBy(dx: -30, dy: 0)
        let besideMovedOwl = CGRect(x: movedOwl.minX - 4000, y: 0, width: 4000, height: 33)
        #expect(!StatusItems.curtainLanded(besideMovedOwl, arrow: arrow, owl: movedOwl))
    }

    @Test func besideTheArrowItOnlyNeedsToBeLeftOfIt() {
        #expect(StatusItems.curtainLanded(CGRect(x: -2512, y: 0, width: 4000, height: 33), arrow: arrow, owl: nil))
        #expect(!StatusItems.curtainLanded(CGRect(x: -2400, y: 0, width: 4000, height: 33), arrow: arrow, owl: nil))
    }
}

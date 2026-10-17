import AppKit
import Testing
@testable import Barkeep

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
        #expect(HiddenIconsDisplay.usesBar(.barkeepBar, visibleWidth: 0, hiddenWidth: 0, availableWidth: 772))
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

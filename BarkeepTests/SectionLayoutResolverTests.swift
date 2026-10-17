import CoreGraphics
import Testing
@testable import Barkeep

struct SectionLayoutResolverTests {
    private func item(_ bundle: String?, x: CGFloat) -> InventoryItem {
        InventoryItem(bundleIdentifier: bundle, frame: CGRect(x: x, y: 0, width: 30, height: 24))
    }

    @Test func assignsItemsBySidesOfTheDividers() {
        let layout = SectionLayoutResolver.resolve(
            items: [item("always", x: 100), item("hidden", x: 300), item("visible", x: 600)],
            separatorFrame: CGRect(x: 500, y: 0, width: 14, height: 24),
            alwaysHiddenFrame: CGRect(x: 200, y: 0, width: 14, height: 24),
            excluding: nil)
        #expect(layout.bundles(in: [.alwaysHidden]) == ["always"])
        #expect(layout.bundles(in: [.hidden]) == ["hidden"])
        #expect(layout.bundles(in: [.visible]) == ["visible"])
    }

    @Test func appWithItemsInSeveralSectionsGetsTheMostVisibleOne() {
        let layout = SectionLayoutResolver.resolve(
            items: [item("multi", x: 300), item("multi", x: 600)],
            separatorFrame: CGRect(x: 500, y: 0, width: 14, height: 24),
            alwaysHiddenFrame: nil,
            excluding: nil)
        #expect(layout.sectionByBundle["multi"] == .visible)
    }

    @Test func skipsOwnBundleAndItemsWithoutBundle() {
        let layout = SectionLayoutResolver.resolve(
            items: [item("me", x: 300), item(nil, x: 300), item("other", x: 300)],
            separatorFrame: CGRect(x: 500, y: 0, width: 14, height: 24),
            alwaysHiddenFrame: nil,
            excluding: "me")
        #expect(layout.sectionByBundle == ["other": .hidden])
    }

    @Test func withoutAlwaysHiddenDividerEverythingLeftIsHidden() {
        let layout = SectionLayoutResolver.resolve(
            items: [item("far", x: 10)],
            separatorFrame: CGRect(x: 500, y: 0, width: 14, height: 24),
            alwaysHiddenFrame: nil,
            excluding: nil)
        #expect(layout.sectionByBundle["far"] == .hidden)
    }
}

import Foundation
import Testing
@testable import BarnOwl

@MainActor
struct OpenPanelTests {
    final class Owner {
        var closes = 0
    }

    @Test func openingOnePanelClosesTheOther() {
        let panels = OpenPanel()
        let perch = Owner(), quick = Owner()
        panels.opening(perch) { perch.closes += 1 }
        panels.opening(quick) { quick.closes += 1 }
        #expect(perch.closes == 1)
        #expect(quick.closes == 0)
    }

    @Test func reopeningTheSamePanelLeavesItOpen() {
        let panels = OpenPanel()
        let search = Owner()
        panels.opening(search) { search.closes += 1 }
        panels.opening(search) { search.closes += 1 }
        #expect(search.closes == 0)
    }

    @Test func aClosedPanelIsntClosedAgain() {
        let panels = OpenPanel()
        let perch = Owner(), clipboard = Owner()
        panels.opening(perch) { perch.closes += 1 }
        panels.closed(perch)
        panels.opening(clipboard) { clipboard.closes += 1 }
        #expect(perch.closes == 0)
    }

    @Test func settingsClosesWhateverIsOpen() {
        let panels = OpenPanel()
        let quick = Owner()
        panels.opening(quick) { quick.closes += 1 }
        panels.closeAll()
        panels.closeAll()
        #expect(quick.closes == 1)
    }
}

struct PresenterDesktopIconsTests {
    @Test func hidesShowingIconsWhenPresentingStarts() {
        #expect(PresenterMode.switchesDesktopIcons(presenting: true, enabled: true, hidden: false, hidThem: false))
        #expect(!PresenterMode.switchesDesktopIcons(presenting: true, enabled: true, hidden: true, hidThem: false))
        #expect(!PresenterMode.switchesDesktopIcons(presenting: true, enabled: false, hidden: false, hidThem: false))
    }

    @Test func showsThemAgainOnlyIfStillHidden() {
        #expect(PresenterMode.switchesDesktopIcons(presenting: false, enabled: true, hidden: true, hidThem: true))
        // Shown again by hand mid-presentation: leave them showing.
        #expect(!PresenterMode.switchesDesktopIcons(presenting: false, enabled: true, hidden: false, hidThem: true))
        // Hidden before presenting started: not Barn Owl's to show.
        #expect(!PresenterMode.switchesDesktopIcons(presenting: false, enabled: true, hidden: true, hidThem: false))
    }
}

struct KeepAwakeConditionTests {
    @Test func batteryIsTooLowOnlyOnBatteryBelowTheLimit() {
        #expect(KeepAwakeController.batteryTooLow(threshold: 10, onAC: false, percent: 8))
        #expect(!KeepAwakeController.batteryTooLow(threshold: 10, onAC: true, percent: 8))
        #expect(!KeepAwakeController.batteryTooLow(threshold: 10, onAC: false, percent: 10))
        #expect(!KeepAwakeController.batteryTooLow(threshold: 0, onAC: false, percent: 2))
        #expect(!KeepAwakeController.batteryTooLow(threshold: 10, onAC: false, percent: nil))
    }

    @Test func displayMaySleepOnlyIfEverythingAllowsIt() {
        let lenient = KeepAwakeRule(conditions: [.downloading], allowDisplaySleep: true)
        let strict = KeepAwakeRule(conditions: [.downloading], allowDisplaySleep: false)
        #expect(KeepAwakeController.displayMaySleep(session: .indefinite, sessionAllows: true, rule: nil,
                                                    presenting: false))
        #expect(!KeepAwakeController.displayMaySleep(session: .indefinite, sessionAllows: false, rule: nil,
                                                     presenting: false))
        #expect(KeepAwakeController.displayMaySleep(session: nil, sessionAllows: false, rule: lenient,
                                                    presenting: false))
        #expect(!KeepAwakeController.displayMaySleep(session: .indefinite, sessionAllows: true, rule: strict,
                                                     presenting: false))
        #expect(!KeepAwakeController.displayMaySleep(session: .indefinite, sessionAllows: true, rule: nil,
                                                     presenting: true))
    }
}

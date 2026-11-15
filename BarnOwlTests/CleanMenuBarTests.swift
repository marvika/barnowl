import AppKit
import Testing
@testable import BarnOwl

/// macOS 27: a clean menu bar for a capture, by taking other apps' icons out
/// of view while it's made.
struct CleanMenuBarTests {
    // MARK: What the menu bar shows for now

    @Test func peeksAddUpAndEndOneByOne() {
        var temporary = TemporaryVisibility()
        temporary.peek(["com.example.opened"], for: "open")
        temporary.peek(["com.example.changed", "com.example.other"], for: "changed")
        #expect(temporary.revealed(opening: "open") == ["com.example.opened", "com.example.changed", "com.example.other"])
        temporary.peek([], for: "changed")
        #expect(temporary.revealed(opening: "open") == ["com.example.opened"])
        temporary.peek([], for: "open")
        #expect(temporary.revealed(opening: "open").isEmpty)
        #expect(!temporary.isClean)
    }

    @Test func aCaptureKeepsChangedIconsOutButNotOneYouOpen() {
        var temporary = TemporaryVisibility()
        temporary.peek(["com.example.changed"], for: "changed")
        temporary.peek(["com.example.pictured"], for: "pictures")
        temporary.holdClean(for: "recording")
        #expect(temporary.isClean)
        #expect(temporary.revealed(opening: "open").isEmpty)
        // Opened from the Perch while recording: its menu is what you're after.
        temporary.peek(["com.example.opened"], for: "open")
        #expect(temporary.revealed(opening: "open") == ["com.example.opened"])
    }

    @Test func whenTheCaptureEndsThePeeksAreAsTheyWere() {
        var temporary = TemporaryVisibility()
        temporary.peek(["com.example.changed"], for: "changed")
        temporary.holdClean(for: "picture")
        temporary.endClean(for: "picture")
        #expect(!temporary.isClean)
        #expect(temporary.revealed(opening: "open") == ["com.example.changed"])
    }

    @Test func aPictureDuringARecordingDoesntEndTheRecordingsHold() {
        var temporary = TemporaryVisibility()
        temporary.holdClean(for: "recording")
        temporary.holdClean(for: "picture")
        temporary.endClean(for: "picture")
        #expect(temporary.isClean)
        // Ending something that never held changes nothing.
        temporary.endClean(for: "never")
        #expect(temporary.isClean)
        temporary.endClean(for: "recording")
        #expect(!temporary.isClean)
    }

    // MARK: Which apps macOS may show

    private let own = "io.github.marvika.BarnOwl"

    @Test func aCleanBarLetsOnlyBarnOwlAndWhatYouOpenThrough() {
        let rows: Set<String> = ["com.example.shown"]
        #expect(NativeVisibilityEngine.appsToShow(own: own, onlyOwn: true, revealed: [], rows: rows) == [own])
        #expect(NativeVisibilityEngine.appsToShow(own: own, onlyOwn: true, revealed: ["com.example.opened"], rows: rows)
                == ["com.example.opened", own])
        // Even when the rows hide nothing: every icon showing is still too many.
        #expect(NativeVisibilityEngine.appsToShow(own: own, onlyOwn: true, revealed: [], rows: nil) == [own])
    }

    @Test func otherwiseTheRowsDecide() {
        #expect(NativeVisibilityEngine.appsToShow(own: own, onlyOwn: false, revealed: [], rows: nil) == nil)
        #expect(NativeVisibilityEngine.appsToShow(own: own, onlyOwn: false, revealed: ["com.example.peeked"],
                                                  rows: ["com.example.shown"])
                == ["com.example.peeked", "com.example.shown", own])
        // With every row showing, a peek has nothing to add.
        #expect(NativeVisibilityEngine.appsToShow(own: own, onlyOwn: false, revealed: ["com.example.peeked"], rows: nil) == nil)
    }

    // MARK: Whether there's anything to hide

    private func icon(_ pid: pid_t, x: CGFloat = 1200, width: CGFloat = 30) -> AgentBar.Icon {
        AgentBar.Icon(pid: pid, frame: CGRect(x: x, y: 4, width: width, height: 24))
    }

    @Test func onlyOtherAppsIconsNeedHiding() {
        // 100 is Barn Owl, 200 MenuBarAgent, which owns the icons macOS always shows.
        let icons = [icon(100), icon(200), icon(200), icon(301), icon(302), icon(301)]
        #expect(CleanMenuBar.others(among: icons, own: 100, agent: 200) == [301, 302])
        #expect(CleanMenuBar.others(among: [icon(100), icon(200)], own: 100, agent: 200).isEmpty)
        // An icon whose app couldn't be read isn't one to wait for.
        #expect(CleanMenuBar.others(among: [icon(0)], own: 100, agent: 200).isEmpty)
        #expect(CleanMenuBar.others(among: [], own: 100, agent: nil).isEmpty)
    }

    @Test func anAreaBelowTheMenuBarHasNoIconsInIt() {
        // AppKit coordinates: the bar is the top 33 points of a 1728 × 1117 screen.
        let bar = CGRect(x: 0, y: 1084, width: 1728, height: 33)
        #expect(!CleanMenuBar.reaches(CGRect(x: 200, y: 300, width: 800, height: 600), menuBars: [bar]))
        #expect(CleanMenuBar.reaches(CGRect(x: 200, y: 300, width: 800, height: 800), menuBars: [bar]))
        #expect(CleanMenuBar.reaches(CGRect(x: 0, y: 0, width: 1728, height: 1117), menuBars: [bar]))
        // Up to the bar's lower edge, and no further.
        #expect(!CleanMenuBar.reaches(CGRect(x: 0, y: 984, width: 400, height: 100), menuBars: [bar]))
        // On a second display, with a bar of its own.
        let second = CGRect(x: 1728, y: 1415, width: 2560, height: 25)
        #expect(CleanMenuBar.reaches(CGRect(x: 2000, y: 1300, width: 300, height: 140), menuBars: [bar, second]))
    }

    // MARK: A menu hanging from an icon

    private let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

    private func window(pid: pid_t, layer: Int, x: CGFloat, y: CGFloat, width: CGFloat = 240) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: ["X": x, "Y": y, "Width": width, "Height": CGFloat(300)]]
    }

    @Test func aMenuUnderItsIconCounts() {
        let icons = [icon(301, x: 1200)]
        #expect(CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: menuLevel, x: 1190, y: 33), icons: icons, screenTops: [0]))
        // A popover a little below the bar, centred on the icon.
        #expect(CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: 101, x: 1050, y: 38, width: 330), icons: icons,
                                             screenTops: [0]))
        // On a display above the main one.
        let above = [AgentBar.Icon(pid: 301, frame: CGRect(x: 1200, y: -1076, width: 30, height: 24))]
        #expect(CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: menuLevel, x: 1190, y: -1055), icons: above,
                                             screenTops: [0, -1080]))
    }

    @Test func otherWindowsAtTheTopOfTheScreenDont() {
        let icons = [icon(301, x: 1200)]
        // A notch app's panel starts at the very top.
        #expect(!CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: menuLevel, x: 700, y: 0, width: 600), icons: icons,
                                              screenTops: [0]))
        // Further along the bar than the icon.
        #expect(!CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: menuLevel, x: 400, y: 33), icons: icons, screenTops: [0]))
        // Another app's, an ordinary window, one lower down, and the menu bar itself.
        #expect(!CleanMenuBar.hangsFromAnIcon(window(pid: 7, layer: menuLevel, x: 1190, y: 33), icons: icons, screenTops: [0]))
        #expect(!CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: 0, x: 1190, y: 33), icons: icons, screenTops: [0]))
        #expect(!CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: menuLevel, x: 1190, y: 400), icons: icons, screenTops: [0]))
        let barLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        #expect(!CleanMenuBar.hangsFromAnIcon(window(pid: 301, layer: barLevel, x: 0, y: 0, width: 1728), icons: icons,
                                              screenTops: [0]))
    }

    // MARK: When the bar has come to rest

    private let full = Data([1, 1, 1, 1]), fading = Data([1, 1, 0, 0]), clean = Data([1, 0, 0, 0])

    /// What each look in turn says: how the bar looks, and when.
    private func atRest(before: Data?, _ looks: [(picture: Data?, time: TimeInterval)]) -> [Bool] {
        var settling = BarSettling(before: before)
        return looks.map { settling.looksAtRest($0.picture, at: $0.time) }
    }

    @Test func thePictureHasToStopChanging() {
        // Fading, then the same three times running.
        #expect(atRest(before: full, [(fading, 0.1), (clean, 0.2), (clean, 0.3), (clean, 0.4), (clean, 0.5)])
                == [false, false, false, true, true])
    }

    @Test func looksBeforeTheFadeStartsArentRest() {
        #expect(atRest(before: full, [(full, 0.1), (full, 0.2), (full, 0.3), (fading, 0.4), (clean, 0.5), (clean, 0.6),
                                      (clean, 0.7)])
                == [false, false, false, false, false, false, true])
    }

    @Test func aPauseBetweenTwoIconsGoingIsntRest() {
        // The same twice, then on it goes.
        #expect(atRest(before: full, [(fading, 0.1), (fading, 0.2), (clean, 0.3), (clean, 0.4), (clean, 0.5)])
                == [false, false, false, false, true])
    }

    @Test func anIconWithNothingDrawnInItOnlyTakesTheFadesTime() {
        // Hiding it changes nothing in the picture.
        #expect(atRest(before: full, [(full, 0.1), (full, 0.2), (full, 0.3), (full, 0.5), (full, 0.11 + BarSettling.fadeTime)])
                == [false, false, false, false, true])
    }

    @Test func withoutPicturesItWaitsOutTheFade() {
        #expect(atRest(before: nil, [(nil, 0.1), (nil, 0.5), (nil, 0.11 + BarSettling.fadeTime)]) == [false, false, true])
        // With pictures but none from before, the same three times isn't trusted sooner either.
        #expect(atRest(before: nil, [(clean, 0.1), (clean, 0.2), (clean, 0.3), (clean, 0.11 + BarSettling.fadeTime)])
                == [false, false, false, true])
        // A picture that couldn't be taken starts the count again.
        #expect(atRest(before: full, [(clean, 0.1), (clean, 0.2), (nil, 0.3), (clean, 0.4), (clean, 0.5), (clean, 0.6)])
                == [false, false, false, false, false, true])
    }
}

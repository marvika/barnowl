import ApplicationServices
import Foundation
import Testing
@testable import BarnOwl

struct ItemSignatureTests {
    private let base = ItemSignature(text: "OneDrive|Backed up and synced", width: 31, windowID: 10)

    @Test func noticesTextWidthAndWindowChanges() {
        #expect(!base.differs(from: base))
        var syncing = base
        syncing.text = "OneDrive|Syncing 3 files"
        #expect(base.differs(from: syncing))
        var wider = base
        wider.width = 45
        #expect(base.differs(from: wider))
        var readded = base
        readded.windowID = 11
        #expect(base.differs(from: readded))
    }

    @Test func ignoresSubpointWidthJitter() {
        var jitter = base
        jitter.width = 31.5
        #expect(!base.differs(from: jitter))
    }
}

struct PictureSignatureTests {
    @Test func smallDifferencesAreIgnored() {
        let a = PictureSignature(pixels: Array(repeating: 100, count: 144))
        let b = PictureSignature(pixels: Array(repeating: 104, count: 144))
        #expect(!a.differs(from: b))
    }

    @Test func aChangedIconIsNoticed() {
        let connected = PictureSignature(pixels: Array(repeating: 200, count: 144))
        var dropped = Array(repeating: UInt8(200), count: 144)
        for index in 0..<72 { dropped[index] = 40 }
        #expect(connected.differs(from: PictureSignature(pixels: dropped)))
    }
}

struct PresenterDetectionTests {
    @Test func readsControlCenterDescriptions() {
        #expect(PresenterMode.describesSharing("Control Center, Screen Recording is in use"))
        #expect(PresenterMode.describesSharing("Control Center, Screen Sharing"))
        #expect(!PresenterMode.describesSharing("Control Center"))
        #expect(!PresenterMode.describesSharing("Control Center, Microphone is in use"))
    }
}

struct DisplayProfileTests {
    @Test func picksTheProfileFromTheDisplays() {
        #expect(DisplayProfile.current(enabled: false, hasExternalDisplay: true) == .single)
        #expect(DisplayProfile.current(enabled: true, hasExternalDisplay: false) == .laptop)
        #expect(DisplayProfile.current(enabled: true, hasExternalDisplay: true) == .desk)
    }

    @Test func profilesSaveSeparately() {
        #expect(DisplayProfile.single.storageKey == "itemRows")
        #expect(DisplayProfile.laptop.storageKey != DisplayProfile.desk.storageKey)
    }
}

@MainActor
struct AudioVideoIndicatorTests {
    @Test func theRecordingIndicatorIsNeverMoved() {
        let indicator = MenuBarItem(windowID: 1, frame: .zero, pid: 1, bundleIdentifier: "com.apple.controlcenter",
                                    appName: "Control Center", title: "Audio and Video Controls",
                                    element: AXElement(raw: AXUIElementCreateSystemWide()),
                                    windowName: "AudioVideoModule")
        #expect(!indicator.isMovable)
    }
}

struct CorrectionLimiterTests {
    @Test func stopsAfterRepeatedCorrections() {
        var limiter = CorrectionLimiter(limit: 2, window: 120)
        let start = Date(timeIntervalSince1970: 0)
        let first = limiter.allow("zscaler", now: start)
        let second = limiter.allow("zscaler", now: start.addingTimeInterval(10))
        let third = limiter.allow("zscaler", now: start.addingTimeInterval(20))
        let other = limiter.allow("onedrive", now: start.addingTimeInterval(20))
        #expect(first && second && !third && other)
    }

    @Test func allowsSpacedOutCorrections() {
        var limiter = CorrectionLimiter(limit: 2, window: 120)
        let start = Date(timeIntervalSince1970: 0)
        _ = limiter.allow("a", now: start)
        let later = limiter.allow("a", now: start.addingTimeInterval(200))
        #expect(later)
    }

    /// An icon macOS keeps putting back isn't dragged again every couple of
    /// minutes: it's left alone until the user moves it themselves.
    @Test func givesUpForGoodUntilAManualMove() {
        var limiter = CorrectionLimiter(limit: 2, window: 120)
        let start = Date(timeIntervalSince1970: 0)
        _ = limiter.allow("display", now: start)
        _ = limiter.allow("display", now: start)
        let refused = limiter.allow("display", now: start.addingTimeInterval(5))
        let muchLater = limiter.allow("display", now: start.addingTimeInterval(3600))
        limiter.reset("display")
        let afterReset = limiter.allow("display", now: start.addingTimeInterval(3601))
        #expect(!refused && !muchLater && afterReset)
    }
}

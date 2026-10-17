import ApplicationServices
import Foundation
import Testing
@testable import Barkeep

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

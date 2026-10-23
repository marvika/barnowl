import KeyboardShortcuts
import Testing
@testable import BarnOwl

/// How scrolling capture is started, and what it may start over.
struct ScrollingCaptureTests {
    @Test func oneScrollingCaptureAtATimeAndNeverOverARecording() {
        let idle = CaptureActivity()
        #expect(idle.canScroll)
        #expect(idle.canSelect() && idle.canSelect(records: true) && idle.canSelect(scrolls: true))

        let scrolling = CaptureActivity(scrolling: true)
        #expect(!scrolling.canScroll)
        // No frozen screen over it at all: it takes Return and Esc for itself.
        #expect(!scrolling.canSelect())
        #expect(!scrolling.canSelect(records: true))
        #expect(!scrolling.canSelect(scrolls: true))

        let recording = CaptureActivity(recording: true)
        #expect(!recording.canScroll)
        #expect(!recording.canSelect(records: true))
        #expect(!recording.canSelect(scrolls: true))
        // A picture can still be taken while you record.
        #expect(recording.canSelect())
    }

    @Test func returnDoesWhatTheOverlayWasStartedFor() {
        #expect(CaptureAction.onReturn() == .primary)
        #expect(CaptureAction.onReturn(scrolls: true) == .scroll)
        #expect(CaptureAction.onReturn(copiesText: true) == .copyText)
        #expect(CaptureAction.onReturn(recording: RecordingSetup()) == .record)
        #expect(CaptureAction.onReturn(recording: RecordingSetup(makesGIF: true)) == .recordGIF)
        #expect(CaptureAction.scroll.needsRoom)
    }

    @Test func hasItsOwnShortcut() throws {
        let scrolling = try #require(KeyboardShortcuts.Name.captureScrolling.defaultShortcut)
        #expect(scrolling == .init(.s, modifiers: [.control, .option, .command]))
        let others: [KeyboardShortcuts.Name] = [.toggleHiddenItems, .clipboard, .searchItems, .captureArea, .captureScreen,
                                                .captureSameArea, .captureText, .editLastCapture, .recordScreen]
        #expect(!others.compactMap(\.defaultShortcut).contains(scrolling))
    }

    @Test func isACommand() {
        let command = AppCommand.captureScrolling
        #expect(command.title == "Scrolling capture")
        #expect(command.symbol == "rectangle.expand.vertical")
        #expect(command.keywords.contains("scrolling") && command.keywords.contains("scroll"))
        // "long screenshot", "page" find it too.
        #expect(command.keywords.contains("long") && command.keywords.contains("page"))
    }

    @Test func overlayHintsSayWhatToSelect() {
        #expect(CaptureMode.area.scrollHint.contains("scrolls"))
        #expect(CaptureMode.window.scrollHint.hasPrefix("Click a window"))
        #expect(CaptureMode.screen.scrollHint.hasPrefix("Click a screen"))
    }
}

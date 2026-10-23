import AppKit
import AVFoundation
import SwiftUI
import Testing
@testable import BarnOwl

/// What keeps a recording from being lost or leaking: the filter, the writer's finish, history
/// making room, takes left behind by a quit, and Esc.
@MainActor
struct RecordingSafetyTests {
    @Test func barnOwlIsLeftOutWholeUnlessOtherAppsAreToo() {
        #expect(ScreenRecorder.filterKind(for: CaptureOptions()) == .leavesOutBarnOwl)
        // Showing the pointer changes nothing about what's left out.
        #expect(ScreenRecorder.filterKind(for: CaptureOptions(showsPointer: true)) == .leavesOutBarnOwl)
        #expect(ScreenRecorder.filterKind(for: CaptureOptions(cleanMenuBar: true)) == .listsWindows)
        #expect(ScreenRecorder.filterKind(for: CaptureOptions(hidesDesktopIcons: true)) == .listsWindows)
        #expect(ScreenRecorder.filterKind(for: CaptureOptions(hiddenWindows: [42])) == .listsWindows)
    }

    @Test func finishingTwiceOrAfterCancellingStillAnswers() async throws {
        let url = RecordingWriterTests.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: RecordingWriterTests.settings())
        writer.appendVideo(RecordingWriterTests.frame(), at: RecordingWriterTests.time(1))
        _ = try await RecordingWriterTests.finish(writer, at: 2).get()
        // A second stop is told so, rather than left waiting for good.
        #expect(await RecordingWriterTests.finish(writer, at: 3).failure == .ended)

        let other = RecordingWriterTests.url()
        let cancelled = try RecordingWriter(url: other, settings: RecordingWriterTests.settings())
        cancelled.appendVideo(RecordingWriterTests.frame(), at: RecordingWriterTests.time(1))
        cancelled.cancel()
        #expect(await RecordingWriterTests.finish(cancelled, at: 2).failure == .ended)
        #expect(!FileManager.default.fileExists(atPath: other.path))
    }

    @Test func aMicThatChangesFormatIsReported() async throws {
        let url = RecordingWriterTests.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try RecordingWriter(url: url, settings: RecordingWriterTests.settings(system: true, microphone: true))
        for step in 0..<10 { writer.appendVideo(RecordingWriterTests.frame(), at: RecordingWriterTests.time(Double(step) / 10)) }
        writer.appendAudio(RecordingWriterTests.audio(at: 0, channels: 2), from: .system)
        writer.appendAudio(RecordingWriterTests.audio(at: 0, channels: 1), from: .microphone)
        writer.appendAudio(RecordingWriterTests.audio(at: 0.5, channels: 1, rate: 44_100), from: .microphone)
        let output = try await RecordingWriterTests.finish(writer, at: 1).get()
        #expect(output.cutShort == [.microphone])
    }

    @Test func makingRoomNeverTakesTheNewOneOrOneBeingEdited() throws {
        let root = try RecordingLibraryTests.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let edited = try RecordingLibraryTests.keep("video", daysAgo: 3, bytes: 4000, now: now, in: root)
        let older = try RecordingLibraryTests.keep("video", daysAgo: 2, bytes: 4000, now: now, in: root)
        let newest = try RecordingLibraryTests.keep("video", daysAgo: 0.5, bytes: 4000, now: now, in: root)
        // A recording recovered from a while back: older than the rest, and it pushes them past the limit.
        let movie = root.appending(path: "recovered.mov")
        try Data(count: 4000).write(to: movie)
        let entry = CaptureLibrary.Entry(id: UUID(), date: now.addingTimeInterval(-4 * 86_400), scale: 2, kind: "video",
                                         appName: nil, fileURL: nil, edited: false, duration: 12)
        // Over the limit: the oldest go, but not the one just kept nor the one open in the editor.
        try CaptureLibrary.storeMovie(movie, poster: RecordingLibraryTests.poster(), entry: entry, days: 30, bytes: 6_000,
                                      in: root, keeping: [edited])
        #expect(CaptureLibrary.movie(entry.id, in: root) != nil)
        #expect(CaptureLibrary.entry(edited, in: root) != nil)
        #expect(CaptureLibrary.entry(newest, in: root) != nil)
        #expect(CaptureLibrary.entry(older, in: root) == nil)
    }

    @Test func takesLeftBehindAreFoundAndSavedOnesLetGo() throws {
        let root = try RecordingLibraryTests.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileManager.default
        func take(_ names: [String]) throws -> URL {
            let folder = root.appending(path: UUID().uuidString)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in names { try Data([1]).write(to: folder.appending(path: name)) }
            return folder
        }
        let unsaved = try take(["Recording 1a2b3c4d.mov"])
        let saved = try take(["Recording 5e6f7a8b.mov", RecordingStore.savedMarker])
        // A drag's copy of a picture lives here too, and isn't a recording.
        let picture = try take(["Screenshot.png"])
        let found = RecordingStore.leftovers(in: root).map { $0.resolvingSymlinksInPath() }
        #expect(found == [unsaved.appending(path: "Recording 1a2b3c4d.mov").resolvingSymlinksInPath()])
        #expect(!manager.fileExists(atPath: saved.path))
        #expect(manager.fileExists(atPath: picture.path))
    }

    @Test func escStopsOnlyFromTheRecordingsOwnControls() {
        #expect(RecordingCoordinator.escStops(keyWindow: nil))
        let pill = RecordingPanel(rootView: EmptyView())
        #expect(RecordingCoordinator.escStops(keyWindow: pill))
        let settings = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        #expect(!RecordingCoordinator.escStops(keyWindow: settings))
    }
}

/// Auto-Scroll, when the stitcher loses its place.
struct AutoScrollPacerTests {
    @Test func stepsBackAndSlowsDownWhenItLosesThePage() {
        var pacer = AutoScrollPacer()
        #expect(pacer.after(grew: true, lost: false) == .down(AutoScrollPacer.firstShare))
        // Too far to follow: back up the step it just took, then smaller ones.
        #expect(pacer.after(grew: false, lost: true) == .back(AutoScrollPacer.firstShare))
        #expect(pacer.share == AutoScrollPacer.firstShare / 2)
        // Found its place again: carries on, slower.
        #expect(pacer.after(grew: true, lost: false) == .down(AutoScrollPacer.firstShare / 2))
    }

    @Test func handsBackToYouRatherThanCallingItTheEnd() {
        var pacer = AutoScrollPacer()
        #expect(pacer.after(grew: false, lost: true) == .back(0.6))
        #expect(pacer.after(grew: false, lost: true) == .back(0.3))
        #expect(pacer.after(grew: false, lost: true) == .tooFast)
    }

    @Test func twoStepsThatMoveNothingAreTheEnd() {
        var pacer = AutoScrollPacer()
        #expect(pacer.after(grew: false, lost: false) == .down(0.6))
        #expect(pacer.after(grew: false, lost: false) == .end)
        // A lost frame in between isn't a stall.
        var other = AutoScrollPacer()
        #expect(other.after(grew: false, lost: false) == .down(0.6))
        #expect(other.after(grew: false, lost: true) == .back(0.6))
        #expect(other.after(grew: false, lost: false) == .down(0.3))
        #expect(other.after(grew: false, lost: false) == .end)
        // Steps never get smaller than the smallest.
        var small = AutoScrollPacer()
        for _ in 0..<2 {
            _ = small.after(grew: false, lost: true)
            _ = small.after(grew: true, lost: false)
        }
        _ = small.after(grew: false, lost: true)
        #expect(small.share >= AutoScrollPacer.smallestShare)
    }
}

/// Text in a tall scrolling capture, read a strip at a time.
struct TallTextTests {
    @Test func stripsOverlapAndShareTheWholePictureOut() {
        #expect(SensitiveTextFinder.strips(height: 3_000) == [.init(rows: 0..<3_000, keeps: 0..<3_000)])
        let strips = SensitiveTextFinder.strips(height: 10_000)
        #expect(strips.count == 3)
        #expect(strips.allSatisfy { $0.rows.count <= 4_000 && $0.rows.contains($0.keeps.lowerBound) })
        // Every row is kept by exactly one strip.
        #expect(strips.first?.keeps.lowerBound == 0 && strips.last?.keeps.upperBound == 10_000)
        for (one, next) in zip(strips, strips.dropFirst()) {
            #expect(one.keeps.upperBound == next.keeps.lowerBound)
            #expect(one.rows.upperBound - next.rows.lowerBound == 300)
        }
    }

    @Test func aLineAcrossAStripsEdgeIsReadOnceWhereItIs() async throws {
        let width = 1_200, height = 9_000
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (top, string) in [(200, "Barn owls hunt by sound"), (3_980, "Across the strip edge here"),
                              (8_800, "The last line of the page")] {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 48),
                                                             .foregroundColor: NSColor.black]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            // The context's origin is its bottom left; `top` counts from the top.
            context.textPosition = CGPoint(x: 40, y: CGFloat(height - top) - 40)
            CTLineDraw(line, context)
        }
        let image = try #require(context.makeImage())
        let text = try await SensitiveTextFinder.scan(image, forReading: true)
        let edge = text.lines.filter { $0.text.contains("strip edge") }
        #expect(edge.count == 1)
        #expect(abs((edge.first?.rect.midY ?? 0) - 4_000) < 50)
        #expect(text.lines.contains { $0.text.contains("Barn owls") })
        #expect(text.lines.contains { $0.text.contains("last line") && $0.rect.minY > 8_700 })
    }
}

/// The video editor never hands out or writes over the movie it edits.
@MainActor
struct VideoEditorFileTests {
    private final class Host: VideoEditorHost {
        func videoEditor(_ editor: VideoEditor, copy file: URL) {}
        func videoEditor(_ editor: VideoEditor, save file: URL) async -> URL? { nil }
        func videoEditor(_ editor: VideoEditor, finish file: URL) {}
        func videoEditor(_ editor: VideoEditor, didExport file: URL) {}
        func videoEditor(_ editor: VideoEditor, editFrame image: CGImage, scale: CGFloat) {}
        func videoEditor(_ editor: VideoEditor, didChange edit: VideoEdit) {}
        func videoEditorDidClose(_ editor: VideoEditor, edited: Bool) {}
    }

    @Test func anUntouchedMovieIsACopyNamedAfterItsTitleWithItsSoundsMixed() async throws {
        let folder = TestMovie.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: "movie.mov")
        try TestMovie.make(at: movie, seconds: 1, audioTracks: ["Computer", "Mic"])
        let host = Host()
        let editor = try await VideoEditor.load(movie: movie, title: "Screen Recording 2026-10-23 at 14:32:07", host: host)
        let file = try #require(await editor.renderFile("Copying"))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(file != movie)
        #expect(file.lastPathComponent == "Screen Recording 2026-10-23 at 14.32.07.mov")
        #expect(file.path.hasPrefix(VideoEditor.temporaryFolder.path))
        #expect(try await AVURLAsset(url: file).loadTracks(withMediaType: .audio).count == 1)
        // Whatever happens to the file handed out, the movie stays.
        try FileManager.default.removeItem(at: file)
        #expect(FileManager.default.fileExists(atPath: movie.path))
        #expect(try await AVURLAsset(url: movie).loadTracks(withMediaType: .audio).count == 2)
    }

    @Test func oneSoundTrackIsCopiedAsItIs() async throws {
        let folder = TestMovie.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: "movie.mov")
        try TestMovie.make(at: movie, seconds: 1, audioTracks: ["Computer"])
        let host = Host()
        let editor = try await VideoEditor.load(movie: movie, title: "Clip", host: host)
        let file = try #require(await editor.renderFile("Copying"))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(file != movie)
        #expect(file.lastPathComponent == "Clip.mov")
        #expect(try Data(contentsOf: file) == Data(contentsOf: movie))
    }

    @Test func exportNeverWritesOverItsSourceAndReplacesOnlyWhenDone() async throws {
        let folder = TestMovie.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: "movie.mov")
        try TestMovie.make(at: movie, seconds: 1)
        let info = try await MovieInfo.load(movie)
        var edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size)
        edit.export.format = .mov
        let before = try Data(contentsOf: movie)
        // The movie itself, however it's spelled, is refused and left whole.
        let spelledOtherwise = folder.appending(path: "./MOVIE.mov")
        await #expect(throws: VideoEditError.self) { try await VideoExporter.export(info, edit: edit, to: movie) }
        await #expect(throws: VideoEditError.self) { try await VideoExporter.export(info, edit: edit, to: spelledOtherwise) }
        #expect(try Data(contentsOf: movie) == before)

        // Over a file that's there: replaced once the new one is whole, nothing left beside it.
        let out = folder.appending(path: "out.mov")
        try Data([9, 9, 9]).write(to: out)
        let result = try await VideoExporter.export(info, edit: edit, to: out)
        #expect(result.url == out)
        #expect(try Data(contentsOf: out) != Data([9, 9, 9]))
        #expect(try await AVURLAsset(url: out).load(.duration).seconds > 0.5)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["movie.mov", "out.mov"])
    }

    @Test func aCancelledExportLeavesWhatWasThere() async throws {
        let folder = TestMovie.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: "movie.mov")
        try TestMovie.make(at: movie, seconds: 2)
        let info = try await MovieInfo.load(movie)
        let edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size)
        let out = folder.appending(path: "out.mp4")
        try Data([7]).write(to: out)
        let task = Task { try await VideoExporter.export(info, edit: edit, to: out) }
        task.cancel()
        if case .failure = await task.result {
            #expect(try Data(contentsOf: out) == Data([7]))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["movie.mov", "out.mp4"])
    }
}

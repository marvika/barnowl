import Foundation
import Testing
@testable import BarnOwl

/// How Capture keeps and saves what the video editor makes.
struct VideoEditorWiringTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "video-wiring-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func savesOverTheSameKindOfFileOnly() {
        let movie = URL(fileURLWithPath: "/Movies/Screen Recording.mov")
        #expect(EditedVideo.overwrites(movie, with: URL(fileURLWithPath: "/tmp/Edited.MOV")) == movie)
        #expect(EditedVideo.overwrites(movie, with: URL(fileURLWithPath: "/tmp/Edited.mp4")) == nil)
        #expect(EditedVideo.overwrites(movie, with: URL(fileURLWithPath: "/tmp/Edited.gif")) == nil)
        #expect(EditedVideo.overwrites(nil, with: URL(fileURLWithPath: "/tmp/Edited.mov")) == nil)
    }

    @Test func placesACopyAndNeverTouchesTheSource() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "movie.mov")
        try Data([1, 2, 3]).write(to: source)
        let saved = root.appending(path: "Screen Recording.mov")

        // A new file.
        #expect(EditedVideo.place(source, at: saved))
        #expect(try Data(contentsOf: saved) == Data([1, 2, 3]))
        // Over one that's there.
        try Data([4, 5]).write(to: source)
        #expect(EditedVideo.place(source, at: saved))
        #expect(try Data(contentsOf: saved) == Data([4, 5]))
        #expect(try Data(contentsOf: source) == Data([4, 5]))
        // Onto itself: nothing to do, and nothing lost.
        #expect(EditedVideo.place(saved, at: saved))
        #expect(try Data(contentsOf: saved) == Data([4, 5]))
        // Nothing half-written left behind.
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(names == ["Screen Recording.mov", "movie.mov"])
    }

    @Test func aMissingSourceLeavesTheSavedFileAlone() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = root.appending(path: "Screen Recording.mov")
        try Data([7]).write(to: saved)
        #expect(!EditedVideo.place(root.appending(path: "gone.mov"), at: saved))
        #expect(try Data(contentsOf: saved) == Data([7]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Screen Recording.mov"])
    }

    @Test func keepsTheCutsWithTheRecording() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 40, height: 20))
        let entry = CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 2, kind: "video", appName: nil, fileURL: nil,
                                         edited: false, duration: 12)
        try CaptureLibrary.store(image, entry: entry, in: root)
        #expect(CaptureLibrary.videoEdit(entry.id, in: root) == nil)

        var edit = VideoEdit(sourceDuration: VideoEdit.ticks(seconds: 12), sourceSize: CGSize(width: 1920, height: 1080),
                             audioTracks: 2)
        edit.clips = [VideoEdit.Clip(start: VideoEdit.ticks(seconds: 2), duration: VideoEdit.ticks(seconds: 5))]
        try CaptureLibrary.storeDocument(try JSONEncoder().encode(edit), for: entry.id, in: root)
        #expect(CaptureLibrary.videoEdit(entry.id, in: root) == edit)
        #expect(CaptureLibrary.entry(entry.id, in: root)?.edited == true)
        #expect(CaptureLibrary.entry(entry.id, in: root)?.media == .video(duration: 12))
    }

    @Test func aRecordingSavedAsAGIFSaysSo() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 40, height: 20))
        let entry = CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 2, kind: "video", appName: nil, fileURL: nil,
                                         edited: false, duration: 12)
        try CaptureLibrary.store(image, entry: entry, in: root)
        CaptureLibrary.update(entry.id, in: root) { entry in
            entry.kind = CaptureMedia.gif(duration: 5).libraryKind ?? "video"
            entry.duration = 5
        }
        #expect(CaptureLibrary.entry(entry.id, in: root)?.media == .gif(duration: 5))
    }
}

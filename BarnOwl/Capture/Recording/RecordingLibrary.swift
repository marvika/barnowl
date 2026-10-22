import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// What a capture is: a picture, or a recording, handed over as a movie or a GIF.
enum CaptureMedia: Equatable, Sendable {
    case image
    case video(duration: TimeInterval)
    case gif(duration: TimeInterval)

    var isMovie: Bool { self != .image }
    var isGIF: Bool { if case .gif = self { return true } else { return false } }

    var duration: TimeInterval? {
        switch self {
        case .image: nil
        case .video(let duration), .gif(let duration): duration
        }
    }

    /// The library entry's `kind` for a recording.
    var libraryKind: String? {
        switch self {
        case .image: nil
        case .video: "video"
        case .gif: "gif"
        }
    }
}

extension CaptureLibrary.Entry {
    /// A recording's entry says so in its kind; anything else is a picture.
    var media: CaptureMedia {
        switch kind {
        case "video": .video(duration: duration ?? 0)
        case "gif": .gif(duration: duration ?? 0)
        default: .image
        }
    }
}

/// Recordings in the library: the movie with its separate sound tracks, for the video editor,
/// beside the first frame as its picture, so history shows it like any capture. Movies are
/// large, so they're kept for at most seven days and two gigabytes, oldest going first.
extension CaptureLibrary {
    static let movieName = "movie.mov"
    static let movieDays = 7
    static let movieBytes: Int64 = 2 << 30

    /// The kept movie, if there is one.
    static func movie(_ id: UUID, in root: URL = folder) -> URL? {
        let url = folder(for: id, in: root).appending(path: movieName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Keeps a recording: moves its movie in, with its first frame as the picture. Runs off
    /// the main thread. Nothing is kept while history is off.
    static func storeMovie(_ movie: URL, poster: CGImage, entry: Entry, days: Int = keepDays, in root: URL = folder) throws {
        guard root != folder || isOn else { return }
        let dir = folder(for: entry.id, in: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let kept = dir.appending(path: movieName)
        try? FileManager.default.removeItem(at: kept)
        try FileManager.default.moveItem(at: movie, to: kept)
        try store(poster, entry: entry, in: root)
        storeThumbnail(poster, for: entry.id, in: root)
        pruneMovies(days: days, in: root)
    }

    /// Lets go of recordings past seven days (or sooner, if captures are kept for less),
    /// and of the oldest once their movies take more than two gigabytes.
    static func pruneMovies(now: Date = Date(), days: Int = keepDays, bytes limit: Int64 = movieBytes,
                            in root: URL = folder) {
        let cutoff = now.addingTimeInterval(-Double(min(days, movieDays)) * 86_400)
        var total: Int64 = 0
        var removed = false
        let movies = entries(in: root).filter(\.media.isMovie)
        for (index, entry) in movies.enumerated() {
            total += movie(entry.id, in: root).flatMap(Self.size(of:)) ?? 0
            // The newest is always kept, however long it is.
            guard entry.date < cutoff || (index > 0 && total > limit) else { continue }
            try? FileManager.default.removeItem(at: folder(for: entry.id, in: root))
            removed = true
        }
        if removed { changed(nil) }
    }

    static func size(of file: URL) -> Int64? {
        var file = file
        file.removeAllCachedResourceValues()
        return (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) }
    }
}

/// Where recordings are saved and what they're called.
enum RecordingStore {
    /// The folder chosen for recordings, or the screenshot folder.
    static func folder(settings: RecordingSettings = .current) -> URL {
        let chosen = settings.folder
        if !chosen.isEmpty, FileManager.default.fileExists(atPath: chosen) { return URL(fileURLWithPath: chosen) }
        return CaptureStore.folder
    }

    /// "Screen Recording 2026-10-23 at 14.32.07", as macOS names its own, unless you've
    /// chosen a name of your own for captures.
    static func baseName(prefix: String, date: Date, appName: String?) -> String {
        let start = prefix == "Screenshot" || prefix.isEmpty ? "Screen Recording" : prefix
        return CaptureStore.baseName(prefix: start, date: date, appName: appName)
    }

    /// A free name in the recordings folder, reserved until `CaptureStore.release`.
    static func reserveURL(date: Date, appName: String?, fileExtension: String) -> URL {
        let app = Preferences.captureNameIncludesApp ? appName : nil
        return CaptureStore.freeURL(in: folder(), baseName: baseName(prefix: Preferences.captureNamePrefix, date: date, appName: app),
                                    fileExtension: fileExtension)
    }

    /// Where a take is written while it's recorded: a folder of its own among the temporary
    /// copies, and a new file for each attempt.
    static func masterURL(for id: UUID) -> URL {
        let folder = CaptureStore.temporaryFolder.appending(path: id.uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Recording \(UUID().uuidString.prefix(8)).mov")
    }

    /// Free space where recordings are written, in bytes.
    static func freeSpace() -> Int64? {
        let values = try? CaptureStore.temporaryFolder.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Enough room to start: two gigabytes. Recording stops below one.
    static let roomToStart: Int64 = 2 << 30
    static let roomToGoOn: Int64 = 1 << 30

    /// The first frame, for the card and history.
    static func poster(of movie: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.appliesPreferredTrackTransform = true
        // Plenty for the card and history; a 6K frame would hold 90 MB for nothing.
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        return try? await generator.image(at: .zero).image
    }

    /// Puts a recording's file on the clipboard; a GIF goes as the picture too, so chat apps
    /// show it moving.
    @MainActor
    static func copy(_ file: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        if file.pathExtension.lowercased() == "gif", let data = try? Data(contentsOf: file) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        }
        pasteboard.writeObjects([item])
    }
}

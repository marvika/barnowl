import AppKit
import ImageIO

/// Keeps every capture editable: the original pixels, the markup document and
/// a little about it, in Application Support/Barn Owl/Captures/<id>/. Saved
/// files are tagged with the id, so reopening one brings its marks back.
/// Kept for 30 days (at most 200 captures; recordings for 7 days and 2 GB). Originals are
/// never redacted here.
enum CaptureLibrary {
    struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let date: Date
        let scale: Double
        /// "selection", "window" or "display"; a recording's is "video" or "gif", as its file is now.
        var kind: String
        let appName: String?
        var fileURL: URL?
        var edited: Bool
        /// Windows inside the capture, in image pixels from the top left, for smart marks.
        var windows: [CGRect]?
        /// The words in it, as read on the Mac: for searching history and Copy Text.
        var text: String?
        /// The saved file's size and date when Barn Owl last wrote it, so a file changed or
        /// copied since is never taken for this capture's own.
        var fileStamp: FileStamp?
        /// Its words have been looked for, found or not, so one without any isn't read again.
        var textWasRead: Bool?
        /// A recording's length in seconds; its kind is "video" or "gif".
        var duration: Double?
    }

    struct FileStamp: Codable, Equatable, Sendable {
        let size: Int
        let modified: Date

        init?(of url: URL) {
            // Never what an earlier look at this URL cached: the file may have changed since.
            var url = url
            url.removeAllCachedResourceValues()
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
            self.size = size
            self.modified = modified
        }

        /// Dates are compared to the second: some volumes keep no more.
        func matches(_ other: FileStamp?) -> Bool {
            guard let other else { return false }
            return size == other.size && abs(modified.timeIntervalSince(other.modified)) < 1
        }
    }

    /// Whether `file` is this capture's own saved file, as Barn Owl last wrote it: tagged with
    /// its id, unchanged since, and not a copy of it while the original is still where it was.
    static func isOwn(_ file: URL, entry: Entry) -> Bool {
        guard id(of: file) == entry.id, let stamp = entry.fileStamp, stamp.matches(FileStamp(of: file)) else { return false }
        guard let saved = entry.fileURL, saved.standardizedFileURL != file.standardizedFileURL else { return true }
        // Moved is fine; a duplicate next to the original isn't the capture's file.
        return !FileManager.default.fileExists(atPath: saved.path)
    }

    static let attribute = "io.github.marvika.barnowl.capture"
    static var keepDays: Int { Preferences.captureKeepDays }
    static let keepCount = 200
    /// Whether captures are kept at all.
    static var isOn: Bool { keepDays > 0 }

    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Barn Owl/Captures")
    }

    static func folder(for id: UUID, in root: URL = folder) -> URL { root.appending(path: id.uuidString) }

    // MARK: Writing

    /// Stores a new capture's original and its entry. Runs off the main thread.
    /// `png` is the original already encoded at full size, if there is one.
    static func store(_ image: CGImage, png: Data? = nil, entry: Entry, in root: URL = folder) throws {
        guard root != folder || isOn else { return }
        let dir = folder(for: entry.id, in: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = try png ?? CaptureStore.encode(image, scale: entry.scale, as: .png, atOneX: false)
        try png.write(to: dir.appending(path: "original.png"), options: .atomic)
        try write(entry, in: root)
    }

    static func write(_ entry: Entry, in root: URL = folder) throws {
        let data = try JSONEncoder().encode(entry)
        try data.write(to: folder(for: entry.id, in: root).appending(path: "entry.json"), options: .atomic)
        changed(entry.id)
    }

    /// Posted on the main thread when a capture is kept, changes, gets a new thumbnail or is
    /// let go; `userInfo["id"]` is its id when it's about one. History keeps in step with it.
    static let didChange = Notification.Name("CaptureLibrary.didChange")

    static func changed(_ id: UUID?) {
        Task { @MainActor in
            NotificationCenter.default.post(name: didChange, object: nil, userInfo: id.map { ["id": $0] })
        }
    }

    /// The markup, as the editor's document encodes it.
    static func storeDocument(_ data: Data, for id: UUID, in root: URL = folder) throws {
        // Only for a capture that's kept: never a folder of marks without its picture.
        let dir = folder(for: id, in: root)
        guard FileManager.default.fileExists(atPath: dir.appending(path: "entry.json").path) else { return }
        try data.write(to: dir.appending(path: "document.json"), options: .atomic)
        if var entry = entry(id, in: root), !entry.edited {
            entry.edited = true
            try write(entry, in: root)
        }
    }

    /// Remembers where the flattened file went, and tags it with the capture's id.
    static func setFile(_ url: URL, for id: UUID, in root: URL = folder) {
        tag(url, id: id)
        guard var entry = entry(id, in: root) else { return }
        let stamp = FileStamp(of: url)
        guard entry.fileURL != url || entry.fileStamp != stamp else { return }
        entry.fileURL = url
        entry.fileStamp = stamp
        try? write(entry, in: root)
    }

    /// Changes a kept capture's entry, if it's kept.
    static func update(_ id: UUID, in root: URL = folder, _ change: (inout Entry) -> Void) {
        guard var entry = entry(id, in: root) else { return }
        let before = entry
        change(&entry)
        if entry != before { try? write(entry, in: root) }
    }

    /// A small picture of the capture as it looks now, marks included, for history.
    static func storeThumbnail(_ image: CGImage, for id: UUID, in root: URL = folder) {
        let dir = folder(for: id, in: root)
        guard FileManager.default.fileExists(atPath: dir.appending(path: "entry.json").path) else { return }
        let small = CaptureStore.thumbnail(image, width: thumbnailWidth)
        guard let png = try? CaptureStore.encode(small, scale: 1, as: .png, atOneX: false) else { return }
        try? png.write(to: dir.appending(path: "thumbnail.png"), options: .atomic)
        changed(id)
    }

    static let thumbnailWidth: CGFloat = 520

    static func tag(_ url: URL, id: UUID) {
        let value = Array(id.uuidString.utf8)
        _ = value.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, value.count, 0, 0) }
    }

    // MARK: Reading

    static func entry(_ id: UUID, in root: URL = folder) -> Entry? {
        guard let data = try? Data(contentsOf: folder(for: id, in: root).appending(path: "entry.json")) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    static func original(_ id: UUID, in root: URL = folder) -> CGImage? {
        let url = folder(for: id, in: root).appending(path: "original.png") as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Whether the marks were changed after the file was last written.
    static func documentIsNewer(than stamp: FileStamp?, for id: UUID, in root: URL = folder) -> Bool {
        guard let stamp else { return false }
        let url = folder(for: id, in: root).appending(path: "document.json")
        guard let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return false
        }
        return changed.timeIntervalSince(stamp.modified) > 1
    }

    /// The thumbnail, or failing that the original.
    static func thumbnail(_ id: UUID, in root: URL = folder) -> CGImage? {
        let url = folder(for: id, in: root).appending(path: "thumbnail.png") as CFURL
        if let source = CGImageSourceCreateWithURL(url, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        return original(id, in: root)
    }

    static func document(_ id: UUID, in root: URL = folder) -> Data? {
        try? Data(contentsOf: folder(for: id, in: root).appending(path: "document.json"))
    }

    /// The capture a saved file came from, if Barn Owl made it.
    static func id(of file: URL) -> UUID? {
        var buffer = [UInt8](repeating: 0, count: 64)
        let length = getxattr(file.path, attribute, &buffer, buffer.count, 0, 0)
        guard length > 0 else { return nil }
        return UUID(uuidString: String(decoding: buffer.prefix(length), as: UTF8.self))
    }

    /// Every entry, newest first.
    static func entries(in root: URL = folder) -> [Entry] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return ids.compactMap(UUID.init(uuidString:)).compactMap { entry($0, in: root) }.sorted { $0.date > $1.date }
    }

    static func latest(in root: URL = folder) -> Entry? { entries(in: root).first }

    // MARK: Tidying

    /// Lets go of captures older than the setting allows, and of any beyond 200, but never
    /// of those in `keeping` (open in the editor).
    static func prune(now: Date = Date(), days: Int = keepDays, in root: URL = folder, keeping: Set<UUID> = []) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var removed = false
        for (index, entry) in entries(in: root).enumerated() where entry.date < cutoff || index >= keepCount {
            guard !keeping.contains(entry.id) else { continue }
            try? FileManager.default.removeItem(at: folder(for: entry.id, in: root))
            removed = true
        }
        if removed { changed(nil) }
        pruneMovies(now: now, days: days, in: root, keeping: keeping)
    }

    /// Lets go of every kept capture now, those waiting for Undo and any half-written too,
    /// but never of those in `keeping` (open in the editor).
    static func clear(in root: URL = folder, keeping: Set<UUID> = []) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names {
            guard let id = UUID(uuidString: name), !keeping.contains(id) else { continue }
            try? FileManager.default.removeItem(at: root.appending(path: name))
        }
        forgetRemoved(in: root)
        changed(nil)
    }
}

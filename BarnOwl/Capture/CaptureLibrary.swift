import AppKit
import ImageIO

/// Keeps every capture editable: the original pixels, the markup document and
/// a little about it, in Application Support/Barn Owl/Captures/<id>/. Saved
/// files are tagged with the id, so reopening one brings its marks back.
/// Kept for 30 days (at most 200 captures). Originals are never redacted here.
enum CaptureLibrary {
    struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let date: Date
        let scale: Double
        let kind: String
        let appName: String?
        var fileURL: URL?
        var edited: Bool
    }

    static let attribute = "io.github.marvika.barnowl.capture"
    static let keepDays = 30
    static let keepCount = 200

    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Barn Owl/Captures")
    }

    static func folder(for id: UUID, in root: URL = folder) -> URL { root.appending(path: id.uuidString) }

    // MARK: Writing

    /// Stores a new capture's original and its entry. Runs off the main thread.
    static func store(_ image: CGImage, entry: Entry, in root: URL = folder) throws {
        let dir = folder(for: entry.id, in: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = try CaptureStore.encode(image, scale: entry.scale, as: .png, atOneX: false)
        try png.write(to: dir.appending(path: "original.png"), options: .atomic)
        try write(entry, in: root)
    }

    static func write(_ entry: Entry, in root: URL = folder) throws {
        let data = try JSONEncoder().encode(entry)
        try data.write(to: folder(for: entry.id, in: root).appending(path: "entry.json"), options: .atomic)
    }

    /// The markup, as the editor's document encodes it.
    static func storeDocument(_ data: Data, for id: UUID, in root: URL = folder) throws {
        let dir = folder(for: id, in: root)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try data.write(to: dir.appending(path: "document.json"), options: .atomic)
        if var entry = entry(id, in: root), !entry.edited {
            entry.edited = true
            try write(entry, in: root)
        }
    }

    /// Remembers where the flattened file went, and tags it with the capture's id.
    static func setFile(_ url: URL, for id: UUID, in root: URL = folder) {
        tag(url, id: id)
        guard var entry = entry(id, in: root), entry.fileURL != url else { return }
        entry.fileURL = url
        try? write(entry, in: root)
    }

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

    /// Lets go of captures older than 30 days, and of any beyond 200.
    static func prune(now: Date = Date(), in root: URL = folder) {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        for (index, entry) in entries(in: root).enumerated() where entry.date < cutoff || index >= keepCount {
            try? FileManager.default.removeItem(at: folder(for: entry.id, in: root))
        }
    }
}

import Foundation
import ImageIO

/// What Capture History shows: every kept capture under its day, found by the words in it,
/// the app it was taken in or the day. Nothing here touches a window, so it's tested alone.
enum CaptureHistory {
    /// A kept capture as history shows it, read off the main thread.
    struct Item: Equatable, Sendable, Identifiable {
        let entry: CaptureLibrary.Entry
        /// Its saved file is still where it was saved.
        let isSaved: Bool
        /// Everything search looks at, folded: its words, its app and its day.
        let searchKey: String

        var id: UUID { entry.id }
        var date: Date { entry.date }
        var isEdited: Bool { entry.edited }
        var savedFile: URL? { isSaved ? entry.fileURL : nil }
        /// The words in it, if any were read.
        var text: String? {
            guard let text = entry.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }
        /// Window captures carry their own clear shadow, so they're shown without a border.
        var isWindow: Bool { entry.kind == Capture.Kind.window.rawValue }
        /// The app it was taken in, or what was taken.
        var subtitle: String {
            if let app = entry.appName, !app.isEmpty { return app }
            switch Capture.Kind(rawValue: entry.kind) {
            case .window: return "Window"
            case .screen: return "Screen"
            default: return "Area"
            }
        }
    }

    /// One day's captures, newest first.
    struct Day<Element>: Identifiable {
        let start: Date
        let title: String
        var items: [Element]
        var id: Date { start }
    }

    // MARK: Days

    /// Names days the way history's headers do: Today, Yesterday, a weekday for the rest of the
    /// week, then the date. Made once per load, as date formatters aren't cheap.
    final class DayNamer {
        let calendar: Calendar
        private let today: Date
        private let weekday: DateFormatter
        private let date: DateFormatter
        private let dateWithYear: DateFormatter
        private let words: DateFormatter

        init(now: Date, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
            self.calendar = calendar
            today = calendar.startOfDay(for: now)
            func formatter(template: String) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.locale = locale
                formatter.setLocalizedDateFormatFromTemplate(template)
                return formatter
            }
            weekday = formatter(template: "EEEE")
            date = formatter(template: "EEEEdMMMM")
            dateWithYear = formatter(template: "EEEEdMMMMy")
            // Only for searching: every way you might type the day.
            words = DateFormatter()
            words.calendar = calendar
            words.timeZone = calendar.timeZone
            words.locale = locale
            words.dateFormat = "EEEE EEE d MMMM MMM yyyy"
        }

        func title(for day: Date) -> String {
            let start = calendar.startOfDay(for: day)
            let daysAgo = calendar.dateComponents([.day], from: start, to: today).day ?? 0
            switch daysAgo {
            case ...0: return "Today"
            case 1: return "Yesterday"
            case 2...6: return weekday.string(from: start)
            default:
                let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: today)
                return (sameYear ? date : dateWithYear).string(from: start)
            }
        }

        /// The day's title, its weekday, month and date: what a search for the day might say.
        func searchWords(for day: Date) -> String {
            title(for: day) + " " + words.string(from: day)
        }
    }

    /// Captures grouped under their days, newest day first, each newest first.
    static func days<Element>(_ items: [Element], date: (Element) -> Date, namer: DayNamer) -> [Day<Element>] {
        let sorted = items.sorted { date($0) > date($1) }
        var days: [Day<Element>] = []
        for item in sorted {
            let start = namer.calendar.startOfDay(for: date(item))
            if let last = days.last, last.start == start {
                days[days.count - 1].items.append(item)
            } else {
                days.append(Day(start: start, title: namer.title(for: start), items: [item]))
            }
        }
        return days
    }

    // MARK: Search

    /// Ignores case, accents and width, so "cafe" finds "Café".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func searchKey(for entry: CaptureLibrary.Entry, namer: DayNamer) -> String {
        let parts: [String] = [entry.text ?? "", entry.appName ?? "", namer.searchWords(for: entry.date)]
        return fold(parts.joined(separator: "\n"))
    }

    /// The words of a query, folded.
    static func terms(of query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every word of the query is somewhere in the capture: its text, its app or its day.
    static func matches(_ key: String, terms: [String]) -> Bool {
        terms.allSatisfy { key.contains($0) }
    }

    static func filter(_ items: [Item], query: String) -> [Item] {
        let terms = terms(of: query)
        guard !terms.isEmpty else { return items }
        return items.filter { matches($0.searchKey, terms: terms) }
    }

    // MARK: Loading

    /// Every kept capture, newest first. Reads files, so it runs off the main thread.
    static func load(in root: URL, now: Date, calendar: Calendar = .autoupdatingCurrent,
                     locale: Locale = .autoupdatingCurrent) -> [Item] {
        let namer = DayNamer(now: now, calendar: calendar, locale: locale)
        return CaptureLibrary.entries(in: root).map { entry in
            let saved = entry.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            return Item(entry: entry, isSaved: saved, searchKey: searchKey(for: entry, namer: namer))
        }
    }

    // MARK: Removing

    /// What to select once `removed` have gone: the next one after them, or else the one before.
    static func selection(afterRemoving removed: Set<UUID>, from order: [UUID]) -> UUID? {
        guard let last = order.lastIndex(where: { removed.contains($0) }) else { return nil }
        if let next = order[(last + 1)...].first(where: { !removed.contains($0) }) { return next }
        return order[..<last].last { !removed.contains($0) }
    }

    // MARK: The grid

    /// How many tiles fit across, and how wide each is, with at least `minimum` points each.
    static func tiles(across available: CGFloat, minimum: CGFloat, spacing: CGFloat) -> (columns: Int, width: CGFloat) {
        let columns = max(1, Int((available + spacing) / (minimum + spacing)))
        let gaps = spacing * CGFloat(columns - 1)
        let width = ((available - gaps) / CGFloat(columns)).rounded(.down)
        return (columns, max(width, 1))
    }
}

extension CaptureLibrary {
    /// Where captures removed from history wait for Undo, until history closes.
    static func removedFolder(in root: URL = folder) -> URL { root.appending(path: ".Removed") }

    /// Takes captures out of history; their saved files stay where they are. They wait in
    /// `removedFolder` so Undo can bring them back, until `forgetRemoved`. Returns those taken.
    @discardableResult
    static func remove(_ ids: [UUID], in root: URL = folder) -> [UUID] {
        let waiting = removedFolder(in: root)
        try? FileManager.default.createDirectory(at: waiting, withIntermediateDirectories: true)
        let moved = ids.filter { id in
            let target = waiting.appending(path: id.uuidString)
            try? FileManager.default.removeItem(at: target)
            return (try? FileManager.default.moveItem(at: folder(for: id, in: root), to: target)) != nil
        }
        if !moved.isEmpty { changed(nil) }
        return moved
    }

    /// Brings removed captures back, as Undo does. Returns those brought back.
    @discardableResult
    static func restore(_ ids: [UUID], in root: URL = folder) -> [UUID] {
        let waiting = removedFolder(in: root)
        let back = ids.filter { id in
            let home = folder(for: id, in: root)
            guard !FileManager.default.fileExists(atPath: home.path) else { return false }
            return (try? FileManager.default.moveItem(at: waiting.appending(path: id.uuidString), to: home)) != nil
        }
        if !back.isEmpty { changed(nil) }
        return back
    }

    /// Lets go of removed captures for good.
    static func forgetRemoved(in root: URL = folder) {
        try? FileManager.default.removeItem(at: removedFolder(in: root))
    }

    /// The capture as it looks now, at most `pixels` on its longer side: the thumbnail, or the
    /// original while there's none yet. Decoded here, off the main thread.
    static func smallPicture(_ id: UUID, pixels: Int, in root: URL = folder) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: pixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true]
        let dir = folder(for: id, in: root)
        for name in ["thumbnail.png", "original.png"] {
            guard let source = CGImageSourceCreateWithURL(dir.appending(path: name) as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            return image
        }
        return nil
    }
}

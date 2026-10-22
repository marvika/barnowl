import AppKit
import Foundation
import Testing
@testable import BarnOwl

/// Capture History: days, search, removing and the grid's arithmetic.
struct CaptureHistoryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_GB")

    /// Friday 23 October 2026, 15:00 in Oslo.
    private var now: Date { date(23, hour: 15) }

    private func date(_ day: Int, month: Int = 10, year: Int = 2026, hour: Int = 12, minute: Int = 0) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day,
                       hour: hour, minute: minute).date!
    }

    private var namer: CaptureHistory.DayNamer { CaptureHistory.DayNamer(now: now, calendar: calendar, locale: locale) }

    private func entry(_ date: Date, app: String? = nil, text: String? = nil, kind: String = "selection",
                       file: URL? = nil) -> CaptureLibrary.Entry {
        var entry = CaptureLibrary.Entry(id: UUID(), date: date, scale: 2, kind: kind, appName: app, fileURL: file,
                                         edited: false)
        entry.text = text
        return entry
    }

    private func item(_ entry: CaptureLibrary.Entry, saved: Bool = false) -> CaptureHistory.Item {
        CaptureHistory.Item(entry: entry, isSaved: saved, searchKey: CaptureHistory.searchKey(for: entry, namer: namer))
    }

    // MARK: Days

    @Test func namesDaysLikePhotos() {
        let namer = namer
        #expect(namer.title(for: date(23, hour: 0)) == "Today")
        #expect(namer.title(for: date(23, hour: 23, minute: 59)) == "Today")
        #expect(namer.title(for: date(22, hour: 23)) == "Yesterday")
        #expect(namer.title(for: date(22, hour: 0)) == "Yesterday")
        // The rest of the week by name; a week ago, the date.
        #expect(namer.title(for: date(21)) == "Wednesday")
        #expect(namer.title(for: date(17)) == "Saturday")
        #expect(namer.title(for: date(16)) == "Friday 16 October")
        #expect(namer.title(for: date(30, month: 9)) == "Wednesday 30 September")
        // Another year says so.
        #expect(namer.title(for: date(31, month: 12, year: 2025)) == "Wednesday, 31 December 2025")
        // A clock set back never makes "Tomorrow".
        #expect(namer.title(for: date(24)) == "Today")
    }

    @Test func daysAcrossTheClockChange() {
        // Summer time ended on Sunday 25 October 2026; Monday is still "Yesterday" on Tuesday.
        let tuesday = CaptureHistory.DayNamer(now: date(27, hour: 9), calendar: calendar, locale: locale)
        #expect(tuesday.title(for: date(26, hour: 23)) == "Yesterday")
        #expect(tuesday.title(for: date(25, hour: 1)) == "Sunday")
    }

    @Test func groupsByDayNewestFirst() {
        let entries = [entry(date(21, hour: 9)), entry(date(23, hour: 8)), entry(date(23, hour: 14)),
                       entry(date(21, hour: 18)), entry(date(10))]
        let days = CaptureHistory.days(entries, date: \.date, namer: namer)
        #expect(days.map(\.title) == ["Today", "Wednesday", "Saturday 10 October"])
        #expect(days[0].items.map(\.date) == [date(23, hour: 14), date(23, hour: 8)])
        #expect(days[1].items.map(\.date) == [date(21, hour: 18), date(21, hour: 9)])
        #expect(days.map(\.start) == [date(23, hour: 0), date(21, hour: 0), date(10, hour: 0)])
        #expect(CaptureHistory.days([CaptureLibrary.Entry](), date: \.date, namer: namer).isEmpty)
    }

    // MARK: Search

    @Test func findsByWordsAppAndDay() {
        let receipt = item(entry(date(23, hour: 9), app: "Safari", text: "Café receipt\tTotal 42,00\nThank you"))
        let deploy = item(entry(date(21), app: "Terminal", text: "Deploy finished in 3 minutes"))
        let plain = item(entry(date(16), app: nil, text: nil))
        let all = [receipt, deploy, plain]
        func found(_ query: String) -> [UUID] { CaptureHistory.filter(all, query: query).map(\.id) }

        #expect(found("") == all.map(\.id))
        #expect(found("   ") == all.map(\.id))
        // Case, accents and width don't matter.
        #expect(found("CAFE") == [receipt.id])
        #expect(found("café") == [receipt.id])
        #expect(found("ｃａｆｅ") == [receipt.id])
        // Words from anywhere in the text, tabs and lines included.
        #expect(found("thank total") == [receipt.id])
        #expect(found("deploy") == [deploy.id])
        // The app.
        #expect(found("terminal") == [deploy.id])
        #expect(found("saf") == [receipt.id])
        // The day: its title, weekday, month or date.
        #expect(found("today") == [receipt.id])
        #expect(found("wednesday") == [deploy.id])
        #expect(found("wed") == [deploy.id])
        #expect(found("16 october") == [plain.id])
        #expect(found("oct") == all.map(\.id))
        // Every word must match.
        #expect(found("safari deploy").isEmpty)
        #expect(found("zebra").isEmpty)
    }

    // MARK: Items

    @Test func itemsDescribeThemselves() {
        #expect(item(entry(now, app: "Notes")).subtitle == "Notes")
        #expect(item(entry(now, app: "", kind: "window")).subtitle == "Window")
        #expect(item(entry(now, kind: "display")).subtitle == "Screen")
        #expect(item(entry(now)).subtitle == "Area")
        #expect(item(entry(now, kind: "window")).isWindow)
        #expect(item(entry(now, text: " \n\t")).text == nil)
        #expect(item(entry(now, text: "Hello")).text == "Hello")
        let file = URL(fileURLWithPath: "/tmp/shot.png")
        #expect(item(entry(now, file: file), saved: true).savedFile == file)
        #expect(item(entry(now, file: file), saved: false).savedFile == nil)
    }

    @Test func saysWhatRemovingLeavesAlone() {
        let saved = item(entry(now), saved: true), unsaved = item(entry(now))
        #expect(CaptureHistoryWindowController.removalNote([saved]) == "The saved file stays where it is")
        #expect(CaptureHistoryWindowController.removalNote([unsaved]) == "It isn't saved anywhere else")
        #expect(CaptureHistoryWindowController.removalNote([saved, saved]) == "Their saved files stay where they are")
        #expect(CaptureHistoryWindowController.removalNote([unsaved, unsaved]) == "They aren't saved anywhere else")
        #expect(CaptureHistoryWindowController.removalNote([saved, unsaved]) == "Saved files stay where they are")
    }

    // MARK: Removing

    @Test func selectsTheNextOneAfterRemoving() {
        let ids = (0..<5).map { _ in UUID() }
        #expect(CaptureHistory.selection(afterRemoving: [ids[1]], from: ids) == ids[2])
        #expect(CaptureHistory.selection(afterRemoving: [ids[1], ids[2]], from: ids) == ids[3])
        // Apart: after the last of them.
        #expect(CaptureHistory.selection(afterRemoving: [ids[0], ids[3]], from: ids) == ids[4])
        // At the end, the one before.
        #expect(CaptureHistory.selection(afterRemoving: [ids[4]], from: ids) == ids[3])
        #expect(CaptureHistory.selection(afterRemoving: [ids[3], ids[4]], from: ids) == ids[2])
        #expect(CaptureHistory.selection(afterRemoving: Set(ids), from: ids) == nil)
        #expect(CaptureHistory.selection(afterRemoving: [UUID()], from: ids) == nil)
    }

    @Test func removesFromHistoryWithUndo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "capture-history-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 40, height: 20))
        let saved = root.appending(path: "Screenshot.png")
        try Data([1, 2, 3]).write(to: saved)
        let first = entry(date(23), app: "Notes", file: saved), second = entry(date(22))
        try CaptureLibrary.store(image, entry: first, in: root)
        try CaptureLibrary.store(image, entry: second, in: root)

        #expect(CaptureLibrary.remove([first.id, UUID()], in: root) == [first.id])
        #expect(CaptureLibrary.entries(in: root).map(\.id) == [second.id])
        #expect(CaptureLibrary.entry(first.id, in: root) == nil)
        // Only Barn Owl's copy goes; the saved file stays.
        #expect(FileManager.default.fileExists(atPath: saved.path))

        // Undo brings it back, marks and all.
        #expect(CaptureLibrary.restore([first.id], in: root) == [first.id])
        #expect(CaptureLibrary.entries(in: root).map(\.id) == [first.id, second.id])
        #expect(CaptureLibrary.original(first.id, in: root)?.width == 40)
        // Nothing to bring back twice.
        #expect(CaptureLibrary.restore([first.id], in: root).isEmpty)

        // Closing history lets go for good.
        CaptureLibrary.remove([second.id], in: root)
        CaptureLibrary.forgetRemoved(in: root)
        #expect(CaptureLibrary.restore([second.id], in: root).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: CaptureLibrary.removedFolder(in: root).path))
        // Clearing and pruning never trip over the waiting folder.
        CaptureLibrary.remove([first.id], in: root)
        CaptureLibrary.prune(now: Date(), days: 30, in: root)
        #expect(CaptureLibrary.entries(in: root).isEmpty)
    }

    @Test func loadsWhatHistoryNeeds() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "capture-history-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 1600, height: 900))
        let saved = root.appending(path: "Saved.png")
        try Data([1]).write(to: saved)
        let kept = entry(date(23, hour: 10), app: "Mail", text: "Invoice", file: saved)
        let moved = entry(date(23, hour: 9), file: root.appending(path: "Gone.png"))
        try CaptureLibrary.store(image, entry: kept, in: root)
        try CaptureLibrary.store(image, entry: moved, in: root)

        let items = CaptureHistory.load(in: root, now: now, calendar: calendar, locale: locale)
        #expect(items.map(\.id) == [kept.id, moved.id])
        #expect(items.map(\.isSaved) == [true, false])
        #expect(items[0].searchKey.contains("invoice") && items[0].searchKey.contains("mail"))
        #expect(items[0].searchKey.contains("today"))
        // The small picture: from the original until there's a thumbnail, never bigger than asked.
        let picture = try #require(CaptureLibrary.smallPicture(kept.id, pixels: 400, in: root))
        #expect(max(picture.width, picture.height) == 400)
        #expect(CaptureLibrary.smallPicture(UUID(), pixels: 400, in: root) == nil)
    }

    // MARK: The grid

    @Test func tilesFillTheWidth() {
        let wide = CaptureHistory.tiles(across: 900, minimum: 176, spacing: 18)
        #expect(wide.columns == 4)
        #expect(wide.width == 211)
        #expect(CaptureHistory.tiles(across: 516, minimum: 176, spacing: 18).columns == 2)
        // Never fewer than one, however narrow.
        let narrow = CaptureHistory.tiles(across: 100, minimum: 176, spacing: 18)
        #expect(narrow.columns == 1 && narrow.width == 100)
    }

    @Test func typingInTheGridStartsASearch() {
        #expect(HistoryCollectionView.startsSearch("a"))
        #expect(HistoryCollectionView.startsSearch("7"))
        #expect(HistoryCollectionView.startsSearch("é"))
        #expect(!HistoryCollectionView.startsSearch(" "))
        #expect(!HistoryCollectionView.startsSearch(""))
        #expect(!HistoryCollectionView.startsSearch("\u{F700}"))
        #expect(!HistoryCollectionView.startsSearch("\r"))
    }

    @Test func splitsAShortcutIntoKeys() {
        #expect(KeyCaps.split("⌃⌥⌘4") == ["⌃", "⌥", "⌘", "4"])
        #expect(KeyCaps.split("⇧⌘F5") == ["⇧", "⌘", "F5"])
        #expect(KeyCaps.split("Space") == ["Space"])
    }

    @Test func historyIsACommand() {
        let command = AppCommand.captureHistory
        #expect(command.title == "Capture history")
        #expect(command.keywords.contains("history") && command.keywords.contains("screenshots"))
    }
}

/// The window's model: what it shows, and what it says about it.
@MainActor
struct CaptureHistoryModelTests {
    private func item(_ text: String, hoursAgo: Double = 1) -> CaptureHistory.Item {
        var entry = CaptureLibrary.Entry(id: UUID(), date: Date().addingTimeInterval(-hoursAgo * 3600), scale: 2,
                                         kind: "selection", appName: "Notes", fileURL: nil, edited: false)
        entry.text = text
        let namer = CaptureHistory.DayNamer(now: Date())
        return CaptureHistory.Item(entry: entry, isSaved: false, searchKey: CaptureHistory.searchKey(for: entry, namer: namer))
    }

    @Test func statesAndSubtitles() {
        let model = CaptureHistoryModel(root: URL(fileURLWithPath: "/nonexistent"), keepDays: 30)
        var changes = 0
        model.onChange = { changes += 1 }
        #expect(model.state == .loading)
        model.show([])
        #expect(model.state == .empty)
        #expect(model.subtitle == "Kept for 30 days")
        let first = item("Quarterly plan"), second = item("Lunch menu")
        model.show([first, second])
        #expect(model.state == .grid)
        #expect(model.subtitle == "2 captures · kept for 30 days")
        #expect(model.subtitle(compact: true) == "2 captures")
        model.query = "plan"
        #expect(model.days.flatMap(\.items).map(\.id) == [first.id])
        #expect(model.subtitle == "1 of 2 captures")
        model.query = "nothing like it"
        #expect(model.state == .noResults)
        model.query = ""
        model.drop([second.id])
        #expect(model.all.map(\.id) == [first.id])
        #expect(model.item(second.id) == nil)
        #expect(model.subtitle == "1 capture · kept for 30 days")
        #expect(changes == 6)
        model.keepDays = 0
        #expect(model.state == .off)
        #expect(model.subtitle == "Not keeping captures")
    }

    @Test func tellsHistoryWhenTheLibraryChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "capture-history-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 40, height: 20))
        let entry = CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 2, kind: "selection", appName: nil,
                                         fileURL: nil, edited: false)
        final class Heard: @unchecked Sendable {
            var ids: [UUID?] = []
        }
        let heard = Heard()
        let observer = NotificationCenter.default.addObserver(forName: CaptureLibrary.didChange, object: nil,
                                                              queue: .main) { note in
            heard.ids.append(note.userInfo?["id"] as? UUID)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try CaptureLibrary.store(image, entry: entry, in: root)
        CaptureLibrary.storeThumbnail(image, for: entry.id, in: root)
        CaptureLibrary.clear(in: root)
        try await Task.sleep(for: .milliseconds(200))
        #expect(heard.ids.contains(entry.id))
        #expect(heard.ids.contains(nil))
    }
}

/// The window itself, offscreen: the keys, Remove from History and Undo.
@MainActor
struct CaptureHistoryWindowTests {
    private func key(_ code: UInt16, _ characters: String, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                         keyCode: code)!
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<40 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func removesWithDeleteAndUndoes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "capture-history-window-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 64, height: 40))
        let today = Calendar.current.startOfDay(for: Date())
        var ids: [UUID] = []
        for hour in [12, 11, 10] {
            let entry = CaptureLibrary.Entry(id: UUID(), date: today.addingTimeInterval(Double(hour) * 3600), scale: 2,
                                             kind: "selection", appName: "Notes", fileURL: nil, edited: false)
            try CaptureLibrary.store(image, entry: entry, in: root)
            ids.append(entry.id)
        }
        let controller = CaptureHistoryWindowController(host: nil, root: root)
        let window = try #require(controller.window)
        // Tests share the app's defaults: never remember this window's frame.
        window.setFrameAutosaveName("")
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: false)
        controller.model.keepDays = 30
        controller.model.reload()
        try await waitUntil { controller.model.all.count == 3 }
        #expect(controller.model.days.flatMap { $0.items.map(\.id) } == ids)
        let grid = controller.grid
        window.makeFirstResponder(grid.collectionView)
        grid.select([ids[0]], scroll: false)

        // → moves on; Delete removes it in one step and selects the next.
        grid.collectionView.keyDown(with: key(124, "\u{F703}", in: window))
        #expect(grid.selectedIDs == [ids[1]])
        grid.collectionView.keyDown(with: key(51, "\u{7F}", in: window))
        #expect(controller.model.item(ids[1]) == nil)
        #expect(CaptureLibrary.entry(ids[1], in: root) == nil)
        #expect(grid.selectedIDs == [ids[2]])
        #expect(window.undoManager?.undoMenuItemTitle == "Undo Remove from History")

        // Undo brings it back, selected.
        controller.undo(nil)
        try await waitUntil { controller.model.item(ids[1]) != nil && grid.selectedIDs == [ids[1]] }
        #expect(CaptureLibrary.entry(ids[1], in: root) != nil)
        #expect(grid.selectedIDs == [ids[1]])

        // Esc clears a search before it closes anything; what was selected still is.
        controller.model.query = "nothing like it"
        #expect(controller.model.state == .noResults)
        #expect(grid.selectedIDs.isEmpty)
        grid.collectionView.keyDown(with: key(53, "\u{1B}", in: window))
        #expect(controller.model.query.isEmpty)
        #expect(grid.selectedIDs == [ids[1]])

        // Closing lets removed captures go for good.
        grid.select([ids[0]], scroll: false)
        controller.removeFromHistory(nil)
        #expect(FileManager.default.fileExists(atPath: CaptureLibrary.removedFolder(in: root).path))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(!FileManager.default.fileExists(atPath: CaptureLibrary.removedFolder(in: root).path))
        #expect(CaptureLibrary.entries(in: root).count == 2)
    }
}

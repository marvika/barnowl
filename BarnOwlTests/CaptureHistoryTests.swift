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
    private func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = [],
                     in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
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

        // → moves on; ⌘⌫ removes it in one step and selects the next.
        grid.collectionView.keyDown(with: key(124, "\u{F703}", in: window))
        #expect(grid.selectedIDs == [ids[1]])
        grid.collectionView.keyDown(with: key(51, "\u{7F}", .command, in: window))
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

/// Stands in for the coordinator: which captures are open in the editor, and what words
/// each has once cropping and hiding are taken into account.
@MainActor
final class FakeHistoryHost: CaptureHistoryHost {
    var editingCaptures: Set<UUID> = []
    /// The words you can see in each; those missing have none.
    var visible: [UUID: String] = [:]
    /// Ones Vision couldn't read.
    var unreadable: Set<UUID> = []
    private(set) var read: [UUID] = []
    private(set) var copied: [UUID] = []

    func openEditor(_ id: UUID) {}
    func copy(_ id: UUID) -> Bool {
        copied.append(id)
        return true
    }
    func pin(_ id: UUID) {}
    func fileForDragging(_ id: UUID) -> URL? { nil }
    func prepareDragFile(_ id: UUID) {}
    func readVisibleText(_ id: UUID) async -> String? {
        read.append(id)
        return unreadable.contains(id) ? nil : visible[id] ?? ""
    }
    func hasText(_ id: UUID) -> Bool { visible[id]?.isEmpty == false }
}

/// The fixes from reviewing history: what stays while it's edited, what Copy Text copies,
/// tidying the library, old captures catching up, and Edit Last Capture.
@MainActor
struct CaptureHistoryReviewTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "capture-history-review-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Kept captures an hour apart, newest first, each with `text` as read when it was taken.
    private func store(_ count: Int, in root: URL, text: String? = nil, ago: TimeInterval = 0,
                       width: Int = 64, height: Int = 40) throws -> [UUID] {
        let image = try #require(CaptureStoreTests.image(width: width, height: height))
        return try (0..<count).map { index in
            var entry = CaptureLibrary.Entry(id: UUID(), date: Date().addingTimeInterval(-ago - Double(index) * 3600),
                                             scale: 2, kind: "selection", appName: "Notes", fileURL: nil, edited: false)
            entry.text = text
            try CaptureLibrary.store(image, entry: entry, in: root)
            return entry.id
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<60 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
    }

    private func window(host: FakeHistoryHost?, root: URL, count: Int) async throws -> CaptureHistoryWindowController {
        let controller = CaptureHistoryWindowController(host: host, root: root)
        let window = try #require(controller.window)
        // Tests share the app's defaults: never remember this window's frame.
        window.setFrameAutosaveName("")
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: false)
        controller.model.keepDays = 30
        controller.model.reload()
        try await waitUntil { controller.model.all.count == count }
        return controller
    }

    // MARK: Open in the editor

    @Test func keepsWhatsOpenInTheEditor() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = try store(3, in: root)
        let host = FakeHistoryHost()
        host.editingCaptures = [ids[0]]
        let controller = try await window(host: host, root: root, count: 3)
        let grid = controller.grid

        // Removing two, one of them open: the other goes, the open one stays selected.
        grid.select([ids[0], ids[1]], scroll: false)
        controller.removeFromHistory(nil)
        #expect(CaptureLibrary.entry(ids[0], in: root) != nil)
        #expect(CaptureLibrary.entry(ids[1], in: root) == nil)
        #expect(grid.selectedIDs == [ids[0]])
        #expect(controller.notice.note?.text == "Kept 1 that's open in the editor")

        // Only the open one: nothing goes, and the window says why.
        controller.removeFromHistory(nil)
        #expect(CaptureLibrary.entry(ids[0], in: root) != nil)
        #expect(controller.notice.note?.text == "Close its editor first to remove it")
        #expect(host.isEditing(ids[0]) && !host.isEditing(ids[2]))

        // Clear Now and pruning leave it too.
        CaptureLibrary.clear(in: root, keeping: [ids[0]])
        #expect(CaptureLibrary.entries(in: root).map(\.id) == [ids[0]])
        let later = Date().addingTimeInterval(90 * 86_400)
        CaptureLibrary.prune(now: later, days: 30, in: root, keeping: [ids[0]])
        #expect(CaptureLibrary.entries(in: root).map(\.id) == [ids[0]])
        CaptureLibrary.prune(now: later, days: 30, in: root)
        #expect(CaptureLibrary.entries(in: root).isEmpty)
    }

    // MARK: Copy Text

    @Test func copyTextCopiesOnlyWhatsVisible() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Read when they were taken, before anything was cropped or hidden.
        let ids = try store(4, in: root, text: "Password hunter2")
        let host = FakeHistoryHost()
        host.visible = [ids[0]: "Quarterly plan", ids[2]: "Lunch menu\nSoup"]
        host.unreadable = [ids[3]]
        let controller = try await window(host: host, root: root, count: 4)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("barnowl-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        controller.pasteboard = pasteboard

        // Three at once: what the host says is visible, in grid order; nothing hidden.
        controller.grid.select([ids[0], ids[1], ids[2]], scroll: false)
        controller.copyText(nil)
        try await waitUntil { pasteboard.string(forType: .string) != nil }
        #expect(pasteboard.string(forType: .string) == "Quarterly plan\n\nLunch menu\nSoup")
        #expect(host.read == [ids[0], ids[1], ids[2]])
        #expect(controller.notice.note?.text == "Text copied · 3 lines")

        // None with words: nothing copied, and it says so.
        pasteboard.clearContents()
        controller.grid.select([ids[1]], scroll: false)
        controller.copyText(nil)
        try await waitUntil { controller.notice.note?.text == "No text found" }
        #expect(controller.notice.note?.text == "No text found")
        #expect(pasteboard.string(forType: .string) == nil)

        controller.grid.select([ids[3]], scroll: false)
        controller.copyText(nil)
        try await waitUntil { controller.notice.note?.text == "Couldn't read the text" }
        #expect(controller.notice.note?.tone == .warning)
        #expect(pasteboard.string(forType: .string) == nil)

        // Copy says so too.
        controller.grid.select([ids[0]], scroll: false)
        controller.copy(nil)
        #expect(host.copied == [ids[0]])
        #expect(controller.notice.note?.text == "Copied")
    }

    @Test func saysHowMuchTextWasCopied() {
        #expect(CaptureHistoryWindowController.textCopied("Hello") == "Text copied")
        #expect(CaptureHistoryWindowController.textCopied("One\nTwo\n\nThree") == "Text copied · 3 lines")
    }

    @Test func offersCopyTextUntilItsKnownThereIsNone() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let unread = try store(1, in: root)[0]
        let none = try store(1, in: root, ago: 7200)[0]
        CaptureLibrary.update(none, in: root) { $0.textWasRead = true }
        let host = FakeHistoryHost()
        let controller = try await window(host: host, root: root, count: 2)
        let item = NSMenuItem(title: "Copy Text", action: #selector(CaptureHistoryWindowController.copyText(_:)),
                              keyEquivalent: "")
        // Not read yet: offered, and read when chosen.
        controller.grid.select([unread], scroll: false)
        #expect(controller.validateMenuItem(item))
        // Read, with no words: not offered, unless the host knows better.
        controller.grid.select([none], scroll: false)
        #expect(!controller.validateMenuItem(item))
        host.visible[none] = "Found later"
        #expect(controller.validateMenuItem(item))
    }

    // MARK: Tidying

    @Test func clearLetsGoOfEverything() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = try store(2, in: root)
        CaptureLibrary.remove([ids[1]], in: root)
        // Half-written: its picture, but no entry.
        let half = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: half, withIntermediateDirectories: true)
        try Data([1]).write(to: half.appending(path: "original.png"))
        let other = root.appending(path: "Notes.txt")
        try Data([1]).write(to: other)

        CaptureLibrary.clear(in: root)
        #expect(CaptureLibrary.entries(in: root).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: CaptureLibrary.removedFolder(in: root).path))
        #expect(!FileManager.default.fileExists(atPath: half.path))
        #expect(CaptureLibrary.restore([ids[1]], in: root).isEmpty)
        // Only Barn Owl's own folders.
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func loadsEachCaptureOnce() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try store(1, in: root)[0]
        try FileManager.default.copyItem(at: CaptureLibrary.folder(for: id, in: root),
                                         to: root.appending(path: UUID().uuidString))
        #expect(CaptureLibrary.entries(in: root).count == 2)
        #expect(CaptureHistory.load(in: root, now: Date()).map(\.id) == [id])
    }

    // MARK: Captures from 0.15.0

    @Test func makesTheThumbnailsOldCapturesNeverGot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let wide = try store(1, in: root, width: 1600, height: 900)[0]
        let small = try store(1, in: root, width: 300, height: 200)[0]
        let thumbnail = CaptureLibrary.folder(for: wide, in: root).appending(path: "thumbnail.png")
        #expect(!FileManager.default.fileExists(atPath: thumbnail.path))

        // Showing it from the original makes the thumbnail, the size Barn Owl makes them.
        let picture = try #require(CaptureLibrary.smallPicture(wide, pixels: 400, in: root))
        #expect(max(picture.width, picture.height) == 400)
        let made = try #require(CaptureLibrary.thumbnail(wide, in: root))
        #expect(made.width == 520 && (292...293).contains(made.height))
        #expect(!CaptureLibrary.storeMissingThumbnail(wide, in: root))
        // Never bigger than the original.
        #expect(CaptureLibrary.storeMissingThumbnail(small, in: root))
        #expect(CaptureLibrary.thumbnail(small, in: root)?.width == 300)

        // Marked up: drawn with its marks, unless its frame wants the desktop picture.
        let marked = try store(1, in: root, width: 800, height: 600)[0]
        var document = EditorDocument(imageSize: CGSize(width: 800, height: 600))
        try CaptureLibrary.storeDocument(JSONEncoder().encode(document), for: marked, in: root)
        #expect(CaptureLibrary.storeMissingThumbnail(marked, in: root))
        #expect(CaptureLibrary.thumbnail(marked, in: root)?.width == 520)
        let desktop = try store(1, in: root)[0]
        document.frame.background = .desktop
        try CaptureLibrary.storeDocument(JSONEncoder().encode(document), for: desktop, in: root)
        #expect(!CaptureLibrary.storeMissingThumbnail(desktop, in: root))
    }

    @Test func readsTheWordsOfOldCapturesOnce() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let read = try store(1, in: root, text: "Already read")[0]
        let words = try store(1, in: root, ago: 3600)[0]
        let empty = try store(1, in: root, ago: 7200)[0]
        let failing = try store(1, in: root, ago: 10800)[0]
        final class Reader: @unchecked Sendable {
            var calls = 0
            var answers: [String?] = []
        }
        struct Failed: Error {}
        // Newest first: words, none, then Vision fails.
        let reader = Reader()
        reader.answers = ["Invoice 42", "", nil]
        let stub: @Sendable (CGImage) async throws -> String = { _ in
            defer { reader.calls += 1 }
            guard reader.calls < reader.answers.count, let answer = reader.answers[reader.calls] else { throw Failed() }
            return answer
        }
        await CaptureLibrary.backfill(in: root, read: stub)
        #expect(reader.calls == 3)
        #expect(CaptureLibrary.entry(read, in: root)?.text == "Already read")
        #expect(CaptureLibrary.entry(words, in: root)?.text == "Invoice 42")
        #expect(CaptureLibrary.entry(words, in: root)?.textWasRead == true)
        #expect(CaptureLibrary.entry(empty, in: root)?.text == nil)
        #expect(CaptureLibrary.entry(empty, in: root)?.textWasRead == true)
        #expect(CaptureLibrary.entry(failing, in: root)?.textWasRead == nil)
        // Thumbnails for all of them along the way.
        for id in [read, words, empty, failing] { #expect(CaptureLibrary.thumbnail(id, in: root)?.width == 64) }
        // Again: only the one Vision couldn't read is tried.
        reader.answers = []
        reader.calls = 0
        await CaptureLibrary.backfill(in: root, read: stub)
        #expect(reader.calls == 1)
        // Search finds the words now.
        let items = CaptureHistory.load(in: root, now: Date())
        #expect(CaptureHistory.filter(items, query: "invoice").map(\.id) == [words])
    }

    // MARK: Edit Last Capture

    @Test func editLastCaptureSkipsOnesLetGo() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(CaptureCoordinator.lastCapture(nil, onlyInMemory: false, in: root) == nil)
        let ids = try store(2, in: root)
        #expect(CaptureCoordinator.lastCapture(ids[1], onlyInMemory: false, in: root) == ids[1])
        #expect(CaptureCoordinator.lastCapture(nil, onlyInMemory: false, in: root) == ids[0])
        // Removed from history: the newest one kept instead.
        CaptureLibrary.remove([ids[1]], in: root)
        #expect(CaptureCoordinator.lastCapture(ids[1], onlyInMemory: false, in: root) == ids[0])
        // Only in memory (still being written, or nothing kept): still there to edit.
        let fresh = UUID()
        #expect(CaptureCoordinator.lastCapture(fresh, onlyInMemory: true, in: root) == fresh)
    }

    // MARK: Keys

    @Test func onlyCommandDeleteRemoves() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = try store(2, in: root)
        let controller = try await window(host: FakeHistoryHost(), root: root, count: 2)
        let window = try #require(controller.window)
        let grid = controller.grid
        window.makeFirstResponder(grid.collectionView)
        grid.select([ids[0]], scroll: false)
        func delete(_ modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: "\u{7F}",
                             charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51)!
        }
        grid.collectionView.keyDown(with: delete([]))
        #expect(controller.model.item(ids[0]) != nil)
        grid.collectionView.keyDown(with: delete(.command))
        #expect(controller.model.item(ids[0]) == nil)

        // Esc in the search field clears it, then leaves it; it never closes the window.
        let field = NSSearchField()
        let editor = NSTextView()
        controller.model.query = "lunch"
        editor.string = "lunch"
        let escape = #selector(NSResponder.cancelOperation(_:))
        #expect(controller.control(field, textView: editor, doCommandBy: escape))
        #expect(controller.model.query.isEmpty)
        editor.string = ""
        #expect(controller.control(field, textView: editor, doCommandBy: escape))
        #expect(controller.model.isLoaded)
    }
}

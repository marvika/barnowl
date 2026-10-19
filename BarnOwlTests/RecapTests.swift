import Foundation
import Testing
@testable import BarnOwl

@MainActor
struct DailyLogTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .gmt
        return calendar
    }()

    /// Monday 12 October 2026 at `hour`:`minute`, plus `days`.
    static func date(_ days: Int = 0, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12 + days, hour: hour, minute: minute, second: second))!
    }

    static func session(_ id: String, _ state: OwletState, repository: String = "barnowl", since: Date = .distantPast) -> AgentSession {
        let folder = URL(fileURLWithPath: "/Users/demo/code/\(repository)")
        return AgentSession(id: id, agent: .claude, pid: nil, name: id, folder: folder,
                            place: ProjectPlace(repository: repository, worktree: nil, root: folder),
                            started: .distantPast, state: state, stateSince: since)
    }

    func makeLog(_ url: URL? = nil) -> DailyLog { DailyLog(fileURL: url, calendar: Self.calendar) }

    @Test func integratesTimeAndCapsGaps() {
        let log = makeLog()
        let start = Self.date(0, 10)
        log.record([Self.session("a", .typing)], now: start)
        log.record([Self.session("a", .typing)], now: start.addingTimeInterval(30))
        #expect(log.summary(for: start).working == 30)
        // An hour asleep counts as a minute at most.
        log.record([Self.session("a", .typing)], now: start.addingTimeInterval(30 + 3600))
        #expect(log.summary(for: start).working == 90)
        // Time runs backwards: nothing.
        log.record([Self.session("a", .typing)], now: start)
        #expect(log.summary(for: start).working == 90)
        #expect(log.summary(for: start).repositories["barnowl"] == 90)
        #expect(log.summary(for: start).hours[11] == 60)
    }

    @Test func countsTheStateSinceTheLastLook() {
        let log = makeLog()
        let start = Self.date(0, 10)
        log.record([Self.session("a", .needsYou), Self.session("b", .needsYou)], now: start)
        log.record([Self.session("a", .typing), Self.session("b", .needsYou)], now: start.addingTimeInterval(20))
        log.record([Self.session("a", .typing), Self.session("b", .typing)], now: start.addingTimeInterval(40))
        let day = log.summary(for: start)
        #expect(day.working == 20) // a, from 20 to 40
        #expect(day.waiting == 60) // a 20 + b 40, added across agents
        #expect(day.needed == 40) // by the clock
        #expect(day.waits.sorted() == [20, 40])
        #expect(day.peak == 2)
        #expect(day.sessions == 2)
    }

    @Test func countsAShipOncePerMoveIntoIt() {
        let log = makeLog()
        let start = Self.date(0, 14)
        let states: [OwletState] = [.typing, .shipped, .shipped, .shipped, .done, .typing, .shipped]
        for (index, state) in states.enumerated() {
            log.record([Self.session("a", state)], now: start.addingTimeInterval(Double(index) * 10))
        }
        #expect(log.summary(for: start).shipped == 2)
    }

    @Test func aSessionFoundShippedCountsOnlyIfItShippedSinceTheLastLook() {
        let log = makeLog()
        let start = Self.date(0, 14)
        // Barn Owl just started: a ship from before doesn't count.
        log.record([Self.session("old", .shipped, since: start.addingTimeInterval(-30))], now: start)
        #expect(log.summary(for: start).shipped == 0)
        let later = start.addingTimeInterval(10)
        log.record([Self.session("old", .shipped, since: start.addingTimeInterval(-30)),
                    Self.session("new", .shipped, since: later.addingTimeInterval(-3))], now: later)
        #expect(log.summary(for: start).shipped == 1)
    }

    @Test func tracksNightLongestAndPeak() {
        let log = makeLog()
        var now = Self.date(1, 23)
        log.record([Self.session("a", .typing), Self.session("b", .typing), Self.session("c", .needsYou)], now: now)
        for _ in 0..<5 {
            now += 60
            log.record([Self.session("a", .typing), Self.session("b", .typing), Self.session("c", .needsYou)], now: now)
        }
        let day = log.summary(for: now)
        #expect(day.night == 600)
        #expect(day.longest == 300)
        #expect(day.longestStart == Self.date(1, 23))
        #expect(day.peak == 2)
        #expect(day.peakAt == Self.date(1, 23))
    }

    @Test func aWeekRunsMondayToSunday() {
        let log = makeLog()
        for (day, minutes) in [(0, 2), (2, 4), (6, 1), (7, 5)] {
            var now = Self.date(day, 12)
            log.record([Self.session("a", .typing, repository: day == 2 ? "site" : "barnowl")], now: now)
            for _ in 0..<minutes {
                now += 60
                log.record([Self.session("a", .typing, repository: day == 2 ? "site" : "barnowl")], now: now)
            }
            log.record([], now: now) // gone until the next day
        }
        let week = log.week(endingOn: Self.date(3, 9))
        #expect(week.start == Self.date(0, 0))
        #expect(week.week == 42)
        #expect(week.days.count == 7)
        #expect(week.days.map(\.day).first == "2026-10-12")
        #expect(week.days.map(\.day).last == "2026-10-18")
        #expect(week.working == 7 * 60) // next Monday's 5 min belongs to week 43
        #expect(week.trees == 2)
        #expect(week.repositories.first?.name == "site")
        #expect(week.heatmap[2][12] == 240)
        #expect(log.week(endingOn: Self.date(7, 9)).working == 5 * 60)
        // Sunday still belongs to the week that started on Monday.
        #expect(log.week(endingOn: Self.date(6, 23)).start == Self.date(0, 0))
    }

    @Test func roundTripsThroughTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DailyLogTests-\(UUID().uuidString)/daily-log.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = makeLog(url)
        var now = Self.date(3, 21, 30)
        log.record([Self.session("claude:secret-session-id", .typing), Self.session("b", .needsYou)], now: now)
        for _ in 0..<90 {
            now += 60
            log.record([Self.session("claude:secret-session-id", .typing), Self.session("b", .needsYou)], now: now)
        }
        log.record([Self.session("claude:secret-session-id", .shipped), Self.session("b", .typing)], now: now + 5)
        log.saveNow()

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("secret-session-id"))

        let reopened = makeLog(url)
        #expect(reopened.week(endingOn: now) == log.week(endingOn: now))
        #expect(reopened.week(endingOn: now).working > 0)
        #expect(reopened.week(endingOn: now).newSpecies == [.snowy])
        // The same session after a relaunch is still the same session.
        reopened.record([Self.session("claude:secret-session-id", .typing)], now: now + 10)
        #expect(reopened.summary(for: now).sessions == 2)
    }

    @Test func aDamagedFileStartsAfresh() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "DailyLogTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{not json".utf8).write(to: url)
        let log = makeLog(url)
        #expect(log.week(endingOn: Self.date(0, 12)).working == 0)
    }
}

@MainActor
struct RecapTests {
    @Test func recapTimeIsFridayAfternoonThroughSunday() {
        let calendar = DailyLogTests.calendar
        let date = { (day: Int, hour: Int) in
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 12 + day, hour: hour))!
        }
        #expect(!RecapWindowController.isRecapTime(date(0, 12), calendar: calendar)) // Monday
        #expect(!RecapWindowController.isRecapTime(date(4, 15), calendar: calendar)) // Friday 15:00
        #expect(RecapWindowController.isRecapTime(date(4, 16), calendar: calendar))
        #expect(RecapWindowController.isRecapTime(date(5, 9), calendar: calendar))
        #expect(RecapWindowController.isRecapTime(date(6, 23), calendar: calendar))
        #expect(!RecapWindowController.isRecapTime(date(7, 0), calendar: calendar))
    }

    @Test func formatsDurations() {
        #expect(RecapFacts.text(114_000) == "31 h 40 m")
        #expect(RecapFacts.text(11_520) == "3 h 12 m")
        #expect(RecapFacts.text(3 * 3600 + 300) == "3 h 05 m")
        #expect(RecapFacts.text(41) == "41 s")
        #expect(RecapFacts.text(150) == "2 m 30 s")
        #expect(RecapFacts.text(1500) == "25 m")
        #expect(RecapFacts.plain(52 * 60) == "52 min")
    }

    @Test func theDemoWeekReadsLikeTheConcept() {
        let week = WeekSummary.demo(now: Date())
        let facts = RecapFacts(week: week)
        #expect(RecapFacts.text(week.working) == "31 h 40 m")
        #expect(week.trees == 4)
        #expect(week.typicalWait == 41)
        #expect(week.shipped == 9)
        #expect(facts.needed == "52 min")
        #expect(facts.busiest?.name == "Tree A")
        #expect(RecapFacts(week: week, showsNames: true).busiest?.name == "barnowl")
        #expect(facts.stats.map(\.label) == ["Most at once", "Longest flight", "Shipped", "Your replies"])
        #expect(facts.perch(limit: 5).count == 4)
    }

    @Test func aQuietWeekSaysNoZeros() {
        var week = WeekSummary.demo(now: Date())
        for index in week.days.indices {
            week.days[index].shipped = 0
            week.days[index].waits = []
        }
        let labels = RecapFacts(week: week).stats.map(\.label)
        #expect(!labels.contains("Shipped"))
        #expect(!labels.contains("Your replies"))
        #expect(labels.count == 4)
    }
}

import Foundation
import Testing
@testable import BarnOwl

/// The Now view's eight weeks: story lines, the heat map and the moons.
struct HistoryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }()

    private func day(_ key: String, hours: Double, at hour: Int = 10, repo: String = "barnowl") -> DaySummary {
        var day = DaySummary(day: key)
        day.working = hours * 3600
        if hours > 0 {
            day.hours[hour] = hours * 3600
            day.repositories[repo] = hours * 3600
        }
        return day
    }

    @Test func storyLinesComeFromTheDays() {
        let history = History(days: [day("2026-10-12", hours: 2), day("2026-10-13", hours: 0),
                                     day("2026-10-14", hours: 6.5, repo: "site"), day("2026-10-15", hours: 1),
                                     day("2026-10-16", hours: 3)],
                              today: "2026-10-16")
        #expect(history.busiest?.day == "2026-10-14")
        #expect(history.streak == 3)
        #expect(history.mostly?.name == "site")
        #expect(abs(history.total - 12.5 * 3600) < 1)
    }

    @Test func aQuietMorningDoesntBreakTheStreak() {
        let history = History(days: [day("2026-10-14", hours: 2), day("2026-10-15", hours: 1), day("2026-10-16", hours: 0)],
                              today: "2026-10-16")
        #expect(history.streak == 2)
    }

    @Test func heatIsByWeekdayMondayFirst() {
        // 12 October 2026 is a Monday, 18 October a Sunday.
        let history = History(days: [day("2026-10-12", hours: 2, at: 9), day("2026-10-18", hours: 1, at: 22)],
                              today: "2026-10-18")
        let heat = history.heat(calendar: calendar)
        #expect(heat[0][9] == 2 * 3600)
        #expect(heat[6][22] == 3600)
    }

    @Test func thePatternIsOnePlainSentence() {
        let days = (12...16).map { day("2026-10-\($0)", hours: 3, at: 14) }
        let history = History(days: days, today: "2026-10-16")
        #expect(history.pattern(calendar: calendar) == "Mostly afternoons, and weekends off.")
        #expect(History(days: [], today: "2026-10-16").pattern(calendar: calendar) == nil)
    }

    @Test func brighterTheMoreWorkUpToAFullDay() {
        #expect(History.brightness(day("2026-10-12", hours: 0)) == 0)
        #expect(History.brightness(day("2026-10-12", hours: 3)) == 0.5)
        #expect(History.brightness(day("2026-10-12", hours: 9)) == 1)
    }

    @MainActor @Test func theLogGivesEightWeeksMondayFirst() throws {
        let log = DailyLog(fileURL: nil, calendar: calendar)
        let tuesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)))
        let history = log.history(endingOn: tuesday)
        #expect(history.days.first?.day == "2026-08-31")
        #expect(history.days.last?.day == "2026-10-20")
        #expect(history.days.count == 7 * 7 + 2)
        #expect(history.today == "2026-10-20")
    }

    @Test func demoHistoryIsMadeUp() {
        let history = History.demo(now: Date(), calendar: calendar)
        #expect(history.days.count > 7 * 7)
        #expect(history.days.allSatisfy { $0.repositories.keys.allSatisfy { ["barnowl", "site", "dotfiles"].contains($0) } })
    }
}

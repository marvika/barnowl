import Foundation
import Testing
@testable import BarnOwl

struct KeepAwakeRuleTests {
    private var snapshot: ConditionSnapshot {
        ConditionSnapshot(runningBundles: ["com.docker.docker"], hasExternalDisplay: true, onAC: true,
                          batteryPercent: 80, microphoneInUse: false, downloading: false, weekday: 3,
                          minuteOfDay: 10 * 60)
    }

    @Test func allConditionsMustHold() {
        #expect(KeepAwakeRule(conditions: [.onPower, .externalDisplay]).holds(in: snapshot))
        #expect(!KeepAwakeRule(conditions: [.onPower, .microphoneInUse]).holds(in: snapshot))
    }

    @Test func disabledAndEmptyRulesNeverHold() {
        #expect(!KeepAwakeRule(conditions: [.onPower], isEnabled: false).holds(in: snapshot))
        #expect(!KeepAwakeRule(conditions: []).holds(in: snapshot))
    }

    @Test func appRunning() {
        #expect(RuleCondition.appRunning(bundleIdentifier: "com.docker.docker", name: "Docker").holds(in: snapshot))
        #expect(!RuleCondition.appRunning(bundleIdentifier: "com.microsoft.teams2", name: "Teams").holds(in: snapshot))
    }

    @Test func scheduleChecksDayAndTime() {
        let weekdays = RuleCondition.schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 8 * 60, endMinute: 17 * 60)
        #expect(weekdays.holds(in: snapshot))  // Tuesday 10:00
        var evening = snapshot
        evening.minuteOfDay = 18 * 60
        #expect(!weekdays.holds(in: evening))
        var sunday = snapshot
        sunday.weekday = 1
        #expect(!weekdays.holds(in: sunday))
    }

    @Test func scheduleCanCrossMidnight() {
        #expect(RuleCondition.minute(23 * 60, isWithin: 22 * 60, 2 * 60))
        #expect(RuleCondition.minute(60, isWithin: 22 * 60, 2 * 60))
        #expect(!RuleCondition.minute(12 * 60, isWithin: 22 * 60, 2 * 60))
    }

    /// Weeknights 22:00–02:00: Friday night runs into Saturday morning, and
    /// Sunday night isn't one of them.
    @Test func overnightSchedulesBelongToTheNightBefore() {
        let nights = RuleCondition.schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 22 * 60, endMinute: 2 * 60)
        func at(_ weekday: Int, _ hour: Int) -> ConditionSnapshot {
            var moment = snapshot
            moment.weekday = weekday
            moment.minuteOfDay = hour * 60
            return moment
        }
        #expect(nights.holds(in: at(7, 1)))   // Saturday 01:00
        #expect(!nights.holds(in: at(2, 1)))  // Monday 01:00
        #expect(nights.holds(in: at(3, 1)))   // Tuesday 01:00
        #expect(nights.holds(in: at(2, 23)))  // Monday 23:00
        #expect(!nights.holds(in: at(1, 23))) // Sunday 23:00
    }

    @Test func titlesReadNaturally() {
        #expect(KeepAwakeRule(conditions: [.onPower, .externalDisplay]).title
                == "On power adapter and an external display is connected")
        #expect(RuleCondition.externalDisplay.title == "An external display is connected")
        let schedule = RuleCondition.schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 8 * 60, endMinute: 17 * 60 + 30)
        #expect(schedule.title == "Weekdays 08:00–17:30")
    }

    @Test func rulesSurviveSaving() throws {
        let rule = KeepAwakeRule(conditions: [.appRunning(bundleIdentifier: "a", name: "A"),
                                              .schedule(weekdays: [1, 7], startMinute: 0, endMinute: 60)],
                                 allowDisplaySleep: true)
        let decoded = try JSONDecoder().decode(KeepAwakeRule.self, from: JSONEncoder().encode(rule))
        #expect(decoded == rule)
    }
}

struct ClosedLidModeTests {
    @Test func readsSleepDisabledFromPmset() {
        let on = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby 1\n"
        let off = "System-wide power settings:\n SleepDisabled\t\t0\n"
        #expect(ClosedLidMode.parse(on))
        #expect(!ClosedLidMode.parse(off))
        #expect(!ClosedLidMode.parse("Currently in use:\n sleep 1\n"))
    }

    /// The rule allows exactly the two pmset commands, for one account.
    @Test func ruleAllowsOnlyTheTwoCommands() throws {
        let rule = try #require(ClosedLidMode.rule(for: "marius.vika"))
        let lines = rule.split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(lines == ["marius.vika ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"])
    }

    /// A name sudoers could read as more than one account ("ALL", a group,
    /// a list, another rule) gets no rule at all.
    @Test(arguments: ["", "ALL", "%admin", "a b", "x,y", "root\nALL", "evil ALL=(ALL) NOPASSWD: ALL #", "1user", "bjørn"])
    func refusesNamesThatArentPlainAccountNames(name: String) {
        #expect(ClosedLidMode.rule(for: name) == nil)
    }

    @Test func ruleFileNameIsOneSudoReads() {
        // sudo skips files in sudoers.d whose names contain a dot or end in ~.
        let name = (ClosedLidMode.rulePath as NSString).lastPathComponent
        #expect(!name.contains(".") && !name.hasSuffix("~"))
        #expect(ClosedLidMode.rulePath.hasPrefix("/private/etc/sudoers.d/"))
    }
}

struct KeepAwakeStatusTests {
    @Test func longSessionsShowTheEndTime() {
        let now = Date(timeIntervalSince1970: 0)
        let status = KeepAwakeFormatter.status(for: .until(now.addingTimeInterval(5 * 3600)), now: now)
        #expect(status.hasPrefix("Awake until "))
        #expect(KeepAwakeFormatter.status(for: .whileDownloading) == "Awake until downloads finish")
    }
}

struct KeepAwakeExtendTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func addsToTheEndTime() {
        let session = KeepAwakeController.Session.until(now.addingTimeInterval(10 * 60))
        #expect(KeepAwakeController.extended(session, by: 30, now: now) == .until(now.addingTimeInterval(40 * 60)))
    }

    @Test func anExpiredSessionExtendsFromNow() {
        let session = KeepAwakeController.Session.until(now.addingTimeInterval(-60))
        #expect(KeepAwakeController.extended(session, by: 15, now: now) == .until(now.addingTimeInterval(15 * 60)))
    }

    @Test func untimedSessionsCantBeExtended() {
        #expect(KeepAwakeController.extended(.indefinite, by: 15, now: now) == nil)
        #expect(KeepAwakeController.extended(.whileDownloading, by: 15, now: now) == nil)
    }

    @Test(arguments: [(30.0, "1m"), (42 * 60.0, "42m"), (65 * 60.0, "1:05"), (8 * 3600.0, "8:00"), (0.0, "<1m")])
    func countdown(seconds: TimeInterval, text: String) {
        #expect(KeepAwakeFormatter.countdown(seconds) == text)
    }

    @Test func searchCanAddTime() {
        #expect(CommandParser.commands(for: "awake +30") == [.extendKeepAwake(minutes: 30)])
        #expect(CommandParser.commands(for: "awake +1h") == [.extendKeepAwake(minutes: 60)])
    }
}

struct KeepAwakeLimitsTests {
    /// "awake 99999999999999999999" used to crash: a typo is capped at a year.
    @Test(arguments: ["99999999999999999999", "99999999999999999999h", "525601"])
    func hugeDurationsAreCapped(word: String) throws {
        let minutes = try #require(CommandParser.duration(from: word))
        #expect(minutes <= KeepAwakeController.longestMinutes)
    }

    @Test func ordinaryDurationsAreUnchanged() {
        #expect(CommandParser.duration(from: "90") == 90)
        #expect(CommandParser.duration(from: "1.5h") == 90)
        #expect(CommandParser.duration(from: "forever") == 0)
    }

    @Test func extendingByAHugeAmountDoesntOverflow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let extended = KeepAwakeController.extended(.until(now), by: Int.max / 2, now: now)
        guard case .until(let end) = extended else { Issue.record("not extended"); return }
        #expect(end.timeIntervalSince(now) <= Double(KeepAwakeController.longestMinutes) * 60)
    }
}

struct SessionCarryOverTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func aSessionCarriesOverAnUpdate() {
        let session = KeepAwakeController.Session.until(now.addingTimeInterval(3600))
        let saved = KeepAwakeController.SavedSession(session: session, saved: now.addingTimeInterval(-30))
        #expect(KeepAwakeController.resumable(saved, now: now) == session)
    }

    @Test func oldOrFinishedSessionsDont() {
        let stale = KeepAwakeController.SavedSession(session: .indefinite, saved: now.addingTimeInterval(-3600))
        let over = KeepAwakeController.SavedSession(session: .until(now.addingTimeInterval(-1)), saved: now)
        #expect(KeepAwakeController.resumable(stale, now: now) == nil)
        #expect(KeepAwakeController.resumable(over, now: now) == nil)
    }

    @Test func sessionsSurviveBeingSaved() throws {
        let session = KeepAwakeController.Session.whileAppRunning(bundleIdentifier: "com.example", name: "Example")
        let data = try JSONEncoder().encode(KeepAwakeController.SavedSession(session: session, saved: now))
        #expect(try JSONDecoder().decode(KeepAwakeController.SavedSession.self, from: data).session == session)
    }
}

import Foundation
import Testing
@testable import Barkeep

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

    @Test func titlesReadNaturally() {
        #expect(KeepAwakeRule(conditions: [.onPower, .externalDisplay]).title
                == "On power adapter and An external display is connected")
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
}

struct KeepAwakeStatusTests {
    @Test func longSessionsShowTheEndTime() {
        let now = Date(timeIntervalSince1970: 0)
        let status = KeepAwakeFormatter.status(for: .until(now.addingTimeInterval(5 * 3600)), now: now)
        #expect(status.hasPrefix("Awake until "))
        #expect(KeepAwakeFormatter.status(for: .whileDownloading) == "Awake until downloads finish")
    }
}

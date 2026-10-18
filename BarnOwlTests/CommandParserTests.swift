import Foundation
import Testing
@testable import BarnOwl

struct CommandParserTests {
    @Test(arguments: [("2h", 120), ("90m", 90), ("45", 45), ("1.5h", 90), ("1,5h", 90), ("forever", 0)])
    func durations(word: String, minutes: Int) {
        #expect(CommandParser.duration(from: word) == minutes)
    }

    @Test func rejectsNonDurations() {
        #expect(CommandParser.duration(from: "dark") == nil)
        #expect(CommandParser.duration(from: "0") == nil)
    }

    @Test func awakeWithADurationStartsThatSession() {
        #expect(CommandParser.commands(for: "awake 2h").first == .keepAwake(minutes: 120))
        #expect(CommandParser.commands(for: "caff 30").first == .keepAwake(minutes: 30))
    }

    @Test func aUnitAfterASpaceStillCounts() {
        #expect(CommandParser.commands(for: "awake 2 h").first == .keepAwake(minutes: 120))
        #expect(CommandParser.commands(for: "awake 90 min").first == .keepAwake(minutes: 90))
        #expect(CommandParser.commands(for: "awake +1 h").first == .extendKeepAwake(minutes: 60))
        #expect(CommandParser.joiningUnits(["dark", "mode"]) == ["dark", "mode"])
    }

    @Test func linksReadDurationsLikeSearch() {
        let items = { (value: String) in [URLQueryItem(name: "minutes", value: value)] }
        #expect(AppDelegate.minutes(in: items("2h"), default: 0) == 120)
        #expect(AppDelegate.minutes(in: items("45"), default: 0) == 45)
        #expect(AppDelegate.minutes(in: nil, default: 15) == 15)
        // A typo must not mean "indefinitely".
        #expect(AppDelegate.minutes(in: items("2x"), default: 0) == nil)
    }

    @Test func awakeAloneOffersDurations() {
        let commands = CommandParser.commands(for: "awake")
        #expect(commands.prefix(3) == [.keepAwake(minutes: 60), .keepAwake(minutes: 120), .keepAwake(minutes: 0)])
        #expect(commands.contains(.stopKeepAwake))
    }

    @Test func findsTogglesByPrefix() {
        #expect(CommandParser.commands(for: "dar") == [.darkMode])
        #expect(CommandParser.commands(for: "mute").contains(.microphone))
        #expect(CommandParser.commands(for: "pres").contains(.presenter))
        #expect(CommandParser.commands(for: "arrange") == [.settings(.layout)])
    }

    @Test func singleLettersMatchNothing() {
        #expect(CommandParser.commands(for: "d").isEmpty)
        #expect(CommandParser.commands(for: "").isEmpty)
    }

    @Test func iconNamesAreNotCommands() {
        #expect(CommandParser.commands(for: "zscaler").isEmpty)
        #expect(CommandParser.commands(for: "onedrive").isEmpty)
    }
}

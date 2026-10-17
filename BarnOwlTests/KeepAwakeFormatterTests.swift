import Foundation
import Testing
@testable import BarnOwl

struct KeepAwakeFormatterTests {
    private static let cases: [(TimeInterval, String)] = [
        (30, "1 min"),
        (15 * 60, "15 min"),
        (59 * 60 + 1, "1 h"),
        (60 * 60, "1 h"),
        (80 * 60, "1 h 20 min"),
        (8 * 3600, "8 h"),
    ]

    @Test(arguments: cases)
    func remaining(interval: TimeInterval, expected: String) {
        #expect(KeepAwakeFormatter.remaining(interval) == expected)
    }

    @Test func statusForTimedSession() {
        let now = Date(timeIntervalSince1970: 0)
        let status = KeepAwakeFormatter.status(for: .until(now.addingTimeInterval(45 * 60)), now: now)
        #expect(status == "Awake for 45 min more")
    }

    @Test func durationLabels() {
        #expect(KeepAwakeFormatter.durationLabel(minutes: 0) == "Indefinitely")
        #expect(KeepAwakeFormatter.durationLabel(minutes: 120) == "2 h")
    }
}

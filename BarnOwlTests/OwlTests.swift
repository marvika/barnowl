import Foundation
import SwiftUI
import Testing
@testable import BarnOwl

struct OwlTests {
    @Test(arguments: ["#F5A633", "f5a633", "#fa3", "  #F5A633\n"])
    func readsColourCodes(text: String) {
        #expect(colourFromHex(text) != nil)
    }

    @Test(arguments: ["F5A63", "#GGGGGG", "hello", "#F5A633 is nice", ""])
    func ignoresOtherText(text: String) {
        #expect(colourFromHex(text) == nil)
    }

    @Test func shortCodesDoubleUp() {
        #expect(colourFromHex("#fa3") == colourFromHex("#ffaa33"))
    }

    @Test func moonPhases() {
        // A new moon (6 January 2000) and a full moon (21 January 2000, 04:40 UTC).
        let newMoon = Moon.phase(on: Date(timeIntervalSince1970: 947_182_440))
        let fullMoon = Moon.phase(on: Date(timeIntervalSince1970: 948_429_600))
        #expect(newMoon < 0.01 || newMoon > 0.99)
        #expect(abs(fullMoon - 0.5) < 0.03)
    }

    @Test func outfitsCombine() {
        let combined = OwlOutfit.headset + .coffee + .sunglasses
        #expect(combined == OwlOutfit(hat: .headset, eyewear: .shades, prop: .coffee))
        // The right-hand side wins where both have something.
        #expect((OwlOutfit.coffee + .thermos).prop == .thermos)
        #expect((OwlOutfit.thermos + .none).prop == .thermos)
    }

    @Test func everyMomentHasATitleAndHint() {
        for moment in OwlMoment.allCases {
            #expect(!moment.title.isEmpty)
            #expect(!moment.hint.isEmpty)
        }
    }
}

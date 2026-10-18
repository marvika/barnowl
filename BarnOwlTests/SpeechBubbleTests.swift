import SwiftUI
import Testing
@testable import BarnOwl

struct SpeechBubblePlacementTests {
    let bubble = CGSize(width: 80, height: 20)

    @Test func goesAboveAndRightWhenThereIsRoom() {
        let room = EdgeInsets(top: 60, leading: 20, bottom: 300, trailing: 400)
        #expect(BubblePlacement.best(for: bubble, owlSide: 46, room: room) == .aboveTrailing)
    }

    @Test func leansLeftAtTheRightEdge() {
        let room = EdgeInsets(top: 60, leading: 300, bottom: 300, trailing: 10)
        #expect(BubblePlacement.best(for: bubble, owlSide: 46, room: room) == .aboveLeading)
    }

    /// The Perch's corner owl: its head touches the top of the window and
    /// it sits at the right-hand end.
    @Test func goesBesideTheHeadWithNoRoomAbove() {
        let room = EdgeInsets(top: 1, leading: 338, bottom: 170, trailing: 36)
        #expect(BubblePlacement.best(for: bubble, owlSide: 30, room: room) == .leading)
        let roomRight = EdgeInsets(top: 1, leading: 10, bottom: 170, trailing: 300)
        #expect(BubblePlacement.best(for: bubble, owlSide: 30, room: roomRight) == .trailing)
    }

    @Test func keepsTheUsualPlaceWithoutAWindow() {
        #expect(BubblePlacement.best(for: bubble, owlSide: 46, room: nil) == .aboveTrailing)
    }

    @Test func longerTextIsWider() {
        let short = SpeechBubble.size(of: "Hoo!", fontSize: 10)
        let long = SpeechBubble.size(of: "I didn't see that!", fontSize: 10)
        #expect(long.width > short.width * 2)
        #expect(short.height == long.height)
    }
}

struct SpeechBubbleOriginTests {
    let bubble = CGSize(width: 80, height: 20)
    let side: CGFloat = 46

    @Test func aboveSitsOverTheHead() {
        for placement in [BubblePlacement.aboveTrailing, .aboveLeading] {
            let origin = placement.origin(for: bubble, owlSide: side)
            // The box ends above the owl; only the tail reaches down to the head.
            #expect(origin.y + bubble.height <= 0)
        }
    }

    @Test func besideStaysClearOfTheOwl() {
        #expect(BubblePlacement.trailing.origin(for: bubble, owlSide: side).x > side)
        #expect(BubblePlacement.leading.origin(for: bubble, owlSide: side).x + bubble.width < 0)
    }

    @Test func leaningMirrorsAroundTheOwl() {
        let right = BubblePlacement.aboveTrailing.origin(for: bubble, owlSide: side)
        let left = BubblePlacement.aboveLeading.origin(for: bubble, owlSide: side)
        #expect(abs((right.x + left.x + bubble.width) - side) < 0.001)
    }
}

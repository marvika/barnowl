import AppKit
import SwiftUI

/// Where the owl's speech bubble goes. It sits above the owl's head so it
/// doesn't cover text beside the owl, and moves to wherever its window has
/// room, so a window edge never cuts it off.
enum BubblePlacement: Equatable {
    /// Above the head, leaning right.
    case aboveTrailing
    /// Above the head, leaning left.
    case aboveLeading
    /// Right of the head.
    case trailing
    /// Left of the head.
    case leading

    /// How far the bubble's inner edge sits from the owl's leading or
    /// trailing edge, as a fraction of the owl's size.
    static let overhang: CGFloat = 0.6
    /// The middle of the owl's head, as a fraction of its size from the top.
    static let headHeight: CGFloat = 0.3

    /// The first placement in reading order that fits in `room`, the space
    /// between the owl and its window's edges. With no room anywhere (or no
    /// window yet), the usual one.
    static func best(for bubble: CGSize, owlSide side: CGFloat, room: EdgeInsets?) -> BubblePlacement {
        guard let room else { return .aboveTrailing }
        let tail = BubbleShape.tailLength(for: bubble.height)
        let sticksOut = bubble.width - side * (1 - overhang)
        let aboveFits = room.top >= bubble.height + tail - side * 0.1
        let besideFitsVertically = room.top >= bubble.height / 2 - side * headHeight
        let besideNeeds = bubble.width + tail + side * 0.04
        if aboveFits, room.trailing >= sticksOut { return .aboveTrailing }
        if aboveFits, room.leading >= sticksOut { return .aboveLeading }
        if besideFitsVertically, room.trailing >= besideNeeds { return .trailing }
        if besideFitsVertically, room.leading >= besideNeeds { return .leading }
        return .aboveTrailing
    }

    /// Where the bubble's top leading corner goes, from the owl's top
    /// leading corner, for an owl `side` points square.
    func origin(for bubble: CGSize, owlSide side: CGFloat) -> CGPoint {
        let tail = BubbleShape.tailLength(for: bubble.height)
        let gap = side * 0.04
        // Above: the tail's tip just reaches the top of the head.
        let aboveY = side * 0.1 - tail - bubble.height
        let besideY = side * Self.headHeight - bubble.height / 2
        switch self {
        case .aboveTrailing: return CGPoint(x: side * Self.overhang, y: aboveY)
        case .aboveLeading: return CGPoint(x: side * (1 - Self.overhang) - bubble.width, y: aboveY)
        case .trailing: return CGPoint(x: side + gap + tail, y: besideY)
        case .leading: return CGPoint(x: -(gap + tail + bubble.width), y: besideY)
        }
    }

    var tilt: Double {
        switch self {
        case .aboveTrailing: -5
        case .aboveLeading: 5
        case .trailing: -3
        case .leading: 3
        }
    }

    /// The corner the bubble grows from as it appears.
    var growsFrom: UnitPoint {
        switch self {
        case .aboveTrailing: .bottomLeading
        case .aboveLeading: .bottomTrailing
        case .trailing: .leading
        case .leading: .trailing
        }
    }
}

/// A small speech bubble with a tail pointing back at the owl.
struct SpeechBubble: View {
    let text: String
    let fontSize: CGFloat
    var placement: BubblePlacement = .aboveTrailing

    /// The bubble's size before it's drawn, to choose where it fits.
    nonisolated static func size(of text: String, fontSize: CGFloat) -> CGSize {
        let descriptor = NSFont.systemFont(ofSize: fontSize, weight: .heavy).fontDescriptor.withDesign(.rounded)
        let font = descriptor.flatMap { NSFont(descriptor: $0, size: fontSize) } ?? .systemFont(ofSize: fontSize, weight: .heavy)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(textSize.width) + fontSize * 1.2, height: ceil(textSize.height) + fontSize * 0.64)
    }

    var body: some View {
        let size = Self.size(of: text, fontSize: fontSize)
        Text(text)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(Brand.indigoDeep)
            .lineLimit(1)
            .fixedSize()
            .frame(width: size.width, height: size.height)
            .background(BubbleShape(placement: placement, cornerRadius: fontSize * 0.6).fill(Brand.cream))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .rotationEffect(.degrees(placement.tilt))
    }
}

/// A rounded box with a tail on the side that faces the owl.
struct BubbleShape: Shape {
    let placement: BubblePlacement
    let cornerRadius: CGFloat

    /// How far the tail reaches out of the box.
    static func tailLength(for height: CGFloat) -> CGFloat { height * 0.28 }

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let length = Self.tailLength(for: rect.height)
        let base = rect.height * 0.32
        var tail = Path()
        switch placement {
        case .aboveTrailing:
            let x = rect.minX + cornerRadius
            tail.move(to: CGPoint(x: x, y: rect.maxY - 1))
            tail.addLine(to: CGPoint(x: x + base, y: rect.maxY - 1))
            tail.addLine(to: CGPoint(x: x - base * 0.4, y: rect.maxY + length))
        case .aboveLeading:
            let x = rect.maxX - cornerRadius
            tail.move(to: CGPoint(x: x, y: rect.maxY - 1))
            tail.addLine(to: CGPoint(x: x - base, y: rect.maxY - 1))
            tail.addLine(to: CGPoint(x: x + base * 0.4, y: rect.maxY + length))
        case .trailing:
            tail.move(to: CGPoint(x: rect.minX + 1, y: rect.midY - base / 2))
            tail.addLine(to: CGPoint(x: rect.minX + 1, y: rect.midY + base / 2))
            tail.addLine(to: CGPoint(x: rect.minX - length, y: rect.midY + base * 0.4))
        case .leading:
            tail.move(to: CGPoint(x: rect.maxX - 1, y: rect.midY - base / 2))
            tail.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY + base / 2))
            tail.addLine(to: CGPoint(x: rect.maxX + length, y: rect.midY + base * 0.4))
        }
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}

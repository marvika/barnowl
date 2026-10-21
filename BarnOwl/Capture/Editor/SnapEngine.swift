import CoreGraphics

/// A line shown while something snaps into line with something else.
struct SnapGuide: Equatable, Sendable {
    enum Axis: Sendable {
        /// A vertical line at x = `position`.
        case vertical
        /// A horizontal line at y = `position`.
        case horizontal
    }

    let axis: Axis
    let position: CGFloat
    /// Where the line starts and ends along its length.
    let from: CGFloat
    let to: CGFloat
}

/// Lines up marks being moved with the image's edges and centre, and with other marks.
enum SnapEngine {
    /// How far to shift `moving` so one of its edges or its centre meets a target's, within
    /// `threshold`, and the guides to show. Each axis snaps on its own.
    static func snap(_ moving: CGRect, to targets: [CGRect], threshold: CGFloat) -> (offset: CGPoint, guides: [SnapGuide]) {
        let movingX: [CGFloat] = [moving.minX, moving.midX, moving.maxX]
        let movingY: [CGFloat] = [moving.minY, moving.midY, moving.maxY]
        var bestX: (gap: CGFloat, delta: CGFloat)?
        var bestY: (gap: CGFloat, delta: CGFloat)?
        for target in targets {
            let targetX: [CGFloat] = [target.minX, target.midX, target.maxX]
            let targetY: [CGFloat] = [target.minY, target.midY, target.maxY]
            for a in movingX {
                for b in targetX {
                    let gap: CGFloat = abs(b - a)
                    if gap <= threshold, gap < (bestX?.gap ?? .infinity) { bestX = (gap, b - a) }
                }
            }
            for a in movingY {
                for b in targetY {
                    let gap: CGFloat = abs(b - a)
                    if gap <= threshold, gap < (bestY?.gap ?? .infinity) { bestY = (gap, b - a) }
                }
            }
        }
        let dx: CGFloat = bestX?.delta ?? 0
        let dy: CGFloat = bestY?.delta ?? 0
        let moved = moving.offsetBy(dx: dx, dy: dy)
        var guides: [SnapGuide] = []
        if bestX != nil {
            guides += lines(moved, targets, vertical: true)
        }
        if bestY != nil {
            guides += lines(moved, targets, vertical: false)
        }
        return (CGPoint(x: dx, y: dy), guides)
    }

    /// Every line where the moved rectangle now meets a target exactly.
    private static func lines(_ moved: CGRect, _ targets: [CGRect], vertical: Bool) -> [SnapGuide] {
        var guides: [SnapGuide] = []
        let ours: [CGFloat] = vertical ? [moved.minX, moved.midX, moved.maxX] : [moved.minY, moved.midY, moved.maxY]
        for target in targets {
            let theirs: [CGFloat] = vertical ? [target.minX, target.midX, target.maxX] : [target.minY, target.midY, target.maxY]
            for value in ours where theirs.contains(where: { abs($0 - value) < 0.5 }) {
                let union = moved.union(target)
                let from: CGFloat = vertical ? union.minY : union.minX
                let to: CGFloat = vertical ? union.maxY : union.maxX
                let axis: SnapGuide.Axis = vertical ? .vertical : .horizontal
                let guide = SnapGuide(axis: axis, position: value, from: from, to: to)
                if !guides.contains(guide) { guides.append(guide) }
            }
        }
        return guides
    }
}

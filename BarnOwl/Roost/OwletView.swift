import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Whether owlets may animate here: only on a visible surface, with the
    /// owl allowed to move, and not in Low Power Mode.
    @Entry var owletsMove = false
}

/// An owlet in one of its poses, animated a frame at a time.
struct OwletSprite: View {
    let sprite: String
    var palette = "golden"
    /// Points per sprite pixel. Whole numbers keep it crisp on any display.
    var scale: CGFloat = 1
    /// Different owlets start their loops at different moments.
    var seed = 0
    var animated = true
    @Environment(\.owletsMove) private var moves

    var body: some View {
        let art = OwletArt.states[sprite] ?? OwletArt.states["idle"] ?? (frames: [], seconds: 1)
        OwletFrames(name: "state:\(sprite)", frames: art.frames, seconds: art.seconds, width: OwletArt.width,
                    height: OwletArt.height, palette: palette, scale: scale, seed: seed, animated: animated && moves)
    }
}

/// A 16 x 16 owlet, for rows and small spaces.
struct OwletIcon: View {
    let icon: String
    var palette = "golden"
    var scale: CGFloat = 1
    var seed = 0
    var animated = true
    @Environment(\.owletsMove) private var moves

    var body: some View {
        let art = OwletArt.icons[icon] ?? OwletArt.icons["nap"] ?? (frames: [], seconds: 1)
        OwletFrames(name: "icon:\(icon)", frames: art.frames, seconds: art.seconds, width: OwletArt.iconSize,
                    height: OwletArt.iconSize, palette: palette, scale: scale, seed: seed, animated: animated && moves)
    }
}

private struct OwletFrames: View {
    let name: String
    let frames: [String]
    let seconds: Double
    let width: Int
    let height: Int
    let palette: String
    let scale: CGFloat
    let seed: Int
    let animated: Bool

    var body: some View {
        Group {
            if animated, frames.count > 1 {
                let step = seconds / Double(frames.count)
                TimelineView(.periodic(from: .now, by: step)) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate / step) + Int(seed.magnitude % UInt(frames.count))
                    frame(at: tick % frames.count)
                }
            } else {
                frame(at: 0)
            }
        }
        .frame(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frame(at index: Int) -> some View {
        if frames.indices.contains(index),
           let image = OwletRenderer.image(frames[index], name: "\(name):\(index)", width: width, height: height,
                                           palette: palette) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
        }
    }
}

/// The branch owlets perch on: the sprites' own bottom two rows (bark over
/// its outline), drawn once along the whole width.
struct OwletBranch: View {
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: 0x8C5A3C)).frame(height: scale)
            Rectangle().fill(Color(hex: 0x4A2C1E)).frame(height: scale)
        }
        .frame(height: 2 * scale)
        .accessibilityHidden(true)
    }
}

/// Puts a one-colour owlet beside the menu bar owl.
@MainActor
enum OwletBadge {
    /// The owl, then one plain owlet while agents are out, with a small dot
    /// above it when one needs you.
    static func compose(_ owl: NSImage, owlet name: String?) -> NSImage {
        guard let name, let owlet = OwletRenderer.template("search") else { return owl }
        let dot = name == "needs"
        let gap: CGFloat = 2
        let size = NSSize(width: owl.size.width + gap + owlet.size.width + (dot ? 2 : 0),
                          height: max(owl.size.height, owlet.size.height))
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .none
            owl.draw(in: NSRect(x: 0, y: (rect.height - owl.size.height) / 2, width: owl.size.width, height: owl.size.height))
            owlet.draw(in: NSRect(x: owl.size.width + gap, y: 0, width: owlet.size.width, height: owlet.size.height))
            if dot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

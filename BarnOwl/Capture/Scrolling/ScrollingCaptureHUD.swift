import AppKit
import SwiftUI

/// What the scrolling HUD shows.
@MainActor
@Observable
final class ScrollingHUDModel {
    enum Hint: Equatable {
        case ready, slower, above, auto, end, limit, needsAccess

        var text: String {
            switch self {
            case .ready: "Scroll down slowly"
            case .slower: "Scroll a little slower"
            case .above: "Scroll down to carry on"
            case .auto: "Scrolling · move the pointer to stop"
            case .end: "That's the end of the page"
            case .limit: "That's the limit for one picture"
            case .needsAccess: "Auto-Scroll needs Accessibility"
            }
        }

        var isWarning: Bool { self == .slower || self == .limit || self == .needsAccess }
    }

    /// The picture's height so far, in pixels.
    var height = 0
    /// The bottom of the picture, small.
    var preview: CGImage?
    var hint = Hint.ready
    var isAutoScrolling = false
    var canAutoScroll = true
    var isFull = false
}

/// The glass bar beside the area: the strip, the height, and what to do.
struct ScrollingCaptureHUD: View {
    let model: ScrollingHUDModel
    let autoScroll: () -> Void
    let done: () -> Void
    let cancel: () -> Void
    /// Off only for offscreen previews, where glass doesn't draw: a flat stand-in instead.
    var glass = true

    var body: some View {
        if glass {
            // Over the app you're scrolling, Barn Owl isn't active: floating glass stays legible.
            bar.captureGlass(in: .rect(cornerRadius: 18), floating: true)
                .environment(\.colorScheme, .dark)
                .fixedSize()
        } else {
            bar.background(Brand.indigoDeep.opacity(0.84), in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
                .environment(\.colorScheme, .dark)
                .fixedSize()
        }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            PreviewStrip(image: model.preview)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(model.height.formatted())
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(model.height)))
                        .animation(.snappy(duration: 0.2), value: model.height)
                    Text("px").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 5) {
                    if model.hint.isWarning {
                        Circle().fill(Brand.amber).frame(width: 6, height: 6)
                    }
                    Text(model.hint.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            // Wide enough for the longest hint, so the bar never changes size.
            .frame(width: 200, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: 4) {
                HUDButton(title: model.isAutoScrolling ? "Stop" : "Auto-Scroll",
                          symbol: model.isAutoScrolling ? "pause.fill" : "play.fill",
                          widest: "Auto-Scroll", action: autoScroll)
                    .disabled(model.isFull)
                    .help(model.canAutoScroll ? "Barn Owl scrolls for you, to the end"
                                              : "Auto-Scroll needs Accessibility access for Barn Owl")
                HUDButton(title: "Done", symbol: "checkmark", key: "↩", prominent: true, action: done)
                    .help("Keep the picture (Return)")
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
                .accessibilityLabel("Cancel")
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .padding(.vertical, 7)
    }

    /// The bottom of the picture as it grows: it fills from the top, then follows the end.
    private struct PreviewStrip: View {
        let image: CGImage?

        var body: some View {
            ZStack(alignment: .top) {
                Rectangle().fill(.white.opacity(0.08))
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .frame(width: 30)
                        .transaction { $0.animation = nil }
                }
            }
            .frame(width: 30, height: 44)
            .clipShape(.rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.22), lineWidth: 0.5) }
            .accessibilityHidden(true)
        }
    }

    private struct HUDButton: View {
        let title: String
        let symbol: String
        var key: String?
        var prominent = false
        /// The longest title it ever has, so it keeps one width.
        var widest: String?
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(action: action) {
                ZStack {
                    if let widest { label(widest).hidden() }
                    label(title)
                }
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(background, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(PressableStyle())
            .onHover { hovering = $0 }
        }

        private func label(_ title: String) -> some View {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)
                Text(title).font(.system(size: 13, weight: .semibold))
                if let key {
                    Text(key)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.white.opacity(prominent ? 0.22 : 0.1), in: .rect(cornerRadius: 4))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }

        private var background: AnyShapeStyle {
            if prominent { return AnyShapeStyle(Brand.lavenderFill.opacity(hovering ? 1 : 0.94)) }
            return AnyShapeStyle(.white.opacity(hovering && isEnabled ? 0.22 : 0.12))
        }
    }
}

/// Holds the HUD: floats over the app you're scrolling and never becomes key,
/// so the keyboard and the scrolling stay with that app.
final class ScrollingHUDPanel: NSPanel {
    init(model: ScrollingHUDModel, autoScroll: @escaping () -> Void, done: @escaping () -> Void,
         cancel: @escaping () -> Void) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let root = ScrollingCaptureHUD(model: model, autoScroll: autoScroll, done: done, cancel: cancel)
        let host = FirstClickHostingView(rootView: root.padding(Self.margin))
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
        setContentSize(host.fittingSize)
    }

    /// Clear space around the bar, for its glass edge and shadow.
    static let margin: CGFloat = 14
    /// From the area's edge to the bar.
    static let gap: CGFloat = 10

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Just below the area, or above it when there's no room, or inside its bottom edge
    /// when it fills the screen. The panel never covers the area itself.
    func place(beside area: CGRect, within visible: CGRect) {
        let size = frame.size
        let inset = Self.gap - Self.margin
        var origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - inset - size.height)
        if origin.y < visible.minY {
            origin.y = area.maxY + inset
            if origin.y + size.height > visible.maxY { origin.y = max(visible.minY, area.minY + 16 - Self.margin) }
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        setFrameOrigin(origin)
    }

    func show() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; animator().alphaValue = 1 }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; animator().alphaValue = 0 }, completionHandler: {
            MainActor.assumeIsolated { self.close() }
        })
    }
}

/// A thin lavender ring just outside the area: what's being captured. Clicks and
/// scrolling go straight through it.
final class ScrollingBorderPanel: NSPanel {
    static let outset: CGFloat = 3

    init(around area: CGRect) {
        let frame = area.insetBy(dx: -Self.outset, dy: -Self.outset)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        contentView = RingView(frame: CGRect(origin: .zero, size: frame.size))
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }

    func show() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; animator().alphaValue = 1 }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; animator().alphaValue = 0 }, completionHandler: {
            MainActor.assumeIsolated { self.close() }
        })
    }

    final class RingView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let outset = ScrollingBorderPanel.outset
            // A dark hairline outside keeps the ring visible on light and dark pages alike.
            let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            outer.lineWidth = 1
            NSColor.black.withAlphaComponent(0.22).setStroke()
            outer.stroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: outset / 2 + 0.25, dy: outset / 2 + 0.25),
                                    xRadius: 3, yRadius: 3)
            ring.lineWidth = 1.5
            NSColor(Brand.lavender).setStroke()
            ring.stroke()
        }
    }
}

/// Buttons answer the first click, though the panel is never key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

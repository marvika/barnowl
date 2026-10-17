import AppKit
import SwiftUI

/// A borderless panel that floats above the menu bar and can take keyboard
/// focus, for the Perch and search.
final class FloatingPanel: NSPanel {
    /// Transparent room around a panel's content for its shadow.
    static let shadowInset: CGFloat = 20

    var onCancel: (() -> Void)?
    /// Called whenever the content changes size, so the owner can keep the
    /// panel anchored (SwiftUI grows it from the bottom-left corner otherwise).
    var onResize: ((FloatingPanel) -> Void)?
    private var resizeObserver: NSObjectProtocol?

    init<Content: View>(rootView: Content) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        // The window shadow would outline the whole (larger, transparent)
        // frame; panels draw their own shadow around the glass instead.
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = [.preferredContentSize]
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = .clear
        contentViewController = controller
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onResize?(self)
            }
        }
    }

    /// Puts the panel's top edge just under the menu bar, centred on `x` (or
    /// right-aligned to it), kept on screen.
    func place(under anchor: NSRect, alignRight: Bool = false) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main else { return }
        let size = frame.size
        // The content has transparent room around it for the shadow.
        let inset = Self.shadowInset
        var x = alignRight ? anchor.maxX - size.width + inset : anchor.midX - size.width / 2
        x = min(max(x, screen.frame.minX + 4 - inset), screen.frame.maxX - size.width - 4 + inset)
        setFrameOrigin(NSPoint(x: x, y: screen.visibleFrame.maxY - size.height + inset - 4))
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Closes a panel when the user clicks anywhere outside it.
@MainActor
final class OutsideClickMonitor {
    private var monitor: Any?

    func start(_ handler: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            // Barn Owl's own clicks, when it moves or opens icons, aren't you
            // clicking elsewhere.
            guard !SyntheticEvents.isMarked(event) else { return }
            MainActor.assumeIsolated { handler() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Lays out views in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var rowSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// An item's picture, or its app's icon when there's no capture yet.
struct ItemImage: View {
    let item: MenuBarItem
    let image: NSImage?
    /// Wide items (text, counters) are scaled down to this width if set.
    var maxWidth: CGFloat?

    var body: some View {
        if let image {
            let scale = min(1, (maxWidth ?? .infinity) / max(image.size.width, 1))
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
        } else {
            Image(nsImage: Self.appIcon(for: item))
                .resizable()
                .frame(width: 18, height: 18)
                .padding(.horizontal, 6)
                .frame(height: 24)
        }
    }

    static func appIcon(for item: MenuBarItem) -> NSImage {
        NSRunningApplication(processIdentifier: item.pid)?.icon
            ?? NSWorkspace.shared.icon(for: .application)
    }
}

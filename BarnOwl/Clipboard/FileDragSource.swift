import AppKit
import SwiftUI

/// Drags files out of the Nest through AppKit, which (unlike SwiftUI's
/// `.draggable`) reports whether the drop landed, so the Nest can let go of
/// files once you've taken them somewhere.
struct FileDragSource: NSViewRepresentable {
    let urls: () -> [URL]
    /// Called once the files were dropped somewhere outside Barn Owl.
    let takenOut: ([URL]) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView(urls: urls, takenOut: takenOut)
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.urls = urls
        view.takenOut = takenOut
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var urls: () -> [URL]
    var takenOut: ([URL]) -> Void
    private var mouseDownEvent: NSEvent?
    private var draggedFiles: [URL] = []

    /// The view behind the drag in progress. The session doesn't keep its
    /// source alive, and the Nest may tuck its tiles away mid-drag.
    private static var dragging: DragSourceView?
    /// Set when one of Barn Owl's own drop targets takes the files, so
    /// dropping a file back on the Nest doesn't take it out.
    private static var landedInBarnOwl = false

    init(urls: @escaping () -> [URL], takenOut: @escaping ([URL]) -> Void) {
        self.urls = urls
        self.takenOut = takenOut
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Barn Owl's drop targets call this when they receive files.
    static func noteDropInBarnOwl() {
        if dragging != nil { landedInBarnOwl = true }
    }

    // The Nest's panel never becomes key, so the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownEvent = nil
        let files = urls()
        guard !files.isEmpty else { return }
        let origin = convert(start, from: nil)
        let items = files.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            // A small fanned stack when dragging several.
            let offset = CGFloat(index) * 6
            item.setDraggingFrame(NSRect(x: origin.x - 24 + offset, y: origin.y - 24 - offset, width: 48, height: 48),
                                  contents: icon)
            return item
        }
        draggedFiles = files
        Self.dragging = self
        Self.landedInBarnOwl = false
        let session = beginDraggingSession(with: items, event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Other apps decide: Finder moves within a disk and copies across.
        context == .outsideApplication ? [.copy, .move, .link, .generic, .delete] : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer {
            Self.dragging = nil
            Self.landedInBarnOwl = false
        }
        guard operation != [], !Self.landedInBarnOwl else { return }
        takenOut(draggedFiles)
    }
}

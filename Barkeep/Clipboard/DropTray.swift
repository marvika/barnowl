import AppKit
import Observation
import SwiftUI

/// A tray under the notch that appears whenever you drag files, holds what
/// you drop on it, and lets you drag the files out again later.
@MainActor
@Observable
final class DropTray {
    enum Mode: Equatable {
        case hidden
        /// A file drag is in progress: big drop target, plus what's held.
        case receiving
        /// Opened by hovering or clicking the tab: drag files out.
        case open
        /// Idle while holding files: a small tab under the notch.
        case tab
    }

    private(set) var mode = Mode.hidden
    var isTargeted = false

    @ObservationIgnored let clipboard: ClipboardHistory
    @ObservationIgnored private var panel: FloatingPanel?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var dragChangeCount = 0
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var hovering = false
    @ObservationIgnored private let outsideClicks = OutsideClickMonitor()

    init(clipboard: ClipboardHistory) {
        self.clipboard = clipboard
    }

    func start() {
        // Drags happen in other apps, so global monitors: a mouse-down marks
        // the drag pasteboard's state, and a drag that changes it with file
        // URLs is a file drag.
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }) { monitors.append(down) }
        if let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }) { monitors.append(dragged) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }) { monitors.append(up) }
        settle()
    }

    private func mouseDown() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
    }

    private func mouseDragged() {
        guard Preferences.dropTrayEnabled, mode != .receiving else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount,
              pasteboard.types?.contains(.fileURL) == true else { return }
        dragChangeCount = pasteboard.changeCount
        set(.receiving)
    }

    private func mouseUp() {
        guard mode == .receiving else { return }
        // Let the drop land first, then step back.
        collapseLater(after: 1.2)
    }

    /// Files dropped on the tray.
    func receive(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        clipboard.addToShelf(files)
        collapseLater(after: 1.5)
    }

    func hover(_ inside: Bool) {
        hovering = inside
        if inside {
            collapseTask?.cancel()
            if mode == .tab { set(.open) }
        } else if mode == .open {
            collapseLater(after: 1.5)
        }
    }

    func toggleOpen() {
        set(mode == .open ? .tab : .open)
    }

    func clear() {
        clipboard.clearShelf()
        settle()
    }

    func remove(_ url: URL) {
        clipboard.removeFromShelf(url)
        if clipboard.shelf.isEmpty { settle() }
    }

    private func collapseLater(after seconds: Double) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.hovering else { return }
            self.settle()
        }
    }

    /// After a settings change: update the resting state, but never in the
    /// middle of a drag or while open.
    func refresh() {
        if mode == .hidden || mode == .tab { settle() }
    }

    /// Back to rest: a tab if something's held (and the tab is wanted), else nothing.
    func settle() {
        isTargeted = false
        let showTab = Preferences.dropTrayEnabled && Preferences.dropTrayTab && !clipboard.shelf.isEmpty
        set(showTab ? .tab : .hidden)
    }

    private func set(_ newMode: Mode) {
        mode = newMode
        if newMode == .hidden {
            outsideClicks.stop()
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        if newMode == .open {
            outsideClicks.start { [weak self] in
                guard let self, self.mode == .open else { return }
                self.settle()
            }
        } else {
            outsideClicks.stop()
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(rootView: DropTrayView(tray: self))
        panel.level = .statusBar
        panel.onResize = { [weak self] in self?.place($0) }
        return panel
    }

    /// Centred under the notch (or the middle of the menu bar), just below it.
    private func place(_ panel: FloatingPanel) {
        guard let screen = NSScreen.screens.first else { return }
        let centre = NotchGeometry.of(screen).map { ($0.minX + $0.maxX) / 2 } ?? screen.frame.midX
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: centre - size.width / 2, y: screen.visibleFrame.maxY - size.height + 6))
    }
}

struct DropTrayView: View {
    let tray: DropTray

    private var files: [URL] { tray.clipboard.shelf }

    var body: some View {
        Group {
            switch tray.mode {
            case .hidden: EmptyView()
            case .tab: tab
            case .receiving, .open: expanded
            }
        }
        .onHover { tray.hover($0) }
        .padding(6)
        .animation(.spring(duration: 0.3), value: tray.mode)
    }

    private var tab: some View {
        Button { tray.toggleOpen() } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                Text("\(files.count) \(files.count == 1 ? "file" : "files")")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .glassEffect(.regular, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Your shelf: click or hover to drag files out")
        .accessibilityLabel("Shelf, \(files.count) files")
    }

    private var expanded: some View {
        VStack(spacing: 8) {
            if tray.mode == .receiving {
                HStack(spacing: 8) {
                    Image(systemName: tray.isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.title2)
                        .symbolEffect(.bounce, value: tray.isTargeted)
                    Text(tray.isTargeted ? "Let go to keep it here" : "Drop here to hold for later")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(tray.isTargeted ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06),
                            in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tray.isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            }
            if !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(files, id: \.self) { url in
                            ShelfTile(url: url) { tray.remove(url) }
                        }
                    }
                }
                .frame(height: 104)
                HStack {
                    Text("Drag files out to use them").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { tray.clear() }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
        .padding(12)
        .frame(width: files.isEmpty ? 300 : min(CGFloat(files.count) * 104 + 24, 560))
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .dropDestination(for: URL.self) { urls, _ in
            tray.receive(urls)
            return true
        } isTargeted: { tray.isTargeted = $0 }
    }
}

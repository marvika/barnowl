import SwiftUI
import UniformTypeIdentifiers

/// Clipboard history and the shelf, in one panel.
struct ClipboardView: View {
    let clipboard: ClipboardHistory
    let paste: (ClipEntry) -> Void
    let close: () -> Void

    enum Tab: String, CaseIterable { case history = "Clipboard", shelf = "Nest" }

    @State private var tab = Tab.history
    @State private var query = ""
    @State private var selection = 0
    @State private var confirmingClear = false
    @FocusState private var focused: Bool

    private var results: [ClipEntry] {
        let words = query.lowercased().split(separator: " ")
        let sorted = clipboard.entries.filter(\.isPinned) + clipboard.entries.filter { !$0.isPinned }
        guard !words.isEmpty else { return sorted }
        return sorted.filter { entry in words.allSatisfy { entry.preview.lowercased().contains($0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                WatchingOwl(snores: false, cue: clipboard.owlCue)
                    .frame(width: 24, height: 24)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Spacer()
                if tab == .history ? !clipboard.entries.isEmpty : !clipboard.shelf.isEmpty {
                    Button("Clear…", systemImage: "trash") { confirmingClear = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(12)
            .confirmationDialog(tab == .history ? "Clear clipboard history?" : "Empty the Nest?",
                                isPresented: $confirmingClear) {
                Button(tab == .history ? "Clear History" : "Empty Nest", role: .destructive) {
                    if tab == .history { clipboard.clear() } else { clipboard.clearShelf() }
                }
            } message: {
                Text(tab == .history ? "Pinned items stay." : "The files themselves stay where they are.")
            }
            Divider()
            if tab == .history { history } else { shelf }
        }
        .frame(width: 460)
        .owlPanel()
        .task {
            // Just copied a password or a colour? The owl reacts once you look.
            try? await Task.sleep(for: .milliseconds(500))
            if Date().timeIntervalSince(clipboard.lastSecretSkipped) < 30 {
                clipboard.owlCue = OwlCue(.didntSee)
            } else if let newest = clipboard.entries.first, Date().timeIntervalSince(newest.date) < 30,
                      let text = newest.text, let colour = colourFromHex(text) {
                clipboard.owlCue = OwlCue(.colour(colour))
            }
        }
        .padding(FloatingPanel.shadowInset)
        .onAppear { focused = true }
    }

    // MARK: History

    private var history: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if results.indices.contains(selection) { paste(results[selection]) } }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onChange(of: query) { selection = 0 }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if results.isEmpty {
                Label {
                    Text(clipboard.entries.isEmpty ? "Things you copy show up here." : "Hoo? Nothing matches “\(query)”")
                } icon: {
                    WatchingOwl(eyesOpen: !clipboard.entries.isEmpty, snores: false).frame(width: 24, height: 24)
                }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                                ClipRow(entry: entry, selected: index == selection)
                                    .id(entry.id)
                                    .onTapGesture { paste(entry) }
                                    .accessibilityAddTraits(index == selection ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityAction { paste(entry) }
                                    .contextMenu {
                                        Button("Paste") { paste(entry) }
                                        Button("Copy") { clipboard.copy(entry); close() }
                                        Button(entry.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(entry) }
                                        Divider()
                                        Button("Delete") { clipboard.delete(entry) }
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: min(CGFloat(results.count) * 46 + 12, 380))
                    .onChange(of: selection) { _, new in
                        if results.indices.contains(new) { proxy.scrollTo(results[new].id) }
                    }
                }
            }
            Text("Return pastes into the app you were using · right-click for more")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 10)
        }
        // Rows move when one is pinned, deleted or copied: keep the same one selected.
        .onChange(of: results.map(\.id)) { old, new in
            if old.indices.contains(selection), let index = new.firstIndex(of: old[selection]) {
                selection = index
            } else {
                selection = max(0, min(selection, new.count - 1))
            }
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    // MARK: Shelf

    @State private var dropTargeted = false

    private var shelf: some View {
        VStack(spacing: 10) {
            if clipboard.shelf.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Drop files in the nest").font(.headline)
                    Text("Then drag them out wherever you need them.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8), count: 4), spacing: 10) {
                        ForEach(clipboard.shelf, id: \.self) { url in
                            ShelfTile(url: url, remove: { clipboard.removeFromShelf(url) }, takenOut: { urls in
                                if !Preferences.nestKeepsDraggedFiles { clipboard.removeFromShelf(urls) }
                            })
                        }
                    }
                    .padding(10)
                }
                .frame(height: min(CGFloat((clipboard.shelf.count + 3) / 4) * 112 + 20, 360))
            }
        }
        .background(dropTargeted ? Brand.accent.opacity(0.15) : .clear, in: .rect(cornerRadius: Theme.cardRadius))
        .padding(8)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            if !files.isEmpty { DragSourceView.noteDropInBarnOwl() }
            clipboard.addToShelf(files)
            return !files.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }
}

private struct ClipRow: View {
    let entry: ClipEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if entry.kind == .image, let data = entry.image, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: entry.symbol).foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview).lineLimit(2).font(.callout)
                Text([entry.sourceApp, entry.date.formatted(.relative(presentation: .named))]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if entry.isPinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .background(selected ? Brand.accent.opacity(0.25) : .clear, in: .rect(cornerRadius: Theme.rowRadius))
        .contentShape(.rect)
    }
}

struct ShelfTile: View {
    let url: URL
    let remove: () -> Void
    /// The file was dragged out and dropped somewhere.
    let takenOut: ([URL]) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 48, height: 48)
            Text(url.lastPathComponent).font(.caption).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(width: 96, height: 100)
        .background(Color.primary.opacity(hovering ? 0.1 : 0.04), in: .rect(cornerRadius: 10))
        .overlay(FileDragSource(urls: { [url] }, takenOut: takenOut))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove from the nest")
            }
        }
        // The button above shows on hover only; VoiceOver gets it as an action.
        .accessibilityAction(named: "Remove from the nest", remove)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}

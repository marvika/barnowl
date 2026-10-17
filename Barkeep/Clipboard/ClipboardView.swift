import SwiftUI
import UniformTypeIdentifiers

/// Clipboard history and the shelf, in one panel.
struct ClipboardView: View {
    let clipboard: ClipboardHistory
    let paste: (ClipEntry) -> Void
    let close: () -> Void

    enum Tab: String, CaseIterable { case history = "Clipboard", shelf = "Shelf" }

    @State private var tab = Tab.history
    @State private var query = ""
    @State private var selection = 0
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
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Spacer()
                if tab == .history, !clipboard.entries.isEmpty {
                    Button("Clear") { clipboard.clear() }.buttonStyle(.borderless)
                } else if tab == .shelf, !clipboard.shelf.isEmpty {
                    Button("Clear") { clipboard.clearShelf() }.buttonStyle(.borderless)
                }
            }
            .padding(12)
            Divider()
            if tab == .history { history } else { shelf }
        }
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(10)
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
                Text(clipboard.entries.isEmpty ? "Things you copy show up here." : "Nothing matches “\(query)”")
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
                    Text("Drop files here to park them").font(.headline)
                    Text("Then drag them out wherever you need them.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8), count: 4), spacing: 10) {
                        ForEach(clipboard.shelf, id: \.self) { url in
                            ShelfTile(url: url) { clipboard.removeFromShelf(url) }
                        }
                    }
                    .padding(10)
                }
                .frame(height: min(CGFloat((clipboard.shelf.count + 3) / 4) * 112 + 20, 360))
            }
        }
        .background(dropTargeted ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 12))
        .padding(8)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
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
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }
}

struct ShelfTile: View {
    let url: URL
    let remove: () -> Void
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
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove from shelf")
            }
        }
        .onHover { hovering = $0 }
        .draggable(url)
        .help(url.path)
    }
}

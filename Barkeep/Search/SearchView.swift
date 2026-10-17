import SwiftUI

/// Spotlight-style search over every menu bar item.
struct SearchView: View {
    let model: AppModel
    let open: (MenuBarItem) -> Void
    let close: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    /// Hidden icons first (they're the ones you can't see), nearest the arrow first.
    private var results: [MenuBarItem] {
        let ordered = model.scanner.items.reversed().sorted { ($0.section == .visible ? 1 : 0) < ($1.section == .visible ? 1 : 0) }
        return ItemSearch.filter(ordered, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField("Search the menu bar", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit(openSelection)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onChange(of: query) { selection = 0 }
            }
            .padding(14)

            if !model.accessibilityTrusted {
                Divider()
                PermissionCallout(symbol: "accessibility", color: .blue, title: "Allow Accessibility",
                                  message: "Barkeep needs it to list and open menu bar icons.",
                                  action: { AccessibilityInventory.requestTrust() })
                    .padding(14)
            } else if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == selection)
                                    .id(item.id)
                                    .onTapGesture { open(item) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: min(CGFloat(results.count) * 40 + 12, 340))
                    .onChange(of: selection) { _, new in
                        if results.indices.contains(new) { proxy.scrollTo(results[new].id) }
                    }
                }
            } else if !query.isEmpty {
                Divider()
                Text("No menu bar icon matches “\(query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
        }
        .frame(width: 560)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(10)
        .onAppear {
            query = ""
            selection = 0
            focused = true
        }
    }

    private func row(_ item: MenuBarItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            ItemImage(item: item, image: model.images.image(for: item), maxWidth: 40)
                .frame(width: 48, height: 30)
                .background(.black.opacity(0.25), in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).fontWeight(.medium)
                if let detail = item.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(badge(for: item))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }

    private func badge(for item: MenuBarItem) -> String {
        if item.isBehindNotch { return "Behind notch" }
        switch item.section {
        case .visible: return "Visible"
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always hidden"
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    private func openSelection() {
        guard results.indices.contains(selection) else { return }
        open(results[selection])
    }
}

import KeyboardShortcuts
import SwiftUI

/// The Perch: hidden icons in a strip under the menu bar.
struct PerchView: View {
    let model: AppModel
    let open: (MenuBarItem) -> Void
    let close: () -> Void

    private var scanner: ItemScanner { model.scanner }
    private var hidden: [MenuBarItem] { model.layout.items(in: .hidden) }
    private var alwaysHidden: [MenuBarItem] { model.layout.items(in: .alwaysHidden) }
    private var behindNotch: [MenuBarItem] { scanner.items.filter(\.isBehindNotch) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.accessibilityTrusted {
                PermissionCallout(
                    symbol: "accessibility", color: .blue,
                    title: "Allow Accessibility",
                    message: "Barn Owl needs it to find your hidden icons and open them.",
                    action: { AccessibilityInventory.requestTrust() })
            } else if hidden.isEmpty && alwaysHidden.isEmpty && behindNotch.isEmpty {
                emptyState
            } else {
                group("Behind the notch", behindNotch)
                group("Hidden", hidden)
                group("Always hidden", alwaysHidden)
                if !model.screenRecordingAllowed {
                    Button {
                        ItemImageCache.requestPermission()
                    } label: {
                        Label("Show real icons: allow Screen Recording", systemImage: "rectangle.dashed.badge.record")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            footer
        }
        .padding(12)
        .frame(minWidth: 280, maxWidth: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .owlPanel()
        .overlay(alignment: .topTrailing) {
            // Perched in the corner, watching the icon you point at. It stays
            // below the menu bar: the Perch sits just under it, and anything
            // higher gets cut off when the menu bar draws on top.
            if model.accessibilityTrusted, !(hidden.isEmpty && alwaysHidden.isEmpty && behindNotch.isEmpty) {
                WatchingOwl(snores: false)
                    .frame(width: 30, height: 30)
                    .offset(x: -12, y: -3)
            }
        }
        .padding(FloatingPanel.shadowInset)
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [MenuBarItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                FlowLayout(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                        ItemTile(item: item, image: model.images.image(for: item), position: position) { open(item) }
                            .contextMenu { ItemContextMenu(model: model, item: item) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            WatchingOwl(eyesOpen: false, accessory: .nightcap)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing on the perch yet").font(.headline)
                Text("Drag icons into Hidden in Settings → Layout, or ⌘-drag them left of the | divider.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(4)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            FooterButton(title: "Search", symbol: "magnifyingglass",
                         hint: KeyboardShortcuts.getShortcut(for: .searchItems)?.description) {
                close()
                model.showSearch()
            }
            FooterButton(title: "Arrange", symbol: "hand.draw") {
                close()
                model.showSettings(.layout)
            }
            Spacer()
            FooterButton(title: nil, symbol: "gearshape") {
                close()
                model.showSettings()
            }
            .help("Barn Owl Settings")
            .accessibilityLabel("Barn Owl Settings")
        }
    }
}

struct ItemTile: View {
    let item: MenuBarItem
    let image: NSImage?
    var position = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ItemImage(item: item, image: image)
                .padding(.horizontal, 2)
                .frame(minWidth: 28, minHeight: 28)
                .background(hovering ? Color.primary.opacity(0.12) : .clear, in: .rect(cornerRadius: Theme.rowRadius))
                .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .arrives(after: min(Double(position) * 0.025, 0.3))
        .onHover { hovering = $0 }
        .help(item.displayName)
        .accessibilityLabel(item.displayName)
    }
}

private struct FooterButton: View {
    let title: String?
    let symbol: String
    var hint: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                if let title { Text(title) }
                if let hint { Text(hint).foregroundStyle(.tertiary) }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hovering ? Color.primary.opacity(0.1) : .clear, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
    }
}

struct PermissionCallout: View {
    let symbol: String
    let color: Color
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, color: color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Allow…", action: action).buttonStyle(.glassProminent)
        }
    }
}

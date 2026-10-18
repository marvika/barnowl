import SwiftUI

/// A System Settings–style icon: a white symbol on a coloured rounded square.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.27))
    }
}

/// A row label with an icon badge, used in setup and Settings forms.
struct BadgeLabel: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small drawing of the right half of a menu bar, showing how the dividers
/// split it. Used to explain hiding without words.
struct MenuBarDiagram: View {
    var collapsed: Bool
    var showsAlwaysHidden = false

    private let alwaysHiddenIcons = ["externaldrive", "printer"]
    private let hiddenIcons = ["shield.lefthalf.filled", "network", "cloud", "shippingbox"]
    private let visibleIcons = ["camera.viewfinder"]
    private let systemIcons = ["wifi", "battery.75percent"]

    var body: some View {
        HStack(spacing: 10) {
            // App menus, so the drawing reads as a menu bar at a glance.
            Image(systemName: "apple.logo").font(.system(size: 12))
            Text("Finder").font(.system(size: 12, weight: .bold))
            Text("File   Edit   View").font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(1).layoutPriority(-1)
            Spacer(minLength: 12)
            if !collapsed {
                if showsAlwaysHidden {
                    icons(alwaysHiddenIcons).opacity(0.35)
                    divider("ellipsis", rotated: true)
                }
                icons(hiddenIcons)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                divider("line.diagonal", rotated: false)
            }
            icons(visibleIcons)
            Image(nsImage: MenuBarOwl.image(openness: collapsed ? 0 : 1, height: 15))
                .renderingMode(.template)
            Image(systemName: collapsed ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Brand.accent)
                .frame(width: 22, height: 20)
                .background(Brand.accent.opacity(0.15), in: .rect(cornerRadius: 5))
                .contentTransition(.symbolEffect(.replace))
            icons(systemIcons)
            Text("Fri 9:41").font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.rowRadius).strokeBorder(.separator))
        .animation(.spring(duration: 0.45), value: collapsed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collapsed ? "Menu bar with icons hidden" : "Menu bar with all icons showing")
    }

    private func icons(_ names: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(names, id: \.self) { Image(systemName: $0).font(.system(size: 12)) }
        }
    }

    private func divider(_ symbol: String, rotated: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11))
            .rotationEffect(.degrees(rotated ? 90 : 0))
            .foregroundStyle(.secondary)
    }
}

/// The app's mark: the owl against the dusk sky, as in the app icon.
struct AppMark: View {
    var size: CGFloat = 72

    var body: some View {
        AppIconArtwork()
            .frame(width: size * 1.24, height: size * 1.24)
            .frame(width: size, height: size)
    }
}

/// A rounded group of rows that lines up with surrounding text, unlike a
/// grouped Form, which insets itself.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.leading, 46) }
                    row.padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: Theme.cardRadius))
    }
}

/// A card row: badge and text on the left, a control on the right.
struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let color: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            BadgeLabel(title: title, subtitle: subtitle, symbol: symbol, color: color)
            Spacer(minLength: 16)
            trailing
        }
    }
}

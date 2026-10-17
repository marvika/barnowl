import AppKit
import SwiftUI

enum Permission {
    case accessibility
    case screenRecording

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    var reason: String {
        switch self {
        case .accessibility: "Finds your hidden icons and opens them from the Barkeep Bar and search."
        case .screenRecording: "Shows real pictures of hidden icons. Without it, Barkeep shows app icons."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    var color: Color {
        switch self {
        case .accessibility: .blue
        case .screenRecording: .red
        }
    }

    @MainActor
    func isGranted(_ model: AppModel) -> Bool {
        switch self {
        case .accessibility: model.accessibilityTrusted
        case .screenRecording: model.screenRecordingAllowed
        }
    }

    @MainActor
    func request() {
        switch self {
        case .accessibility: AccessibilityInventory.requestTrust()
        case .screenRecording: ItemImageCache.requestPermission()
        }
    }
}

/// A permission with its status, a button to grant it, and, for Screen
/// Recording, which macOS only applies after a restart, a relaunch button.
struct PermissionRow: View {
    let permission: Permission
    let model: AppModel
    @State private var requested = false

    private var subtitle: String {
        guard requested, !permission.isGranted(model) else { return permission.reason }
        switch permission {
        case .accessibility:
            return "Turn on Barkeep in System Settings → Privacy & Security → Accessibility."
        case .screenRecording:
            return "Turn on Barkeep under Screen & System Audio Recording, then relaunch Barkeep."
        }
    }

    var body: some View {
        CardRow(title: permission.title, subtitle: subtitle, symbol: permission.symbol,
                color: permission.color) {
            if permission.isGranted(model) {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else if requested && permission == .screenRecording {
                Button("Relaunch Barkeep") { Relaunch.now() }
            } else {
                Button("Allow…") {
                    requested = true
                    permission.request()
                }
            }
        }
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

enum Relaunch {
    @MainActor
    static func now() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

/// Three side-by-side choices for where hidden icons appear.
struct HiddenIconsDisplayPicker: View {
    @Binding var selection: HiddenIconsDisplay

    var body: some View {
        HStack(spacing: 10) {
            choice(.automatic, symbol: "wand.and.sparkles",
                   caption: "Menu bar when there's room, Barkeep Bar when there isn't.")
            choice(.menuBar, symbol: "menubar.rectangle", caption: "Icons slide back into the menu bar.")
            choice(.barkeepBar, symbol: "rectangle.topthird.inset.filled",
                   caption: "Icons appear in a strip under the menu bar.")
        }
        // Equal heights, sized to the tallest caption rather than the window.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func choice(_ value: HiddenIconsDisplay, symbol: String, caption: String) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(value.title).fontWeight(.semibold)
                Text(caption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(selected ? 0.9 : 0.5), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

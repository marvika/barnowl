import SwiftUI

/// What the canvas's corners show: the zoom and the output's size.
@MainActor
@Observable
final class CanvasViewState {
    var zoom: CGFloat = 1
    var outputSize = CGSize.zero
}

/// Bottom trailing: zoom out, the zoom level with its menu, zoom in.
struct ZoomCapsule: View {
    let state: CanvasViewState
    let zoom: (ZoomRequest) -> Void

    enum ZoomRequest {
        case zoomIn, zoomOut, fit, actual, percent(CGFloat)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { zoom(.zoomOut) } label: {
                Image(systemName: "minus.magnifyingglass").frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .help("Zoom Out (⌘−)")
            .accessibilityLabel("Zoom Out")
            Menu {
                Button("Zoom to Fit") { zoom(.fit) }.keyboardShortcut("9", modifiers: .command)
                Button("Actual Size") { zoom(.actual) }.keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("50%") { zoom(.percent(0.5)) }
                Button("100%") { zoom(.percent(1)) }
                Button("200%") { zoom(.percent(2)) }
            } label: {
                HStack(spacing: 3) {
                    Text(verbatim: "\(Int((state.zoom * 100).rounded()))%")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .frame(minWidth: 48)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Zoom")
            .accessibilityLabel("Zoom \(Int((state.zoom * 100).rounded())) percent")
            Button { zoom(.zoomIn) } label: {
                Image(systemName: "plus.magnifyingglass").frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .help("Zoom In (⌘+)")
            .accessibilityLabel("Zoom In")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .frame(height: 28)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Bottom leading: how big the result is, in pixels.
struct SizeReadout: View {
    let state: CanvasViewState

    var body: some View {
        Text(verbatim: "\(Int(state.outputSize.width)) × \(Int(state.outputSize.height)) px")
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .glassEffect(.regular, in: .capsule)
            .accessibilityLabel("\(Int(state.outputSize.width)) by \(Int(state.outputSize.height)) pixels")
    }
}

/// Bottom centre: a line about the tool, its first few times; or a passing note.
struct HintStrip: View {
    let model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = model.transientHint ?? toolHint
        ZStack {
            if let text {
                Text(text)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity)
                    .id(text)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: text)
    }

    private var toolHint: String? {
        guard model.editingText == nil, model.review == nil, model.showsToolHint(model.tool) else { return nil }
        // Select with nothing selected has its hint in the options bar already.
        if model.tool == .select, model.selection.isEmpty { return nil }
        return Self.hint(model.tool)
    }

    static func hint(_ tool: EditorTool) -> String {
        switch tool {
        case .select: "⌥-drag duplicates · ⌘-drag skips snapping · Tab picks the next mark"
        case .arrow: "Drag to draw · ⇧ keeps 45° · drag the middle to bend"
        case .rectangle: "Drag to draw · click text or a window to fit it · ⇧ for a square"
        case .ellipse: "Drag to draw · click text or a window to fit it · ⇧ for a circle"
        case .text: "Click to type · Return adds a line · Esc finishes"
        case .counter: "Click to number · type to add a label · drag to point"
        case .highlighter: "Click a line of text · drag across words"
        case .pen: "Draw freely"
        case .redact: "Drag to hide · click a word to hide it · ⇧B finds private info"
        case .spotlight: "Drag to light up an area · click text or a window to fit it"
        case .crop: "Drag the edges · Return crops · Esc cancels"
        }
    }
}

/// Top centre, below the toolbar: a key or token is visible, perhaps with other private things.
/// It speaks as the capture card does, and hides the same things.
struct SecretBanner: View {
    let model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .foregroundStyle(Brand.amber)
                .accessibilityHidden(true)
            Text(model.privateSentence)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Button(model.hidePrivateTitle) { model.hidePrivate() }
                .buttonStyle(AmberButtonStyle())
                .help(model.privateCount == 1 ? "Hide it in what you copy and save" : "Hide them in what you copy and save")
            Button("Review") { model.beginReview() }
                .help("See everything private before hiding it (⇧B)")
            Button {
                model.secretBannerDismissed = true
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Leave them visible")
            .accessibilityLabel("Dismiss")
        }
        .controlSize(.small)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Hiding private things: amber with a deep indigo label, as on the capture card.
struct AmberButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Brand.indigoDeep)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Brand.amber.opacity(configuration.isPressed ? 0.8 : 1), in: .capsule)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(.capsule)
    }
}

/// The ? sheet: every key, grouped as Tools, Colour & Size, Marks and Finish.
struct ShortcutsSheet: View {
    let dismiss: () -> Void

    struct Row: Hashable {
        let title: String
        let keys: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts").font(.system(size: 15, weight: .semibold))
            HStack(alignment: .top, spacing: 28) {
                column(.tools)
                VStack(alignment: .leading, spacing: 16) {
                    column(.colourAndSize)
                    column(.marks)
                }
                column(.finish)
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640)
    }

    private func column(_ group: EditorCommand.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(Self.rows(group), id: \.self) { row in
                HStack {
                    Text(row.title).font(.system(size: 12))
                    Spacer(minLength: 16)
                    Text(verbatim: row.keys).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 190, alignment: .leading)
    }

    @MainActor static func rows(_ group: EditorCommand.Group) -> [Row] {
        var rows = EditorCommand.all.filter { $0.group == group && !$0.keyLabel.isEmpty }.map { command in
            switch command.id {
            case .done: Row(title: "Done, even while typing", keys: command.keyLabel)
            case .smaller: Row(title: command.title, keys: "[ or −")
            case .bigger: Row(title: command.title, keys: "] or +")
            default: Row(title: command.title, keys: command.keyLabel)
            }
        }
        switch group {
        case .colourAndSize:
            rows.insert(Row(title: "Colours", keys: "1 – 8"), at: 0)
        case .marks:
            rows += [
                Row(title: "Duplicate while dragging", keys: "⌥ drag"),
                Row(title: "Move", keys: "← → ↑ ↓"),
                Row(title: "Move further", keys: "⇧ arrows"),
                Row(title: "Next mark", keys: "Tab"),
                Row(title: "Delete", keys: "⌫"),
                Row(title: "No snapping", keys: "⌘ drag"),
            ]
        case .finish:
            rows.insert(Row(title: "Done", keys: "↩"), at: 0)
            rows += [Row(title: "Step back", keys: "Esc"), Row(title: "Close, keeping changes", keys: "⌘W")]
        case .tools:
            rows += [Row(title: "Pan", keys: "Space drag")]
        }
        return rows
    }
}

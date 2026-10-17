import SwiftUI
import UniformTypeIdentifiers

/// Drag icons between rows to arrange the real menu bar.
struct LayoutEditorView: View {
    let model: AppModel
    /// Setup shows only the two main rows.
    var compact = false

    @AppStorage(PrefKey.alwaysHiddenEnabled) private var alwaysHiddenEnabled = false
    @State private var editingGroup: MenuBarGroup?

    private var layout: LayoutController { model.layout }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.accessibilityTrusted {
                Card { PermissionRow(permission: .accessibility, model: model) }
            }
            LayoutRowView(model: model, row: .visible, title: "Menu bar",
                          subtitle: "Always visible next to the clock.", symbol: "menubar.rectangle", color: .blue)
            LayoutRowView(model: model, row: .hidden, title: "Hidden",
                          subtitle: "Shown when you click the arrow or open the Barkeep Bar.",
                          symbol: "eye.slash.fill", color: .gray)
            if !compact {
                if alwaysHiddenEnabled || !model.groups.groups.isEmpty {
                    LayoutRowView(model: model, row: .alwaysHidden, title: "Always hidden",
                                  subtitle: "Only shown with option-click or search.",
                                  symbol: "eye.trianglebadge.exclamationmark.fill", color: .indigo)
                }
                ForEach(model.groups.groups) { group in
                    LayoutRowView(model: model, row: .group(group.id), title: group.name,
                                  subtitle: "A group icon in the menu bar opens these.",
                                  symbol: group.symbol, color: .orange) {
                        Button("Edit") { editingGroup = group }
                    }
                }
                Button {
                    editingGroup = MenuBarGroup(name: "", symbol: MenuBarGroup.symbolChoices[0])
                } label: {
                    Label("New Group", systemImage: "plus.circle.fill")
                }
                .controlSize(.large)
            }
            if let error = layout.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .overlay(alignment: .topTrailing) {
            if layout.isBusy {
                ProgressView().controlSize(.small).padding(6)
            }
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorSheet(model: model, group: group)
        }
        .task {
            model.refreshPermissions()
            model.scanner.refresh()
        }
    }
}

/// One row: a header and a wrapping strip of icon chips that accepts drops.
struct LayoutRowView<Accessory: View>: View {
    let model: AppModel
    let row: LayoutRow
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    @ViewBuilder var accessory: Accessory
    @State private var targeted = false

    init(model: AppModel, row: LayoutRow, title: String, subtitle: String, symbol: String, color: Color,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.model = model
        self.row = row
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.color = color
        self.accessory = accessory()
    }

    private var items: [MenuBarItem] {
        let items = model.layout.items(in: row)
        // The menu bar row reads right to left from the clock in real life;
        // keep left-to-right here so it matches what you see.
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BadgeLabel(title: title, subtitle: subtitle, symbol: symbol, color: color)
                Spacer()
                accessory
            }
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(items) { item in
                    ItemChip(model: model, item: item, row: row)
                }
                if items.isEmpty {
                    Text("Drop icons here")
                        .font(.callout).foregroundStyle(.tertiary)
                        .frame(height: 52)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(8)
            .background(targeted ? color.opacity(0.18) : Color.primary.opacity(0.04), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? color : .clear, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            .dropDestination(for: String.self) { keys, _ in
                guard let key = keys.first else { return false }
                Task { await model.layout.place(key, in: row) }
                return true
            } isTargeted: { targeted = $0 }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

/// An icon in the editor: its menu bar picture on a menu bar–like background,
/// with its name underneath. Drop another icon on it to put that one before it.
private struct ItemChip: View {
    let model: AppModel
    let item: MenuBarItem
    let row: LayoutRow
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 3) {
            ItemImage(item: item, image: model.images.image(for: item), maxWidth: 56)
                .frame(minWidth: 40, minHeight: 28)
                .padding(.horizontal, 4)
                .background(.black.opacity(0.55), in: .rect(cornerRadius: 7))
                .overlay(alignment: .topTrailing) {
                    if !item.isMovable {
                        Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                            .padding(3)
                    } else if model.watcher.isWatching(item.key) {
                        Image(systemName: "bell.fill").font(.system(size: 8)).foregroundStyle(.orange)
                            .padding(3)
                            .help("Shown for a while when it changes")
                    }
                }
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .frame(maxWidth: 64)
                .foregroundStyle(.secondary)
        }
        .padding(4)
        .overlay(alignment: .leading) {
            if targeted {
                Capsule().fill(Color.accentColor).frame(width: 3).offset(x: -4)
            }
        }
        .opacity(item.isMovable ? 1 : 0.55)
        .help(item.isMovable ? item.displayName : "\(item.name) can't be moved")
        .accessibilityLabel(item.displayName)
        .modifier(DraggableIf(enabled: item.isMovable, key: item.key))
        .dropDestination(for: String.self) { keys, _ in
            guard let key = keys.first, key != item.key else { return false }
            Task { await model.layout.place(key, in: row, before: item.key) }
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu { ItemContextMenu(model: model, item: item) }
    }
}

private struct DraggableIf: ViewModifier {
    let enabled: Bool
    let key: String

    func body(content: Content) -> some View {
        if enabled { content.draggable(key) } else { content }
    }
}

/// Moves for one icon, shared by the editor and the Barkeep Bar.
struct ItemContextMenu: View {
    let model: AppModel
    let item: MenuBarItem

    var body: some View {
        let current = model.layout.row(of: item)
        if item.isMovable {
            if current != .visible {
                Button("Always Show in Menu Bar") { Task { await model.layout.place(item.key, in: .visible) } }
            }
            if current != .hidden {
                Button("Hide") { Task { await model.layout.place(item.key, in: .hidden) } }
            }
            if current != .alwaysHidden {
                Button("Always Hide") { Task { await model.layout.place(item.key, in: .alwaysHidden) } }
            }
            if !model.groups.groups.isEmpty {
                Menu("Move to Group") {
                    ForEach(model.groups.groups) { group in
                        Button(group.name) { Task { await model.layout.place(item.key, in: .group(group.id)) } }
                            .disabled(current == .group(group.id))
                    }
                }
            }
            Divider()
            Button("Replace Icon…") { model.iconToReplace = item }
            Toggle("Show When It Changes", isOn: Binding(
                get: { model.watcher.isWatching(item.key) },
                set: { model.watcher.setWatching(item.key, $0) }))
        } else {
            Text("macOS keeps \(item.name) in place")
        }
    }
}

/// Create or edit a group: a name and an icon.
private struct GroupEditorSheet: View {
    let model: AppModel
    @State var group: MenuBarGroup
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !model.groups.groups.contains { $0.id == group.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Group" : "Edit Group").font(.title2.bold())
            TextField("Name, for example Work", text: $group.name)
                .textFieldStyle(.roundedBorder)
            Text("Icon").font(.headline)
            TextField("Or show text or an emoji instead", text: Binding(
                get: { group.label ?? "" }, set: { group.label = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 6), spacing: 8) {
                ForEach(MenuBarGroup.symbolChoices, id: \.self) { symbol in
                    Button {
                        group.symbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(group.symbol == symbol ? Color.accentColor.opacity(0.3) : .clear,
                                        in: .rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(group.symbol == symbol ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
            if !isNew && group.memberKeys.count == 1 {
                Toggle("Clicking opens the icon's menu directly", isOn: $group.opensDirectly)
            }
            if isNew {
                Text("The group gets its own icon in the menu bar. Drag icons into its row to add them.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !isNew {
                    Button("Delete Group", role: .destructive) {
                        Task { await model.deleteGroup(group.id) }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    let name = group.name.trimmingCharacters(in: .whitespaces)
                    group.name = name.isEmpty ? "Group" : name
                    if isNew {
                        Task { await model.createGroup(name: group.name, symbol: group.symbol, label: group.label) }
                    } else {
                        model.groups.update(group)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

/// Pick a symbol, text or emoji to show instead of an app's own icon.
struct CustomIconSheet: View {
    let model: AppModel
    let item: MenuBarItem
    @State private var symbol = "star.fill"
    @State private var label = ""
    @Environment(\.dismiss) private var dismiss

    private static let symbols = MenuBarGroup.symbolChoices + [
        "lock.shield.fill", "network.badge.shield.half.filled", "icloud.fill", "externaldrive.fill",
        "camera.fill", "mic.fill", "envelope.fill", "calendar", "terminal.fill", "shippingbox.fill",
        "person.crop.circle", "globe",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ItemImage(item: item, image: model.images.image(for: item), maxWidth: 40)
                    .padding(4)
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 7))
                VStack(alignment: .leading) {
                    Text("Replace \(item.name)'s icon").font(.title3.bold())
                    Text("Your icon opens \(item.name)'s menu; the original stays hidden.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 8), spacing: 8) {
                ForEach(Self.symbols, id: \.self) { name in
                    Button {
                        symbol = name
                        label = ""
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(symbol == name && label.isEmpty ? Color.accentColor.opacity(0.3) : .clear,
                                        in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
            }
            TextField("Or type text or an emoji, like VPN or 🛡️", text: $label)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Replace Icon") {
                    Task { await model.setCustomIcon(for: item, symbol: symbol, label: label) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

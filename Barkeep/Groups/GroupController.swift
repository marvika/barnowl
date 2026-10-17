import AppKit
import SwiftUI

/// Puts one status item in the menu bar per group. Clicking it opens a strip
/// with the group's icons; the members themselves wait in the always-hidden
/// section.
@MainActor
final class GroupController {
    private let model: AppModel
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var panel: FloatingPanel?
    private var openGroup: UUID?
    private let outsideClicks = OutsideClickMonitor()

    init(model: AppModel) {
        self.model = model
    }

    /// Creates or removes status items so there's one per group.
    func sync() {
        let groups = model.groups.groups
        for (id, item) in statusItems where !groups.contains(where: { $0.id == id }) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems[id] = nil
        }
        for group in groups {
            let item = statusItems[group.id] ?? makeItem(for: group)
            statusItems[group.id] = item
            item.button?.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.name)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            item.button?.toolTip = group.name
        }
    }

    func windowID(of group: UUID) -> CGWindowID? {
        StatusItems.windowID(of: statusItems[group])
    }

    var allWindowIDs: Set<CGWindowID> { Set(statusItems.values.compactMap { StatusItems.windowID(of: $0) }) }

    private func makeItem(for group: MenuBarGroup) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BarkeepGroup-\(group.id.uuidString)"
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.identifier = NSUserInterfaceItemIdentifier(group.id.uuidString)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            model.showSettings(.layout)
            return
        }
        if openGroup == id, panel?.isVisible == true {
            close()
        } else {
            show(id, under: sender.window?.frame)
        }
    }

    func show(_ id: UUID, under anchor: NSRect?) {
        close()
        model.refreshPermissions()
        model.scanner.refresh()
        let view = GroupPanelView(model: model, groupID: id, open: { [weak self] item in
            self?.close()
            self?.model.opener.open(item, near: self?.windowID(of: id))
        }, close: { [weak self] in self?.close() })
        let panel = FloatingPanel(rootView: view)
        panel.onCancel = { [weak self] in self?.close() }
        if let anchor {
            panel.onResize = { $0.place(under: anchor) }
            panel.layoutIfNeeded()
            panel.place(under: anchor)
        }
        panel.orderFrontRegardless()
        self.panel = panel
        openGroup = id
        outsideClicks.start { [weak self] in self?.close() }
    }

    func close() {
        outsideClicks.stop()
        panel?.orderOut(nil)
        panel = nil
        openGroup = nil
    }
}

private struct GroupPanelView: View {
    let model: AppModel
    let groupID: UUID
    let open: (MenuBarItem) -> Void
    let close: () -> Void

    private var group: MenuBarGroup? { model.groups.groups.first { $0.id == groupID } }

    private var members: [MenuBarItem] {
        guard let group else { return [] }
        let byKey = Dictionary(model.scanner.items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return group.memberKeys.compactMap { byKey[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: group?.symbol ?? "folder")
                Text(group?.name ?? "Group").font(.headline)
                Spacer()
                Button {
                    close()
                    model.showSettings(.layout)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Edit groups")
                .accessibilityLabel("Edit groups")
            }
            if members.isEmpty {
                Text("This group is empty. Drag icons into it in Barkeep Settings → Layout.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 2) {
                    ForEach(members) { item in
                        ItemTile(item: item, image: model.images.image(for: item)) { open(item) }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200, maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(8)
    }
}

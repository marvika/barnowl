import SwiftUI

/// Spotlight-style search over every menu bar item.
struct SearchView: View {
    let model: AppModel
    let open: (MenuBarItem) -> Void
    let run: (AppCommand) -> Void
    let close: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private enum Result: Identifiable {
        case command(AppCommand)
        case item(MenuBarItem)

        var id: String {
            switch self {
            case .command(let command): "command-\(command.title)"
            case .item(let item): "item-\(item.windowID)"
            }
        }
    }

    /// Commands first, then icons: hidden ones first (they're the ones you
    /// can't see), nearest the arrow first.
    @State private var owlCue: OwlCue?
    @State private var foundFor = ""

    /// Little tricks: "hoot" and "dance", and a hop when exactly one thing matches.
    private func cueOwl() {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        switch text {
        case "hoot", "hoo": owlCue = OwlCue(.hoot)
        case "dance": owlCue = OwlCue(.dance)
        default:
            if !text.isEmpty, results.count == 1, foundFor != text {
                foundFor = text
                owlCue = OwlCue(.found)
            }
        }
    }

    private var results: [Result] {
        let commands = CommandParser.commands(for: query).prefix(5).map(Result.command)
        let ordered = model.scanner.items.reversed().sorted { ($0.section == .visible ? 1 : 0) < ($1.section == .visible ? 1 : 0) }
        return commands + ItemSearch.filter(ordered, query: query).map(Result.item)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField("Search icons, or type a command like “awake 2h”", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit(openSelection)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onChange(of: query) {
                        selection = 0
                        cueOwl()
                    }
                // Watches whichever result is selected.
                WatchingOwl(lookAt: CGVector(dx: -0.5, dy: min(1, 0.3 + CGFloat(selection) * 0.25)),
                            playful: false, snores: false, cue: owlCue)
                    .frame(width: 28, height: 28)
            }
            .padding(14)

            if !model.accessibilityTrusted {
                Divider()
                PermissionCallout(symbol: "accessibility", color: .blue, title: "Allow Accessibility",
                                  message: "Barn Owl needs it to list and open menu bar icons.",
                                  action: { AccessibilityInventory.requestTrust() })
                    .padding(14)
            } else if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                if let heading = heading(before: index) {
                                    Text(heading)
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.top, index == 0 ? 2 : 8).padding(.bottom, 2)
                                }
                                Group {
                                    switch result {
                                    case .command(let command): commandRow(command, selected: index == selection)
                                    case .item(let item): row(item, selected: index == selection)
                                    }
                                }
                                .id(result.id)
                                .onTapGesture { perform(result) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: min(CGFloat(results.count) * 40 + CGFloat(headingCount) * 24 + 12, 380))
                    .onChange(of: selection) { _, new in
                        if results.indices.contains(new) { proxy.scrollTo(results[new].id) }
                    }
                }
            } else if !query.isEmpty {
                Divider()
                Label {
                    Text("Hoo? Nothing matches “\(query)”")
                } icon: {
                    WatchingOwl(snores: false, entrance: .puzzled).frame(width: 28, height: 28)
                }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
        }
        .frame(width: 560)
        .owlPanel()
        .padding(FloatingPanel.shadowInset)
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
            if selected {
                ReturnHint(verb: "Open")
            } else if let place = place(of: item) {
                Text(place).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(selected ? Brand.accent.opacity(0.25) : .clear, in: .rect(cornerRadius: Theme.rowRadius))
        .contentShape(.rect)
    }

    private func commandRow(_ command: AppCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: command.symbol, color: Brand.amber, size: 28)
                .frame(width: 48)
            Text(command.title).fontWeight(.medium)
            Spacer()
            if selected { ReturnHint(verb: "Run") }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(selected ? Brand.accent.opacity(0.25) : .clear, in: .rect(cornerRadius: Theme.rowRadius))
        .contentShape(.rect)
    }

    private func perform(_ result: Result) {
        switch result {
        case .command(let command): run(command)
        case .item(let item): open(item)
        }
    }

    /// Where an icon lives, when that's worth saying: not for ones you can see.
    private func place(of item: MenuBarItem) -> String? {
        if let group = model.groups.group(containing: item.key) { return "In \(group.name)" }
        if item.isBehindNotch { return "Behind the notch" }
        switch item.section {
        case .visible: return nil
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always hidden"
        }
    }

    /// A heading where commands start, and where icons start.
    private func heading(before index: Int) -> String? {
        let isCommand = { (i: Int) -> Bool in if case .command = results[i] { true } else { false } }
        if index == 0 { return isCommand(0) ? "Commands" : nil }
        return isCommand(index - 1) && !isCommand(index) ? "Menu bar icons" : nil
    }

    private var headingCount: Int {
        results.indices.filter { heading(before: $0) != nil }.count
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    private func openSelection() {
        guard results.indices.contains(selection) else { return }
        perform(results[selection])
    }
}

/// "↩ Open" on the selected row, so Return's meaning is never a guess.
private struct ReturnHint: View {
    let verb: String

    var body: some View {
        HStack(spacing: 4) {
            Text(verb)
            Image(systemName: "return")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

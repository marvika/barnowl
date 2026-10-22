import AppKit
import SwiftUI

/// One thing you can do in the video editor, with its title and keys. The one table drives the
/// menu bar, the keys, the tooltips and the shortcuts sheet.
struct VideoCommand {
    enum ID: String, CaseIterable {
        case copy, save, export, editFrame, done, close, revert
        case undo, redo, split, delete, trimStart, trimEnd, deselect
        case playPause, playBackward, stop, playForward, previousFrame, nextFrame, backSecond, forwardSecond
        case goToStart, goToEnd, loop
        case select, blade, crop, slower, faster, normalSpeed, fadeSound
        case zoomIn, zoomOut, zoomToFit, showInspector, shortcuts
    }

    enum Menu: String, CaseIterable {
        case file = "File"
        case edit = "Edit"
        case playback = "Playback"
        case clip = "Clip"
        case view = "View"
    }

    enum Group: String, CaseIterable {
        case play = "Play"
        case edit = "Edit"
        case finish = "Finish"
    }

    let id: ID
    let title: String
    /// The key, as AppKit spells it ("" for none).
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let menu: Menu
    let group: Group?

    init(_ id: ID, _ title: String, key: String = "", _ modifiers: NSEvent.ModifierFlags = [], menu: Menu, group: Group? = nil) {
        self.id = id
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.menu = menu
        self.group = group
    }

    var isBareKey: Bool {
        !key.isEmpty && modifiers.intersection([.command, .control, .option]).isEmpty
    }

    static let left = String(UnicodeScalar(NSLeftArrowFunctionKey).map(Character.init) ?? " ")
    static let right = String(UnicodeScalar(NSRightArrowFunctionKey).map(Character.init) ?? " ")
    static let up = String(UnicodeScalar(NSUpArrowFunctionKey).map(Character.init) ?? " ")
    static let down = String(UnicodeScalar(NSDownArrowFunctionKey).map(Character.init) ?? " ")

    /// The keys as people read them: ⇧⌘E, Space, ←.
    var keyLabel: String {
        guard !key.isEmpty else { return "" }
        var label = ""
        if modifiers.contains(.control) { label += "⌃" }
        if modifiers.contains(.option) { label += "⌥" }
        if modifiers.contains(.shift) { label += "⇧" }
        if modifiers.contains(.command) { label += "⌘" }
        let name: String = switch key {
        case "\r": "↩"
        case "\u{8}": "⌫"
        case "\u{1b}": "Esc"
        case " ": "Space"
        case Self.left: "←"
        case Self.right: "→"
        case Self.up: "↑"
        case Self.down: "↓"
        default: key.uppercased()
        }
        return label + name
    }

    @MainActor static let all: [VideoCommand] = [
        VideoCommand(.copy, "Copy Video", key: "c", [.command, .shift], menu: .file, group: .finish),
        VideoCommand(.save, "Save", key: "s", .command, menu: .file, group: .finish),
        VideoCommand(.export, "Export…", key: "e", .command, menu: .file, group: .finish),
        VideoCommand(.editFrame, "Edit Frame as Picture", key: "e", [.command, .shift], menu: .file, group: .finish),
        VideoCommand(.done, "Done", key: "\r", .command, menu: .file, group: .finish),
        VideoCommand(.close, "Close", key: "w", .command, menu: .file),
        VideoCommand(.revert, "Revert to Original", menu: .file),

        VideoCommand(.undo, "Undo", key: "z", .command, menu: .edit),
        VideoCommand(.redo, "Redo", key: "z", [.command, .shift], menu: .edit),
        VideoCommand(.split, "Split Clip", key: "b", .command, menu: .edit, group: .edit),
        VideoCommand(.delete, "Delete Clip", key: "\u{8}", menu: .edit, group: .edit),
        VideoCommand(.trimStart, "Trim Start to Playhead", key: "i", menu: .edit, group: .edit),
        VideoCommand(.trimEnd, "Trim End to Playhead", key: "o", menu: .edit, group: .edit),
        VideoCommand(.deselect, "Deselect", key: "a", [.command, .shift], menu: .edit),

        VideoCommand(.playPause, "Play", key: " ", menu: .playback, group: .play),
        VideoCommand(.playBackward, "Play Backward", key: "j", menu: .playback, group: .play),
        VideoCommand(.stop, "Pause", key: "k", menu: .playback, group: .play),
        VideoCommand(.playForward, "Play Forward", key: "l", menu: .playback, group: .play),
        VideoCommand(.previousFrame, "Previous Frame", key: left, menu: .playback, group: .play),
        VideoCommand(.nextFrame, "Next Frame", key: right, menu: .playback, group: .play),
        VideoCommand(.backSecond, "Back One Second", key: left, .shift, menu: .playback, group: .play),
        VideoCommand(.forwardSecond, "Forward One Second", key: right, .shift, menu: .playback, group: .play),
        VideoCommand(.goToStart, "Go to Start", key: up, menu: .playback, group: .play),
        VideoCommand(.goToEnd, "Go to End", key: down, menu: .playback, group: .play),
        VideoCommand(.loop, "Loop", key: "l", [.command, .option], menu: .playback),

        VideoCommand(.select, "Select", key: "v", menu: .clip, group: .edit),
        VideoCommand(.blade, "Blade", key: "b", menu: .clip, group: .edit),
        VideoCommand(.crop, "Crop", key: "c", menu: .clip, group: .edit),
        VideoCommand(.slower, "Slower", key: "[", menu: .clip, group: .edit),
        VideoCommand(.faster, "Faster", key: "]", menu: .clip, group: .edit),
        VideoCommand(.normalSpeed, "Normal Speed", key: "0", menu: .clip),
        VideoCommand(.fadeSound, "Fade Sound In and Out", menu: .clip),

        VideoCommand(.zoomIn, "Zoom In", key: "+", .command, menu: .view),
        VideoCommand(.zoomOut, "Zoom Out", key: "-", .command, menu: .view),
        VideoCommand(.zoomToFit, "Zoom to Fit", key: "9", .command, menu: .view),
        VideoCommand(.showInspector, "Show Inspector", key: "i", [.command, .option], menu: .view),
        VideoCommand(.shortcuts, "Keyboard Shortcuts", key: "?", menu: .view),
    ]

    @MainActor static func command(_ id: ID) -> VideoCommand? {
        all.first { $0.id == id }
    }

    /// "Blade (B)".
    @MainActor static func tooltip(_ id: ID, _ title: String? = nil) -> String {
        guard let command = command(id) else { return title ?? "" }
        let name = title ?? command.title
        return command.keyLabel.isEmpty ? name : "\(name) (\(command.keyLabel))"
    }

    /// The command a key press means, if any: plain keys and keys with ⇧ or ⌘.
    @MainActor static func command(for event: NSEvent) -> ID? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard let typed = event.charactersIgnoringModifiers else { return nil }
        let key: String
        switch event.keyCode {
        case 51, 117: key = "\u{8}"
        case 36, 76: key = "\r"
        case 123: key = left
        case 124: key = right
        case 125: key = down
        case 126: key = up
        case 49: key = " "
        default: key = typed.lowercased() == typed ? typed : typed.lowercased()
        }
        // ? is ⇧/ on most layouts.
        if typed == "?" { return .shortcuts }
        if key == "=" || key == "+", flags == .command { return .zoomIn }
        let arrows: Set<String> = [left, right, up, down]
        let relevant = arrows.contains(key) ? flags.subtracting(.function) : flags
        return all.first { $0.key == key && $0.modifiers == relevant }?.id
    }
}

/// The menu bar while a video editor is in front: Barn Owl, File, Edit, Playback, Clip, View
/// and Window. Whatever was there before comes back when it goes to the back or closes.
@MainActor
enum VideoEditorMenus {
    private static var menu: NSMenu?
    private static var window: NSMenu?
    private static var previous: NSMenu?

    static func install() {
        let menu = self.menu ?? make()
        self.menu = menu
        guard NSApp.mainMenu !== menu else { return }
        previous = NSApp.mainMenu
        NSApp.mainMenu = menu
        NSApp.windowsMenu = window
    }

    static func uninstall() {
        guard let menu, NSApp.mainMenu === menu else { return }
        NSApp.mainMenu = previous
        previous = nil
    }

    private static func make() -> NSMenu {
        let main = NSMenu(title: "Main")
        main.addItem(submenuItem(appMenu()))
        for kind in VideoCommand.Menu.allCases { main.addItem(submenuItem(menu(kind))) }
        let window = windowMenu()
        self.window = window
        main.addItem(submenuItem(window))
        return main
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Barn Owl")
        menu.addItem(withTitle: "About Barn Owl", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",", modifiers: .command) { EditorMenus.openSettings() })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Barn Owl", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
                                  keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Barn Owl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func standard(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = .command
        return item
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    /// Separators go before these, within each menu.
    private static let breaks: Set<VideoCommand.ID> = [.done, .revert, .split, .deselect, .previousFrame, .goToStart, .loop,
                                                       .slower, .fadeSound, .zoomToFit, .showInspector]

    private static func menu(_ kind: VideoCommand.Menu) -> NSMenu {
        let menu = NSMenu(title: kind.rawValue)
        for command in VideoCommand.all where command.menu == kind {
            if command.id == .split {
                // The usual text commands, for the save panel's name field; ⌘C copies the movie.
                menu.addItem(.separator())
                menu.addItem(standard("Cut", #selector(NSText.cut(_:)), key: "x"))
                menu.addItem(standard("Copy", #selector(NSText.copy(_:)), key: "c"))
                menu.addItem(standard("Paste", #selector(NSText.paste(_:)), key: "v"))
                menu.addItem(standard("Select All", #selector(NSText.selectAll(_:)), key: "a"))
            }
            if breaks.contains(command.id), !menu.items.isEmpty { menu.addItem(.separator()) }
            let item = NSMenuItem(title: command.title, action: #selector(VideoEditorWindowController.performVideoCommand(_:)),
                                  keyEquivalent: command.key)
            item.keyEquivalentModifierMask = command.modifiers
            item.representedObject = command.id.rawValue
            menu.addItem(item)
        }
        return menu
    }
}

/// The ? sheet: every key, grouped as Play, Edit and Finish.
struct VideoShortcutsSheet: View {
    let dismiss: () -> Void

    struct Row: Hashable {
        let title: String
        let keys: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts").font(.system(size: 15, weight: .semibold))
            HStack(alignment: .top, spacing: 28) {
                ForEach(VideoCommand.Group.allCases, id: \.self) { group in column(group) }
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640)
    }

    private func column(_ group: VideoCommand.Group) -> some View {
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
        .frame(width: 196, alignment: .leading)
    }

    @MainActor static func rows(_ group: VideoCommand.Group) -> [Row] {
        var rows: [Row] = []
        for command in VideoCommand.all where command.group == group && !command.keyLabel.isEmpty {
            switch command.id {
            case .playPause: rows.append(Row(title: "Play or Pause", keys: "Space"))
            case .previousFrame: rows.append(Row(title: "One frame", keys: "← →"))
            case .nextFrame: continue
            case .backSecond: rows.append(Row(title: "One second", keys: "⇧← ⇧→"))
            case .forwardSecond: continue
            case .goToStart: rows.append(Row(title: "Start or end", keys: "↑ ↓"))
            case .goToEnd: continue
            case .slower: rows.append(Row(title: "Slower or faster", keys: "[ ]"))
            case .faster: continue
            default: rows.append(Row(title: command.title, keys: command.keyLabel))
            }
        }
        switch group {
        case .play: rows.append(Row(title: "Faster each press", keys: "J J  L L"))
        case .edit: rows += [Row(title: "Zoom the timeline", keys: "⌘+ ⌘− or pinch")]
        case .finish:
            rows.insert(Row(title: "Done", keys: "↩"), at: 0)
            rows += [Row(title: "Step back", keys: "Esc"), Row(title: "Close, keeping changes", keys: "⌘W")]
        }
        return rows
    }
}

import AppKit

/// One thing you can do in the editor, with its title and keys. The one table drives the menu
/// bar, the toolbar's tooltips and the keyboard shortcuts sheet.
struct EditorCommand {
    enum ID: String, CaseIterable {
        case copy, save, pin, done, close, revert
        case undo, redo, cut, copyMarks, copyText, paste, delete, selectAll, duplicate
        case actualSize, zoomToFit, zoomIn, zoomOut, showFrame, shortcuts
        case bringToFront, sendToBack, bringForward, sendBackward
        case alignLeft, alignCentre, alignRight, alignTop, alignMiddle, alignBottom
        case select, arrow, line, rectangle, filled, ellipse, text, counter, highlighter, pen, redact, review
        case spotlight, crop
        case colour1, colour2, colour3, colour4, colour5, colour6, colour7, colour8
        case smaller, bigger, pickColour
        case bold, fontBigger, fontSmaller, showFonts
    }

    enum Menu: String, CaseIterable {
        case file = "File"
        case edit = "Edit"
        case view = "View"
        case arrange = "Arrange"
        case tools = "Tools"
        case format = "Format"
    }

    enum Group: String, CaseIterable {
        case tools = "Tools"
        case colourAndSize = "Colour & Size"
        case marks = "Marks"
        case finish = "Finish"
    }

    let id: ID
    let title: String
    /// The key equivalent, as AppKit spells it ("" for none).
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let menu: Menu
    /// A submenu within `menu`, such as Align or Colour.
    let submenu: String?
    /// A standard action (Undo, Cut…), so text being typed handles it itself.
    let action: Selector?
    let group: Group?

    init(_ id: ID, _ title: String, key: String = "", _ modifiers: NSEvent.ModifierFlags = [], menu: Menu,
         submenu: String? = nil, action: Selector? = nil, group: Group? = nil) {
        self.id = id
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.menu = menu
        self.submenu = submenu
        self.action = action
        self.group = group
    }

    /// Plain letters, digits and brackets: only while not typing.
    var isBareKey: Bool {
        !key.isEmpty && modifiers.intersection([.command, .control, .option]).isEmpty
    }

    /// The keys as people read them: ⇧⌘F, ⌘↩, [.
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
        default: key.uppercased()
        }
        return label + name
    }

    static let colourKeys: [ID] = [.colour1, .colour2, .colour3, .colour4, .colour5, .colour6, .colour7, .colour8]

    /// − and + size marks too, alongside [ and ], on every keyboard layout.
    static let sizeKeys: [String: ID] = ["-": .smaller, "+": .bigger, "=": .bigger]
    /// Plain keys some layouts type with ⌥, as Norwegian does [ and ] (⌥8, ⌥9).
    static let optionKeys: Set<String> = ["[", "]"]

    static func tool(_ tool: EditorTool) -> ID {
        switch tool {
        case .select: .select
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .counter: .counter
        case .highlighter: .highlighter
        case .pen: .pen
        case .redact: .redact
        case .spotlight: .spotlight
        case .crop: .crop
        }
    }

    @MainActor static let all: [EditorCommand] = {
        var commands: [EditorCommand] = [
            EditorCommand(.copy, "Copy Image", key: "c", [.command, .shift], menu: .file, group: .finish),
            EditorCommand(.save, "Save", key: "s", .command, menu: .file, group: .finish),
            EditorCommand(.pin, "Pin to Screen", key: "p", [.command, .option], menu: .file, group: .finish),
            EditorCommand(.done, "Done", key: "\r", .command, menu: .file, group: .finish),
            EditorCommand(.close, "Close", key: "w", .command, menu: .file, action: #selector(NSWindow.performClose(_:))),
            EditorCommand(.revert, "Revert to Original", menu: .file),

            EditorCommand(.undo, "Undo", key: "z", .command, menu: .edit, action: #selector(EditorCanvas.undo(_:))),
            EditorCommand(.redo, "Redo", key: "z", [.command, .shift], menu: .edit, action: #selector(EditorCanvas.redo(_:))),
            EditorCommand(.cut, "Cut", key: "x", .command, menu: .edit, action: #selector(NSText.cut(_:))),
            EditorCommand(.copyMarks, "Copy", key: "c", .command, menu: .edit, action: #selector(NSText.copy(_:))),
            EditorCommand(.copyText, "Copy Text", key: "c", [.command, .option], menu: .edit),
            EditorCommand(.paste, "Paste", key: "v", .command, menu: .edit, action: #selector(NSText.paste(_:))),
            EditorCommand(.delete, "Delete", menu: .edit, action: #selector(NSText.delete(_:)), group: .marks),
            EditorCommand(.selectAll, "Select All", key: "a", .command, menu: .edit, action: #selector(NSText.selectAll(_:))),
            EditorCommand(.duplicate, "Duplicate", key: "d", .command, menu: .edit, group: .marks),

            EditorCommand(.actualSize, "Actual Size", key: "0", .command, menu: .view),
            EditorCommand(.zoomToFit, "Zoom to Fit", key: "9", .command, menu: .view),
            EditorCommand(.zoomIn, "Zoom In", key: "+", .command, menu: .view),
            EditorCommand(.zoomOut, "Zoom Out", key: "-", .command, menu: .view),
            EditorCommand(.showFrame, "Show Frame", key: "i", [.command, .option], menu: .view),
            EditorCommand(.shortcuts, "Keyboard Shortcuts", key: "?", menu: .view),

            EditorCommand(.bringToFront, "Bring to Front", key: "f", [.command, .shift], menu: .arrange, group: .marks),
            EditorCommand(.sendToBack, "Send to Back", key: "b", [.command, .shift], menu: .arrange, group: .marks),
            EditorCommand(.bringForward, "Bring Forward", key: "f", [.command, .shift, .option], menu: .arrange),
            EditorCommand(.sendBackward, "Send Backward", key: "b", [.command, .shift, .option], menu: .arrange),
        ]
        for (id, alignment) in zip([ID.alignLeft, .alignCentre, .alignRight, .alignTop, .alignMiddle, .alignBottom],
                                   MarkAlignment.allCases) {
            commands.append(EditorCommand(id, alignment.title, menu: .arrange, submenu: "Align"))
        }
        commands += [
            EditorCommand(.select, "Select", key: "v", menu: .tools, group: .tools),
            EditorCommand(.arrow, "Arrow", key: "a", menu: .tools, group: .tools),
            EditorCommand(.line, "Line", key: "l", menu: .tools, group: .tools),
            EditorCommand(.rectangle, "Rectangle", key: "r", menu: .tools, group: .tools),
            EditorCommand(.filled, "Filled Rectangle", key: "f", menu: .tools, group: .tools),
            EditorCommand(.ellipse, "Ellipse", key: "o", menu: .tools, group: .tools),
            EditorCommand(.text, "Text", key: "t", menu: .tools, group: .tools),
            EditorCommand(.counter, "Counter", key: "n", menu: .tools, group: .tools),
            EditorCommand(.highlighter, "Highlighter", key: "h", menu: .tools, group: .tools),
            EditorCommand(.pen, "Pen", key: "p", menu: .tools, group: .tools),
            EditorCommand(.redact, "Redact", key: "b", menu: .tools, group: .tools),
            EditorCommand(.review, "Hide Private Info…", key: "B", .shift, menu: .tools, group: .tools),
            EditorCommand(.spotlight, "Spotlight", key: "s", menu: .tools, group: .tools),
            EditorCommand(.crop, "Crop", key: "c", menu: .tools, group: .tools),
        ]
        for (index, id) in colourKeys.enumerated() {
            commands.append(EditorCommand(id, MarkColour.paletteNames[index], key: String(index + 1), menu: .tools,
                                          submenu: "Colour"))
        }
        commands += [
            EditorCommand(.pickColour, "Pick from Capture", key: "i", menu: .tools, submenu: "Colour", group: .colourAndSize),
            EditorCommand(.smaller, "Smaller", key: "[", menu: .tools, submenu: "Size", group: .colourAndSize),
            EditorCommand(.bigger, "Bigger", key: "]", menu: .tools, submenu: "Size", group: .colourAndSize),

            EditorCommand(.bold, "Bold", key: "b", .command, menu: .format, submenu: "Font"),
            EditorCommand(.fontBigger, "Bigger", key: "+", .command, menu: .format, submenu: "Font"),
            EditorCommand(.fontSmaller, "Smaller", key: "-", .command, menu: .format, submenu: "Font"),
            EditorCommand(.showFonts, "Show Fonts", key: "t", .command, menu: .format, submenu: "Font"),
        ]
        return commands
    }()

    @MainActor static func command(_ id: ID) -> EditorCommand? {
        all.first { $0.id == id }
    }

    /// A tool's tooltip: "Arrow (A)".
    @MainActor static func tooltip(_ tool: EditorTool) -> String {
        guard let command = command(Self.tool(tool)) else { return tool.title }
        return "\(command.title) (\(command.keyLabel))"
    }
}

/// The menu bar while editors are open: Barn Owl, File, Edit, View, Arrange, Tools, Format and
/// Window, built from the command table. Whatever menu was there before comes back when the
/// last editor closes.
@MainActor
enum EditorMenus {
    private static var openEditors = 0
    private static var previous: NSMenu?
    private static var installed: NSMenu?

    static func editorOpened() {
        openEditors += 1
        guard installed == nil else { return }
        previous = NSApp.mainMenu
        let menu = makeMainMenu()
        installed = menu
        NSApp.mainMenu = menu
    }

    static func editorClosed() {
        openEditors = max(0, openEditors - 1)
        guard openEditors == 0, let installed else { return }
        if NSApp.mainMenu === installed { NSApp.mainMenu = previous }
        self.installed = nil
        previous = nil
    }

    static var isInstalled: Bool { installed != nil }

    static func makeMainMenu() -> NSMenu {
        let main = NSMenu(title: "Main")
        main.addItem(submenuItem(appMenu()))
        for kind in EditorCommand.Menu.allCases {
            main.addItem(submenuItem(menu(kind)))
        }
        let window = windowMenu()
        main.addItem(submenuItem(window))
        NSApp.windowsMenu = window
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
        menu.addItem(ClosureMenuItem("Settings…", key: ",", modifiers: .command) { openSettings() })
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

    /// Barn Owl's Settings window, the way barnowl://settings opens it.
    static func openSettings() {
        guard let url = URL(string: "barnowl://settings") else { return }
        NSApp.delegate?.application?(NSApp, open: [url])
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    /// Separators go between these, within each menu.
    private static let breaks: Set<EditorCommand.ID> = [.done, .revert, .cut, .duplicate, .zoomIn, .showFrame, .bringForward,
                                                        .alignLeft, .line, .redact, .crop, .colour1, .showFonts]

    private static func menu(_ kind: EditorCommand.Menu) -> NSMenu {
        let menu = NSMenu(title: kind.rawValue)
        var submenus: [String: NSMenu] = [:]
        for command in EditorCommand.all where command.menu == kind {
            let item = NSMenuItem(title: command.title,
                                  action: command.action ?? #selector(EditorWindowController.performEditorCommand(_:)),
                                  keyEquivalent: command.key)
            item.keyEquivalentModifierMask = command.modifiers
            item.representedObject = command.id.rawValue
            if let name = command.submenu {
                if let existing = submenus[name] {
                    existing.addItem(item)
                } else {
                    let submenu = NSMenu(title: name)
                    submenu.addItem(item)
                    submenus[name] = submenu
                    if breaks.contains(command.id), !menu.items.isEmpty { menu.addItem(.separator()) }
                    menu.addItem(submenuItem(submenu))
                }
                continue
            }
            if breaks.contains(command.id), !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(item)
        }
        return menu
    }
}

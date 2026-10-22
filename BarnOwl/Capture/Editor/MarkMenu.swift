import AppKit

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], checked: Bool = false,
         _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}

/// The right-click menu on a mark: the same choices as the options bar, plus arranging.
@MainActor
struct MarkMenu {
    let canvas: EditorCanvas
    var model: EditorModel { canvas.model }

    func make() -> NSMenu {
        let menu = NSMenu(title: "Mark")
        let marks = model.selectedMarks
        let kinds = Set(marks.map(\.kind))
        let kind: Mark.Kind? = kinds.count == 1 ? kinds.first : nil
        if !kinds.contains(where: \.isColourless) {
            menu.addItem(submenu("Colour", colourItems(kind: kind)))
        }
        if let kind, !SizeLadder.presets(for: kind).isEmpty {
            menu.addItem(submenu("Size", sizeItems(kind)))
        }
        if let kind {
            let styles = styleItems(kind)
            if !styles.isEmpty { menu.addItem(submenu(kind == .magnifier ? "Shape" : "Style", styles)) }
        }
        if kind == .magnifier {
            menu.addItem(submenu("Zoom", zoomItems()))
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Duplicate", key: "d", modifiers: .command) { model.duplicateSelection() })
        menu.addItem(submenu("Arrange", [
            ClosureMenuItem("Bring to Front", key: "f", modifiers: [.command, .shift]) { model.bringToFront() },
            ClosureMenuItem("Bring Forward", key: "f", modifiers: [.command, .shift, .option]) { model.bringForward() },
            ClosureMenuItem("Send Backward", key: "b", modifiers: [.command, .shift, .option]) { model.sendBackward() },
            ClosureMenuItem("Send to Back", key: "b", modifiers: [.command, .shift]) { model.sendToBack() },
        ]))
        if marks.count == 1, let mark = marks.first, let text = model.text(under: mark) {
            menu.addItem(ClosureMenuItem(mark.kind == .text ? "Copy Text" : "Copy Text Underneath") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            })
        }
        if let kind {
            menu.addItem(ClosureMenuItem("Reset \(kind.title) Style") { model.resetStyle() })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Delete") { model.deleteSelection() })
        return menu
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for entry in items { menu.addItem(entry) }
        item.submenu = menu
        return item
    }

    private func colourItems(kind: Mark.Kind?) -> [NSMenuItem] {
        let palette: [MarkColour] = kind == .highlighter ? MarkColour.highlighterPalette : MarkColour.palette
        let current = model.shownColour
        return palette.map { colour in
            let item = ClosureMenuItem(colour.name, checked: colour == current) { model.setColour(colour) }
            item.image = Swatches.dot(colour, diameter: 12)
            return item
        }
    }

    private func sizeItems(_ kind: Mark.Kind) -> [NSMenuItem] {
        let presets = SizeLadder.presets(for: kind)
        let current = model.shownStyle.weight
        return presets.enumerated().map { index, weight in
            ClosureMenuItem(SizeLadder.presetNames[index], checked: abs(current - weight) < 0.01) {
                model.updateStyle("Change Size") { $0.weight = weight }
            }
        }
    }

    private func zoomItems() -> [NSMenuItem] {
        let current = model.shownStyle.zoom
        return SizeLadder.zooms.map { zoom in
            ClosureMenuItem(SizeLadder.zoomTitle(zoom), checked: abs(current - zoom) < 0.01) {
                model.updateStyle("Change Zoom") { $0.zoom = zoom }
            }
        }
    }

    private func styleItems(_ kind: Mark.Kind) -> [NSMenuItem] {
        let style = model.shownStyle
        switch kind {
        case .arrow:
            return ArrowChoice.allCases.map { choice in
                ClosureMenuItem(choice.title, checked: choice.matches(style)) {
                    model.updateStyle { choice.apply(&$0) }
                }
            }
        case .rectangle, .ellipse:
            return ShapeFill.allCases.map { fill in
                ClosureMenuItem(fill.title, checked: style.fill == fill) { model.updateStyle { $0.fill = fill } }
            }
        case .text:
            return TextStyle.allCases.map { option in
                ClosureMenuItem(option.title, checked: style.textStyle == option) { model.updateStyle { $0.textStyle = option } }
            }
        case .counter:
            return CounterFormat.allCases.map { format in
                ClosureMenuItem(format.title, checked: style.counterFormat == format) {
                    model.updateStyle { $0.counterFormat = format }
                }
            }
        case .redact:
            return RedactStyle.allCases.map { option in
                ClosureMenuItem(option.title, checked: style.redact == option) { model.updateStyle { $0.redact = option } }
            }
        case .spotlight:
            var items: [NSMenuItem] = SpotlightShape.allCases.map { shape in
                ClosureMenuItem(shape.title, checked: style.spotlight == shape) { model.updateStyle { $0.spotlight = shape } }
            }
            items.append(.separator())
            items += SpotlightEffect.allCases.map { effect in
                ClosureMenuItem(effect.title, checked: style.spotlightEffect == effect) {
                    model.updateStyle { $0.spotlightEffect = effect }
                }
            }
            return items
        case .magnifier:
            return SpotlightShape.allCases.map { shape in
                ClosureMenuItem(shape.title, checked: style.spotlight == shape) { model.updateStyle { $0.spotlight = shape } }
            }
        case .highlighter, .pen, .image:
            return []
        }
    }
}

/// The four arrow styles in the options bar: straight, curved, both ends, and a plain line.
enum ArrowChoice: String, CaseIterable {
    case straight, curved, double, line

    var title: String {
        switch self {
        case .straight: "Straight"
        case .curved: "Curved"
        case .double: "Double-Headed"
        case .line: "Line"
        }
    }

    func matches(_ style: MarkStyle) -> Bool {
        switch self {
        case .straight: style.heads == .end && !style.curved
        case .curved: style.heads == .end && style.curved
        case .double: style.heads == .both
        case .line: style.heads == .none
        }
    }

    func apply(_ style: inout MarkStyle) {
        switch self {
        case .straight:
            style.heads = .end
            style.curved = false
        case .curved:
            style.heads = .end
            style.curved = true
        case .double:
            style.heads = .both
        case .line:
            style.heads = .none
        }
    }
}

/// Small pictures of colours, for menus and buttons.
@MainActor
enum Swatches {
    static func dot(_ colour: MarkColour, diameter: CGFloat) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            NSColor(cgColor: colour.cgColor())?.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}

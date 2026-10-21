import AppKit
import Observation

/// A tool in the editor's toolbar, with the key that picks it.
enum EditorTool: String, CaseIterable, Codable, Sendable {
    case select, arrow, line, rectangle, filledBox, ellipse, text, counter, highlighter, pen, redact, spotlight, crop

    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .filledBox: "f"
        case .ellipse: "o"
        case .text: "t"
        case .counter: "n"
        case .highlighter: "h"
        case .pen: "p"
        case .redact: "b"
        case .spotlight: "s"
        case .crop: "c"
        }
    }

    init?(key: String) {
        guard let tool = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = tool
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .filledBox: "Filled Box"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .counter: "Counter"
        case .highlighter: "Highlighter"
        case .pen: "Pen"
        case .redact: "Redact"
        case .spotlight: "Spotlight"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .filledBox: "rectangle.fill"
        case .ellipse: "circle"
        case .text: "textformat"
        case .counter: "1.circle"
        case .highlighter: "highlighter"
        case .pen: "scribble"
        case .redact: "eye.slash"
        case .spotlight: "flashlight.on.fill"
        case .crop: "crop"
        }
    }

    /// The mark this tool draws, if it draws one.
    var markKind: Mark.Kind? {
        switch self {
        case .select, .crop: nil
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .filledBox: .filledBox
        case .ellipse: .ellipse
        case .text: .text
        case .counter: .counter
        case .highlighter: .highlighter
        case .pen: .pen
        case .redact: .redact
        case .spotlight: .spotlight
        }
    }
}

/// What the editor's buttons hand back to the host.
enum EditorAction: Sendable {
    case copy, save, pin, done
}

/// The editor's state: the document with its undo history, the selection, and the tool with its
/// colour, size and style (remembered per tool).
@MainActor
@Observable
final class EditorModel {
    let image: CGImage
    /// Pixels per point.
    let scale: CGFloat

    private(set) var document: EditorDocument {
        didSet { onChange?() }
    }
    var selection: Set<UUID> = [] {
        didSet { if selection != oldValue { onChange?() } }
    }
    private(set) var tool: EditorTool {
        didSet { onChange?() }
    }
    private(set) var colour = MarkColour.amber
    private(set) var size = StrokeSize.medium
    private(set) var style = MarkStyle()
    var showsInspector = false {
        didSet { onInspectorChange?() }
    }
    /// The crop being adjusted while the crop tool is out, in image pixels.
    var cropDraft: CGRect? {
        didSet { onChange?() }
    }
    /// The text mark being typed into.
    var editingText: UUID?
    /// An action just done, confirmed on its button for a moment.
    private(set) var confirmed: EditorAction?
    private(set) var savedDocument: EditorDocument

    @ObservationIgnored let undoManager = UndoManager()
    /// Redraws the canvas.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onInspectorChange: (() -> Void)?
    /// Puts down any text being typed before the tool changes.
    @ObservationIgnored var willChangeTool: (() -> Void)?
    /// Copy, save, pin and done, for the editor to carry out.
    @ObservationIgnored var onAction: ((EditorAction) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var toolBeforeCrop = EditorTool.select

    enum Keys {
        static let lastTool = "captureEditor.lastTool"
        static let selectsAfterDrawing = "captureEditor.selectsAfterDrawing"
        static func settings(_ tool: EditorTool) -> String { "captureEditor.tool.\(tool.rawValue)" }
    }

    init(image: CGImage, scale: CGFloat, defaults: UserDefaults = .standard) {
        self.image = image
        self.scale = max(scale, 0.5)
        self.defaults = defaults
        let document = EditorDocument(imageSize: CGSize(width: image.width, height: image.height), scale: self.scale)
        self.document = document
        savedDocument = document
        let last = defaults.string(forKey: Keys.lastTool).flatMap(EditorTool.init(rawValue:)) ?? .arrow
        tool = last == .crop ? .arrow : last
        undoManager.groupsByEvent = false
        loadSettings(for: tool)
    }

    var isDirty: Bool { document != savedDocument }

    /// Whether to switch to Select after drawing a mark; off keeps the tool, like CleanShot.
    var selectsAfterDrawing: Bool { defaults.bool(forKey: Keys.selectsAfterDrawing) }

    var selectedMarks: [Mark] { document.marks.filter { selection.contains($0.id) } }

    /// The kind the style control applies to: the selection's, when it's all one kind, else the tool's.
    var styleKind: Mark.Kind? {
        let kinds = Set(selectedMarks.map(\.kind))
        if kinds.count == 1 { return kinds.first }
        return kinds.isEmpty ? tool.markKind : nil
    }

    /// What the toolbar shows: the selection's colour, size and style, or the tool's.
    var shownColour: MarkColour { selectedMarks.last?.colour ?? colour }
    var shownSize: StrokeSize { selectedMarks.last?.size ?? size }
    var shownStyle: MarkStyle { selectedMarks.last?.style ?? style }

    // MARK: Tools

    func choose(_ tool: EditorTool) {
        guard tool != self.tool else { return }
        willChangeTool?()
        if self.tool == .crop { cropDraft = nil }
        if tool == .crop {
            toolBeforeCrop = self.tool
            selection = []
        } else {
            defaults.set(tool.rawValue, forKey: Keys.lastTool)
        }
        self.tool = tool
        loadSettings(for: tool)
        if tool == .crop { cropDraft = document.crop }
    }

    func setColour(_ colour: MarkColour) {
        if tool.markKind != nil {
            self.colour = colour
            saveSettings()
        }
        changeSelection("Change Colour") { $0.colour = colour }
    }

    func setSize(_ size: StrokeSize) {
        if tool.markKind != nil {
            self.size = size
            saveSettings()
        }
        changeSelection("Change Size") { $0.size = size }
    }

    func setStyle(_ change: @escaping (inout MarkStyle) -> Void) {
        if tool.markKind != nil {
            change(&style)
            saveSettings()
        }
        changeSelection("Change Style") { mark in
            let before = mark.style.arrow
            change(&mark.style)
            guard mark.kind == .arrow, mark.style.arrow != before else { return }
            switch mark.style.arrow {
            case .straight: mark.control = nil
            case .curved: mark.control = mark.control ?? MarkGeometry.defaultBend(start: mark.start, end: mark.end)
            case .double: break
            }
        }
    }

    /// A new mark of `kind` at `point`, in the tool's colour, size and style.
    func newMark(_ kind: Mark.Kind, at point: CGPoint) -> Mark {
        Mark(kind: kind, colour: colour, size: size, style: style, start: point, end: point)
    }

    private struct ToolSettings: Codable {
        var colour: MarkColour
        var size: StrokeSize
        var style: MarkStyle
    }

    private func loadSettings(for tool: EditorTool) {
        let data = defaults.data(forKey: Keys.settings(tool))
        let saved = data.flatMap { try? JSONDecoder().decode(ToolSettings.self, from: $0) }
        colour = saved?.colour ?? (tool == .redact ? .ink : .amber)
        size = saved?.size ?? .medium
        style = saved?.style ?? MarkStyle()
    }

    private func saveSettings() {
        let settings = ToolSettings(colour: colour, size: size, style: style)
        guard tool.markKind != nil, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Keys.settings(tool))
    }

    // MARK: Editing

    /// Changes the document as one undoable step.
    func apply(_ name: String, _ change: (inout EditorDocument) -> Void) {
        let before = document
        var next = document
        change(&next)
        guard next != before else { return }
        document = next
        registerUndo(restoring: before, name)
    }

    /// Changes the document while a drag or typing is under way; `commit` makes it one step.
    func setLive(_ document: EditorDocument) {
        self.document = document
    }

    /// Records everything since `before` as one undoable step.
    func commit(from before: EditorDocument, _ name: String) {
        guard before != document else { return }
        registerUndo(restoring: before, name)
    }

    private func changeSelection(_ name: String, _ change: (inout Mark) -> Void) {
        guard !selection.isEmpty else { return }
        let ids = selection
        // Text being typed gets one undo step when it's put down, which covers this too.
        if let editing = editingText, ids == [editing] {
            var next = document
            next.update(editing, change)
            document = next
            return
        }
        apply(name) { document in
            for id in ids { document.update(id, change) }
        }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        apply(ids.count == 1 ? "Delete Mark" : "Delete Marks") { $0.remove(ids) }
        selection = []
    }

    func duplicateSelection() {
        let offset: CGFloat = 12 * scale
        let copies: [Mark] = selectedMarks.map { mark in
            var copy = MarkGeometry.moved(mark, by: offset, offset)
            copy.id = UUID()
            return copy
        }
        guard !copies.isEmpty else { return }
        apply("Duplicate") { $0.marks += copies }
        selection = Set(copies.map(\.id))
    }

    func nudgeSelection(by dx: CGFloat, _ dy: CGFloat) {
        let ids = selection
        guard !ids.isEmpty else { return }
        apply("Move") { document in
            for id in ids { document.update(id) { $0 = MarkGeometry.moved($0, by: dx, dy) } }
        }
    }

    func selectAll() {
        selection = Set(document.marks.map(\.id))
    }

    func add(_ mark: Mark) {
        apply("Add \(mark.kind.title)") { $0.marks.append(mark) }
        selection = [mark.id]
    }

    func setFrame(_ name: String, _ change: (inout FrameSettings) -> Void) {
        apply(name) { change(&$0.frame) }
    }

    /// Changes the frame without an undo step, while a slider moves.
    func setFrameLive(_ change: (inout FrameSettings) -> Void) {
        var next = document
        change(&next.frame)
        document = next
    }

    // MARK: Crop

    func applyCrop() {
        guard let draft = cropDraft else { return }
        let rect = draft.integral.intersection(document.imageBounds)
        if !rect.isNull, rect.width >= 4, rect.height >= 4 {
            apply("Crop") { $0.crop = rect }
        }
        cropDraft = nil
        choose(toolBeforeCrop)
    }

    func cancelCrop() {
        cropDraft = nil
        choose(toolBeforeCrop)
    }

    // MARK: Undo

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
    }

    private func registerUndo(restoring snapshot: EditorDocument, _ name: String) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(snapshot, name) }
        }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }

    /// Puts a snapshot back, registering the way back again (so undo becomes redo, and back).
    private func restore(_ snapshot: EditorDocument, _ name: String) {
        let current = document
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(current, name) }
        }
        undoManager.setActionName(name)
        document = snapshot
        selection = selection.filter { snapshot[$0] != nil }
        if cropDraft != nil { cropDraft = snapshot.crop }
    }

    // MARK: Actions

    func perform(_ action: EditorAction) {
        onAction?(action)
    }

    func markSaved() {
        savedDocument = document
    }

    /// Shows a tick on the action's button for a moment.
    func confirm(_ action: EditorAction) {
        confirmed = action
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            if self?.confirmed == action { self?.confirmed = nil }
        }
    }
}

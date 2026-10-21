import AppKit
import Observation

/// What the editor's buttons hand back to the host.
enum EditorAction: Sendable {
    case copy, save, pin, done
}

/// Where Esc went, one step back at a time.
enum EscapeStep: Equatable, Sendable {
    case finishedText, cancelledReview, leftCrop, deselected, choseSelect
    /// Nothing changed: close the editor.
    case close
    /// Something changed, so Esc doesn't close; say how to.
    case explained
}

/// What Return does when no text is being typed.
enum ReturnStep: Equatable, Sendable {
    case applyCrop, hideReviewed, done
}

/// Alignment for several marks.
enum MarkAlignment: String, CaseIterable, Sendable {
    case left, centre, right, top, middle, bottom

    var title: String {
        switch self {
        case .left: "Align Left Edges"
        case .centre: "Align Centres"
        case .right: "Align Right Edges"
        case .top: "Align Top Edges"
        case .middle: "Align Middles"
        case .bottom: "Align Bottom Edges"
        }
    }
}

/// The editor's state: the document with its undo history, the selection, the tool, and the
/// style book that remembers your colours and sizes.
@MainActor
@Observable
final class EditorModel {
    let image: CGImage
    /// Pixels per point.
    let scale: CGFloat
    let renderer: AnnotationRenderer

    private(set) var document: EditorDocument {
        didSet { onDocumentChange?(oldValue, document) }
    }
    var selection: Set<UUID> = [] {
        didSet { if selection != oldValue { onChromeChange?() } }
    }
    private(set) var tool: EditorTool {
        didSet { if tool != oldValue { onToolChange?() } }
    }
    private(set) var styleBook: StyleBook
    /// The frame inspector is open.
    var showsFrame = false {
        didSet { if showsFrame != oldValue { onFrameVisibilityChange?() } }
    }
    /// The crop being adjusted while the crop tool is out, in image pixels.
    var cropDraft: CGRect? {
        didSet { onChromeChange?() }
    }
    var cropAspect = CropAspect.free
    /// The text mark (or counter, for its label) being typed into.
    var editingText: UUID?
    /// An action just done, confirmed on its button for a moment.
    private(set) var confirmed: EditorAction?
    /// What the capture's text and windows are, once the background scan is done.
    private(set) var insight: CaptureInsight?
    /// Hide Private Info's review, while it's open.
    var review: PrivateInfoReview? {
        didSet { onChromeChange?() }
    }
    /// The banner about a visible key was closed, or acted on.
    var secretBannerDismissed = false
    /// A short note at the bottom of the canvas, such as how to close after changes.
    var transientHint: String?
    var showsShortcuts = false
    /// Changes since the editor opened: up for each change and redo, down for each undo.
    private(set) var changeCount = 0

    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored var onDocumentChange: ((EditorDocument, EditorDocument) -> Void)?
    /// Selection, crop or review changed: redraw the handles and guides.
    @ObservationIgnored var onChromeChange: (() -> Void)?
    @ObservationIgnored var onToolChange: (() -> Void)?
    @ObservationIgnored var onFrameVisibilityChange: (() -> Void)?
    /// A change was committed (not a live drag), for autosave.
    @ObservationIgnored var onCommit: (() -> Void)?
    /// Puts down any text being typed.
    @ObservationIgnored var endTextEditing: (() -> Void)?
    /// Copy, save, pin and done, for the editor to carry out.
    @ObservationIgnored var onAction: ((EditorAction) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var toolBeforeCrop = EditorTool.arrow
    @ObservationIgnored private var nudgeBase: EditorDocument?
    @ObservationIgnored private var nudgeTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    /// The document before a slider started moving, so the whole slide is one undo step.
    @ObservationIgnored private var liveBase: EditorDocument?

    enum Keys {
        static let lastTool = "captureEditor.lastTool"
        static let styleBook = "captureEditor.styleBook"
        static let selectsAfterDrawing = "captureEditor.selectsAfterDrawing"
        static func hintUses(_ tool: EditorTool) -> String { "captureEditor.hintUses.\(tool.rawValue)" }
    }

    init(image: CGImage, scale: CGFloat, document: EditorDocument? = nil, insight: CaptureInsight? = nil,
         desktop: CGImage? = nil, defaults: UserDefaults = .standard) {
        self.image = image
        self.scale = max(scale, 0.5)
        self.defaults = defaults
        renderer = AnnotationRenderer(image: image, scale: max(scale, 0.5), desktop: desktop)
        let size = CGSize(width: image.width, height: image.height)
        var opened = document ?? EditorDocument(imageSize: size, scale: max(scale, 0.5))
        if opened.imageSize != size {
            // A document for another image: keep its marks, but fit the crop to this one.
            opened.imageSize = size
            opened.crop = opened.crop.intersection(CGRect(origin: .zero, size: size))
            if opened.crop.isNull || opened.crop.width < 1 { opened.crop = CGRect(origin: .zero, size: size) }
        }
        self.document = opened
        let book = defaults.data(forKey: Keys.styleBook).flatMap { try? JSONDecoder().decode(StyleBook.self, from: $0) }
        styleBook = book ?? StyleBook()
        tool = Self.openingTool(defaults: defaults)
        self.insight = insight
        undoManager.groupsByEvent = false
    }

    /// The last drawing tool you used; Arrow the first time. Never Select or Crop.
    static func openingTool(defaults: UserDefaults) -> EditorTool {
        let last = defaults.string(forKey: Keys.lastTool).flatMap(EditorTool.init(rawValue:))
        guard let last, last != .select, last != .crop else { return .arrow }
        return last
    }

    var isEdited: Bool { changeCount != 0 }

    /// Whether to switch to Select after drawing a mark; off keeps the tool, like CleanShot.
    var selectsAfterDrawing: Bool { defaults.bool(forKey: Keys.selectsAfterDrawing) }

    var selectedMarks: [Mark] { document.marks.filter { selection.contains($0.id) } }

    // MARK: Tools

    func choose(_ tool: EditorTool) {
        endTextEditing?()
        flushNudge()
        if review != nil, tool != .redact { review = nil }
        guard tool != self.tool else { return }
        if self.tool == .crop { cropDraft = nil }
        if tool == .crop {
            toolBeforeCrop = self.tool
            selection = []
            cropDraft = document.crop
        } else if tool != .select {
            defaults.set(tool.rawValue, forKey: Keys.lastTool)
        }
        self.tool = tool
        noteHintUse(tool)
    }

    /// Arrow (A) draws arrows; Line (L) the same tool without heads.
    func chooseArrow(line: Bool) {
        choose(.arrow)
        var style = styleBook.style(for: .arrow)
        if line {
            style.heads = .none
        } else if style.heads == .none {
            style.heads = .end
        }
        rememberStyle(style, for: .arrow)
    }

    /// Rectangle (R) draws outlines; Filled (F) the same tool, filled.
    func chooseRectangle(filled: Bool) {
        choose(.rectangle)
        var style = styleBook.style(for: .rectangle)
        if filled {
            style.fill = .solid
        } else if style.fill == .solid {
            style.fill = .none
        }
        rememberStyle(style, for: .rectangle)
    }

    // MARK: Style

    /// The kind the options bar is about: the selection's, when it's all one kind, else the tool's.
    var activeKind: Mark.Kind? {
        if !selection.isEmpty {
            let kinds = Set(selectedMarks.map(\.kind))
            return kinds.count == 1 ? kinds.first : nil
        }
        return tool.markKind
    }

    /// What the options bar shows: the selection's look, or what the tool will draw.
    var shownColour: MarkColour {
        if let mark = selectedMarks.last { return mark.colour }
        guard let kind = tool.markKind else { return styleBook.penColour }
        return styleBook.colour(for: kind)
    }

    var shownStyle: MarkStyle {
        if let mark = selectedMarks.last { return mark.style }
        guard let kind = activeKind else { return MarkStyle() }
        return styleBook.style(for: kind)
    }

    func setColour(_ colour: MarkColour) {
        if selection.isEmpty {
            if let kind = tool.markKind { rememberColour(colour, for: kind) }
            return
        }
        for kind in Set(selectedMarks.map(\.kind)) { rememberColour(colour, for: kind) }
        changeSelection("Change Colour") { mark in
            guard mark.kind != .spotlight, mark.kind != .image else { return }
            mark.colour = colour
        }
    }

    /// Changes the style of the selection (and remembers it for each kind selected), or the
    /// style the tool will draw with.
    func updateStyle(_ name: String = "Change Style", _ change: (inout MarkStyle) -> Void) {
        if selection.isEmpty {
            guard let kind = tool.markKind else { return }
            var style = styleBook.style(for: kind)
            change(&style)
            rememberStyle(style, for: kind)
            return
        }
        changeSelection(name) { mark in
            let wasCurved = mark.control != nil
            change(&mark.style)
            guard mark.kind == .arrow, mark.style.curved != wasCurved else { return }
            mark.control = mark.style.curved ? MarkGeometry.defaultBend(start: mark.start, end: mark.end) : nil
        }
        var remembered: Set<Mark.Kind> = []
        for mark in selectedMarks.reversed() where !remembered.contains(mark.kind) {
            remembered.insert(mark.kind)
            rememberStyle(mark.style, for: mark.kind)
        }
    }

    /// [ and ]: the next size on the active kind's ladder (text sizes for text).
    func stepSize(up: Bool) {
        guard let kind = activeKind else { return }
        let style = shownStyle
        if kind == .text {
            let next = SizeLadder.step(style.fontSize, in: SizeLadder.textSizes, up: up)
            updateStyle("Change Size") { $0.fontSize = next }
        } else {
            let steps = SizeLadder.steps(for: kind)
            guard !steps.isEmpty else { return }
            let next = SizeLadder.step(style.weight, in: steps, up: up)
            updateStyle("Change Size") { $0.weight = next }
        }
    }

    /// ⌘B: semibold and bold, back and forth.
    func toggleBold() {
        let bold = shownStyle.fontWeight == .bold
        updateStyle("Change Weight") { $0.fontWeight = bold ? .semibold : .bold }
    }

    /// Whether text is what ⌘B, ⌘+ and ⌘− are about: typing, text selected, or the Text tool out.
    var isTextContext: Bool {
        if editingText.flatMap({ document[$0] })?.kind == .text { return true }
        if !selection.isEmpty { return selectedMarks.allSatisfy { $0.kind == .text } }
        return tool == .text
    }

    func resetStyle() {
        guard let kind = activeKind else { return }
        styleBook.reset(kind)
        saveStyleBook()
        if !selection.isEmpty {
            let style = styleBook.style(for: kind)
            let colour = styleBook.colour(for: kind)
            changeSelection("Reset Style") { mark in
                mark.style = style
                if mark.kind != .spotlight { mark.colour = colour }
            }
        }
    }

    private func rememberColour(_ colour: MarkColour, for kind: Mark.Kind) {
        styleBook.remember(colour: colour, for: kind)
        saveStyleBook()
    }

    private func rememberStyle(_ style: MarkStyle, for kind: Mark.Kind) {
        styleBook.remember(style: style, for: kind)
        saveStyleBook()
    }

    func noteRecent(_ colour: MarkColour) {
        styleBook.noteRecent(colour)
        saveStyleBook()
    }

    private func saveStyleBook() {
        guard let data = try? JSONEncoder().encode(styleBook) else { return }
        defaults.set(data, forKey: Keys.styleBook)
    }

    /// A new mark of `kind` at `point`, as the style book says.
    func newMark(_ kind: Mark.Kind, at point: CGPoint) -> Mark {
        var style = styleBook.style(for: kind)
        if kind == .counter { style.weight = max(style.weight, 12) }
        return Mark(kind: kind, colour: styleBook.colour(for: kind), style: style, start: point, end: point)
    }

    // MARK: Editing

    /// Changes the document as one undoable step.
    func apply(_ name: String, _ change: (inout EditorDocument) -> Void) {
        flushNudge()
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

    /// A slider started moving: changes until `endLiveChange` are one undo step.
    func beginLiveChange() {
        flushNudge()
        liveBase = document
    }

    func endLiveChange(_ name: String) {
        guard let base = liveBase else { return }
        liveBase = nil
        commit(from: base, name)
    }

    private func changeSelection(_ name: String, _ change: (inout Mark) -> Void) {
        guard !selection.isEmpty else { return }
        let ids = selection
        if liveBase != nil {
            var next = document
            for id in ids { next.update(id, change) }
            document = next
            return
        }
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

    /// Arrow keys move the selection; a run of presses is one undo step.
    func nudgeSelection(by dx: CGFloat, _ dy: CGFloat) {
        let ids = selection
        guard !ids.isEmpty else { return }
        if nudgeBase == nil { nudgeBase = document }
        var next = document
        for id in ids { next.update(id) { $0 = MarkGeometry.moved($0, by: dx, dy) } }
        document = next
        nudgeTask?.cancel()
        nudgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.flushNudge()
        }
    }

    /// Puts a run of nudges down as one step.
    func flushNudge() {
        nudgeTask?.cancel()
        nudgeTask = nil
        guard let base = nudgeBase else { return }
        nudgeBase = nil
        commit(from: base, "Move")
    }

    func selectAll() {
        selection = Set(document.marks.map(\.id))
    }

    /// Tab and ⇧Tab: the next or previous mark, in the order they were made.
    func selectNext(backwards: Bool) {
        let marks = document.marks
        guard !marks.isEmpty else { return }
        let current = marks.lastIndex { selection.contains($0.id) }
        let next: Int
        if let current {
            let step = backwards ? marks.count - 1 : 1
            next = (current + step) % marks.count
        } else {
            next = backwards ? marks.count - 1 : 0
        }
        selection = [marks[next].id]
    }

    func add(_ mark: Mark) {
        apply("Add \(mark.kind.title)") { $0.marks.append(mark) }
        selection = [mark.id]
    }

    func add(_ marks: [Mark], name: String) {
        guard !marks.isEmpty else { return }
        apply(name) { $0.marks += marks }
        selection = Set(marks.map(\.id))
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

    func setCounterStart(_ start: Int) {
        apply("Change Numbering") { $0.counterStart = max(0, start) }
    }

    // MARK: Arrange

    /// Moves the selection to the top (or bottom) of its layer.
    func bringToFront() { reorder("Bring to Front") { marks, picked in marks.removeAll { picked.contains($0.id) }; marks += picked.ordered } }
    func sendToBack() { reorder("Send to Back") { marks, picked in marks.removeAll { picked.contains($0.id) }; marks.insert(contentsOf: picked.ordered, at: 0) } }

    func bringForward() {
        reorder("Bring Forward") { marks, picked in
            for index in marks.indices.reversed() where picked.contains(marks[index].id) {
                let next = index + 1
                guard next < marks.count, !picked.contains(marks[next].id) else { continue }
                marks.swapAt(index, next)
            }
        }
    }

    func sendBackward() {
        reorder("Send Backward") { marks, picked in
            for index in marks.indices where picked.contains(marks[index].id) {
                let previous = index - 1
                guard previous >= 0, !picked.contains(marks[previous].id) else { continue }
                marks.swapAt(index, previous)
            }
        }
    }

    private struct Picked {
        let ids: Set<UUID>
        let ordered: [Mark]
        func contains(_ id: UUID) -> Bool { ids.contains(id) }
    }

    private func reorder(_ name: String, _ change: (inout [Mark], Picked) -> Void) {
        let ids = selection
        guard !ids.isEmpty else { return }
        let picked = Picked(ids: ids, ordered: document.marks.filter { ids.contains($0.id) })
        apply(name) { change(&$0.marks, picked) }
    }

    /// Lines the selected marks up with each other, or one mark with the image.
    func align(_ alignment: MarkAlignment) {
        let marks = selectedMarks
        guard !marks.isEmpty else { return }
        let boxes: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: marks.map { ($0.id, MarkGeometry.bounds($0, scale: scale)) })
        let union: CGRect = marks.count == 1 ? document.crop : boxes.values.reduce(CGRect.null) { $0.union($1) }
        apply(alignment.title) { document in
            for mark in marks {
                guard let box = boxes[mark.id] else { continue }
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                switch alignment {
                case .left: dx = union.minX - box.minX
                case .centre: dx = union.midX - box.midX
                case .right: dx = union.maxX - box.maxX
                case .top: dy = union.minY - box.minY
                case .middle: dy = union.midY - box.midY
                case .bottom: dy = union.maxY - box.maxY
                }
                document.update(mark.id) { $0 = MarkGeometry.moved($0, by: dx, dy) }
            }
        }
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

    /// Back to the whole image, while cropping.
    func resetCropDraft() {
        cropDraft = document.imageBounds
        cropAspect = .free
    }

    // MARK: Undo

    var canUndo: Bool { undoManager.canUndo || nudgeBase != nil }

    func undo() {
        flushNudge()
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
        changeCount += 1
        onCommit?()
    }

    /// Puts a snapshot back, registering the way back again (so undo becomes redo, and back).
    private func restore(_ snapshot: EditorDocument, _ name: String) {
        let current = document
        let undoing = undoManager.isUndoing
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(current, name) }
        }
        undoManager.setActionName(name)
        document = snapshot
        selection = selection.filter { snapshot[$0] != nil }
        if cropDraft != nil { cropDraft = snapshot.crop }
        changeCount += undoing ? -1 : 1
        onCommit?()
    }

    // MARK: Keys

    /// Esc, one step back: finish typing, leave review, leave crop, deselect, go to Select,
    /// and finally close, but only if nothing changed.
    func escape() -> EscapeStep {
        if editingText != nil {
            endTextEditing?()
            editingText = nil
            return .finishedText
        }
        if review != nil {
            review = nil
            return .cancelledReview
        }
        if tool == .crop {
            cancelCrop()
            return .leftCrop
        }
        if !selection.isEmpty {
            selection = []
            return .deselected
        }
        if tool != .select {
            choose(.select)
            return .choseSelect
        }
        guard isEdited else { return .close }
        showHint("Return finishes · ⌘W closes and keeps your changes")
        return .explained
    }

    /// Return, when no text is being typed: crop, hide what's reviewed, or finish.
    func returnStep() -> ReturnStep {
        if tool == .crop { return .applyCrop }
        if review != nil { return .hideReviewed }
        return .done
    }

    func showHint(_ text: String) {
        transientHint = text
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.transientHint = nil
        }
    }

    // MARK: Hints

    /// Each tool's hint shows its first three times.
    func showsToolHint(_ tool: EditorTool) -> Bool {
        defaults.integer(forKey: Keys.hintUses(tool)) <= 3
    }

    private func noteHintUse(_ tool: EditorTool) {
        let key = Keys.hintUses(tool)
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    /// Counts the tool the editor opened with as a use.
    func noteOpened() {
        noteHintUse(tool)
    }

    // MARK: Actions

    func perform(_ action: EditorAction) {
        onAction?(action)
    }

    /// Shows a tick on the action's button for a moment.
    func confirm(_ action: EditorAction) {
        confirmed = action
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            if self?.confirmed == action { self?.confirmed = nil }
        }
    }

    // MARK: Insight

    func update(insight: CaptureInsight) {
        self.insight = insight
        onChromeChange?()
    }
}

/// The crop tool's proportions.
enum CropAspect: String, CaseIterable, Sendable {
    case free, original, wide, standard, square

    var title: String {
        switch self {
        case .free: "Freeform"
        case .original: "Original"
        case .wide: "16:9"
        case .standard: "4:3"
        case .square: "Square"
        }
    }

    /// Width over height, or nil when free.
    func value(imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        case .wide: 16.0 / 9.0
        case .standard: 4.0 / 3.0
        case .square: 1
        }
    }
}

import AppKit
import AVFoundation
import Observation

/// What the video editor hands back to its host.
enum VideoEditorAction: Equatable {
    case copy, save, done, export, editFrame
}

/// The timeline's tools: pick and trim clips, or cut them where you click.
enum VideoTool: String, CaseIterable {
    case select, blade

    var title: String {
        switch self {
        case .select: "Select"
        case .blade: "Blade"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .blade: "scissors"
        }
    }
}

/// Shapes a crop can keep while you drag it.
enum CropShape: String, CaseIterable {
    case free, wide, standard, square, vertical

    var title: String {
        switch self {
        case .free: "Free"
        case .wide: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        case .vertical: "9:16"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .free: nil
        case .wide: 16.0 / 9
        case .standard: 4.0 / 3
        case .square: 1
        case .vertical: 9.0 / 16
        }
    }
}

/// The video editor's state: the edit with its undo history, the selected clip, the playhead,
/// the tool, and what the timeline shows. Playback lives in `VideoPlayback`, driven from here.
@MainActor
@Observable
final class VideoEditorModel {
    let info: MovieInfo
    /// Pixels per point of the recording (2 on Retina), for "Edit Frame as Picture".
    let scale: CGFloat
    let playback: VideoPlayback

    private(set) var edit: VideoEdit {
        didSet {
            guard edit != oldValue else { return }
            // A shorter movie pulls the playhead in with it.
            if playhead > edit.duration { playhead = edit.duration }
            onEditChange?(oldValue, edit)
        }
    }

    /// The selected clip.
    var selection: UUID? {
        didSet { if selection != oldValue { onSelectionChange?() } }
    }
    /// Where the playhead is in the edited movie, in ticks.
    private(set) var playhead: Int64 = 0
    private(set) var isPlaying = false
    /// The shuttle speed while playing: 1, 2, 4, 8 forwards, negative backwards.
    private(set) var rate: Float = 0
    var loops = false {
        didSet { UserDefaults.standard.set(loops, forKey: Self.loopKey) }
    }
    var tool: VideoTool = .select {
        didSet { if tool != oldValue { onToolChange?() } }
    }
    /// While cropping: the crop being dragged, in movie pixels from the top left.
    private(set) var cropDraft: CGRect?
    var cropShape: CropShape = .free
    var showsInspector = true {
        didSet {
            UserDefaults.standard.set(showsInspector, forKey: Self.inspectorKey)
            if showsInspector != oldValue { onInspectorChange?() }
        }
    }
    /// How far the timeline is zoomed in: 1 shows the whole movie.
    var timelineZoom: CGFloat = 1 {
        didSet { if timelineZoom != oldValue { onZoomChange?() } }
    }
    /// A passing note at the bottom of the picture.
    private(set) var transientHint: String?
    /// The export's size in bytes, roughly; nil while it's worked out.
    private(set) var estimate: Int64?
    /// While making a file: how far along, from 0 to 1, and what it's making.
    private(set) var progress: Double?
    private(set) var progressTitle = ""

    /// The filmstrip's pictures, by movie time in ticks, sorted.
    private(set) var thumbnails: [(time: Int64, image: CGImage)] = []
    /// Each sound track's loudness peaks (`VideoMedia.peaksPerSecond` a second of movie time).
    private(set) var peaks: [[Float]] = []

    @ObservationIgnored let undoManager = UndoManager()
    /// Changes since the editor opened, less those undone.
    private(set) var changeCount = 0
    @ObservationIgnored private var liveBase: VideoEdit?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var estimateTask: Task<Void, Never>?
    @ObservationIgnored private var progressCancel: (() -> Void)?

    @ObservationIgnored var onAction: ((VideoEditorAction) -> Void)?
    /// After every committed change (for autosave).
    @ObservationIgnored var onCommit: (() -> Void)?
    @ObservationIgnored var onEditChange: ((VideoEdit, VideoEdit) -> Void)?
    @ObservationIgnored var onSelectionChange: (() -> Void)?
    @ObservationIgnored var onToolChange: (() -> Void)?
    @ObservationIgnored var onInspectorChange: (() -> Void)?
    @ObservationIgnored var onZoomChange: (() -> Void)?
    @ObservationIgnored var onPlayheadChange: (() -> Void)?
    @ObservationIgnored var onMediaChange: (() -> Void)?
    /// A drag that changed the edit ended: the edit before it and after.
    @ObservationIgnored var onLiveEnd: ((VideoEdit, VideoEdit) -> Void)?

    static let loopKey = "videoEditor.loops"
    static let inspectorKey = "videoEditor.showsInspector"

    init(info: MovieInfo, scale: CGFloat, edit: VideoEdit?) {
        self.info = info
        self.scale = scale
        var start = edit ?? VideoEdit(sourceDuration: info.duration, sourceSize: info.size,
                                      audioTracks: info.audioTracks.count)
        if edit == nil { start.export.format = info.format }
        // A document from another movie of the same name can't apply.
        if start.sourceDuration != info.duration || start.sourceSize != info.size {
            start = VideoEdit(sourceDuration: info.duration, sourceSize: info.size, audioTracks: info.audioTracks.count,
                              export: start.export)
        }
        if start.levels.count != info.audioTracks.count {
            let levels = start.levels
            start.levels = (0..<info.audioTracks.count).map { levels.indices.contains($0) ? levels[$0] : VideoEdit.Level() }
        }
        self.edit = start
        playback = VideoPlayback(info: info)
        undoManager.groupsByEvent = false
        loops = UserDefaults.standard.bool(forKey: Self.loopKey)
        if UserDefaults.standard.object(forKey: Self.inspectorKey) != nil {
            showsInspector = UserDefaults.standard.bool(forKey: Self.inspectorKey)
        }
        playback.onTime = { [weak self] time in self?.playbackMoved(to: time) }
        playback.onEnd = { [weak self] in self?.playbackEnded() }
        playback.onStop = { [weak self] in self?.playbackStopped() }
    }

    var isEdited: Bool { changeCount != 0 }
    var duration: Int64 { edit.duration }
    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }
    var isCropping: Bool { cropDraft != nil }

    var selectedClip: VideoEdit.Clip? {
        guard let selection, let index = edit.index(of: selection) else { return nil }
        return edit.clips[index]
    }

    /// The clip the clip commands act on: the selected one, or else the one under the playhead.
    var targetClip: VideoEdit.Clip? {
        if let selectedClip { return selectedClip }
        guard let (index, _) = edit.clip(at: playhead) else { return nil }
        return edit.clips[index]
    }

    /// The picture's size after the crop.
    var outputSize: CGSize { (edit.crop ?? CGRect(origin: .zero, size: info.size)).size }

    // MARK: Loading

    /// Starts playback and the timeline's pictures and sound.
    func start() {
        playback.load(edit)
        refreshEstimate()
        loadMedia()
    }

    func stop() {
        estimateTask?.cancel()
        hintTask?.cancel()
        progressCancel?()
        playback.close()
        onAction = nil
        onCommit = nil
    }

    private func loadMedia() {
        let count = min(160, max(16, Int(VideoEdit.seconds(info.duration) * 2)))
        let step = max(1, info.duration / Int64(count))
        let times = (0..<count).map { min(info.duration - 1, Int64($0) * step + step / 2) }
        let url = info.url
        Task { [weak self] in
            await VideoMedia.thumbnails(url, times: times, height: 112) { time, image in
                self?.addThumbnail(time, image)
            }
        }
        for (index, track) in info.audioTracks.enumerated() {
            Task { [weak self] in
                let found = await VideoMedia.peaks(url, trackID: track.trackID)
                guard let self else { return }
                while self.peaks.count <= index { self.peaks.append([]) }
                self.peaks[index] = found
                self.onMediaChange?()
            }
        }
    }

    private func addThumbnail(_ time: Int64, _ image: CGImage) {
        let index = thumbnails.firstIndex { $0.time > time } ?? thumbnails.count
        thumbnails.insert((time, image), at: index)
        onMediaChange?()
    }

    /// For previews and tests: the pictures and sound shapes, given directly.
    func setMedia(thumbnails: [(Int64, CGImage)], peaks: [[Float]]) {
        self.thumbnails = thumbnails.sorted { $0.0 < $1.0 }.map { (time: $0.0, image: $0.1) }
        self.peaks = peaks
        onMediaChange?()
    }

    /// The filmstrip picture nearest movie time `time`.
    func thumbnail(near time: Int64) -> CGImage? {
        guard !thumbnails.isEmpty else { return nil }
        var low = 0, high = thumbnails.count - 1
        while low < high {
            let middle = (low + high) / 2
            if thumbnails[middle].time < time { low = middle + 1 } else { high = middle }
        }
        if low > 0, abs(thumbnails[low - 1].time - time) < abs(thumbnails[low].time - time) { low -= 1 }
        return thumbnails[low].image
    }

    // MARK: Editing

    /// Commits a change as one undo step.
    func apply(_ name: String, _ change: (inout VideoEdit) -> Void) {
        var next = edit
        change(&next)
        guard next != edit else { return }
        let before = edit
        edit = next
        registerUndo(restoring: before, name)
    }

    /// Starts a change made over many steps (a drag), committed by `endLiveChange`.
    func beginLiveChange() {
        if liveBase == nil { liveBase = edit }
    }

    func setLive(_ change: (inout VideoEdit) -> Void) {
        var next = edit
        change(&next)
        edit = next
    }

    func endLiveChange(_ name: String) {
        guard let base = liveBase else { return }
        liveBase = nil
        guard base != edit else { return }
        registerUndo(restoring: base, name)
        onLiveEnd?(base, edit)
    }

    var isLiveChanging: Bool { liveBase != nil }

    /// ⌘B: splits the clip under the playhead there; the right-hand piece is then selected.
    func split() {
        var newID: UUID?
        apply("Split Clip") { newID = $0.split(at: playhead) }
        if let newID {
            selection = newID
        } else {
            NSSound.beep()
            showHint("Too close to the clip's edge to split")
        }
    }

    /// Splits at `time` without moving the playhead (the blade).
    func split(at time: Int64) {
        var newID: UUID?
        apply("Split Clip") { newID = $0.split(at: time) }
        if newID == nil { NSSound.beep() }
    }

    /// Delete: takes the selected clip out, and what follows moves up.
    func deleteSelection() {
        guard let clip = selectedClip ?? targetClip, let index = edit.index(of: clip.id) else { return }
        guard edit.clips.count > 1 else {
            NSSound.beep()
            showHint("The last clip stays · trim it instead")
            return
        }
        let start = edit.clipStarts[index]
        apply("Delete Clip") { $0.remove(clip.id) }
        selection = nil
        seek(to: min(start, max(0, edit.duration - 1)))
    }

    /// I: the clip starts at the playhead.
    func trimStartToPlayhead() {
        guard let clip = targetClip, let index = edit.index(of: clip.id) else { return }
        let start = edit.clipStarts[index]
        guard playhead > start, playhead < start + clip.outputDuration else { return NSSound.beep() }
        let source = edit.sourceTime(at: playhead)
        apply("Trim Start") { $0.trimStart(clip.id, to: source) }
        seek(to: start)
    }

    /// O: the clip ends at the playhead.
    func trimEndToPlayhead() {
        guard let clip = targetClip, let index = edit.index(of: clip.id) else { return }
        let start = edit.clipStarts[index]
        guard playhead > start, playhead < start + clip.outputDuration else { return NSSound.beep() }
        let source = edit.sourceTime(at: playhead)
        apply("Trim End") { $0.trimEnd(clip.id, to: source) }
    }

    func setSpeed(_ speed: Double) {
        guard let clip = targetClip else { return }
        let source = edit.sourceTime(at: playhead)
        apply("Change Speed") { $0.setSpeed(speed, for: clip.id) }
        if let time = edit.outputTime(ofSource: source, preferring: clip.id) { seek(to: time) }
    }

    func setFades(_ fades: Bool) {
        apply(fades ? "Fade Sound" : "Don't Fade Sound") { $0.fadesSound = fades }
    }

    func setMuted(_ muted: Bool, track: Int) {
        guard edit.levels.indices.contains(track) else { return }
        apply(muted ? "Mute" : "Unmute") { $0.levels[track].muted = muted }
    }

    /// While a volume slider moves; `endLiveChange` makes it one undo step.
    func setVolumeLive(_ volume: Double, track: Int) {
        guard edit.levels.indices.contains(track) else { return }
        beginLiveChange()
        setLive {
            $0.levels[track].volume = min(max(0, volume), 2)
            if volume > 0 { $0.levels[track].muted = false }
        }
    }

    /// Export choices are kept with the edit, but aren't edits: no undo, and not "edited".
    func setExport(_ change: (inout VideoExportSettings) -> Void) {
        var settings = edit.export
        change(&settings)
        guard settings != edit.export else { return }
        edit.export = settings
        refreshEstimate()
        onCommit?()
    }

    /// Back to the movie as recorded (keeping the export choices).
    func revertToOriginal() {
        apply("Revert to Original") { edit in
            let export = edit.export
            edit = VideoEdit(sourceDuration: info.duration, sourceSize: info.size, audioTracks: info.audioTracks.count,
                             export: export)
        }
        selection = nil
    }

    // MARK: Crop

    func beginCrop() {
        guard cropDraft == nil else { return }
        pause()
        cropDraft = edit.crop ?? CGRect(origin: .zero, size: info.size)
        onToolChange?()
        playback.rebuild(edit, fullFrame: true, at: playhead)
    }

    func updateCropDraft(_ rect: CGRect) {
        guard cropDraft != nil else { return }
        cropDraft = rect
    }

    func applyCrop() {
        guard let draft = cropDraft else { return }
        cropDraft = nil
        let bounds = CGRect(origin: .zero, size: info.size)
        let rect = draft.integral.intersection(bounds)
        let crop: CGRect? = rect.isNull || rect.size == info.size || rect.width < 16 || rect.height < 16 ? nil : rect
        apply("Crop") { $0.crop = crop }
        onToolChange?()
        playback.rebuild(edit, fullFrame: false, at: playhead)
    }

    func cancelCrop() {
        guard cropDraft != nil else { return }
        cropDraft = nil
        onToolChange?()
        playback.rebuild(edit, fullFrame: false, at: playhead)
    }

    /// The crop draft back to the whole picture.
    func resetCropDraft() {
        cropShape = .free
        cropDraft = CGRect(origin: .zero, size: info.size)
    }

    /// The draft reshaped to `shape`, as large as fits around its centre.
    func setCropShape(_ shape: CropShape) {
        cropShape = shape
        guard let draft = cropDraft, let ratio = shape.ratio else { return }
        let bounds = CGRect(origin: .zero, size: info.size)
        var width = draft.width
        var height = width / ratio
        if height > bounds.height {
            height = bounds.height
            width = height * ratio
        }
        if width > bounds.width {
            width = bounds.width
            height = width / ratio
        }
        var rect = CGRect(x: draft.midX - width / 2, y: draft.midY - height / 2, width: width, height: height)
        rect.origin.x = min(max(0, rect.minX), bounds.width - width)
        rect.origin.y = min(max(0, rect.minY), bounds.height - height)
        cropDraft = rect.integral
    }

    // MARK: Undo

    func undo() {
        guard undoManager.canUndo, !isLiveChanging else { return }
        undoManager.undo()
    }

    func redo() {
        guard undoManager.canRedo, !isLiveChanging else { return }
        undoManager.redo()
    }

    private func registerUndo(restoring snapshot: VideoEdit, _ name: String) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(snapshot, name) }
        }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
        changeCount += 1
        onCommit?()
    }

    private func restore(_ snapshot: VideoEdit, _ name: String) {
        let current = edit
        let undoing = undoManager.isUndoing
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(current, name) }
        }
        undoManager.setActionName(name)
        // Export choices aren't part of undo.
        var restored = snapshot
        restored.export = edit.export
        edit = restored
        if let selection, edit.index(of: selection) == nil { self.selection = nil }
        changeCount += undoing ? -1 : 1
        showHint(undoing ? "Undo \(name)" : "Redo \(name)")
        if playhead > edit.duration { seek(to: max(0, edit.duration - 1)) }
        onCommit?()
    }

    // MARK: Playback

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play(rate: Float = 1) {
        guard cropDraft == nil else { return }
        // From the start again once at the end, as QuickTime does.
        if rate > 0, playhead >= edit.duration - info.frameTicks { seek(to: 0) }
        self.rate = rate
        isPlaying = true
        playback.play(rate: rate)
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        rate = 0
        playback.pause()
    }

    /// J and L: faster each press in the same direction; the other way starts over at 1×.
    func shuttle(forward: Bool) {
        let next: Float
        if forward {
            next = rate > 0 ? min(rate * 2, 8) : 1
        } else {
            next = rate < 0 ? max(rate * 2, -8) : -1
        }
        if !forward, playhead <= 0 { return NSSound.beep() }
        play(rate: next)
    }

    /// Moves the playhead; the picture follows, exactly.
    func seek(to time: Int64) {
        let clamped = min(max(0, time), max(0, edit.duration))
        playhead = clamped
        playback.seek(to: clamped)
        onPlayheadChange?()
    }

    func step(frames: Int) {
        pause()
        let target = playhead + Int64(frames) * info.frameTicks
        seek(to: min(max(0, target), max(0, edit.duration - info.frameTicks)))
    }

    func step(seconds: Double) {
        pause()
        seek(to: playhead + VideoEdit.ticks(seconds: seconds))
    }

    func goToStart() {
        pause()
        seek(to: 0)
    }

    func goToEnd() {
        pause()
        seek(to: max(0, edit.duration - info.frameTicks))
    }

    private func playbackMoved(to time: Int64) {
        guard isPlaying else { return }
        playhead = min(max(0, time), edit.duration)
        onPlayheadChange?()
    }

    private func playbackEnded() {
        if loops, rate > 0 {
            seek(to: 0)
            playback.play(rate: rate)
            return
        }
        let backwards = rate < 0
        isPlaying = false
        rate = 0
        playback.pause()
        playhead = backwards ? 0 : edit.duration
        onPlayheadChange?()
    }

    private func playbackStopped() {
        guard isPlaying else { return }
        isPlaying = false
        rate = 0
        onPlayheadChange?()
    }

    // MARK: Hints, estimate and progress

    func showHint(_ text: String) {
        transientHint = text
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.transientHint = nil
        }
    }

    /// Works the export's size out again, shortly after the last change.
    func refreshEstimate() {
        estimateTask?.cancel()
        let info = info
        let edit = edit
        let quick = VideoExporter.estimate(info, edit: edit)
        estimate = quick
        // A GIF's size depends on what moves: measure a few seconds of it.
        guard edit.export.format == .gif else { return }
        estimateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let options = GIFMaker.Options(width: edit.export.gifWidth, fps: edit.export.gifFPS)
            let measured = await GIFMaker.estimate(info, edit: edit, options: options)
            guard !Task.isCancelled, let self else { return }
            self.estimate = measured ?? quick
        }
    }

    func beginProgress(_ title: String, cancel: @escaping () -> Void) {
        progressTitle = title
        progress = 0
        progressCancel = cancel
    }

    func updateProgress(_ value: Double) {
        guard progress != nil else { return }
        progress = max(progress ?? 0, min(1, value))
    }

    func endProgress() {
        progress = nil
        progressCancel = nil
    }

    func cancelProgress() {
        progressCancel?()
        endProgress()
    }

    func perform(_ action: VideoEditorAction) {
        onAction?(action)
    }
}

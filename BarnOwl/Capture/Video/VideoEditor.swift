import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Whoever opened the video editor: it takes the finished file when you copy, save or finish,
/// a frame when you edit one as a picture, and keeps the edit so the movie can be opened again
/// with its cuts still editable.
///
/// `file` is the edited movie or GIF in a temporary folder, named after the editor's title; or,
/// when nothing was changed and the export settings match the movie, the movie itself. Copy it
/// or move it; never delete the movie itself.
@MainActor
protocol VideoEditorHost: AnyObject {
    /// Copy: put the file on the pasteboard.
    func videoEditor(_ editor: VideoEditor, copy file: URL)
    /// Saves over the capture's file, or as a new one. Returns where it went, or nil if it couldn't.
    func videoEditor(_ editor: VideoEditor, save file: URL) async -> URL?
    /// Done: the host copies (and saves per settings); the editor closes itself right after.
    func videoEditor(_ editor: VideoEditor, finish file: URL)
    /// Export… wrote the file where the person chose; it's there already.
    func videoEditor(_ editor: VideoEditor, didExport file: URL)
    /// Edit Frame as Picture: the frame under the playhead, cropped, at full size. `scale` is
    /// pixels per point, as the screenshot editor takes it.
    func videoEditor(_ editor: VideoEditor, editFrame image: CGImage, scale: CGFloat)
    /// The edit changed; called at most about once a second, and once more on close if changed.
    func videoEditor(_ editor: VideoEditor, didChange edit: VideoEdit)
    /// Closed. `edited` is whether anything changed since it opened.
    func videoEditorDidClose(_ editor: VideoEditor, edited: Bool)
}

/// The video editor for one movie: trim, split and delete clips, change their speed, crop,
/// set each sound track's level, and export to MP4, MOV or GIF. The host keeps it until
/// `videoEditorDidClose`, and runs Barn Owl as a regular app while it's open (as for the
/// screenshot editor); the editor puts up its own menus while it's in front.
@MainActor
final class VideoEditor {
    private weak var host: VideoEditorHost?
    let model: VideoEditorModel
    let title: String
    private(set) var controller: VideoEditorWindowController?
    private var closed = false
    private var activationObserver: NSObjectProtocol?
    private var reportTask: Task<Void, Never>?
    private var reported: VideoEdit
    private var lastReport = Date.distantPast
    private var rendering: Task<URL?, Never>?
    private var rendered: (edit: VideoEdit, url: URL)?
    private var started = false

    /// Reads the movie, then makes its editor (not shown yet). Throws when it can't be read.
    /// `edit` reopens earlier cuts (`VideoEdit` is Codable: keep it with the capture);
    /// `scale` is pixels per point, for Edit Frame as Picture.
    static func load(movie: URL, title: String, scale: CGFloat = 2, edit: VideoEdit? = nil,
                     host: VideoEditorHost) async throws -> VideoEditor {
        let info = try await MovieInfo.load(movie)
        return VideoEditor(info: info, title: title, scale: scale, edit: edit, host: host)
    }

    init(info: MovieInfo, title: String, scale: CGFloat = 2, edit: VideoEdit? = nil, host: VideoEditorHost) {
        self.host = host
        self.title = title
        model = VideoEditorModel(info: info, scale: scale, edit: edit)
        reported = model.edit
        model.onAction = { [weak self] action in self?.perform(action) }
        model.onCommit = { [weak self] in self?.scheduleReport() }
        Self.tidyTemporaryFiles()
    }

    /// Orders the window front and makes it key. If Barn Owl isn't active yet, the window is
    /// made key again the moment it is.
    func show() {
        guard !closed else { return }
        let controller = self.controller ?? makeController()
        guard let window = controller.window else { return }
        if !started {
            started = true
            model.start()
            loadPoster()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(controller.timeline)
        if !NSApp.isActive, activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            }
        }
    }

    private func becameActive() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        guard !closed, let controller, let window = controller.window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.timeline)
    }

    func close() {
        if let window = controller?.window, window.isVisible {
            window.close()
        } else {
            didClose()
        }
    }

    /// The current edit.
    var edit: VideoEdit { model.edit }

    // MARK: Window

    @discardableResult
    func makeController() -> VideoEditorWindowController {
        if let controller { return controller }
        let controller = VideoEditorWindowController(model: model, title: title)
        controller.onClose = { [weak self] in self?.didClose() }
        controller.onShareFile = { [weak self] completion in
            guard let self else { return completion(nil) }
            Task { completion(await self.renderFile("Making it")) }
        }
        self.controller = controller
        return controller
    }

    /// The first frame, until the player shows it.
    private func loadPoster() {
        let info = model.info
        let edit = model.edit
        Task { [weak self] in
            guard let image = await VideoMedia.editedFrame(info, edit: edit, at: 0) else { return }
            guard let self, let stage = self.controller?.stage, !stage.playerLayer.isReadyForDisplay else { return }
            stage.showStill(image)
        }
    }

    private func didClose() {
        guard !closed else { return }
        closed = true
        reportTask?.cancel()
        rendering?.cancel()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        if model.edit != reported {
            reported = model.edit
            host?.videoEditor(self, didChange: model.edit)
        }
        model.stop()
        host?.videoEditorDidClose(self, edited: model.isEdited)
    }

    // MARK: Autosave

    private func scheduleReport() {
        guard reportTask == nil, !closed else { return }
        let wait: TimeInterval = max(0.05, 1 - Date().timeIntervalSince(lastReport))
        reportTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.reportTask = nil
            self.report()
        }
    }

    private func report() {
        guard !closed, model.edit != reported else { return }
        reported = model.edit
        lastReport = Date()
        host?.videoEditor(self, didChange: model.edit)
    }

    // MARK: Actions

    private func perform(_ action: VideoEditorAction) {
        if model.isCropping { model.applyCrop() }
        model.pause()
        switch action {
        case .export:
            showExportPanel()
        case .editFrame:
            editFrame()
        case .copy, .save, .done:
            Task { [weak self] in
                guard let self else { return }
                let verb = action == .copy ? "Copying" : "Saving"
                guard let file = await self.renderFile(verb) else { return }
                await self.deliver(action, file)
            }
        }
    }

    private func deliver(_ action: VideoEditorAction, _ file: URL) async {
        guard !closed else { return }
        switch action {
        case .copy:
            host?.videoEditor(self, copy: file)
            controller?.confirmCopy()
        case .save:
            let url = await host?.videoEditor(self, save: file)
            let note = url.map { "Saved · \($0.lastPathComponent)" } ?? "Couldn't save"
            model.showHint(note)
            controller?.announce(note)
        case .done:
            report()
            host?.videoEditor(self, finish: file)
            close()
        case .export, .editFrame:
            break
        }
    }

    private func editFrame() {
        let info = model.info
        let edit = model.edit
        let time = model.playhead
        let scale = model.scale
        Task { [weak self] in
            guard let image = await VideoMedia.editedFrame(info, edit: edit, at: time) else { return NSSound.beep() }
            guard let self, !self.closed else { return }
            self.host?.videoEditor(self, editFrame: image, scale: scale)
        }
    }

    // MARK: Files

    /// Whether the movie itself is what the settings would make.
    private func isPassthrough(_ edit: VideoEdit) -> Bool {
        let settings = edit.export
        return edit.isUntouched && settings.format == model.info.format && settings.format != .gif
            && settings.size == .original && settings.quality == .standard
    }

    /// The edited file, made once per edit: the same file again if nothing changed since.
    func renderFile(_ verb: String) async -> URL? {
        let edit = model.edit
        if isPassthrough(edit) { return model.info.url }
        if let rendered, rendered.edit == edit, FileManager.default.fileExists(atPath: rendered.url.path) { return rendered.url }
        if let rendering { return await rendering.value }
        let folder = Self.temporaryFolder.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: Self.fileName(title, format: edit.export.format))
        let task = Task { [weak self] () -> URL? in
            guard let self else { return nil }
            return await self.write(edit, to: url, verb: verb)
        }
        rendering = task
        let result = await task.value
        rendering = nil
        if let result { rendered = (edit, result) }
        return result
    }

    /// Writes the edit to `url`, showing progress with Cancel.
    private func write(_ edit: VideoEdit, to url: URL, verb: String) async -> URL? {
        let info = model.info
        let model = model
        let title = edit.export.format == .gif ? "Making GIF…" : "\(verb)…"
        let work = Task.detached(priority: .userInitiated) {
            try await VideoExporter.export(info, edit: edit, to: url) { fraction in
                Task { @MainActor in model.updateProgress(fraction) }
            }
        }
        model.beginProgress(title) { work.cancel() }
        let result = await work.result
        model.endProgress()
        switch result {
        case .success: return url
        case .failure(let error):
            if !(error is CancellationError) {
                NSSound.beep()
                model.showHint(error.localizedDescription)
            }
            return nil
        }
    }

    private func showExportPanel() {
        guard let window = controller?.window else { return }
        let format = model.edit.export.format
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(title, format: format)
        panel.allowedContentTypes = [Self.type(format)]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let self else { return }
                Task { await self.export(to: url) }
            }
        }
    }

    private func export(to url: URL) async {
        let edit = model.edit
        // The movie as it is, if that's what was asked for.
        if isPassthrough(edit) {
            do {
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.copyItem(at: model.info.url, to: url)
            } catch {
                NSSound.beep()
                model.showHint("Couldn't export · \(error.localizedDescription)")
                return
            }
        } else {
            guard await write(edit, to: url, verb: "Exporting") != nil else { return }
        }
        host?.videoEditor(self, didExport: url)
        model.showHint("Exported · \(url.lastPathComponent)")
        controller?.announce("Exported")
    }

    static func type(_ format: VideoExportSettings.Format) -> UTType {
        switch format {
        case .gif: .gif
        case .mov: .quickTimeMovie
        case .mp4: .mpeg4Movie
        }
    }

    /// "Screen Recording 2026-10-23 at 14.32.07.mp4": the title, safe as a file name.
    static func fileName(_ title: String, format: VideoExportSettings.Format) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Video" : cleaned
        return "\(base).\(format.fileExtension)"
    }

    static var temporaryFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Barn Owl Video")
    }

    /// Files made more than a day ago have long been pasted or saved.
    static func tidyTemporaryFiles(now: Date = Date()) {
        let folder = temporaryFolder
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        for entry in entries {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            if now.timeIntervalSince(created) > 86_400 { try? manager.removeItem(at: entry) }
        }
    }
}

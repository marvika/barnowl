import AppKit

/// A recording open in the video editor, and what's been done with it there.
struct VideoEditing {
    let editor: VideoEditor
    let captureID: UUID
    /// The edit as Save last wrote it, so closing right after doesn't count as unsaved.
    var savedEdit: VideoEdit?
    /// Done was chosen: its card is already on the way.
    var finished = false
    /// Export… wrote it somewhere.
    var exported = false
}

extension CaptureLibrary {
    /// A recording's cuts as the video editor last left them, kept as its document.
    static func videoEdit(_ id: UUID, in root: URL = folder) -> VideoEdit? {
        guard let data = document(id, in: root), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(VideoEdit.self, from: data)
    }
}

/// Where an edited recording goes when it's saved.
enum EditedVideo {
    /// The saved file, when the edit is the same kind of file (a MOV over a MOV); otherwise nil,
    /// and it's saved anew, so an MP4 or a GIF never takes a movie's name.
    static func overwrites(_ saved: URL?, with file: URL) -> URL? {
        guard let saved, saved.pathExtension.lowercased() == file.pathExtension.lowercased() else { return nil }
        return saved
    }

    /// Copies `file` to `url`, over whatever is there: written beside it first and swapped in,
    /// so a failed copy never leaves half a movie. `file` is never moved or removed.
    static func place(_ file: URL, at url: URL) -> Bool {
        if file.standardizedFileURL == url.standardizedFileURL { return true }
        let manager = FileManager.default
        let temporary = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).\(url.pathExtension)")
        do {
            try manager.copyItem(at: file, to: temporary)
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
            return true
        } catch {
            try? manager.removeItem(at: temporary)
            return false
        }
    }
}

/// The video editor's host: copies, saves and hands on what it makes, as the screenshot editor's
/// host does for pictures, and keeps each recording's cuts with it in history.
extension CaptureCoordinator: VideoEditorHost {
    private func captureID(for editor: VideoEditor) -> UUID? { videoEditors[ObjectIdentifier(editor)]?.captureID }

    func videoEditor(_ editor: VideoEditor, copy file: URL) {
        guard let id = captureID(for: editor) else { return }
        RecordingStore.copy(file)
        copied.insert(id)
    }

    func videoEditor(_ editor: VideoEditor, save file: URL) async -> URL? {
        guard let id = captureID(for: editor) else { return nil }
        let edit = editor.edit
        let url = await saveEditedVideo(file, for: id, edit: edit)
        if url != nil { videoEditors[ObjectIdentifier(editor)]?.savedEdit = edit }
        return url
    }

    /// Done: copied, and saved over its file if it has one (anew only if saving is on), then
    /// back on a card, as for pictures.
    func videoEditor(_ editor: VideoEditor, finish file: URL) {
        guard let id = captureID(for: editor), let capture = capture(id) else { return }
        videoEditors[ObjectIdentifier(editor)]?.finished = true
        let saves = capture.fileURL != nil || Preferences.captureSaves
        let edit = editor.edit
        let showsCard = Preferences.captureThen != .nothing
        Task {
            let saved = saves ? await saveEditedVideo(file, for: id, edit: edit) : nil
            // The saved file, which lasts, rather than the editor's temporary one.
            RecordingStore.copy(saved ?? file)
            copied.insert(id)
            guard showsCard, let capture = self.capture(id) else {
                if saves, saved == nil { NSSound.beep() }
                return
            }
            let status: String
            if !saves {
                status = "Edited · copied"
            } else {
                status = saved != nil ? "Edited · copied and saved" : "Edited · copied · couldn't save"
            }
            cards.add(capture, status: status, kept: true)
        }
    }

    func videoEditor(_ editor: VideoEditor, didExport file: URL) {
        videoEditors[ObjectIdentifier(editor)]?.exported = true
    }

    /// Edit Frame as Picture: a new capture of its own, in the screenshot editor.
    func videoEditor(_ editor: VideoEditor, editFrame image: CGImage, scale: CGFloat) {
        guard let id = captureID(for: editor) else { return }
        let frame = Capture(image: image, scale: scale, kind: .area, date: Date(), appName: capture(id)?.appName)
        deliver(frame, action: .edit, windows: [])
    }

    /// Kept with the recording in history, so its cuts are still there next time.
    func videoEditor(_ editor: VideoEditor, didChange edit: VideoEdit) {
        guard let id = captureID(for: editor), let data = try? JSONEncoder().encode(edit) else { return }
        inOrder(id) { try? CaptureLibrary.storeDocument(data, for: id) }
    }

    func videoEditorDidClose(_ editor: VideoEditor, edited: Bool) {
        guard let editing = videoEditors.removeValue(forKey: ObjectIdentifier(editor)) else { return becomeAccessoryWhenDone() }
        let id = editing.captureID
        if !editing.finished, let capture = capture(id) {
            if edited {
                // Its file has the recording as it was, unless Save or Export wrote the edit.
                let savedAsIs = editing.savedEdit == editor.edit
                let status: String
                if savedAsIs {
                    status = "Edited · saved, not copied yet"
                } else {
                    status = editing.exported ? "Edited · exported" : "Edits kept for next time"
                }
                cards.add(capture, status: status, kept: savedAsIs || editing.exported)
            } else if !isSaved(id), !copied.contains(id) {
                // Opened and closed untouched: unless it's saved or copied, the card is where it lives.
                cards.add(capture, status: status(copied: false, saved: false), kept: false)
            }
        }
        becomeAccessoryWhenDone()
    }

    /// Puts the editor's file where the recording's goes: over its saved file when that's the
    /// same kind, or anew in the recordings folder; history and the card follow. `file` is only
    /// ever copied.
    func saveEditedVideo(_ file: URL, for id: UUID, edit: VideoEdit) async -> URL? {
        guard let capture = capture(id) else { return nil }
        let over = EditedVideo.overwrites(isSaved(id) ? capture.fileURL : nil, with: file)
        let fileExtension = file.pathExtension.lowercased()
        let url = over ?? RecordingStore.reserveURL(date: capture.date, appName: capture.appName, fileExtension: fileExtension)
        let reserved = over == nil
        let placed = await Task.detached(priority: .userInitiated) { () -> Bool in
            defer { if reserved { CaptureStore.release(url) } }
            return EditedVideo.place(file, at: url)
        }.value
        guard placed else {
            Log.app.error("Saving an edited recording failed")
            return nil
        }
        CaptureLibrary.setFile(url, for: id)
        let duration = VideoEdit.seconds(edit.duration)
        let media: CaptureMedia = fileExtension == "gif" ? .gif(duration: duration) : .video(duration: duration)
        CaptureLibrary.update(id) { entry in
            entry.kind = media.libraryKind ?? "video"
            entry.duration = duration
        }
        recordingSaved(id, file: url, media: media)
        return url
    }
}

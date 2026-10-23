import AppKit
import SwiftUI

/// The video editor's colours, beside the screenshot editor's backdrop and accents.
@MainActor
enum VideoEditorStyle {
    /// Under the timeline: lighter than the backdrop in light appearance, a little lifted in dark.
    static let panel = NSColor(name: "videoEditor.panel", dynamicProvider: VideoEditorStyle.panel(for:))

    nonisolated static func panel(for appearance: NSAppearance) -> NSColor {
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 0x26 / 255, green: 0x26 / 255, blue: 0x2A / 255, alpha: 1)
        }
        return NSColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF9 / 255, alpha: 1)
    }

    static var accent: Color { Color(nsColor: EditorCanvas.accent) }
    static var accentFill: Color { Color(nsColor: EditorCanvas.accentFill) }

    static func trackColour(_ index: Int) -> Color { Color(nsColor: VideoTimelineView.colour(forTrack: index)) }

    /// "8.2 MB", "640 KB".
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = count < 1_000_000 ? [.useKB] : [.useMB, .useGB]
        return formatter.string(fromByteCount: count)
    }
}

// MARK: Transport

/// Above the timeline: where the playhead is, the play controls in the middle, and loop and
/// zoom at the trailing end.
struct VideoTransportBar: View {
    let model: VideoEditorModel
    let zoom: (CGFloat?) -> Void

    static let height: CGFloat = 44

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(verbatim: VideoEdit.preciseClock(model.playhead))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    Text(verbatim: "/ \(VideoEdit.preciseClock(model.duration))")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(VideoEdit.preciseClock(model.playhead)) of \(VideoEdit.preciseClock(model.duration))")
                Spacer(minLength: 12)
                HStack(spacing: 2) {
                    Toggle(isOn: Binding(get: { model.loops }, set: { model.loops = $0 })) {
                        Image(systemName: "repeat").frame(width: 26, height: 24)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .foregroundStyle(model.loops ? VideoEditorStyle.accentFill : Color.secondary)
                    .help(VideoCommand.tooltip(.loop))
                    .accessibilityLabel("Loop")
                    Divider().frame(height: 16).padding(.horizontal, 6)
                    Button { zoom(0.66) } label: {
                        Image(systemName: "minus.magnifyingglass").frame(width: 26, height: 24)
                    }
                    .help(VideoCommand.tooltip(.zoomOut, "Zoom Out"))
                    .accessibilityLabel("Zoom Out")
                    Button { zoom(nil) } label: {
                        Image(systemName: "arrow.left.and.right").frame(width: 26, height: 24)
                    }
                    .help(VideoCommand.tooltip(.zoomToFit))
                    .accessibilityLabel("Zoom to Fit")
                    Button { zoom(1.5) } label: {
                        Image(systemName: "plus.magnifyingglass").frame(width: 26, height: 24)
                    }
                    .help(VideoCommand.tooltip(.zoomIn, "Zoom In"))
                    .accessibilityLabel("Zoom In")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button { model.step(frames: -1) } label: {
                    Image(systemName: "backward.frame.fill").font(.system(size: 14))
                }
                .help(VideoCommand.tooltip(.previousFrame))
                .accessibilityLabel("Previous Frame")
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19))
                        .frame(width: 28, height: 28)
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                Button { model.step(frames: 1) } label: {
                    Image(systemName: "forward.frame.fill").font(.system(size: 14))
                }
                .help(VideoCommand.tooltip(.nextFrame))
                .accessibilityLabel("Next Frame")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(model.isCropping)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
    }
}

// MARK: Lane headers

/// Left of the timeline: what each lane is, and each sound track's mute and volume.
struct TimelineHeaders: View {
    let model: VideoEditorModel

    static let width: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: VideoTimelineView.Metrics.ruler + VideoTimelineView.Metrics.gap)
            HStack(spacing: 7) {
                Image(systemName: "film").foregroundStyle(.secondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Video").font(.system(size: 12, weight: .semibold))
                    Text(clipsLine).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(height: VideoTimelineView.Metrics.video, alignment: .leading)
            ForEach(Array(model.info.audioTracks.enumerated()), id: \.offset) { index, track in
                Color.clear.frame(height: VideoTimelineView.Metrics.gap)
                AudioLaneHeader(model: model, index: index, name: track.name)
                    .frame(height: VideoTimelineView.Metrics.audio)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(width: Self.width, alignment: .leading)
    }

    private var clipsLine: String {
        let count = model.edit.clips.count
        return count == 1 ? VideoEdit.clock(model.duration) : "\(count) clips · \(VideoEdit.clock(model.duration))"
    }
}

private struct AudioLaneHeader: View {
    let model: VideoEditorModel
    let index: Int
    let name: String

    private var level: VideoEdit.Level {
        model.edit.levels.indices.contains(index) ? model.edit.levels[index] : VideoEdit.Level()
    }

    var body: some View {
        let muted = level.muted || level.volume == 0
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Button {
                    model.setMuted(!level.muted, track: index)
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .frame(width: 18, height: 16)
                        .foregroundStyle(muted ? Color.secondary : VideoEditorStyle.trackColour(index))
                }
                .buttonStyle(.borderless)
                .help(level.muted ? "Unmute \(name)" : "Mute \(name)")
                .accessibilityLabel(level.muted ? "Unmute \(name)" : "Mute \(name)")
                Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                // Only when it's been changed: 100% goes without saying.
                if level.volume != 1 || level.muted {
                    Text(verbatim: level.muted ? "Off" : "\(Int((level.volume * 100).rounded()))%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Slider(value: Binding(get: { level.volume }, set: { model.setVolumeLive($0, track: index) }), in: 0...2) { editing in
                if !editing { model.endLiveChange("Change Volume") }
            }
            .controlSize(.mini)
            .tint(VideoEditorStyle.trackColour(index))
            .accessibilityLabel("\(name) volume")
            .opacity(level.muted ? 0.5 : 1)
        }
    }
}

// MARK: Inspector

/// The trailing inspector: the clip under the playhead, the sound, and how the movie is made
/// when you copy, save or export it.
struct VideoInspector: View {
    let model: VideoEditorModel
    let export: () -> Void

    static let width: CGFloat = 260

    private var settings: VideoExportSettings { model.edit.export }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let clip = model.targetClip { clipSection(clip) }
                if !model.info.audioTracks.isEmpty { soundSection }
                exportSection
            }
            .font(.system(size: 12.5))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .tint(VideoEditorStyle.accent)
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Clip

    private func clipSection(_ clip: VideoEdit.Clip) -> some View {
        let index = (model.edit.index(of: clip.id) ?? 0) + 1
        let count = model.edit.clips.count
        let title = count == 1 ? "Clip" : "Clip \(index) of \(count)"
        let range = "\(VideoEdit.preciseClock(clip.start)) – \(VideoEdit.preciseClock(clip.end))"
        let plays = VideoEdit.preciseClock(clip.outputDuration)
        return VStack(alignment: .leading, spacing: 14) {
            header(title, clip.speed == 1 ? "\(range) · plays \(plays)" : "\(range) · plays \(plays) at \(VideoTimelineView.speedTitle(clip.speed))")
            section("Speed") {
                Picker("Speed", selection: Binding(get: { clip.speed }, set: { model.setSpeed($0) })) {
                    ForEach(VideoEdit.speeds, id: \.self) { speed in
                        Text(VideoTimelineView.speedTitle(speed)).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(spacing: 8) {
                Button("Split") { model.split() }
                    .help(VideoCommand.tooltip(.split))
                Button("Delete") { model.deleteSelection() }
                    .help(VideoCommand.tooltip(.delete))
                    .disabled(count < 2)
            }
            .controlSize(.small)
        }
    }

    // MARK: Sound

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Sound", soundLine)
            HStack {
                Text("Fade in and out")
                Spacer(minLength: 8)
                Toggle("Fade in and out", isOn: Binding(get: { model.edit.fadesSound }, set: { model.setFades($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    private var soundLine: String {
        let names = model.info.audioTracks.enumerated().map { index, track in
            let level = model.edit.levels.indices.contains(index) ? model.edit.levels[index] : VideoEdit.Level()
            return level.muted ? "\(track.name) muted" : track.name
        }
        return names.joined(separator: " · ")
    }

    // MARK: Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Export", "How Copy, Save and Done make the file.")
            section("Format") {
                Picker("Format", selection: Binding(get: { settings.format }, set: { format in
                    model.setExport { $0.format = format }
                })) {
                    ForEach(VideoExportSettings.Format.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if settings.format == .gif { gifOptions } else { movieOptions }
            estimateView
            Button(action: export) {
                Text("Export…").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .help(VideoCommand.tooltip(.export))
        }
    }

    private var movieOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Size") {
                Picker("Size", selection: Binding(get: { settings.size }, set: { size in
                    model.setExport { $0.size = size }
                })) {
                    ForEach(sizes, id: \.self) { size in
                        Text(sizeTitle(size)).tag(size)
                    }
                }
                .labelsHidden()
            }
            section("Quality") {
                Picker("Quality", selection: Binding(get: { settings.quality }, set: { quality in
                    model.setExport { $0.quality = quality }
                })) {
                    ForEach(VideoExportSettings.Quality.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(qualityLine).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Sizes that would actually make the picture smaller, and the original.
    private var sizes: [VideoExportSettings.Size] {
        let output = model.outputSize
        var seen: Set<String> = []
        return VideoExportSettings.Size.allCases.filter { size in
            var probe = settings
            probe.size = size
            let pixels = probe.pixelSize(for: output)
            return seen.insert("\(pixels.width)x\(pixels.height)").inserted || size == settings.size
        }
    }

    private func sizeTitle(_ size: VideoExportSettings.Size) -> String {
        var probe = settings
        probe.size = size
        let pixels = probe.pixelSize(for: model.outputSize)
        return "\(size.title) · \(Int(pixels.width)) × \(Int(pixels.height))"
    }

    private var qualityLine: String {
        switch settings.quality {
        case .high: "Sharpest text, larger file."
        case .standard: "Crisp text at a sensible size."
        case .small: "HEVC: about half the size. Plays on Macs and iPhones; some websites want H.264."
        }
    }

    private var gifOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Width") {
                Picker("Width", selection: Binding(get: { settings.gifWidth }, set: { width in
                    model.setExport { $0.gifWidth = width }
                })) {
                    ForEach(VideoExportSettings.gifWidths, id: \.self) { width in
                        Text(verbatim: "\(width)").tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            section("Frame rate") {
                Picker("Frame rate", selection: Binding(get: { settings.gifFPS }, set: { fps in
                    model.setExport { $0.gifFPS = fps }
                })) {
                    ForEach(VideoExportSettings.gifRates, id: \.self) { fps in
                        Text(verbatim: "\(fps) fps").tag(fps)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var estimateView: some View {
        let pixels = settings.pixelSize(for: model.outputSize)
        let seconds = VideoEdit.seconds(model.duration)
        let bytes = model.estimate
        let longGIF = settings.format == .gif && ((bytes ?? 0) > 15_000_000 || seconds > 30)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(bytes.map { "About \(VideoEditorStyle.bytes($0))" } ?? "Working it out…")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Text(verbatim: "\(VideoEdit.clock(model.duration)) · \(Int(pixels.width)) × \(Int(pixels.height))")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
            if longGIF {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.amber)
                    Text(gifWarning).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternarySystemFill), in: .rect(cornerRadius: 10))
    }

    private var gifWarning: String {
        var movie = model.edit
        movie.export.format = .mp4
        let mp4 = VideoExporter.estimate(model.info, edit: movie)
        return "Long for a GIF. As MP4 it would be about \(VideoEditorStyle.bytes(mp4))."
    }
}

// MARK: Overlays

/// Bottom centre of the picture: a passing note, or what the tool does.
struct VideoHintStrip: View {
    let model: VideoEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = model.transientHint ?? toolHint
        ZStack {
            if let text {
                Text(text)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity)
                    .id(text)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: text)
    }

    private var toolHint: String? {
        if model.isCropping || model.progress != nil { return nil }
        switch model.tool {
        case .blade: return "Click a clip to cut it there · V goes back to Select"
        case .select: return nil
        }
    }
}

/// While cropping: the shape, Reset, Cancel and Crop, on glass under the picture.
struct CropBar: View {
    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("Shape", selection: Binding(get: { model.cropShape }, set: { model.setCropShape($0) })) {
                ForEach(CropShape.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button("Reset") { model.resetCropDraft() }
            Divider().frame(height: 16)
            Button("Cancel") { model.cancelCrop() }
                .keyboardShortcut(.cancelAction)
            Button("Crop") { model.applyCrop() }
                .buttonStyle(.borderedProminent)
                .tint(VideoEditorStyle.accentFill)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
    }
}

/// While a file is made: what, how far, and Cancel.
struct ExportProgressCapsule: View {
    let model: VideoEditorModel

    var body: some View {
        if let progress = model.progress {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: "\(model.progressTitle) \(Int((progress * 100).rounded()))%")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(VideoEditorStyle.accent)
                        .frame(width: 200)
                }
                Button("Cancel") { model.cancelProgress() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }
}

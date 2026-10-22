import AppKit

/// The timeline: a ruler, the clips as a filmstrip, a lane of sound for each track, and the
/// playhead. Clips sit end to end in the order they play. Click to move the playhead (it snaps
/// to clip edges), drag a clip's edge to trim it, and with the blade, click to cut.
@MainActor
final class VideoTimelineView: NSView {
    let model: VideoEditorModel
    let playhead = PlayheadView()
    /// Keys the timeline doesn't handle itself go to the editor.
    var onKey: ((NSEvent) -> Bool)?
    /// While trimming: the edge's movie time, so the picture can show that frame.
    var onTrimPreview: ((Int64?) -> Void)?

    enum Metrics {
        static let ruler: CGFloat = 24
        static let video: CGFloat = 58
        static let audio: CGFloat = 40
        static let gap: CGFloat = 6
        static let inset: CGFloat = 14
        static let bottom: CGFloat = 12
        static let clipGap: CGFloat = 2
        static let corner: CGFloat = 6
        /// How near an edge counts as on it.
        static let grab: CGFloat = 7
    }

    static func height(audioTracks: Int) -> CGFloat {
        let audio: CGFloat = CGFloat(audioTracks) * (Metrics.audio + Metrics.gap)
        return Metrics.ruler + Metrics.gap + Metrics.video + audio + Metrics.bottom
    }

    /// The selected clip's trim colour, as in Photos and iMovie.
    nonisolated static let trimYellow = NSColor(srgbRed: 1, green: 0.8, blue: 0.05, alpha: 1)

    /// Sound lanes take the owl's colours: lavender for the computer, amber for the mic.
    nonisolated static func colour(forTrack index: Int) -> NSColor {
        switch index {
        case 0: NSColor(srgbRed: 0x8C / 255, green: 0x87 / 255, blue: 1, alpha: 1)
        case 1: NSColor(srgbRed: 0xF5 / 255, green: 0xA6 / 255, blue: 0x33 / 255, alpha: 1)
        default: NSColor.systemTeal
        }
    }

    private enum Drag {
        case scrub
        case trim(UUID, start: Bool, anchor: CGFloat, base: VideoEdit.Clip)
    }

    private var drag: Drag?
    /// Points per second, held still while trimming so the clips don't rescale under the pointer.
    private var frozenScale: CGFloat?
    /// While trimming a start: the clip's index and how far it and the rest stay shifted, so its
    /// right edge holds still until the drag ends.
    private var startTrimShift: (index: Int, ticks: Int64)?
    private var bladeX: CGFloat?
    private var trimLabel: (text: String, x: CGFloat)?
    private var trackingArea: NSTrackingArea?

    init(model: VideoEditorModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: Self.height(audioTracks: model.info.audioTracks.count)))
        wantsLayer = true
        addSubview(playhead)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Timeline")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    private var visibleWidth: CGFloat {
        enclosingScrollView?.contentSize.width ?? bounds.width
    }

    /// Points per second of the edited movie.
    var pointsPerSecond: CGFloat {
        if let frozenScale { return frozenScale }
        let seconds = max(VideoEdit.seconds(model.duration), 0.5)
        let fit: CGFloat = max(10, visibleWidth - 2 * Metrics.inset) / CGFloat(seconds)
        return fit * model.timelineZoom
    }

    /// The most the timeline zooms in: about 14 points a frame.
    var maximumZoom: CGFloat {
        let seconds = max(VideoEdit.seconds(model.duration), 0.5)
        let fit: CGFloat = max(10, visibleWidth - 2 * Metrics.inset) / CGFloat(seconds)
        let most: CGFloat = 14 * CGFloat(model.info.frameRate)
        return max(1, most / fit)
    }

    func x(_ ticks: Int64) -> CGFloat {
        Metrics.inset + CGFloat(VideoEdit.seconds(ticks)) * pointsPerSecond
    }

    func ticks(atX x: CGFloat) -> Int64 {
        VideoEdit.ticks(seconds: Double((x - Metrics.inset) / pointsPerSecond))
    }

    var rulerRect: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: Metrics.ruler) }

    var videoLane: CGRect {
        CGRect(x: 0, y: Metrics.ruler + Metrics.gap, width: bounds.width, height: Metrics.video)
    }

    func audioLane(_ index: Int) -> CGRect {
        let top: CGFloat = videoLane.maxY + Metrics.gap + CGFloat(index) * (Metrics.audio + Metrics.gap)
        return CGRect(x: 0, y: top, width: bounds.width, height: Metrics.audio)
    }

    /// Where each clip sits, from its start to its end, allowing for a start being trimmed.
    func clipSpans() -> [(clip: VideoEdit.Clip, start: Int64, end: Int64)] {
        var spans: [(VideoEdit.Clip, Int64, Int64)] = []
        var cursor: Int64 = 0
        for (index, clip) in model.edit.clips.enumerated() {
            var start = cursor
            if let shift = startTrimShift, index >= shift.index { start += shift.ticks }
            spans.append((clip, start, start + clip.outputDuration))
            cursor += clip.outputDuration
        }
        return spans
    }

    func clipRect(start: Int64, end: Int64, in lane: CGRect) -> CGRect {
        let left: CGFloat = x(start) + Metrics.clipGap / 2
        let right: CGFloat = x(end) - Metrics.clipGap / 2
        return CGRect(x: left, y: lane.minY, width: max(2, right - left), height: lane.height)
    }

    /// Sizes the timeline for the zoom, and keeps the playhead where it is on screen.
    func relayout() {
        let content: CGFloat = 2 * Metrics.inset + CGFloat(VideoEdit.seconds(model.duration)) * pointsPerSecond
        let width = max(visibleWidth, content.rounded(.up))
        let height = Self.height(audioTracks: model.info.audioTracks.count)
        if frame.width != width || frame.height != height {
            setFrameSize(NSSize(width: width, height: height))
        }
        placePlayhead()
        needsDisplay = true
    }

    func placePlayhead() {
        let px = x(model.playhead).rounded()
        playhead.frame = CGRect(x: px - PlayheadView.width / 2, y: 0, width: PlayheadView.width, height: bounds.height)
        playhead.isScrubbing = drag.map { if case .scrub = $0 { true } else { false } } ?? false
    }

    /// While playing, turns the page when the playhead runs off the visible part.
    func keepPlayheadVisible() {
        guard let scrollView = enclosingScrollView else { return }
        let visible = scrollView.contentView.bounds
        let px = x(model.playhead)
        guard px < visible.minX + 8 || px > visible.maxX - 8 else { return }
        let origin = max(0, min(px - 40, bounds.width - visible.width))
        scrollView.contentView.scroll(to: NSPoint(x: origin, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawRuler(in: context, dirty: dirtyRect)
        let spans = clipSpans()
        for span in spans { drawClip(span.clip, start: span.start, end: span.end, in: context) }
        for index in model.info.audioTracks.indices {
            for span in spans { drawSound(index, clip: span.clip, start: span.start, end: span.end, in: context) }
        }
        if let selected = spans.first(where: { $0.clip.id == model.selection }) {
            drawSelection(start: selected.start, end: selected.end, in: context)
        }
        if let bladeX { drawBlade(at: bladeX, in: context) }
        if let trimLabel { drawLabel(trimLabel.text, at: trimLabel.x, in: context) }
    }

    private func drawRuler(in context: CGContext, dirty: CGRect) {
        let pps = pointsPerSecond
        let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800]
        let major = steps.first { CGFloat($0) * pps >= 64 } ?? 3600
        let minorSteps: Double = major >= 60 ? 6 : (major == 15 ? 3 : 5)
        let minor = major / minorSteps
        let seconds = VideoEdit.seconds(model.duration)
        let line = NSColor.tertiaryLabelColor.cgColor
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        context.saveGState()
        context.setStrokeColor(line)
        context.setLineWidth(1)
        let first = max(0, floor(Double((dirty.minX - Metrics.inset) / pps) / minor) - 1)
        var index = Int(first)
        while true {
            let time = Double(index) * minor
            if time > seconds + minor { break }
            let px = (Metrics.inset + CGFloat(time) * pps).rounded() + 0.5
            if px > dirty.maxX + 60 { break }
            let isMajor = index % Int(minorSteps) == 0
            let height: CGFloat = isMajor ? 8 : 4
            if time <= seconds + 0.0001 {
                context.move(to: CGPoint(x: px, y: Metrics.ruler - height))
                context.addLine(to: CGPoint(x: px, y: Metrics.ruler))
            }
            if isMajor, time <= seconds + 0.0001 {
                let label = Self.rulerLabel(time, step: major) as NSString
                let width = label.size(withAttributes: attributes).width
                // At the very end, the label goes before its tick.
                let lx: CGFloat = px + 3 + width > bounds.maxX - 2 ? px - 3 - width : px + 3
                label.draw(at: CGPoint(x: lx, y: 3), withAttributes: attributes)
            }
            index += 1
        }
        context.strokePath()
        context.restoreGState()
    }

    nonisolated static func rulerLabel(_ seconds: Double, step: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        let minutes = whole / 60
        let secs = whole % 60
        if step < 1 {
            let tenths = Int(((seconds - Double(whole)) * 10).rounded())
            return tenths == 0 ? String(format: "%d:%02d", minutes, secs) : String(format: "%d:%02d.%d", minutes, secs, tenths)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func drawClip(_ clip: VideoEdit.Clip, start: Int64, end: Int64, in context: CGContext) {
        let rect = clipRect(start: start, end: end, in: videoLane)
        guard rect.maxX >= 0, rect.minX <= bounds.width else { return }
        let path = CGPath(roundedRect: rect, cornerWidth: Metrics.corner, cornerHeight: Metrics.corner, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.setFillColor(NSColor.quaternaryLabelColor.cgColor)
        context.fill(rect)
        // Pictures across the clip, each showing the moment under its middle.
        let crop = model.edit.crop ?? CGRect(origin: .zero, size: model.info.size)
        let aspect: CGFloat = crop.height > 0 ? crop.width / crop.height : 16 / 9
        let tileWidth: CGFloat = max(24, rect.height * aspect)
        var left = rect.minX
        while left < rect.maxX {
            let middle = min(left + tileWidth / 2, rect.maxX - 1)
            let into = max(0, ticks(atX: middle) - start)
            let source = clip.start + Int64((Double(into) * clip.speed).rounded())
            if let image = model.thumbnail(near: min(source, clip.end)) {
                let picture = Self.cropped(image, crop: model.edit.crop, sourceSize: model.info.size) ?? image
                let tile = CGRect(x: left, y: rect.minY, width: tileWidth, height: rect.height)
                // Flipped view: draw the picture upright.
                context.saveGState()
                context.translateBy(x: 0, y: tile.maxY + tile.minY)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .medium
                context.draw(picture, in: tile)
                context.restoreGState()
            }
            left += tileWidth
        }
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor(white: 0, alpha: 0.25).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
        if clip.speed != 1 { drawSpeedBadge(clip.speed, in: rect, context: context) }
    }

    static func cropped(_ image: CGImage, crop: CGRect?, sourceSize: CGSize) -> CGImage? {
        guard let crop, sourceSize.width > 0 else { return nil }
        let scale = CGFloat(image.width) / sourceSize.width
        let rect = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
        return image.cropping(to: rect.integral)
    }

    private func drawSpeedBadge(_ speed: Double, in rect: CGRect, context: CGContext) {
        let text = Self.speedTitle(speed) as NSString
        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let symbol = speed > 1 ? "hare.fill" : "tortoise.fill"
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        let iconWidth: CGFloat = icon == nil ? 0 : 14
        let badge = CGRect(x: rect.minX + 5, y: rect.minY + 5, width: size.width + iconWidth + 12, height: 17)
        guard badge.maxX < rect.maxX - 4 else { return }
        context.saveGState()
        context.addPath(CGPath(roundedRect: badge, cornerWidth: 8.5, cornerHeight: 8.5, transform: nil))
        context.setFillColor(NSColor(white: 0, alpha: 0.55).cgColor)
        context.fillPath()
        context.restoreGState()
        if let icon {
            let tinted = icon.tinted(.white)
            tinted.draw(in: CGRect(x: badge.minX + 6, y: badge.midY - 5.5, width: 12, height: 11))
        }
        text.draw(at: CGPoint(x: badge.minX + 6 + iconWidth, y: badge.midY - size.height / 2), withAttributes: attributes)
    }

    nonisolated static func speedTitle(_ speed: Double) -> String {
        switch speed {
        case 0.5: "½×"
        case 1.5: "1½×"
        default: "\(Int(speed))×"
        }
    }

    private func drawSound(_ track: Int, clip: VideoEdit.Clip, start: Int64, end: Int64, in context: CGContext) {
        let lane = audioLane(track)
        let rect = clipRect(start: start, end: end, in: lane)
        guard rect.maxX >= 0, rect.minX <= bounds.width else { return }
        let level = model.edit.levels.indices.contains(track) ? model.edit.levels[track] : VideoEdit.Level()
        let colour = level.muted ? NSColor.systemGray : Self.colour(forTrack: track)
        let path = CGPath(roundedRect: rect, cornerWidth: Metrics.corner - 1, cornerHeight: Metrics.corner - 1, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.setFillColor(colour.withAlphaComponent(level.muted ? 0.12 : 0.18).cgColor)
        context.fillPath()
        context.addPath(path)
        context.clip()
        let peaks = model.peaks.indices.contains(track) ? model.peaks[track] : []
        if !peaks.isEmpty {
            let gain: CGFloat = level.muted ? 0.35 : CGFloat(min(level.volume, 2)) / 1.4 + 0.05
            let half: CGFloat = (rect.height - 8) / 2
            let step: CGFloat = 2.5
            let perSecond = Double(VideoMedia.peaksPerSecond)
            var bx = rect.minX + 1
            context.setFillColor(colour.withAlphaComponent(level.muted ? 0.45 : 0.9).cgColor)
            while bx < rect.maxX - 1 {
                let from = max(0, ticks(atX: bx) - start)
                let to = max(from, ticks(atX: bx + step) - start)
                let sourceFrom = Double(clip.start) + Double(from) * clip.speed
                let sourceTo = Double(clip.start) + Double(to) * clip.speed
                let first = Int(sourceFrom / Double(VideoEdit.timescale) * perSecond)
                let last = max(first, Int(sourceTo / Double(VideoEdit.timescale) * perSecond))
                var peak: Float = 0
                if first < peaks.count {
                    for index in first...min(last, peaks.count - 1) { peak = max(peak, peaks[index]) }
                }
                let height: CGFloat = max(1, min(half, CGFloat(sqrt(peak)) * half * gain * 1.2))
                context.fill(CGRect(x: bx, y: rect.midY - height, width: 1.5, height: height * 2))
                bx += step
            }
        } else {
            context.setFillColor(colour.withAlphaComponent(0.5).cgColor)
            context.fill(CGRect(x: rect.minX, y: rect.midY - 0.5, width: rect.width, height: 1))
        }
        context.restoreGState()
    }

    private func drawSelection(start: Int64, end: Int64, in context: CGContext) {
        let rect = clipRect(start: start, end: end, in: videoLane).insetBy(dx: -1, dy: -1)
        let yellow = Self.trimYellow.cgColor
        context.saveGState()
        let outer = CGPath(roundedRect: rect, cornerWidth: Metrics.corner + 1, cornerHeight: Metrics.corner + 1, transform: nil)
        context.addPath(outer)
        context.setStrokeColor(yellow)
        context.setLineWidth(3)
        context.strokePath()
        // Thick edges to pull, with a dark notch, as in Photos.
        let handle: CGFloat = 10
        for left in [true, false] {
            let bar = CGRect(x: left ? rect.minX - 1 : rect.maxX - handle + 1, y: rect.minY - 1, width: handle,
                             height: rect.height + 2)
            context.saveGState()
            let rounded = CGPath(roundedRect: bar, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(rounded)
            context.setFillColor(yellow)
            context.fillPath()
            context.restoreGState()
            let notch = CGRect(x: bar.midX - 1, y: bar.midY - 8, width: 2, height: 16)
            context.addPath(CGPath(roundedRect: notch, cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.setFillColor(NSColor(white: 0, alpha: 0.55).cgColor)
            context.fillPath()
        }
        context.restoreGState()
    }

    private func drawBlade(at px: CGFloat, in context: CGContext) {
        let top = videoLane.minY - 2
        let bottom = model.info.audioTracks.isEmpty ? videoLane.maxY + 2 : audioLane(model.info.audioTracks.count - 1).maxY + 2
        context.saveGState()
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: px, y: top))
        context.addLine(to: CGPoint(x: px, y: bottom))
        context.strokePath()
        context.restoreGState()
    }

    private func drawLabel(_ text: String, at px: CGFloat, in context: CGContext) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let size = (text as NSString).size(withAttributes: attributes)
        var box = CGRect(x: px - size.width / 2 - 7, y: 2, width: size.width + 14, height: 19)
        box.origin.x = min(max(2, box.minX), bounds.width - box.width - 2)
        context.saveGState()
        context.addPath(CGPath(roundedRect: box, cornerWidth: 9.5, cornerHeight: 9.5, transform: nil))
        context.setFillColor(Self.trimYellow.cgColor)
        context.fillPath()
        context.restoreGState()
        (text as NSString).draw(at: CGPoint(x: box.minX + 7, y: box.midY - size.height / 2), withAttributes: attributes)
    }

    // MARK: Hit testing

    private enum Hit {
        case ruler
        case edge(UUID, start: Bool)
        case clip(UUID)
        case empty
    }

    private func hit(_ point: CGPoint) -> Hit {
        if point.y < Metrics.ruler + Metrics.gap / 2 { return .ruler }
        let lanesBottom = model.info.audioTracks.isEmpty ? videoLane.maxY : audioLane(model.info.audioTracks.count - 1).maxY
        guard point.y <= lanesBottom + Metrics.gap / 2 else { return .empty }
        let spans = clipSpans()
        // Edges first, the selected clip's before the rest.
        let ordered = spans.sorted { lhs, _ in lhs.clip.id == model.selection }
        for span in ordered {
            let rect = clipRect(start: span.start, end: span.end, in: videoLane)
            let grab: CGFloat = min(Metrics.grab, rect.width / 3)
            if abs(point.x - rect.minX) <= grab { return .edge(span.clip.id, start: true) }
            if abs(point.x - rect.maxX) <= grab { return .edge(span.clip.id, start: false) }
        }
        for span in spans {
            let rect = clipRect(start: span.start, end: span.end, in: videoLane)
            if point.x >= rect.minX - Metrics.clipGap, point.x <= rect.maxX + Metrics.clipGap { return .clip(span.clip.id) }
        }
        return .empty
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
                                                         .cursorUpdate], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if model.tool == .blade, case .clip = hit(point) {
            bladeX = snappedX(point.x)
        } else if bladeX != nil {
            bladeX = nil
        }
        needsDisplay = true
        updateCursor(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        bladeX = nil
        needsDisplay = true
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursor(at point: CGPoint) {
        switch hit(point) {
        case .edge where model.tool == .select:
            NSCursor.resizeLeftRight.set()
        case .clip where model.tool == .blade, .edge where model.tool == .blade:
            Self.bladeCursor.set()
        default:
            NSCursor.arrow.set()
        }
    }

    static let bladeCursor: NSCursor = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Blade")?
            .withSymbolConfiguration(configuration) else { return .crosshair }
        return NSCursor(image: image.tinted(.labelColor), hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2))
    }()

    /// Near the playhead, the blade cuts there.
    private func snappedX(_ px: CGFloat) -> CGFloat {
        let head = x(model.playhead)
        return abs(px - head) <= 6 ? head : px
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let hit = hit(point)
        if model.tool == .blade {
            switch hit {
            case .clip, .edge:
                model.split(at: ticks(atX: snappedX(point.x)))
                needsDisplay = true
                return
            default: break
            }
        }
        switch hit {
        case .ruler:
            beginScrub(at: point)
        case .edge(let id, let start):
            guard let index = model.edit.index(of: id) else { return }
            model.pause()
            model.selection = id
            frozenScale = pointsPerSecond
            model.beginLiveChange()
            drag = .trim(id, start: start, anchor: point.x, base: model.edit.clips[index])
            updateTrim(at: point)
        case .clip(let id):
            if event.clickCount == 1 { model.selection = id }
            beginScrub(at: point)
        case .empty:
            model.selection = nil
            beginScrub(at: point)
        }
        needsDisplay = true
    }

    private func beginScrub(at point: CGPoint) {
        model.pause()
        drag = .scrub
        scrub(to: point.x)
    }

    private func scrub(to px: CGFloat) {
        var time = ticks(atX: px)
        // Clip edges pull the playhead to them.
        for start in model.edit.clipStarts + [model.duration] where abs(x(start) - px) <= 5 {
            time = start
            break
        }
        model.seek(to: min(max(0, time), max(0, model.duration - 1)))
        placePlayhead()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .scrub:
            scrub(to: point.x)
            autoscroll(with: event)
        case .trim:
            updateTrim(at: point)
            autoscroll(with: event)
        case nil:
            break
        }
    }

    private func updateTrim(at point: CGPoint) {
        guard case .trim(let id, let isStart, let anchor, let base)? = drag,
              let index = model.edit.index(of: id) else { return }
        let delta = Double(point.x - anchor) / Double(pointsPerSecond) * base.speed
        var moved = Int64((delta * Double(VideoEdit.timescale)).rounded())
        let frame = model.info.frameTicks
        // Whole frames, and the playhead pulls the edge to it.
        moved = (moved / frame) * frame
        let starts = model.edit.clipStarts
        if isStart {
            let target = base.start + moved
            model.setLive { $0.trimStart(id, to: target) }
            let clip = model.edit.clips[index]
            // The right edge holds still while you drag; the rest closes up when you let go.
            startTrimShift = (index, base.outputDuration - clip.outputDuration)
            trimLabel = (VideoEdit.preciseClock(clip.start), x(starts[index] + (startTrimShift?.ticks ?? 0)))
            onTrimPreview?(clip.start)
        } else {
            var target = base.end + moved
            let head = model.playhead
            if let clipEnd = Optional(starts[index] + VideoEdit.Clip(start: base.start, duration: target - base.start,
                                                                     speed: base.speed).outputDuration),
               abs(x(clipEnd) - x(head)) <= 5, head > starts[index] {
                target = base.start + Int64(Double(head - starts[index]) * base.speed)
            }
            model.setLive { $0.trimEnd(id, to: target) }
            let clip = model.edit.clips[index]
            trimLabel = (VideoEdit.preciseClock(clip.end), x(starts[index] + clip.outputDuration))
            onTrimPreview?(max(clip.start, clip.end - frame))
        }
        relayout()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            placePlayhead()
            needsDisplay = true
        }
        guard case .trim(let id, let isStart, _, _)? = drag else { return }
        startTrimShift = nil
        trimLabel = nil
        frozenScale = nil
        model.endLiveChange("Trim Clip")
        onTrimPreview?(nil)
        if let index = model.edit.index(of: id) {
            let starts = model.edit.clipStarts
            let edge = isStart ? starts[index] : starts[index] + model.edit.clips[index].outputDuration - model.info.frameTicks
            model.seek(to: max(starts[index], edge))
        }
        relayout()
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil).x)
    }

    override func scrollWheel(with event: NSEvent) {
        // ⌘-scroll zooms, as in Final Cut; plain scrolling moves along.
        if event.modifierFlags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 10
            zoom(by: 1 + delta, around: convert(event.locationInWindow, from: nil).x)
            return
        }
        super.scrollWheel(with: event)
    }

    /// Zooms the timeline, keeping the moment at `anchor` under the pointer.
    func zoom(by factor: CGFloat, around anchor: CGFloat? = nil) {
        guard let scrollView = enclosingScrollView else {
            model.timelineZoom = min(max(1, model.timelineZoom * factor), maximumZoom)
            return
        }
        let visible = scrollView.contentView.bounds
        let px = anchor ?? x(model.playhead)
        let time = ticks(atX: px)
        let onScreen = px - visible.minX
        model.timelineZoom = min(max(1, model.timelineZoom * factor), maximumZoom)
        relayout()
        let origin = max(0, min(x(time) - onScreen, bounds.width - visible.width))
        scrollView.contentView.scroll(to: NSPoint(x: origin, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        var clipID: UUID?
        switch hit(point) {
        case .clip(let id), .edge(let id, _): clipID = id
        default: break
        }
        guard let clipID else { return nil }
        model.selection = clipID
        needsDisplay = true
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Split at Playhead") { [weak self] in self?.model.split() })
        menu.addItem(ClosureMenuItem("Trim Start to Playhead") { [weak self] in self?.model.trimStartToPlayhead() })
        menu.addItem(ClosureMenuItem("Trim End to Playhead") { [weak self] in self?.model.trimEndToPlayhead() })
        let speed = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        let speeds = NSMenu(title: "Speed")
        let current = model.selectedClip?.speed ?? 1
        for value in VideoEdit.speeds {
            speeds.addItem(ClosureMenuItem(Self.speedTitle(value), checked: value == current) { [weak self] in
                self?.model.setSpeed(value)
            })
        }
        speed.submenu = speeds
        menu.addItem(speed)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Delete Clip") { [weak self] in self?.model.deleteSelection() })
        return menu
    }
}

/// The playhead: a white line with a knob on the ruler.
final class PlayheadView: NSView {
    static let width: CGFloat = 13
    var isScrubbing = false {
        didSet { if isScrubbing != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let mid = bounds.midX
        // A dark edge keeps the white line and knob visible on light ground and light pictures.
        let edge = CGColor(gray: 0, alpha: 0.45)
        context.setFillColor(edge)
        context.fill(CGRect(x: mid - 1.75, y: 12, width: 3.5, height: bounds.height - 12))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: mid - 1, y: 12, width: 2, height: bounds.height - 12))
        // The knob: a rounded tab pointing down at the line.
        let knob = CGMutablePath()
        knob.addRoundedRect(in: CGRect(x: mid - 6, y: 2, width: 12, height: 11), cornerWidth: 3, cornerHeight: 3)
        knob.move(to: CGPoint(x: mid - 6, y: 9))
        knob.addLine(to: CGPoint(x: mid, y: 17))
        knob.addLine(to: CGPoint(x: mid + 6, y: 9))
        knob.closeSubpath()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 0.5), blur: 1.5, color: CGColor(gray: 0, alpha: 0.4))
        context.addPath(knob)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.addPath(knob)
        context.setStrokeColor(edge)
        context.setLineWidth(0.75)
        context.strokePath()
    }
}

private extension NSImage {
    /// A template image filled with one colour.
    func tinted(_ colour: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            colour.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}

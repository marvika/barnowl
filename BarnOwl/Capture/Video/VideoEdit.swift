import CoreGraphics
import CoreMedia
import Foundation

/// A movie's edits, kept apart from the movie so they can be changed again: the clips taken
/// from it in order, the crop, each sound track's level, and how to export it. Times are whole
/// ticks of 1/600 s, which every common frame rate divides, so no range ever ends on a fraction.
struct VideoEdit: Codable, Equatable, Sendable {
    static let currentSchema = 1
    /// Ticks per second for every time in the document.
    static let timescale: CMTimeScale = 600
    /// No clip is shorter than this (20 ms).
    static let minimumClip: Int64 = 12
    /// The speeds a clip can play at.
    static let speeds: [Double] = [0.5, 1, 1.5, 2, 4]

    /// A stretch of the movie, played at a speed.
    struct Clip: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        /// Where it starts in the movie, in ticks.
        var start: Int64
        /// How much of the movie it takes, in ticks.
        var duration: Int64
        /// 1 is normal speed; 2 plays it in half the time.
        var speed: Double = 1

        init(id: UUID = UUID(), start: Int64, duration: Int64, speed: Double = 1) {
            self.id = id
            self.start = start
            self.duration = duration
            self.speed = speed
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            start = try c.decodeIfPresent(Int64.self, forKey: .start) ?? 0
            duration = try c.decodeIfPresent(Int64.self, forKey: .duration) ?? 0
            speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        }

        var end: Int64 { start + duration }

        /// How long it plays for, in ticks.
        var outputDuration: Int64 {
            guard speed != 1 else { return duration }
            return max(1, Int64((Double(duration) / speed).rounded()))
        }
    }

    /// One sound track's level.
    struct Level: Codable, Equatable, Sendable {
        /// From 0 to 2: 1 is as recorded.
        var volume: Double = 1
        var muted = false

        init(volume: Double = 1, muted: Bool = false) {
            self.volume = volume
            self.muted = muted
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
            muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        }

        var isUntouched: Bool { volume == 1 && !muted }
        /// What the mix plays it at.
        var gain: Float { muted ? 0 : Float(volume) }
    }

    var schemaVersion = VideoEdit.currentSchema
    /// The movie's own length, in ticks.
    var sourceDuration: Int64
    /// The movie's picture, upright, in pixels.
    var sourceSize: CGSize
    var clips: [Clip]
    /// The part of the picture kept, in pixels from the top left; nil keeps all of it.
    var crop: CGRect?
    /// Each sound track's level, in the movie's track order.
    var levels: [Level]
    /// Fade the sound in at the start and out at the end.
    var fadesSound = false
    /// How Copy, Save, Done and Export make the file.
    var export: VideoExportSettings

    /// The whole movie, untouched.
    init(sourceDuration: Int64, sourceSize: CGSize, audioTracks: Int = 0, export: VideoExportSettings = VideoExportSettings()) {
        self.sourceDuration = max(1, sourceDuration)
        self.sourceSize = sourceSize
        clips = [Clip(start: 0, duration: max(1, sourceDuration))]
        levels = Array(repeating: Level(), count: audioTracks)
        self.export = export
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sourceDuration = max(1, try c.decode(Int64.self, forKey: .sourceDuration))
        sourceSize = try c.decode(CGSize.self, forKey: .sourceSize)
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
        crop = try c.decodeIfPresent(CGRect.self, forKey: .crop)
        levels = try c.decodeIfPresent([Level].self, forKey: .levels) ?? []
        fadesSound = try c.decodeIfPresent(Bool.self, forKey: .fadesSound) ?? false
        export = try c.decodeIfPresent(VideoExportSettings.self, forKey: .export) ?? VideoExportSettings()
        schemaVersion = Self.currentSchema
        sanitise()
    }

    /// Keeps a document read from disk within the movie: clips inside it and long enough,
    /// speeds from the list, the crop on the picture.
    mutating func sanitise() {
        clips = clips.compactMap { clip in
            var clip = clip
            clip.start = min(max(0, clip.start), sourceDuration - Self.minimumClip)
            clip.duration = min(max(Self.minimumClip, clip.duration), sourceDuration - clip.start)
            clip.speed = Self.speeds.min { abs($0 - clip.speed) < abs($1 - clip.speed) } ?? 1
            return clip.duration > 0 ? clip : nil
        }
        if clips.isEmpty { clips = [Clip(start: 0, duration: sourceDuration)] }
        if let crop {
            let kept = crop.integral.intersection(CGRect(origin: .zero, size: sourceSize))
            self.crop = kept.isNull || kept.width < 16 || kept.height < 16 || kept.size == sourceSize ? nil : kept
        }
        for index in levels.indices { levels[index].volume = min(max(0, levels[index].volume), 2) }
    }

    // MARK: Time

    /// How long the edited movie plays for, in ticks.
    var duration: Int64 { clips.reduce(0) { $0 + $1.outputDuration } }

    /// Whether this is the movie exactly as recorded, sound and all.
    var isUntouched: Bool {
        clips.count == 1 && clips[0].start == 0 && clips[0].duration == sourceDuration && clips[0].speed == 1 && crop == nil
            && levels.allSatisfy(\.isUntouched) && !fadesSound
    }

    /// Where each clip starts in the edited movie, in ticks.
    var clipStarts: [Int64] {
        var starts: [Int64] = []
        var cursor: Int64 = 0
        for clip in clips {
            starts.append(cursor)
            cursor += clip.outputDuration
        }
        return starts
    }

    /// The clip playing at `time` in the edited movie, and how far into it (in output ticks).
    /// The very end belongs to the last clip.
    func clip(at time: Int64) -> (index: Int, offset: Int64)? {
        guard !clips.isEmpty else { return nil }
        var cursor: Int64 = 0
        for (index, clip) in clips.enumerated() {
            let length = clip.outputDuration
            if time < cursor + length { return (index, max(0, time - cursor)) }
            cursor += length
        }
        let last = clips.count - 1
        return (last, clips[last].outputDuration)
    }

    /// The movie's own time showing at `time` in the edited movie.
    func sourceTime(at time: Int64) -> Int64 {
        guard let (index, offset) = clip(at: time) else { return 0 }
        let clip = clips[index]
        let into = Int64((Double(offset) * clip.speed).rounded())
        return min(clip.start + into, clip.end)
    }

    /// Where the movie's own time `source` shows in the edited movie, if a clip keeps it.
    /// Prefers the clip `preferring` when clips overlap.
    func outputTime(ofSource source: Int64, preferring id: UUID? = nil) -> Int64? {
        let starts = clipStarts
        var found: Int64?
        for (index, clip) in clips.enumerated() where source >= clip.start && source <= clip.end {
            let time = starts[index] + Int64((Double(source - clip.start) / clip.speed).rounded())
            if clip.id == id { return time }
            if found == nil { found = time }
        }
        return found
    }

    func index(of id: UUID) -> Int? { clips.firstIndex { $0.id == id } }

    // MARK: Editing

    /// Splits the clip playing at `time` in two. Returns the new right-hand clip's id, or nil
    /// when `time` is too near a clip's edge.
    @discardableResult
    mutating func split(at time: Int64) -> UUID? {
        guard let (index, offset) = clip(at: time) else { return nil }
        let clip = clips[index]
        let into = Int64((Double(offset) * clip.speed).rounded())
        guard into >= Self.minimumClip, clip.duration - into >= Self.minimumClip else { return nil }
        var left = clip
        left.duration = into
        var right = clip
        right.id = UUID()
        right.start = clip.start + into
        right.duration = clip.duration - into
        clips[index] = left
        clips.insert(right, at: index + 1)
        return right.id
    }

    /// Takes a clip out; what follows closes the gap. The last clip always stays.
    @discardableResult
    mutating func remove(_ id: UUID) -> Bool {
        guard clips.count > 1, let index = index(of: id) else { return false }
        clips.remove(at: index)
        return true
    }

    /// Moves a clip's start to `source` in the movie, keeping its end.
    mutating func trimStart(_ id: UUID, to source: Int64) {
        guard let index = index(of: id) else { return }
        let end = clips[index].end
        let start = min(max(0, source), end - Self.minimumClip)
        clips[index].start = start
        clips[index].duration = end - start
    }

    /// Moves a clip's end to `source` in the movie, keeping its start.
    mutating func trimEnd(_ id: UUID, to source: Int64) {
        guard let index = index(of: id) else { return }
        let start = clips[index].start
        let end = max(min(sourceDuration, source), start + Self.minimumClip)
        clips[index].duration = end - start
    }

    mutating func setSpeed(_ speed: Double, for id: UUID) {
        guard let index = index(of: id) else { return }
        clips[index].speed = speed
    }

    /// Moves a clip to another place in the order.
    mutating func move(_ id: UUID, to destination: Int) {
        guard let index = index(of: id) else { return }
        let clip = clips.remove(at: index)
        clips.insert(clip, at: min(max(0, destination), clips.count))
    }

    // MARK: Composition

    /// One clip as the composition lays it out: the movie's range, where it lands, how long it plays.
    struct Segment: Equatable, Sendable {
        let source: CMTimeRange
        let at: CMTime
        let duration: CMTime
    }

    /// The clips in order, as composition time ranges.
    var segments: [Segment] {
        var cursor: Int64 = 0
        return clips.map { clip in
            let segment = Segment(source: CMTimeRange(start: Self.time(clip.start), duration: Self.time(clip.duration)),
                                  at: Self.time(cursor), duration: Self.time(clip.outputDuration))
            cursor += clip.outputDuration
            return segment
        }
    }

    static func time(_ ticks: Int64) -> CMTime { CMTime(value: ticks, timescale: timescale) }

    static func ticks(_ time: CMTime) -> Int64 {
        guard time.isNumeric else { return 0 }
        return Int64((time.seconds * Double(timescale)).rounded())
    }

    static func ticks(seconds: Double) -> Int64 { Int64((seconds * Double(timescale)).rounded()) }

    static func seconds(_ ticks: Int64) -> Double { Double(ticks) / Double(timescale) }

    /// "0:42", "1:05:09": how long, for people.
    static func clock(_ ticks: Int64) -> String {
        let total = Int((seconds(ticks)).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "0:12.4": the playhead, to a tenth of a second.
    static func preciseClock(_ ticks: Int64) -> String {
        let tenths = Int((seconds(ticks) * 10).rounded(.down))
        let total = tenths / 10
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d.%d", hours, minutes, secs, tenths % 10) }
        return String(format: "%d:%02d.%d", minutes, secs, tenths % 10)
    }
}

/// What an edited movie becomes: the file type, its size and quality, and for a GIF its width
/// and frame rate.
struct VideoExportSettings: Codable, Equatable, Sendable {
    enum Format: String, Codable, CaseIterable, Sendable {
        case mp4, mov, gif

        var title: String {
            switch self {
            case .mp4: "MP4"
            case .mov: "MOV"
            case .gif: "GIF"
            }
        }

        var fileExtension: String { rawValue }
    }

    /// The largest the picture can be; never larger than the movie.
    enum Size: String, Codable, CaseIterable, Sendable {
        case original, hd1080, hd720, sd480

        var title: String {
            switch self {
            case .original: "Original"
            case .hd1080: "1080p"
            case .hd720: "720p"
            case .sd480: "480p"
            }
        }

        /// The long and short edges it fits in.
        var box: (long: CGFloat, short: CGFloat)? {
            switch self {
            case .original: nil
            case .hd1080: (1920, 1080)
            case .hd720: (1280, 720)
            case .sd480: (854, 480)
            }
        }
    }

    enum Quality: String, Codable, CaseIterable, Sendable {
        case high, standard, small

        var title: String {
            switch self {
            case .high: "High"
            case .standard: "Standard"
            case .small: "Small"
            }
        }
    }

    var format: Format = .mp4
    var size: Size = .original
    var quality: Quality = .standard
    /// A GIF's width in pixels (never wider than the movie).
    var gifWidth: Int = GIFMaker.Options.defaultWidth
    /// A GIF's frames per second.
    var gifFPS: Int = GIFMaker.Options.defaultFPS

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decodeIfPresent(Format.self, forKey: .format)) ?? .mp4
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? .original
        quality = (try? c.decodeIfPresent(Quality.self, forKey: .quality)) ?? .standard
        gifWidth = try c.decodeIfPresent(Int.self, forKey: .gifWidth) ?? GIFMaker.Options.defaultWidth
        gifFPS = try c.decodeIfPresent(Int.self, forKey: .gifFPS) ?? GIFMaker.Options.defaultFPS
    }

    static let gifWidths = [480, 800, 1200]
    static let gifRates = [10, 15, 24]

    /// The picture's size in pixels for a movie whose (cropped) picture is `size`: fitted in
    /// the chosen box, never enlarged, and with even sides as video encoders want.
    func pixelSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        if format == .gif {
            let width = min(CGFloat(gifWidth), size.width)
            let height = (size.height * width / size.width).rounded()
            return CGSize(width: width.rounded(), height: max(1, height))
        }
        var scale: CGFloat = 1
        if let box = self.size.box {
            let landscape = size.width >= size.height
            let maxWidth: CGFloat = landscape ? box.long : box.short
            let maxHeight: CGFloat = landscape ? box.short : box.long
            scale = min(1, maxWidth / size.width, maxHeight / size.height)
        }
        let width = Self.even(size.width * scale)
        let height = Self.even(size.height * scale)
        return CGSize(width: width, height: height)
    }

    static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded(.down) * 2)
    }
}

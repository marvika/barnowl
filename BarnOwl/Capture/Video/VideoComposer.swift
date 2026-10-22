import AVFoundation
import CoreGraphics
import Synchronization

/// What the editor needs to know about a movie, read once when it opens.
struct MovieInfo: Equatable, Sendable {
    /// One sound track in the movie.
    struct AudioTrack: Equatable, Sendable {
        let trackID: CMPersistentTrackID
        /// "Computer", "Mic", or the track's own name.
        let name: String
    }

    let url: URL
    /// Its length, in ticks of 1/600 s.
    let duration: Int64
    /// The picture as it plays, upright, in pixels.
    let size: CGSize
    /// The most frames it shows in a second (screen recordings vary), at most 60.
    let frameRate: Double
    /// The picture's bits per second, as stored.
    let videoDataRate: Double
    let audioTracks: [AudioTrack]
    /// Whether it has a picture at all.
    let hasVideo: Bool

    /// The file's own kind, by its extension.
    var format: VideoExportSettings.Format {
        switch url.pathExtension.lowercased() {
        case "gif": .gif
        case "mov", "qt": .mov
        default: .mp4
        }
    }

    /// One frame, in ticks.
    var frameTicks: Int64 { max(1, Int64((Double(VideoEdit.timescale) / max(frameRate, 1)).rounded())) }

    /// Reads a movie's tracks and timing. Throws when it can't be read or has no picture.
    static func load(_ url: URL) async throws -> MovieInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEditError.noPicture }
        let (natural, transform, minFrame, dataRate) = try await video.load(.naturalSize, .preferredTransform,
                                                                              .minFrameDuration, .estimatedDataRate)
        let upright = natural.applying(transform)
        let size = CGSize(width: abs(upright.width).rounded(), height: abs(upright.height).rounded())
        var rate: Double = minFrame.isNumeric && minFrame.seconds > 0 ? 1 / minFrame.seconds : 30
        if !rate.isFinite || rate <= 0 { rate = 30 }
        rate = min(rate, 60)

        let audio = try await asset.loadTracks(withMediaType: .audio)
        var names: [String?] = []
        for track in audio { names.append(await Self.name(of: track)) }
        let fallback = Self.fallbackNames(count: audio.count)
        var tracks: [AudioTrack] = []
        for (index, track) in audio.enumerated() {
            tracks.append(AudioTrack(trackID: track.trackID, name: names[index] ?? fallback[index]))
        }
        return MovieInfo(url: url, duration: VideoEdit.ticks(duration), size: size, frameRate: rate,
                         videoDataRate: Double(dataRate), audioTracks: tracks, hasVideo: true)
    }

    /// Names for sound tracks that don't name themselves: a recording keeps the computer's
    /// sound first and the mic second.
    static func fallbackNames(count: Int) -> [String] {
        switch count {
        case 0: []
        case 1: ["Sound"]
        case 2: ["Computer", "Mic"]
        default: (1...count).map { "Sound \($0)" }
        }
    }

    /// A track's title, from its metadata ("Computer" and "Mic" in Barn Owl's recordings).
    private static func name(of track: AVAssetTrack) async -> String? {
        guard let items = try? await track.load(.metadata) else { return nil }
        let identifiers: [AVMetadataIdentifier] = [.commonIdentifierTitle, .quickTimeUserDataTrackName,
                                                   .quickTimeMetadataDisplayName]
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
            }
        }
        return nil
    }
}

enum VideoEditError: LocalizedError {
    case noPicture
    case unreadable
    case cancelled
    case writeFailed(String?)
    case tooLongForGIF

    var errorDescription: String? {
        switch self {
        case .noPicture: "This file has no picture to edit."
        case .unreadable: "Barn Owl couldn't read this movie."
        case .cancelled: "Cancelled."
        case .writeFailed(let reason): reason.map { "Couldn't make the file: \($0)" } ?? "Couldn't make the file."
        case .tooLongForGIF: "Too long for a GIF. Trim it, or export a movie instead."
        }
    }
}

/// An edited movie, ready to play, read or write: the clips laid end to end, the sound at its
/// levels, and the picture cropped and sized. Not Sendable: build it where it's used.
struct VideoComposition {
    let composition: AVComposition
    /// Crops and sizes the picture; nil plays it as it is.
    let videoComposition: AVVideoComposition?
    let audioMix: AVAudioMix?
    /// The picture's size in pixels.
    let renderSize: CGSize
    let duration: CMTime
    /// The composition's sound tracks, by the movie's track order, for each one that's kept.
    let audioTrackIDs: [Int: CMPersistentTrackID]
}

/// Builds compositions from a movie and its edits. Preview, movie export and GIF all come out
/// of the same composition, so what plays is what you get.
enum VideoComposer {
    /// How the composition will be used.
    struct Output: Sendable {
        /// The picture's size in pixels; nil for the crop's own size.
        var size: CGSize?
        /// Frames per second for the picture; nil keeps the movie's.
        var frameRate: Double?
        /// Keep every sound track, muted ones at zero, so levels can change while playing.
        var keepsMutedTracks = false
        /// Always make a video composition, even with nothing to crop or scale.
        var alwaysComposes = false

        static let preview = Output(keepsMutedTracks: true)
    }

    static func build(_ asset: AVURLAsset, info: MovieInfo, edit: VideoEdit, output: Output) async throws -> sending VideoComposition {
        guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEditError.noPicture }
        let transform = try await source.load(.preferredTransform)
        let audioSources = try await asset.loadTracks(withMediaType: .audio)
        var audioRanges: [CMTimeRange] = []
        for track in audioSources { audioRanges.append(try await track.load(.timeRange)) }

        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoEditError.unreadable
        }
        video.preferredTransform = transform

        // The sound tracks that are heard (all of them, for preview).
        var audio: [(index: Int, source: AVAssetTrack, range: CMTimeRange, track: AVMutableCompositionTrack,
                     level: VideoEdit.Level)] = []
        for (index, track) in audioSources.enumerated() {
            let level = edit.levels.indices.contains(index) ? edit.levels[index] : VideoEdit.Level()
            guard output.keepsMutedTracks || level.gain > 0 else { continue }
            guard let added = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                continue
            }
            audio.append((index, track, audioRanges[index], added, level))
        }

        var cursor = CMTime.zero
        for segment in edit.segments {
            try video.insertTimeRange(segment.source, of: source, at: cursor)
            for entry in audio {
                // Only what the track has: a mic can start late or stop early.
                let heard = segment.source.intersection(entry.range)
                guard heard.duration > .zero else { continue }
                let at = cursor + (heard.start - segment.source.start)
                let range = entry.track.timeRange
                let end = range.isValid && !range.isEmpty ? range.end : .zero
                if end < at { entry.track.insertEmptyTimeRange(CMTimeRange(start: end, end: at)) }
                try entry.track.insertTimeRange(heard, of: entry.source, at: at)
            }
            if segment.duration != segment.source.duration {
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: segment.source.duration), toDuration: segment.duration)
            }
            cursor = cursor + segment.duration
        }
        // Tracks that ended early run silent to the end, so every track is as long as the picture.
        for entry in audio where entry.track.timeRange.end < cursor && entry.track.timeRange.duration > .zero {
            entry.track.insertEmptyTimeRange(CMTimeRange(start: entry.track.timeRange.end, end: cursor))
        }
        // A track left with nothing in it is dropped: empty tracks upset readers and exports.
        for entry in audio where entry.track.segments.isEmpty || entry.track.timeRange.duration == .zero {
            composition.removeTrack(entry.track)
        }
        let kept = audio.filter { composition.track(withTrackID: $0.track.trackID) != nil }

        let duration = cursor
        let mix = audioMix(kept.map { ($0.track.trackID, $0.level) }, duration: duration, fades: edit.fadesSound)

        let crop = edit.crop ?? CGRect(origin: .zero, size: info.size)
        let size = output.size ?? CGSize(width: VideoExportSettings.even(crop.width), height: VideoExportSettings.even(crop.height))
        var videoComposition: AVVideoComposition?
        if output.alwaysComposes || edit.crop != nil || output.size != nil || output.frameRate != nil {
            let scaleX: CGFloat = size.width / crop.width
            let scaleY: CGFloat = size.height / crop.height
            let shift = CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
            let scale = CGAffineTransform(scaleX: scaleX, y: scaleY)
            let placed = transform.concatenating(shift).concatenating(scale)
            var layer = AVVideoCompositionLayerInstruction.Configuration(trackID: video.trackID)
            layer.setTransform(placed, at: .zero)
            let instruction = AVVideoCompositionInstruction.Configuration(
                layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
                timeRange: CMTimeRange(start: .zero, duration: duration))
            let rate: Double = output.frameRate ?? info.frameRate
            let frame = CMTime(value: Int64((Double(VideoEdit.timescale) / max(rate, 1)).rounded()), timescale: VideoEdit.timescale)
            let configuration = AVVideoComposition.Configuration(
                colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
                colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2,
                colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
                frameDuration: frame,
                instructions: [AVVideoCompositionInstruction(configuration: instruction)],
                renderSize: size)
            videoComposition = AVVideoComposition(configuration: configuration)
        }
        let immutable = composition.copy() as? AVComposition ?? composition
        return VideoComposition(composition: immutable, videoComposition: videoComposition, audioMix: mix, renderSize: size,
                                duration: duration,
                                audioTrackIDs: Dictionary(uniqueKeysWithValues: kept.map { ($0.index, $0.track.trackID) }))
    }

    /// Each track at its level, faded in and out if asked.
    static func audioMix(_ tracks: [(CMPersistentTrackID, VideoEdit.Level)], duration: CMTime, fades: Bool) -> AVAudioMix? {
        guard !tracks.isEmpty else { return nil }
        guard fades || tracks.contains(where: { !$0.1.isUntouched }) else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { id, level in
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = id
            let gain = level.gain
            if fades, gain > 0, duration.seconds > 1 {
                let fade = CMTime(seconds: min(0.5, duration.seconds / 4), preferredTimescale: VideoEdit.timescale)
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain, timeRange: CMTimeRange(start: .zero, duration: fade))
                parameters.setVolume(gain, at: fade)
                parameters.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0,
                                         timeRange: CMTimeRange(start: duration - fade, duration: fade))
            } else {
                parameters.setVolume(gain, at: .zero)
            }
            return parameters
        }
        return mix.copy() as? AVAudioMix ?? mix
    }
}

// MARK: Background work

/// Carries AVFoundation objects that aren't Sendable to the one queue that uses them from then on.
struct Handoff<Value>: @unchecked Sendable {
    let value: Value
}

/// Set when the work should stop; checked between frames.
final class CancelFlag: Sendable {
    private let state = Mutex(false)

    var isCancelled: Bool { state.withLock { $0 } }

    func cancel() { state.withLock { $0 = true } }
}

/// Media work that blocks (decoding, encoding) runs on a queue of its own, never on Swift's
/// shared threads, and stops when its task is cancelled.
enum MediaQueue {
    static func run<T: Sendable>(_ flag: CancelFlag = CancelFlag(), qos: DispatchQoS.QoSClass = .userInitiated,
                                 _ work: @escaping @Sendable (CancelFlag) throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: qos).async {
                    continuation.resume(with: Result { try work(flag) })
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }
}

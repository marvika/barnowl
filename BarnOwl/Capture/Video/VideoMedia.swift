import AVFoundation
import CoreGraphics

/// The timeline's pictures and sound shapes, made off the main thread from the movie itself
/// (not the edit), so they're made once and every edit reuses them.
enum VideoMedia {
    /// How finely the sound is drawn: loudness peaks per second.
    static let peaksPerSecond = 50

    /// Pictures of the movie at `times` (ticks), `height` pixels tall, handed over as they come.
    static func thumbnails(_ url: URL, times: [Int64], height: CGFloat,
                           each: @escaping @MainActor (Int64, CGImage) -> Void) async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 0, height: height)
        let tolerance = CMTime(value: 3, timescale: 30)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let requested = times.map { VideoEdit.time($0) }
        for await result in generator.images(for: requested) {
            if Task.isCancelled { return }
            guard let image = try? result.image else { continue }
            let ticks = VideoEdit.ticks(result.requestedTime)
            await each(ticks, image)
        }
    }

    /// One picture at `ticks` in the movie, exactly that frame, at full size.
    static func frame(_ url: URL, at ticks: Int64, maximumSize: CGSize = .zero) async -> CGImage? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try? await generator.image(at: VideoEdit.time(ticks)).image
    }

    /// The edited movie's frame at `ticks` (edited time), cropped as the edit says, at full size.
    static func editedFrame(_ info: MovieInfo, edit: VideoEdit, at ticks: Int64) async -> CGImage? {
        let source = edit.sourceTime(at: min(ticks, max(0, edit.duration - 1)))
        guard let frame = await frame(info.url, at: min(source, max(0, info.duration - 1))) else { return nil }
        guard let crop = edit.crop else { return frame }
        // The frame is upright, in pixels from the top left, as the crop is.
        return frame.cropping(to: crop)
    }

    /// Loudness peaks of one sound track, `peaksPerSecond` a second over the whole movie, from
    /// 0 to 1. Empty if the track can't be read.
    static func peaks(_ url: URL, trackID: CMPersistentTrackID) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTrack(withTrackID: trackID) else { return [] }
        let job = Handoff(value: (asset, track))
        let result = try? await MediaQueue.run(qos: .utility) { flag -> [Float] in
            let (asset, track) = job.value
            return try read(asset, track: track, flag: flag)
        }
        return result ?? []
    }

    private static func read(_ asset: AVAsset, track: AVAssetTrack, flag: CancelFlag) throws -> [Float] {
        let rate = 8_000
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        defer { reader.cancelReading() }
        let bucket = rate / peaksPerSecond
        var peaks: [Float] = []
        var current: Float = 0
        var filled = 0
        var started = false
        while let sample = output.copyNextSampleBuffer() {
            if flag.isCancelled { throw CancellationError() }
            if !started {
                // Silence before the track begins (a mic that started late).
                started = true
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if start.isFinite, start > 0 { peaks += [Float](repeating: 0, count: Int(start * Double(peaksPerSecond))) }
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var values = [Float](repeating: 0, count: count)
            let copied = values.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: bytes.baseAddress!)
            }
            guard copied == kCMBlockBufferNoErr else { continue }
            values.withUnsafeBufferPointer { samples in
                for index in 0..<count {
                    current = max(current, abs(samples[index]))
                    filled += 1
                    if filled == bucket {
                        peaks.append(min(1, current))
                        current = 0
                        filled = 0
                    }
                }
            }
        }
        if filled > 0 { peaks.append(min(1, current)) }
        return peaks
    }
}

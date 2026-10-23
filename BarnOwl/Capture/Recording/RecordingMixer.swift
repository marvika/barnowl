import AVFoundation

/// Makes the file you're handed from a recording with computer audio and the microphone on
/// separate tracks: the picture copied as it is, and both sounds mixed into one track, which
/// every player and chat app plays. Takes seconds, since the video isn't encoded again. The
/// separate tracks stay in the library's copy, for the video editor.
enum RecordingMixer {
    enum Failure: Error {
        case unreadable
        case couldNotWrite(String)
    }

    /// Whether a recording needs mixing: more than one audio track.
    static func needsMixing(_ output: RecordingWriter.Output) -> Bool { output.audio.count > 1 }

    static func mix(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first else { throw Failure.unreadable }
        let formats = try await videoTrack.load(.formatDescriptions)
        let job = try MixJob(asset: asset, video: videoTrack, videoFormat: formats.first, audio: audioTracks,
                             destination: destination)
        try await withTaskCancellationHandler {
            try await job.run()
        } onCancel: {
            job.cancel()
        }
    }
}

/// One mix, on its own queue. Readers and writers aren't safe to share, so nothing else
/// touches these once it starts.
private final class MixJob: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderTrackOutput
    private let videoInput: AVAssetWriterInput
    private let audioOutput: AVAssetReaderAudioMixOutput?
    private let audioInput: AVAssetWriterInput?
    private let destination: URL
    private let queue = DispatchQueue(label: "io.github.marvika.BarnOwl.mix")

    init(asset: AVAsset, video: AVAssetTrack, videoFormat: CMFormatDescription?, audio: [AVAssetTrack],
         destination: URL) throws {
        self.destination = destination
        try? FileManager.default.removeItem(at: destination)
        reader = try AVAssetReader(asset: asset)
        writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        writer.movieTimeScale = RecordingWriter.timescale
        // The picture as it is: no decoding, no encoding.
        videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.expectsMediaDataInRealTime = false
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw RecordingMixer.Failure.unreadable }
        reader.add(videoOutput)
        writer.add(videoInput)
        if audio.isEmpty {
            audioOutput = nil
            audioInput = nil
        } else {
            let pcm: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
                                      AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                                      AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
                                      AVLinearPCMIsBigEndianKey: false]
            let output = AVAssetReaderAudioMixOutput(audioTracks: audio, audioSettings: pcm)
            let mix = AVMutableAudioMix()
            mix.inputParameters = audio.map { track in
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.setVolume(1, at: .zero)
                return parameters
            }
            output.audioMix = mix
            var settings = RecordingWriter.audioSettings(.system)
            settings[AVEncoderBitRateKey] = 160_000
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { throw RecordingMixer.Failure.unreadable }
            reader.add(output)
            writer.add(input)
            audioOutput = output
            audioInput = input
        }
    }

    func run() async throws {
        guard reader.startReading() else { throw RecordingMixer.Failure.unreadable }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw RecordingMixer.Failure.couldNotWrite(writer.error?.localizedDescription ?? "")
        }
        writer.startSession(atSourceTime: .zero)
        let group = DispatchGroup()
        pump(videoOutput, into: videoInput, group: group)
        if let audioOutput, let audioInput { pump(audioOutput, into: audioInput, group: group) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: queue) { continuation.resume() }
        }
        if reader.status == .cancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw RecordingMixer.Failure.unreadable
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw RecordingMixer.Failure.couldNotWrite(writer.error?.localizedDescription ?? "")
        }
    }

    /// Stops reading: what's left is let go of, and `run` throws `CancellationError`.
    func cancel() {
        queue.async { self.reader.cancelReading() }
    }

    /// Moves samples from the reader to the writer as fast as the writer takes them.
    private func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, group: DispatchGroup) {
        group.enter()
        nonisolated(unsafe) let output = output
        nonisolated(unsafe) let input = input
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    group.leave()
                    return
                }
                if !input.append(sample) {
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }
}

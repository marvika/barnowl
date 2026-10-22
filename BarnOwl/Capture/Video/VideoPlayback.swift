import AVFoundation

/// Plays the edited movie: an AVPlayer on the same composition the export uses. When the clips
/// or crop change it builds a new item (shortly after the last change) and carries on from the
/// same moment; a level change only swaps the sound mix. Seeks are exact and coalesced, so
/// scrubbing shows every frame it can without falling behind.
@MainActor
final class VideoPlayback {
    let player = AVPlayer()
    let info: MovieInfo
    private let asset: AVURLAsset
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var stallObserver: NSKeyValueObservation?
    private var rebuildTask: Task<Void, Never>?
    private var generation = 0
    /// The sound tracks in the current item, by the movie's track order.
    private var audioTrackIDs: [Int: CMPersistentTrackID] = [:]
    private var edit: VideoEdit?
    private var fullFrame = false
    private var wantedRate: Float = 0
    private var seekTarget: Int64?
    private var seeking = false
    private var closed = false
    private(set) var isReady = false

    /// Where it is while playing, about 60 times a second.
    var onTime: ((Int64) -> Void)?
    /// It reached the end (or the start, playing backwards).
    var onEnd: (() -> Void)?
    /// It stopped by itself, such as when it can't play backwards.
    var onStop: (() -> Void)?
    /// The first picture of an item is ready.
    var onReady: (() -> Void)?

    init(info: MovieInfo) {
        self.info = info
        asset = AVURLAsset(url: info.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = true
        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.player.rate != 0 else { return }
                self.onTime?(VideoEdit.ticks(time))
            }
        }
        stallObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let rate = player.rate
            // KVO can arrive on any thread; the decision is made on the main one.
            Task { @MainActor in
                guard let self, rate == 0, self.player.rate == 0, self.wantedRate != 0, !self.seeking,
                      self.rebuildTask == nil else { return }
                // Stopped though asked to play: at an end, or it can't go that way.
                let at = VideoEdit.ticks(self.player.currentTime())
                let duration = self.edit?.duration ?? 0
                if self.wantedRate < 0, at <= 0 {
                    self.wantedRate = 0
                    self.onEnd?()
                } else if self.wantedRate > 0, at >= duration - 1 {
                    return
                } else {
                    self.wantedRate = 0
                    self.onStop?()
                }
            }
        }
    }

    func close() {
        closed = true
        rebuildTask?.cancel()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        stallObserver?.invalidate()
        player.replaceCurrentItem(with: nil)
    }

    /// The first item.
    func load(_ edit: VideoEdit) {
        rebuild(edit, fullFrame: false, at: 0, delay: .zero)
    }

    /// A new item for a changed edit, shortly after the last change; `fullFrame` shows the
    /// picture uncropped (while cropping).
    func rebuild(_ edit: VideoEdit, fullFrame: Bool, at time: Int64, delay: Duration = .milliseconds(90)) {
        self.edit = edit
        self.fullFrame = fullFrame
        rebuildTask?.cancel()
        generation += 1
        let generation = generation
        rebuildTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            await self.build(edit, fullFrame: fullFrame, at: time, generation: generation)
        }
    }

    private func build(_ edit: VideoEdit, fullFrame: Bool, at time: Int64, generation: Int) async {
        var shown = edit
        if fullFrame { shown.crop = nil }
        guard let built = try? await VideoComposer.build(asset, info: info, edit: shown, output: .preview) else {
            if generation == self.generation { rebuildTask = nil }
            return
        }
        guard generation == self.generation, !closed else { return }
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = built.videoComposition
        item.audioMix = built.audioMix
        item.audioTimePitchAlgorithm = .spectral
        audioTrackIDs = built.audioTrackIDs
        let resume = wantedRate
        let target = seekTarget ?? time
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantedRate != 0 else { return }
                self.wantedRate = 0
                self.onEnd?()
            }
        }
        player.replaceCurrentItem(with: item)
        rebuildTask = nil
        isReady = true
        seekTarget = nil
        seeking = false
        seek(to: min(target, max(0, edit.duration - 1)))
        if resume != 0 { play(rate: resume) }
        onReady?()
    }

    /// The edit's sound levels, without a new item.
    func updateMix(_ edit: VideoEdit) {
        self.edit = edit
        guard let item = player.currentItem else { return }
        let tracks = audioTrackIDs.sorted { $0.key < $1.key }.map { index, id in
            (id, edit.levels.indices.contains(index) ? edit.levels[index] : VideoEdit.Level())
        }
        let duration = VideoEdit.time(edit.duration)
        // Always a mix, so going back to the recorded levels takes effect too.
        let mix = VideoComposer.audioMix(tracks, duration: duration, fades: edit.fadesSound) ?? Self.flatMix(tracks.map(\.0))
        item.audioMix = tracks.isEmpty ? nil : mix
    }

    private static func flatMix(_ ids: [CMPersistentTrackID]) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = ids.map { id in
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = id
            parameters.setVolume(1, at: .zero)
            return parameters
        }
        return mix
    }

    // MARK: Transport

    func play(rate: Float) {
        wantedRate = rate
        guard player.currentItem != nil else { return }
        if rate < 0, player.currentItem?.canPlayReverse != true {
            wantedRate = 0
            onStop?()
            return
        }
        player.rate = rate
    }

    func pause() {
        wantedRate = 0
        player.pause()
    }

    /// Shows exactly the frame at `time`. While a seek is under way, only the latest request
    /// waits; the ones in between are skipped.
    func seek(to time: Int64) {
        seekTarget = time
        guard !seeking, player.currentItem != nil, rebuildTask == nil else { return }
        seekNext()
    }

    private func seekNext() {
        guard let target = seekTarget, let item = player.currentItem else {
            seeking = false
            return
        }
        seekTarget = nil
        seeking = true
        let generation = generation
        item.seek(to: VideoEdit.time(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.seeking = false
                if self.seekTarget != nil { self.seekNext() }
            }
        }
    }
}

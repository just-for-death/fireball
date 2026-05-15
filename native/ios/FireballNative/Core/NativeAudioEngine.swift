import AVFoundation
import CoreMedia
import MediaPlayer

@MainActor
final class NativeAudioEngine {
    private let player = AVPlayer()
    private var queue: [Track] = []
    private var currentIndex: Int = 0
    private var timeObserverToken: Any?

    var onStateUpdate: ((Int, Bool, Double, Double) -> Void)?
    var onTrackEnded: (() -> Void)?
    var onInterrupted: ((Bool) -> Void)?
    /// When set, lock screen / headset next routes here (e.g. view model resolves lazy URLs).
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?

    init() {
        configureAudioSession()
        setupRemoteCommands()
        setupObservers()
    }

    func playQueue(_ tracks: [Track], startIndex: Int) {
        queue = tracks
        currentIndex = max(0, min(startIndex, max(0, tracks.count - 1)))
        loadCurrentTrackAndPlay()
    }

    private func loadCurrentTrackAndPlay() {
        guard queue.indices.contains(currentIndex) else { return }
        guard let urlString = queue[currentIndex].url?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else { return }
        guard let url = playbackURL(from: urlString) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        installTimeObserverIfNeeded()
        refreshNowPlaying()
    }

    /// Supports `http(s):` streams and `file:` URLs from the library resolver.
    private func playbackURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        if trimmed.hasPrefix("file:") {
            if let u = URL(string: trimmed) { return u }
            let withoutScheme = trimmed.replacingOccurrences(of: "file://", with: "")
            let path = withoutScheme.removingPercentEncoding ?? withoutScheme
            return URL(fileURLWithPath: path.isEmpty ? withoutScheme : path)
        }
        return URL(string: trimmed)
    }

    func seek(to seconds: Double) {
        let t = max(0, seconds)
        let time = CMTime(seconds: t, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.refreshNowPlaying()
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        refreshNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        currentIndex = min(currentIndex + 1, queue.count - 1)
        loadCurrentTrackAndPlay()
        refreshNowPlaying()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
        loadCurrentTrackAndPlay()
        refreshNowPlaying()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onTrackEnded?()
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                self.player.pause()
                self.refreshNowPlaying()
                self.onInterrupted?(true)
            case .ended:
                let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    self.player.play()
                }
                self.refreshNowPlaying()
                self.onInterrupted?(false)
            @unknown default:
                break
            }
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            self?.refreshNowPlaying()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            self?.refreshNowPlaying()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if let onRemoteNext = self.onRemoteNext {
                onRemoteNext()
                return .success
            }
            self.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if let onRemotePrevious = self.onRemotePrevious {
                onRemotePrevious()
                return .success
            }
            self.previous()
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    private func refreshNowPlaying() {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex]
        let currentSeconds = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        let totalSeconds = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? 0 : 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyPlaybackRate: player.timeControlStatus == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentSeconds
        ]
        if let duration = track.duration {
            info[MPMediaItemPropertyPlaybackDuration] = TimeInterval(duration)
        } else if totalSeconds > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = totalSeconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        onStateUpdate?(currentIndex, player.timeControlStatus == .playing, currentSeconds, totalSeconds)
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserverToken == nil else { return }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.refreshNowPlaying()
        }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

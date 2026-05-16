import AVFoundation
import CoreMedia
import MediaPlayer
import UIKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class NativeAudioEngine {
    private let player = AVPlayer()
    private var queue: [Track] = []
    private var currentIndex: Int = 0
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?

    var onStateUpdate: ((Int, Bool, Double, Double) -> Void)?
    var onTrackEnded: (() -> Void)?
    var onInterrupted: ((Bool) -> Void)?
    /// When set, lock screen / headset next routes here (e.g. view model resolves lazy URLs).
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?
    /// Called when the current queue item has no playable URL or load fails.
    var onPlaybackFailed: ((String) -> Void)?

    private var settingsProvider: (() -> FireballSettings)?

    func bindSettings(_ provider: @escaping () -> FireballSettings) {
        settingsProvider = provider
    }

    init() {
        configureAudioSession()
        setupRemoteCommands()
        setupObservers()
        setupRouteChangeObserver()
    }

    @discardableResult
    func playQueue(_ tracks: [Track], startIndex: Int) -> Bool {
        queue = tracks
        currentIndex = max(0, min(startIndex, max(0, tracks.count - 1)))
        return loadCurrentTrackAndPlay()
    }

    var isPlaybackActive: Bool { isPlaying }

    /// Latest duration from AVPlayer item metadata (used when UI duration is still zero).
    var lastReportedDurationSeconds: Double {
        let d = player.currentItem?.duration.seconds ?? 0
        return d.isFinite && d > 0 ? d : 0
    }

    /// Loads the queue and prepares the current item without starting playback (session restore).
    func prepareQueue(_ tracks: [Track], startIndex: Int) {
        queue = tracks
        currentIndex = max(0, min(startIndex, max(0, tracks.count - 1)))
        guard prepareCurrentItemWithoutPlay() else { return }
        refreshNowPlaying()
    }

    func pausePlayback() {
        player.pause()
        refreshNowPlaying()
    }

    /// Stops playback, clears logical queue (mini-player dismiss / session reset).
    func stopAndClearPlayback() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        queue = []
        currentIndex = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        onStateUpdate?(-1, false, 0, 0)
    }

    func resumeIfPaused() {
        guard queue.indices.contains(currentIndex) else { return }
        if player.currentItem == nil {
            loadCurrentTrackAndPlay()
            return
        }
        if !isPlaying {
            player.play()
            refreshNowPlaying()
        }
    }

    private var isPlaying: Bool {
        switch player.timeControlStatus {
        case .playing, .waitingToPlayAtSpecifiedRate:
            return true
        default:
            return false
        }
    }

    private func prepareCurrentItemWithoutPlay() -> Bool {
        guard queue.indices.contains(currentIndex) else { return false }
        let track = queue[currentIndex]
        guard let urlString = track.url?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else {
            onPlaybackFailed?("No stream URL for \"\(track.title)\".")
            return false
        }
        guard let remote = playbackURL(from: urlString) else {
            onPlaybackFailed?("Invalid playback URL for \"\(track.title)\".")
            return false
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: remote))
        observeItemFailure(player.currentItem)
        observeEndOfCurrentItem()
        player.pause()
        installTimeObserverIfNeeded()
        return true
    }

    @discardableResult
    private func loadCurrentTrackAndPlay() -> Bool {
        guard prepareCurrentItemWithoutPlay() else { return false }
        player.play()
        refreshNowPlaying()
        return true
    }

    private func observeItemFailure(_ item: AVPlayerItem?) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        guard let item else { return }
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard let self else { return }
            guard observed.status == .failed else { return }
            let msg = observed.error?.localizedDescription ?? "Playback failed"
            Task { @MainActor in
                self.onPlaybackFailed?(msg)
                self.refreshNowPlaying()
            }
        }
    }

    /// Updates the logical queue (next/previous ordering) without reloading the current AV item when the playing track is unchanged.
    func applyQueueMutation(_ tracks: [Track], currentIndex: Int) {
        guard tracks.indices.contains(currentIndex) else { return }
        let oldId = queue.indices.contains(self.currentIndex) ? queue[self.currentIndex].effectiveId : nil
        let newId = tracks[currentIndex].effectiveId
        queue = tracks
        self.currentIndex = currentIndex
        if oldId == newId, player.currentItem != nil {
            refreshNowPlaying()
            return
        }
        _ = loadCurrentTrackAndPlay()
    }

    private func observeEndOfCurrentItem() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        guard let item = player.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard note.object as? AVPlayerItem === self.player.currentItem else { return }
            self.onTrackEnded?()
        }
    }

    /// Supports `http(s):` streams and `file:` URLs from the library resolver.
    private func playbackURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let resolved: URL?
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            resolved = absolute
        } else if trimmed.hasPrefix("file:") {
            if let u = URL(string: trimmed) {
                resolved = u
            } else {
                let withoutScheme = trimmed.replacingOccurrences(of: "file://", with: "")
                let path = withoutScheme.removingPercentEncoding ?? withoutScheme
                resolved = URL(fileURLWithPath: path.isEmpty ? withoutScheme : path)
            }
        } else {
            resolved = URL(string: trimmed)
        }
        guard let resolved else { return nil }
        if resolved.isFileURL {
            return resolved
        }
        let settings = settingsProvider?() ?? FireballSettings()
        if let cached = StreamPlaybackCache.localPlaybackURL(remoteURL: resolved, settings: settings) {
            return cached
        }
        if settings.streamCacheEnabled {
            Task { await StreamPlaybackCache.prefetch(remoteURL: resolved, settings: settings) }
        }
        return resolved
    }

    func seek(to seconds: Double) {
        let t = max(0, seconds)
        let time = CMTime(seconds: t, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.refreshNowPlaying()
        }
    }

    func togglePlayPause() {
        if isPlaying {
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

    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
            if reason == .oldDeviceUnavailable {
                self.player.pause()
                self.refreshNowPlaying()
                self.onInterrupted?(true)
            }
        }
    }

    private func setupObservers() {
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentSeconds
        ]
        if let duration = track.duration {
            info[MPMediaItemPropertyPlaybackDuration] = TimeInterval(duration)
        } else if totalSeconds > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = totalSeconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        onStateUpdate?(currentIndex, isPlaying, currentSeconds, totalSeconds)

        if let artUrl = track.artwork, let url = URL(string: artUrl) {
            let title = track.title
            let artist = track.artist
            Task { [weak self] in
                guard let self else { return }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                await MainActor.run {
                    guard self.queue.indices.contains(self.currentIndex),
                          self.queue[self.currentIndex].effectiveId == track.effectiveId else { return }
                    var withArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    withArt[MPMediaItemPropertyTitle] = title
                    withArt[MPMediaItemPropertyArtist] = artist
                    withArt[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = withArt
                }
            }
        }
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
        itemStatusObservation?.invalidate()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

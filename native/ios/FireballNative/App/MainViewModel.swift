import Combine
import Foundation
import SwiftUI

enum RepeatMode: String, CaseIterable {
    case off, all, one
}

struct ArtistOpenRequest: Identifiable, Hashable {
    let appleId: Int?
    let fallbackDisplayName: String

    var id: String {
        switch appleId {
        case let i?:
            return "i\(i):\(fallbackDisplayName)"
        case nil:
            return "n:\(fallbackDisplayName)"
        }
    }
}

@MainActor
final class MainViewModel: ObservableObject {
    private enum Status {
        static let gotifyOk = "gotify: success"
        static let gotifyFail = "gotify: failed"
        static let lbdlAuthOk = "lbdl auth: success"
        static let lbdlAuthFail = "lbdl auth: failed"
        static let lbdlJobOkPrefix = "lbdl job: success"
        static let lbdlJobFail = "lbdl job: failed"
        static let remoteCmdOk = "remote command: success"
        static let remoteCmdFail = "remote command: failed"
        static let remotePairOk = "remote pair: success"
        static let remotePairFail = "remote pair: failed"
        static let gdriveOk = "gdrive backup: success"
        static let gdriveFail = "gdrive backup: failed"
        static let invidiousLoginOk = "invidious login: success"
        static let invidiousLoginFail = "invidious login: failed"
        static let invidiousSyncOk = "invidious playlist sync: success"
        static let invidiousSyncFail = "invidious playlist sync: failed"
        static let invidiousPushOk = "invidious playlist push: success"
        static let invidiousPushFail = "invidious playlist push: failed"
    }

    @Published var library = LibrarySnapshot()
    @Published var query = ""
    @Published var searchResults: [Track] = []
    @Published var isSearching = false
    @Published var queue: [Track] = []
    @Published var currentIndex: Int? = nil
    @Published var isPlaying = false
    @Published var shuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var sleepTimerEnd: Date? = nil
    @Published var sleepAfterCurrent = false
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var currentLyrics: String? = nil
    @Published var integrationStatus: String? = nil
    @Published var error: String? = nil
    @Published var invidiousPlaylists: [(id: String, title: String)] = []
    @Published var chartCountryCode = "us"
    @Published var trendingTracks: [Track] = []
    @Published var trendingLoading = false
    @Published var lbRecentTracks: [Track] = []
    @Published var lbTopTracks: [Track] = []
    @Published var lbTopRange = "month"
    @Published var lbHomeLoading = false
    @Published var isPlaybackLoading = false
    @Published var searchFocusRequest: String?
    @Published var searchSuggestions: [Track] = []
    @Published var searchAlbumResults: [Album] = []
    @Published var artistOpenRequest: ArtistOpenRequest?

    private let repository: FireballRepository
    private let listenBrainz = ListenBrainzClient()
    private let lastFm = LastFmClient()
    private let bluetoothMonitor = BluetoothRouteMonitor()
    private let speechAnnouncer = SpeechAnnouncer()
    private let webDav = WebDavSyncClient()
    private let gotify = GotifyClient()
    private let lbdl = LbdlClient()
    private let remoteLan = RemoteLanClient()
    private let gDrive = GoogleDriveBackupClient()
    private let sponsorBlock = SponsorBlockClient()
    private let audioEngine = NativeAudioEngine()
    private let lyricsAi: LyricsAndAIService
    private var scrobbledTrackIds = Set<String>()
    private var lastLibraryPersistAt = Date.distantPast
    private var aiQueueExpandedForTrackIds = Set<String>()
    private var sponsorSegmentsForVideo: [SponsorSegment] = []
    private var sponsorSegmentsVideoId: String?
    private var sponsorSkippedUUIDs = Set<String>()
    private var activePlayTask: Task<Void, Never>?
    private var suggestionCancellable: AnyCancellable?
    private var suggestionTask: Task<Void, Never>?

    init(repository: FireballRepository) {
        self.repository = repository
        self.library = repository.loadLibrary()
        self.lyricsAi = LyricsAndAIService(api: FireballAPIClient())
        audioEngine.bindSettings { [weak self] in
            self?.library.settings ?? FireballSettings()
        }
        audioEngine.onStateUpdate = { [weak self] engineIndex, isPlaying, position, duration in
            guard let self else { return }
            if engineIndex >= 0 {
                self.currentIndex = engineIndex
            } else {
                self.currentIndex = nil
            }
            self.isPlaying = isPlaying
            self.positionSeconds = position
            self.durationSeconds = duration
            self.maybeAutoSkipSponsor(positionSeconds: position)
            self.syncLiveActivity()
        }
        audioEngine.onTrackEnded = { [weak self] in
            guard let self else { return }
            if self.sleepAfterCurrent {
                self.isPlaying = false
                self.setSleepAfterCurrent(false)
                return
            }
            if self.repeatMode == .one {
                self.audioEngine.seek(to: 0)
                self.audioEngine.resumeIfPaused()
                self.isPlaying = true
                return
            }
            Task { await self.advanceAfterTrackFinished() }
        }
        audioEngine.onInterrupted = { [weak self] interrupted in
            guard let self else { return }
            if interrupted {
                self.isPlaying = false
            } else {
                self.isPlaying = self.audioEngine.isPlaybackActive
            }
        }
        audioEngine.onRemoteNext = { [weak self] in
            Task { @MainActor in await self?.userPressedNext() }
        }
        audioEngine.onRemotePrevious = { [weak self] in
            Task { @MainActor in await self?.userPressedPrevious() }
        }
        audioEngine.onPlaybackFailed = { [weak self] message in
            self?.error = message
            self?.isPlaying = false
        }
        restorePlaybackSession()
        bluetoothMonitor.start(
            isEnabled: { [weak self] in self?.library.settings.bluetoothAutoplayEnabled ?? false },
            shouldResume: { [weak self] in
                guard let self else { return false }
                return !self.queue.isEmpty && self.currentTrack != nil && !self.isPlaying
            },
            onResume: { [weak self] in self?.audioEngine.resumeIfPaused() }
        )
        bootstrapEngineFromRestoredSession()
        Task { await sleepTimerLoop() }
        let chartCodes = HomeCountries.visibleCodes(saved: library.settings.homeCountries)
        chartCountryCode = chartCodes.first?.lowercased() ?? "us"
        Task {
            await refreshHome()
            await checkFollowedArtistNewReleases()
            ArtistReleaseBackgroundRefresh.scheduleIfNeeded(settings: library.settings)
        }
        setupSearchSuggestionDebounce()
    }

    /// Debounced search-as-you-type (matches Android [MainViewModel.updateQuery] semantics).
    private func setupSearchSuggestionDebounce() {
        suggestionCancellable = $query
            .debounce(for: .milliseconds(340), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] raw in
                guard let self else { return }
                self.suggestionTask?.cancel()
                self.suggestionTask = Task { await self.refreshSearchSuggestionsLocked(raw) }
            }
    }

    func refreshSearchSuggestionsNow() {
        Task { await refreshSearchSuggestionsLocked(query) }
    }

    /// Mirrors Android [refreshSearchSuggestionsLocked].
    private func refreshSearchSuggestionsLocked(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            searchSuggestions = []
            return
        }
        let settings = library.settings
        if settings.offlineModeEnabled {
            let needle = q.lowercased()
            let pooled = (library.favorites + library.history).uniqued(by: \.effectiveId)
            searchSuggestions =
                pooled
                .filter { $0.title.lowercased().contains(needle) || $0.artist.lowercased().contains(needle) }
                .prefix(8)
                .map { $0 }
            return
        }

        let needle = q.lowercased()
        let artistStubs: [Track] = library.artists.map { a in
            Track(id: a.artistId, videoId: nil, title: "Artist · \(a.name)", artist: a.name, artwork: a.artwork, url: nil, duration: nil, album: nil, year: nil)
        }
        let pooled = (library.favorites + library.history + artistStubs).uniqued(by: \.effectiveId)
        var localMatches = pooled.filter {
            $0.title.lowercased().contains(needle) || $0.artist.lowercased().contains(needle)
        }
        let remote = await repository.searchTracks(query: q, settings: settings).prefix(8)
        guard !Task.isCancelled else { return }
        guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        searchSuggestions =
            (localMatches + remote)
                .uniqued(by: \.effectiveId)
                .prefix(12)
                .prefix(10)
                .map { $0 }
    }

    func refreshHome() async {
        await refreshHomeCharts()
        await refreshListenBrainzHome()
    }

    func selectLbTopRange(_ range: String) {
        let normalized = range.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != lbTopRange else { return }
        lbTopRange = normalized
        Task { await refreshListenBrainzHome(topOnly: true) }
    }

    private func refreshListenBrainzHome(topOnly: Bool = false) async {
        let settings = library.settings
        let ready = settings.listenBrainzEnabled &&
            !settings.listenBrainzUsername.isEmpty &&
            !settings.listenBrainzToken.isEmpty
        guard ready else {
            lbRecentTracks = []
            lbTopTracks = []
            lbHomeLoading = false
            return
        }
        lbHomeLoading = true
        let recent: [Track]
        if topOnly {
            recent = lbRecentTracks
        } else {
            recent = await listenBrainz.recentListens(
                username: settings.listenBrainzUsername,
                token: settings.listenBrainzToken,
                count: 8
            )
        }
        let top = await listenBrainz.topRecordings(
            username: settings.listenBrainzUsername,
            token: settings.listenBrainzToken,
            range: lbTopRange,
            count: 10
        )
        lbRecentTracks = recent
        lbTopTracks = top
        lbHomeLoading = false
    }

    func followArtist(name: String, artwork: String? = nil) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            let artist = await repository.resolveArtistForFollow(artistName: name, fallbackArtwork: artwork)
            if library.artists.contains(where: { $0.artistId == artist.artistId }) { return }
            library.artists.append(artist)
            persist()
        }
    }

    func unfollowArtist(artistId: String) {
        guard !artistId.isEmpty else { return }
        library.artists.removeAll { $0.artistId == artistId }
        persist()
    }

    func playQueueIndex(_ index: Int) {
        Task { await openQueueIndex(index) }
    }

    func selectChartCountry(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != chartCountryCode else { return }
        chartCountryCode = normalized
        Task { await refreshHomeCharts(countryCode: normalized) }
    }

    func refreshHomeCharts(countryCode: String? = nil) async {
        let cc = countryCode ?? chartCountryCode
        trendingLoading = true
        trendingTracks = await repository.fetchTopSongs(countryCode: cc, limit: 20)
        trendingLoading = false
    }

    private func checkFollowedArtistNewReleases() async {
        let snapshot = library
        let wantGotify =
            snapshot.settings.gotifyEnabled &&
            !snapshot.settings.gotifyUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !snapshot.settings.gotifyToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let onGotify: (@Sendable (String, String) async -> Bool)? =
            wantGotify
                ? { [weak self] title, message -> Bool in
                    guard let self else { return false }
                    return await self.gotify.send(
                        url: self.library.settings.gotifyUrl,
                        token: self.library.settings.gotifyToken,
                        title: title,
                        message: message
                    )
                } : nil

        let wantDevice = snapshot.settings.notifyArtistReleasesOnDevice
        let onDevice: (@Sendable (String, String) async -> Void)? =
            wantDevice
                ? { title, message in
                    await ArtistReleaseNotifier.notify(title: title, message: message)
                } : nil

        guard let updated = await repository.checkFollowedArtistNewReleases(
            snapshot: snapshot,
            onGotifyNotify: onGotify,
            onDeviceNotify: onDevice,
        )
        else { return }
        library = updated
        repository.saveLibrary(updated)
    }

    func refreshFollowedArtistReleaseChecksFromForeground() async {
        await checkFollowedArtistNewReleases()
    }

    private func bootstrapEngineFromRestoredSession() {
        guard let idx = currentIndex, !queue.isEmpty, queue.indices.contains(idx) else { return }
        audioEngine.prepareQueue(queue, startIndex: idx)
        isPlaying = false
    }

    func isFavorite(_ track: Track) -> Bool {
        library.favorites.contains { $0.effectiveId == track.effectiveId }
    }

    private func restorePlaybackSession() {
        let session = library.playbackSession
        if session.queue.isEmpty {
            queue = []
            currentIndex = nil
        } else {
            queue = session.queue
            if session.currentIndex >= 0, session.currentIndex < session.queue.count {
                currentIndex = session.currentIndex
            }
        }
        shuffled = session.shuffled
        if let mode = RepeatMode(rawValue: session.repeatMode) {
            repeatMode = mode
        }
    }

    private func savePlaybackSession() {
        let persistedIndex: Int
        if queue.isEmpty {
            persistedIndex = -1
        } else if let idx = currentIndex, queue.indices.contains(idx) {
            persistedIndex = idx
        } else {
            persistedIndex = 0
        }
        library.playbackSession = PlaybackSession(
            queue: queue,
            currentIndex: persistedIndex,
            shuffled: shuffled,
            repeatMode: repeatMode.rawValue
        )
    }

    var currentTrack: Track? {
        guard let currentIndex else { return nil }
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        error = nil
        isSearching = true
        searchSuggestions = []
        searchAlbumResults = []
        let settings = library.settings
        if settings.offlineModeEnabled {
            let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let local = (library.history + library.favorites).uniqued(by: \.effectiveId)
            searchResults = local.filter {
                $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
            }
            isSearching = false
            return
        }

        async let tracksFetched = repository.searchTracks(query: query, settings: settings)
        async let albumsFetched = repository.searchAlbumsCatalog(query: query, settings: settings)
        let tracks = await tracksFetched
        let albums = await albumsFetched
        searchResults = tracks
        searchAlbumResults = albums

        if tracks.isEmpty && albums.isEmpty && !settings.offlineModeEnabled {
            error = "No results. Try another query or check Invidious / network."
        }
        isSearching = false
    }

    func play(track: Track, source: [Track]) {
        let settings = library.settings
        activePlayTask?.cancel()
        activePlayTask = Task {
            defer { isPlaybackLoading = false }
            isPlaybackLoading = true
            error = nil
            scrobbledTrackIds.removeAll()
            let resolvedTrack = await repository.resolvePlayableTrack(track, settings: settings)
            let queue = source.map { $0.effectiveId == track.effectiveId ? resolvedTrack : $0 }
            let idx = max(0, queue.firstIndex(where: { $0.effectiveId == track.effectiveId }) ?? 0)

            let offline = settings.offlineModeEnabled
            let privacy = settings.privacyModeEnabled

            guard let url = resolvedTrack.url, !url.isEmpty else {
                guard !Task.isCancelled else { return }
                error = "Could not get a stream for this track. Invidious, public mirrors, and direct YouTube (InnerTube) were tried. Set a custom Invidious instance or check your network."
                isPlaying = false
                audioEngine.pausePlayback()
                if !offline {
                    currentLyrics = await lyricsAi.fetchLyrics(track: resolvedTrack, settings: settings)
                } else {
                    currentLyrics = nil
                }
                return
            }

            guard !Task.isCancelled else { return }
            self.queue = queue
            currentIndex = idx
            savePlaybackSession()
            isPlaying = true

            if !privacy {
                addHistory(resolvedTrack)
            }

            audioEngine.playQueue(queue, startIndex: idx)
            await loadSponsorSegmentsAfterPlay(for: resolvedTrack)

            if !offline {
                currentLyrics = await lyricsAi.fetchLyrics(track: resolvedTrack, settings: settings)
            } else {
                currentLyrics = nil
            }

            if !offline && !privacy {
                if settings.listenBrainzEnabled && settings.listenBrainzPlayingNow && !settings.listenBrainzToken.isEmpty {
                    await listenBrainz.submitPlayingNow(
                        token: settings.listenBrainzToken,
                        title: resolvedTrack.title,
                        artist: resolvedTrack.artist
                    )
                }
                await submitLastFmPlayingNow(track: resolvedTrack, settings: settings)
            }
            speechAnnouncer.announceIfNeeded(track: resolvedTrack, enabled: settings.speakSongDetailsEnabled)
            syncLiveActivity()
            if !privacy {
                FireballAnalytics.log("track_started", settings: settings, properties: ["id": resolvedTrack.effectiveId])
            }
        }
    }

    func playFromPlaylist(track: Track, source: [Track]) {
        play(track: track, source: source)
    }

    func createPlaylist(title: String) {
        let raw = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let slug =
            raw
                .lowercased()
                .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let safeSlug = slug.isEmpty ? "playlist" : String(slug.prefix(48))
        let id = "local_\(safeSlug)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        library.playlists.append(Playlist(id: id, title: raw, videos: []))
        persist()
    }

    func appendTracksUpNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        Task {
            let settings = library.settings
            guard let idx = currentIndex, !queue.isEmpty else {
                play(track: tracks[0], source: tracks)
                return
            }
            var resolved: [Track] = []
            for t in tracks {
                let r = await repository.resolvePlayableTrack(t, settings: settings)
                if let u = r.url?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                    resolved.append(r)
                }
            }
            guard !resolved.isEmpty else {
                error = "Could not resolve tracks for Play next."
                return
            }
            var q = queue
            let insertAt = min(idx + 1, q.count)
            q.insert(contentsOf: resolved, at: insertAt)
            queue = q
            audioEngine.applyQueueMutation(q, currentIndex: idx)
            persist()
        }
    }

    func appendTracksToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        Task {
            let settings = library.settings
            guard let idx = currentIndex, !queue.isEmpty else {
                play(track: tracks[0], source: tracks)
                return
            }
            var resolved: [Track] = []
            for t in tracks {
                let r = await repository.resolvePlayableTrack(t, settings: settings)
                if let u = r.url?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                    resolved.append(r)
                }
            }
            guard !resolved.isEmpty else {
                error = "Could not resolve tracks for queue."
                return
            }
            var q = queue
            q.append(contentsOf: resolved)
            queue = q
            audioEngine.applyQueueMutation(q, currentIndex: idx)
            persist()
        }
    }

    func stopPlaybackAndDismissMiniPlayer() {
        activePlayTask?.cancel()
        scrobbledTrackIds.removeAll()
        resetSponsorState()
        sponsorSkippedUUIDs.removeAll()
        audioEngine.stopAndClearPlayback()
        queue = []
        currentIndex = nil
        isPlaying = false
        currentLyrics = nil
        positionSeconds = 0
        durationSeconds = 0
        library.playbackSession = PlaybackSession()
        savePlaybackSession()
        lastLibraryPersistAt = Date()
        repository.saveLibrary(library)
        NowPlayingLiveActivityManager.end()
    }

    func consumeSearchFocusRequest() {
        searchFocusRequest = nil
    }

    /// Switch to Search with this query; consumed by root UI via `searchFocusRequest`.
    func requestSearchForArtist(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchFocusRequest = q
        error = nil
    }

    func requestArtistDetail(artistDisplayName: String) {
        let trimmed = artistDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let appleId =
            library.artists.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
                .flatMap { Int($0.artistId.trimmingCharacters(in: .whitespacesAndNewlines)) }
        navigateArtistDetailInternal(appleArtistId: appleId, fallback: trimmed)
    }

    func requestArtistDetail(appleArtistId: Int?, fallbackDisplayName: String) {
        let t = fallbackDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = t.isEmpty ? "Artist" : t
        navigateArtistDetailInternal(appleArtistId: appleArtistId, fallback: trimmed)
    }

    func consumeArtistOpenRequest() {
        artistOpenRequest = nil
    }

    private func navigateArtistDetailInternal(appleArtistId: Int?, fallback: String) {
        let name = fallback.isEmpty ? "Artist" : fallback
        artistOpenRequest = ArtistOpenRequest(appleId: appleArtistId, fallbackDisplayName: name)
        error = nil
    }

    func browseArtistPage(artistAppleId: Int?, fallbackName: String) async -> ArtistBrowseResult? {
        let t = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let namePassed = t.isEmpty ? nil : t
        return await repository.browseArtist(
            library: library,
            artistAppleId: artistAppleId,
            artistName: namePassed,
        )
    }

    func albumTracksCatalog(collectionId: Int) async -> [Track] {
        await repository.catalogAlbumTracks(collectionId: collectionId)
    }

    func playCatalogAlbum(_ album: Album) {
        guard let cid = Int(album.id) else {
            error = "Invalid album identifier."
            return
        }
        Task { @MainActor in
            let tracks = await albumTracksCatalog(collectionId: cid)
            guard let first = tracks.first else {
                error = "No tracks resolved for album."
                return
            }
            play(track: first, source: tracks)
        }
    }

    func userPlaylistsForPicker() -> [Playlist] {
        library.playlists.filter { $0.id != "ai_queue" }
    }

    func addTrackToPlaylist(track: Track, playlistId: String) {
        let id = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, let idx = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        let pl = library.playlists[idx]
        guard !pl.videos.contains(where: { $0.effectiveId == track.effectiveId }) else { return }
        library.playlists = library.playlists.enumerated().map { i, p in
            i == idx ? Playlist(id: p.id, title: p.title, videos: p.videos + [track]) : p
        }
        persist()
    }

    func playTrackUpNext(track: Track) {
        Task {
            let settings = library.settings
            guard let idx = currentIndex, !queue.isEmpty else {
                play(track: track, source: [track])
                return
            }
            let resolved = await repository.resolvePlayableTrack(track, settings: settings)
            let url = resolved.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !url.isEmpty else {
                error = "Could not resolve audio for Play next."
                return
            }
            var q = queue
            let insertAt = min(idx + 1, q.count)
            q.insert(resolved, at: insertAt)
            queue = q
            audioEngine.applyQueueMutation(q, currentIndex: idx)
            persist()
        }
    }

    func appendTrackToQueue(track: Track) {
        Task {
            let settings = library.settings
            guard let idx = currentIndex, !queue.isEmpty else {
                play(track: track, source: [track])
                return
            }
            let resolved = await repository.resolvePlayableTrack(track, settings: settings)
            let url = resolved.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !url.isEmpty else {
                error = "Could not resolve audio."
                return
            }
            var q = queue
            q.append(resolved)
            queue = q
            audioEngine.applyQueueMutation(q, currentIndex: idx)
            persist()
        }
    }

    func toggleFavorite(_ track: Track) {
        let wasFavorite = library.favorites.contains(where: { $0.effectiveId == track.effectiveId })
        if wasFavorite {
            library.favorites.removeAll { $0.effectiveId == track.effectiveId }
        } else {
            library.favorites.append(track)
        }
        persist()
        if !wasFavorite {
            autoPushFavoriteTrack(track)
        }
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        audioEngine.togglePlayPause()
    }

    func seekTo(seconds: Double) {
        audioEngine.seek(to: seconds)
    }

    func next() {
        Task { await userPressedNext() }
    }

    func previous() {
        Task { await userPressedPrevious() }
    }

    func updateSettings(_ mutation: (inout FireballSettings) -> Void) {
        let previous = library.settings
        var settings = library.settings
        mutation(&settings)
        library.settings = settings
        persist()
        if previous.dynamicIslandEnabled && !settings.dynamicIslandEnabled {
            NowPlayingLiveActivityManager.end()
        }
        let lbChanged = previous.listenBrainzEnabled != settings.listenBrainzEnabled ||
            previous.listenBrainzToken != settings.listenBrainzToken ||
            previous.listenBrainzUsername != settings.listenBrainzUsername
        if lbChanged {
            Task { await refreshListenBrainzHome() }
        }
        if previous.homeCountries != settings.homeCountries {
            let visible = HomeCountries.visibleCodes(saved: settings.homeCountries)
            if !visible.contains(where: { $0.caseInsensitiveCompare(chartCountryCode) == .orderedSame }) {
                chartCountryCode = visible.first?.lowercased() ?? "us"
                Task { await refreshHomeCharts(countryCode: chartCountryCode) }
            }
        }
        if !previous.notifyArtistReleasesOnDevice && settings.notifyArtistReleasesOnDevice {
            Task {
                _ = await ArtistReleaseNotifier.requestAuthorizationIfNeeded()
                await checkFollowedArtistNewReleases()
            }
        }
        ArtistReleaseBackgroundRefresh.scheduleIfNeeded(settings: settings)
    }

    func toggleShuffle() {
        shuffled.toggle()
        savePlaybackSession()
        persist()
    }

    func cycleRepeat() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
        savePlaybackSession()
        persist()
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerEnd = minutes.map { Date().addingTimeInterval(Double($0 * 60)) }
        sleepAfterCurrent = false
    }

    func setSleepAfterCurrent(_ enabled: Bool) {
        sleepAfterCurrent = enabled
        if enabled { sleepTimerEnd = nil }
    }

    func webDavPullMerge() async {
        let settings = library.settings
        guard !settings.webDavUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            integrationStatus = "webdav pull: missing URL"
            return
        }
        guard let json = await webDav.pullLibraryJson(
            baseURL: settings.webDavUrl,
            username: settings.webDavUsername,
            password: settings.webDavPassword
        ), let data = json.data(using: .utf8),
              let remote = try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
        else {
            integrationStatus = "webdav pull: failed"
            return
        }

        library.history = Array((library.history + remote.history).uniqued(by: \.effectiveId).prefix(200))
        library.favorites = (library.favorites + remote.favorites).uniqued(by: \.effectiveId)
        library.playlists = (library.playlists + remote.playlists).uniqued(by: \.id)
        library.artists = (library.artists + remote.artists).uniqued(by: \.artistId)
        library.albums = (library.albums + remote.albums).uniqued(by: \.id)
        persist()
        integrationStatus = "webdav pull: success"
    }

    func webDavPush() async {
        let settings = library.settings
        guard !settings.webDavUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            integrationStatus = "webdav push: missing URL"
            return
        }
        guard let data = try? JSONEncoder().encode(library),
              let json = String(data: data, encoding: .utf8) else {
            integrationStatus = "webdav push: encode failed"
            return
        }
        let ok = await webDav.pushLibraryJson(
            baseURL: settings.webDavUrl,
            username: settings.webDavUsername,
            password: settings.webDavPassword,
            json: json
        )
        integrationStatus = ok ? "webdav push: success" : "webdav push: failed"
    }

    private func addHistory(_ track: Track) {
        library.history.removeAll { $0.effectiveId == track.effectiveId }
        library.history.insert(track, at: 0)
        library.history = Array(library.history.prefix(200))
        persist()
    }

    private func persist() {
        savePlaybackSession()
        lastLibraryPersistAt = Date()
        repository.saveLibrary(library)
        scheduleWebDavLivePushIfNeeded()
    }

    private func persistPlaybackSessionDebounced() {
        savePlaybackSession()
        let now = Date()
        guard now.timeIntervalSince(lastLibraryPersistAt) >= 3 else { return }
        lastLibraryPersistAt = now
        repository.saveLibrary(library)
        scheduleWebDavLivePushIfNeeded()
    }

    private func scheduleWebDavLivePushIfNeeded() {
        let settings = library.settings
        guard settings.webDavLiveSync,
              !settings.webDavUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let snapshot = library
        Task {
            guard let data = try? JSONEncoder().encode(snapshot),
                  let json = String(data: data, encoding: .utf8) else { return }
            _ = await webDav.pushLibraryJson(
                baseURL: settings.webDavUrl,
                username: settings.webDavUsername,
                password: settings.webDavPassword,
                json: json
            )
        }
    }

    private func sleepTimerLoop() async {
        while !Task.isCancelled {
            if let sleepTimerEnd, Date() >= sleepTimerEnd {
                self.sleepTimerEnd = nil
                if isPlaying {
                    togglePlayPause()
                }
            }
            if sleepAfterCurrent && isPlaying && durationSeconds > 0 && positionSeconds >= durationSeconds - 1 {
                togglePlayPause()
                setSleepAfterCurrent(false)
            }
            await maybeScrobbleCurrent()
            await maybeAppendAIQueue()
            if isPlaying, currentIndex != nil {
                persistPlaybackSessionDebounced()
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func maybeScrobbleCurrent() async {
        guard let track = currentTrack else { return }
        let settings = library.settings
        guard settings.scrobbleEnabled else { return }
        if settings.offlineModeEnabled || settings.privacyModeEnabled { return }
        let lbReady = settings.listenBrainzEnabled && !settings.listenBrainzToken.isEmpty
        let lastFmReady = !settings.lastFmApiKey.isEmpty &&
            !settings.lastFmApiSecret.isEmpty &&
            !settings.lastFmSessionKey.isEmpty
        guard lbReady || lastFmReady else { return }
        guard isPlaying else { return }
        guard ScrobbleRules.shouldScrobble(
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            percent: settings.listenBrainzScrobblePercent,
            maxSeconds: settings.listenBrainzScrobbleMaxSeconds,
            minTrackSeconds: settings.listenBrainzScrobbleMinTrackSeconds
        ) else { return }
        guard scrobbledTrackIds.insert(track.effectiveId).inserted else { return }

        let listenedAt = Int64(Date().timeIntervalSince1970)
        if lbReady {
            await listenBrainz.submitScrobble(
                token: settings.listenBrainzToken,
                title: track.title,
                artist: track.artist,
                listenedAt: listenedAt
            )
        }
        if lastFmReady {
            _ = await lastFm.scrobble(
                apiKey: settings.lastFmApiKey,
                apiSecret: settings.lastFmApiSecret,
                sessionKey: settings.lastFmSessionKey,
                title: track.title,
                artist: track.artist,
                listenedAt: listenedAt,
                album: track.album
            )
        }
        FireballAnalytics.log("scrobble", settings: settings, properties: ["id": track.effectiveId])
    }

    private func maybeAppendAIQueue() async {
        guard let track = currentTrack, let idx = currentIndex else { return }
        let atTail = idx == queue.count - 1
        guard atTail else { return }
        let mode = library.settings.queueMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mode == "ai" else { return }
        guard library.settings.ollamaEnabled else { return }
        guard !library.settings.ollamaUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !library.settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        if library.settings.offlineModeEnabled || library.settings.privacyModeEnabled { return }
        guard aiQueueExpandedForTrackIds.insert(track.effectiveId).inserted else { return }

        let suggestions = await lyricsAi.generateAIQueue(settings: library.settings, seed: track)
        guard !suggestions.isEmpty else { return }
        let generated = suggestions.enumerated().map { offset, line -> Track in
            let parts = line.components(separatedBy: " - ")
            return Track(
                id: "ai_\(track.effectiveId)_\(offset)",
                videoId: nil,
                title: parts.first?.trimmingCharacters(in: .whitespaces).nonEmpty ?? line,
                artist: parts.dropFirst().first?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "AI suggestion",
                artwork: nil,
                url: nil,
                duration: nil,
                album: nil,
                year: nil
            )
        }
        queue.append(contentsOf: generated)
        savePlaybackSession()
        persistAIQueue(generated)
    }

    private func persistAIQueue(_ generated: [Track]) {
        guard !generated.isEmpty else { return }
        let existing = library.playlists.first(where: { $0.id == "ai_queue" })
        let mergedVideos = ((existing?.videos ?? []) + generated).uniqued(by: \.effectiveId).suffix(200)
        let aiPlaylist = Playlist(id: "ai_queue", title: "AI Queue", videos: Array(mergedVideos))
        library.playlists.removeAll { $0.id == "ai_queue" }
        library.playlists.append(aiPlaylist)
        persist()
    }

    func sendGotifyTest() async -> Bool {
        guard library.settings.gotifyEnabled else {
            integrationStatus = "gotify: disabled in settings"
            return false
        }
        let ok = await gotify.send(
            url: library.settings.gotifyUrl,
            token: library.settings.gotifyToken,
            title: "Fireball Native",
            message: "Gotify integration works."
        )
        integrationStatus = ok ? Status.gotifyOk : Status.gotifyFail
        return ok
    }

    func checkLbdl() async -> Bool {
        let ok = await lbdl.authStatus(
            baseUrl: library.settings.lbdlUrl,
            username: library.settings.lbdlUsername,
            password: library.settings.lbdlPassword
        )
        integrationStatus = ok ? Status.lbdlAuthOk : Status.lbdlAuthFail
        return ok
    }

    func createLbdlJobFromQueue() async -> String? {
        var links: [String] = []
        for track in queue {
            if let url = track.url, !url.isEmpty {
                links.append(url)
            } else if let vid = track.videoId, !vid.isEmpty {
                links.append("https://www.youtube.com/watch?v=\(vid)")
            }
        }
        guard !links.isEmpty else {
            integrationStatus = "lbdl job: no URLs in queue"
            return nil
        }
        let jobId = await lbdl.createJob(
            baseUrl: library.settings.lbdlUrl,
            username: library.settings.lbdlUsername,
            password: library.settings.lbdlPassword,
            links: links
        )
        integrationStatus = jobId != nil ? "\(Status.lbdlJobOkPrefix) (\(jobId!))" : Status.lbdlJobFail
        return jobId
    }

    func sendRemoteCommand(_ action: String, value: String? = nil) async -> Bool {
        guard library.settings.remoteServerEnabled else {
            integrationStatus = "remote: disabled in settings"
            return false
        }
        let ok = await remoteLan.sendCommand(
            host: library.settings.remoteHostIp,
            port: library.settings.remotePeerPort,
            action: action,
            value: value
        )
        integrationStatus = ok ? Status.remoteCmdOk : Status.remoteCmdFail
        return ok
    }

    func pairRemote(code: String) async -> Bool {
        guard library.settings.remoteServerEnabled else {
            integrationStatus = "remote: disabled in settings"
            return false
        }
        let ok = await remoteLan.pair(
            host: library.settings.remoteHostIp,
            port: library.settings.remotePeerPort,
            code: code
        )
        integrationStatus = ok ? Status.remotePairOk : Status.remotePairFail
        return ok
    }

    func backupToGoogleDrive(accessToken: String) async -> Bool {
        guard library.settings.gDriveEnabled else {
            integrationStatus = "gdrive: disabled in settings"
            return false
        }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            integrationStatus = "gdrive: missing access token"
            return false
        }
        guard let data = try? JSONEncoder().encode(library),
              let json = String(data: data, encoding: .utf8) else { return false }
        let ok = await gDrive.uploadAppDataJson(
            accessToken: token,
            fileName: "fireball_library.json",
            content: json
        )
        if ok {
            var s = library.settings
            s.lastBackupAt = ISO8601DateFormatter().string(from: Date())
            library.settings = s
            persist()
        }
        integrationStatus = ok ? Status.gdriveOk : Status.gdriveFail
        return ok
    }

    // MARK: - Playback navigation & SponsorBlock

    private func resetSponsorState() {
        sponsorSegmentsForVideo = []
        sponsorSegmentsVideoId = nil
        sponsorSkippedUUIDs.removeAll()
    }

    private func loadSponsorSegmentsAfterPlay(for track: Track) async {
        resetSponsorState()
        let settings = library.settings
        guard settings.sponsorBlock, !settings.sponsorBlockCategories.isEmpty, let vid = track.videoId, !vid.isEmpty else { return }
        sponsorSegmentsVideoId = vid
        sponsorSegmentsForVideo = await sponsorBlock.segments(videoId: vid, categories: settings.sponsorBlockCategories)
    }

    private func maybeAutoSkipSponsor(positionSeconds position: Double) {
        let settings = library.settings
        guard settings.sponsorBlock, !settings.sponsorBlockCategories.isEmpty else { return }
        guard let vid = currentTrack?.videoId, vid == sponsorSegmentsVideoId else { return }
        guard !sponsorSegmentsForVideo.isEmpty else { return }
        for seg in sponsorSegmentsForVideo {
            let start = seg.start
            let end = seg.end
            guard end > start else { continue }
            if position < start + 0.04 || position >= end - 0.04 { continue }
            if sponsorSkippedUUIDs.contains(seg.uuid) { continue }
            sponsorSkippedUUIDs.insert(seg.uuid)
            let uuid = seg.uuid
            Task { await sponsorBlock.markViewed(uuid: uuid) }
            seekTo(seconds: end)
            break
        }
    }

    private func openQueueIndex(_ index: Int) async {
        guard queue.indices.contains(index) else { return }
        var q = queue
        var track = q[index]
        if track.url == nil || (track.url ?? "").isEmpty {
            track = await repository.resolvePlayableTrack(track, settings: library.settings)
            q[index] = track
            queue = q
        }
        guard let u = track.url, !u.isEmpty else {
            error = "No stream URL for this track in the queue."
            isPlaying = false
            audioEngine.pausePlayback()
            return
        }
        error = nil
        scrobbledTrackIds.removeAll()
        guard audioEngine.playQueue(q, startIndex: index) else { return }
        currentIndex = index
        isPlaying = true
        savePlaybackSession()
        persist()
        let settings = library.settings
        let lyricsTrackId = track.effectiveId
        if !settings.offlineModeEnabled && !settings.privacyModeEnabled {
            let lyrics = await lyricsAi.fetchLyrics(track: track, settings: settings)
            if currentIndex == index, queue.indices.contains(index), queue[index].effectiveId == lyricsTrackId {
                currentLyrics = lyrics
            }
        }
        await loadSponsorSegmentsAfterPlay(for: track)
        if !settings.offlineModeEnabled && !settings.privacyModeEnabled {
            if settings.listenBrainzEnabled && settings.listenBrainzPlayingNow && !settings.listenBrainzToken.isEmpty {
                await listenBrainz.submitPlayingNow(
                    token: settings.listenBrainzToken,
                    title: track.title,
                    artist: track.artist
                )
            }
            await submitLastFmPlayingNow(track: track, settings: settings)
        }
        speechAnnouncer.announceIfNeeded(track: track, enabled: settings.speakSongDetailsEnabled)
        syncLiveActivity()
    }

    private func submitLastFmPlayingNow(track: Track, settings: FireballSettings) async {
        guard !settings.lastFmApiKey.isEmpty,
              !settings.lastFmApiSecret.isEmpty,
              !settings.lastFmSessionKey.isEmpty
        else { return }
        _ = await lastFm.updateNowPlaying(
            apiKey: settings.lastFmApiKey,
            apiSecret: settings.lastFmApiSecret,
            sessionKey: settings.lastFmSessionKey,
            title: track.title,
            artist: track.artist,
            album: track.album
        )
    }

    private func syncLiveActivity() {
        guard let track = currentTrack else {
            NowPlayingLiveActivityManager.end()
            return
        }
        if #available(iOS 16.1, *) {
            NowPlayingLiveActivityManager.update(
                enabled: library.settings.dynamicIslandEnabled,
                title: track.title,
                artist: track.artist,
                isPlaying: isPlaying
            )
        }
    }

    func validateLastFmKey() async -> Bool {
        let ok = await lastFm.validateApiKey(library.settings.lastFmApiKey)
        integrationStatus = ok ? "last.fm: api key valid" : "last.fm: api key invalid"
        return ok
    }

    func connectLastFm(password: String) async -> Bool {
        let settings = library.settings
        guard let session = await lastFm.mobileSession(
            apiKey: settings.lastFmApiKey,
            apiSecret: settings.lastFmApiSecret,
            username: settings.lastFmUsername,
            password: password
        ) else {
            integrationStatus = "last.fm: login failed"
            return false
        }
        library.settings.lastFmSessionKey = session
        persist()
        integrationStatus = "last.fm: connected"
        return true
    }

    private func advanceAfterTrackFinished() async {
        guard let idx = currentIndex else { return }
        let mode = library.settings.queueMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if repeatMode == .one {
            isPlaying = true
            audioEngine.seek(to: 0)
            return
        }
        if shuffled, queue.count > 1 {
            let choices = queue.indices.filter { $0 != idx }
            if let next = choices.randomElement() {
                await openQueueIndex(next)
                return
            }
        }
        if idx + 1 < queue.count {
            await openQueueIndex(idx + 1)
        } else if repeatMode == .all {
            await openQueueIndex(0)
        } else if mode == "repeat" {
            await openQueueIndex(0)
        } else {
            isPlaying = false
            audioEngine.pausePlayback()
        }
    }

    private func userPressedNext() async {
        guard let idx = currentIndex else { return }
        if repeatMode == .one {
            audioEngine.seek(to: 0)
            audioEngine.resumeIfPaused()
            isPlaying = true
            return
        }
        if shuffled, queue.count > 1 {
            let choices = queue.indices.filter { $0 != idx }
            if let next = choices.randomElement() {
                await openQueueIndex(next)
                return
            }
        }
        if idx + 1 < queue.count {
            await openQueueIndex(idx + 1)
        } else if repeatMode == .all {
            await openQueueIndex(0)
        } else if library.settings.queueMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "repeat" {
            await openQueueIndex(0)
        }
    }

    private func userPressedPrevious() async {
        guard let idx = currentIndex else { return }
        if repeatMode == .one {
            audioEngine.seek(to: 0)
            audioEngine.resumeIfPaused()
            isPlaying = true
            return
        }
        if positionSeconds > 3 {
            audioEngine.seek(to: 0)
            return
        }
        if shuffled, queue.count > 1 {
            let choices = queue.indices.filter { $0 != idx }
            if let pick = choices.randomElement() {
                await openQueueIndex(pick)
                return
            }
        }
        await openQueueIndex(max(0, idx - 1))
    }

    func clearError() {
        error = nil
    }

    func invidiousLogin(username: String, password: String) {
        let settings = library.settings
        guard !settings.invidiousInstance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty
        else {
            integrationStatus = "\(Status.invidiousLoginFail) (missing instance, user, or password)"
            return
        }
        Task {
            do {
                let result = try await repository.invidiousLogin(settings: settings, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                var s = library.settings
                s.invidiousSid = result.sid
                s.invidiousUsername = result.username
                library.settings = s
                persist()
                integrationStatus = Status.invidiousLoginOk
                await refreshInvidiousPlaylists()
            } catch {
                integrationStatus = "\(Status.invidiousLoginFail) (\(error.localizedDescription))"
            }
        }
    }

    func refreshInvidiousPlaylists() async {
        let settings = library.settings
        guard let sid = settings.invidiousSid, !sid.isEmpty, !settings.invidiousInstance.isEmpty else {
            invidiousPlaylists = []
            return
        }
        let list = await repository.invidiousAuthPlaylists(settings: settings)
        invidiousPlaylists = list
    }

    func invidiousSyncPlaylist(playlistId: String) {
        let trimmed = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let settings = library.settings
            guard let synced = await repository.invidiousSyncPlaylist(settings: settings, playlistId: trimmed) else {
                integrationStatus = Status.invidiousSyncFail
                return
            }
            var pls = library.playlists.filter { $0.id != synced.id }
            pls.append(synced)
            library.playlists = pls
            persist()
            integrationStatus = Status.invidiousSyncOk
        }
    }

    func invidiousPushPlaylist(localPlaylistId: String, existingInvidiousId: String?) {
        let lid = localPlaylistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lid.isEmpty else { return }
        Task {
            let settings = library.settings
            guard let local = library.playlists.first(where: { $0.id == lid }) else {
                integrationStatus = Status.invidiousPushFail
                return
            }
            let remote = existingInvidiousId.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            guard let remoteId = await repository.invidiousPushPlaylist(settings: settings, local: local, existingInvidiousId: remote) else {
                integrationStatus = Status.invidiousPushFail
                return
            }
            var s = library.settings
            var map = s.invidiousPlaylistMappings
            map[local.id] = remoteId
            s.invidiousPlaylistMappings = map
            library.settings = s
            persist()
            integrationStatus = Status.invidiousPushOk
        }
    }

    private func autoPushFavoriteTrack(_ track: Track) {
        let settings = library.settings
        guard settings.invidiousAutoPush,
              !settings.invidiousInstance.isEmpty,
              let sid = settings.invidiousSid, !sid.isEmpty,
              let remoteId = settings.invidiousPlaylistMappings["favorites"], !remoteId.isEmpty
        else { return }
        Task {
            let local = Playlist(id: "favorites", title: "Favorites", videos: [track])
            _ = await repository.invidiousPushPlaylist(settings: settings, local: local, existingInvidiousId: remoteId)
        }
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }

    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

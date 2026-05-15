import Foundation
import SwiftUI

enum RepeatMode: String, CaseIterable {
    case off, all, one
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

    private let repository: FireballRepository
    private let listenBrainz = ListenBrainzClient()
    private let webDav = WebDavSyncClient()
    private let gotify = GotifyClient()
    private let lbdl = LbdlClient()
    private let remoteLan = RemoteLanClient()
    private let gDrive = GoogleDriveBackupClient()
    private let sponsorBlock = SponsorBlockClient()
    private let audioEngine = NativeAudioEngine()
    private let lyricsAi: LyricsAndAIService
    private var scrobbledTrackIds = Set<String>()
    private var aiQueueExpandedForTrackIds = Set<String>()
    private var sponsorSegmentsForVideo: [SponsorSegment] = []
    private var sponsorSegmentsVideoId: String?
    private var sponsorSkippedUUIDs = Set<String>()

    init(repository: FireballRepository) {
        self.repository = repository
        self.library = repository.loadLibrary()
        self.lyricsAi = LyricsAndAIService(api: FireballAPIClient())
        audioEngine.onStateUpdate = { [weak self] currentIndex, isPlaying, position, duration in
            guard let self else { return }
            self.currentIndex = currentIndex >= 0 ? currentIndex : self.currentIndex
            self.isPlaying = isPlaying
            self.positionSeconds = position
            self.durationSeconds = duration
            self.maybeAutoSkipSponsor(positionSeconds: position)
        }
        audioEngine.onTrackEnded = { [weak self] in
            guard let self else { return }
            if self.sleepAfterCurrent {
                self.isPlaying = false
                self.setSleepAfterCurrent(false)
                return
            }
            if self.repeatMode == .one {
                if let idx = self.currentIndex {
                    self.audioEngine.playQueue(self.queue, startIndex: idx)
                }
                return
            }
            Task { await self.advanceAfterTrackFinished() }
        }
        audioEngine.onInterrupted = { [weak self] interrupted in
            guard let self else { return }
            if interrupted {
                self.isPlaying = false
            }
        }
        audioEngine.onRemoteNext = { [weak self] in
            Task { @MainActor in await self?.userPressedNext() }
        }
        audioEngine.onRemotePrevious = { [weak self] in
            Task { @MainActor in await self?.userPressedPrevious() }
        }
        Task { await sleepTimerLoop() }
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

        searchResults = await repository.searchTracks(query: query, settings: settings)
        isSearching = false
    }

    func play(track: Track, source: [Track]) {
        let settings = library.settings
        Task {
            error = nil
            let resolvedTrack = await repository.resolvePlayableTrack(track, settings: settings)
            let queue = source.map { $0.effectiveId == track.effectiveId ? resolvedTrack : $0 }
            let idx = max(0, queue.firstIndex(where: { $0.effectiveId == track.effectiveId }) ?? 0)

            self.queue = queue
            currentIndex = idx

            let offline = settings.offlineModeEnabled
            let privacy = settings.privacyModeEnabled

            if !privacy {
                addHistory(resolvedTrack)
            }

            guard let url = resolvedTrack.url, !url.isEmpty else {
                error = "Could not get a stream for this track. Set an Invidious instance, sign in if required, or enable Piped fallback."
                isPlaying = false
                if !offline {
                    currentLyrics = await lyricsAi.fetchLyrics(track: resolvedTrack, settings: settings)
                } else {
                    currentLyrics = nil
                }
                return
            }

            isPlaying = true
            audioEngine.playQueue(queue, startIndex: idx)
            await loadSponsorSegmentsAfterPlay(for: resolvedTrack)

            if !offline {
                currentLyrics = await lyricsAi.fetchLyrics(track: resolvedTrack, settings: settings)
            } else {
                currentLyrics = nil
            }

            if !offline && !privacy && settings.listenBrainzEnabled && settings.listenBrainzPlayingNow {
                await listenBrainz.submitPlayingNow(
                    token: settings.listenBrainzToken,
                    title: resolvedTrack.title,
                    artist: resolvedTrack.artist
                )
            }
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
        isPlaying.toggle()
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
        var settings = library.settings
        mutation(&settings)
        library.settings = settings
        persist()
    }

    func toggleShuffle() { shuffled.toggle() }

    func cycleRepeat() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
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
        guard let json = await webDav.pullLibraryJson(
            baseURL: settings.webDavUrl,
            username: settings.webDavUsername,
            password: settings.webDavPassword
        ), let data = json.data(using: .utf8),
              let remote = try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
        else { return }

        library.history = Array((library.history + remote.history).uniqued(by: \.effectiveId).prefix(200))
        library.favorites = (library.favorites + remote.favorites).uniqued(by: \.effectiveId)
        library.playlists = (library.playlists + remote.playlists).uniqued(by: \.id)
        library.artists = (library.artists + remote.artists).uniqued(by: \.artistId)
        library.albums = (library.albums + remote.albums).uniqued(by: \.id)
        persist()
    }

    func webDavPush() async {
        let settings = library.settings
        guard let data = try? JSONEncoder().encode(library),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = await webDav.pushLibraryJson(
            baseURL: settings.webDavUrl,
            username: settings.webDavUsername,
            password: settings.webDavPassword,
            json: json
        )
    }

    private func addHistory(_ track: Track) {
        library.history.removeAll { $0.effectiveId == track.effectiveId }
        library.history.insert(track, at: 0)
        library.history = Array(library.history.prefix(200))
        persist()
    }

    private func persist() {
        repository.saveLibrary(library)
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
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func maybeScrobbleCurrent() async {
        guard let track = currentTrack else { return }
        let settings = library.settings
        if settings.offlineModeEnabled || settings.privacyModeEnabled { return }
        guard settings.listenBrainzEnabled, !settings.listenBrainzToken.isEmpty else { return }
        guard durationSeconds > 0 else { return }

        let thresholdByPercent = durationSeconds * Double(settings.listenBrainzScrobblePercent) / 100.0
        let thresholdByMax = Double(settings.listenBrainzScrobbleMaxSeconds)
        let threshold = max(1, min(thresholdByPercent, thresholdByMax))
        guard positionSeconds >= threshold else { return }
        guard scrobbledTrackIds.insert(track.effectiveId).inserted else { return }

        await listenBrainz.submitScrobble(
            token: settings.listenBrainzToken,
            title: track.title,
            artist: track.artist,
            listenedAt: Int64(Date().timeIntervalSince1970)
        )
    }

    private func maybeAppendAIQueue() async {
        guard let track = currentTrack, let idx = currentIndex else { return }
        let atTail = idx >= queue.count - 2
        guard atTail else { return }
        guard library.settings.ollamaEnabled else { return }
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
        let links = queue.compactMap { $0.url }
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
        let ok = await remoteLan.pair(
            host: library.settings.remoteHostIp,
            port: library.settings.remotePeerPort,
            code: code
        )
        integrationStatus = ok ? Status.remotePairOk : Status.remotePairFail
        return ok
    }

    func backupToGoogleDrive(accessToken: String) async -> Bool {
        guard let data = try? JSONEncoder().encode(library),
              let json = String(data: data, encoding: .utf8) else { return false }
        let ok = await gDrive.uploadAppDataJson(
            accessToken: accessToken,
            fileName: "fireball_library.json",
            content: json
        )
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
            return
        }
        error = nil
        currentIndex = index
        isPlaying = true
        audioEngine.playQueue(q, startIndex: index)
        await loadSponsorSegmentsAfterPlay(for: track)
    }

    private func advanceAfterTrackFinished() async {
        guard let idx = currentIndex else { return }
        if idx + 1 < queue.count {
            await openQueueIndex(idx + 1)
        } else if repeatMode == .all {
            await openQueueIndex(0)
        } else {
            isPlaying = false
        }
    }

    private func userPressedNext() async {
        guard let idx = currentIndex else { return }
        if repeatMode == .one {
            isPlaying = true
            audioEngine.playQueue(queue, startIndex: idx)
            return
        }
        if shuffled, queue.count > 1 {
            let r = Int.random(in: 0..<queue.count)
            await openQueueIndex(r)
            return
        }
        if idx + 1 < queue.count {
            await openQueueIndex(idx + 1)
        } else if repeatMode == .all {
            await openQueueIndex(0)
        }
    }

    private func userPressedPrevious() async {
        guard let idx = currentIndex else { return }
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

import Foundation

/// iTunes-backed artist browse payload (catalog + filtered local playlists).
struct ArtistBrowseResult: Sendable, Equatable {
    let artistAppleId: Int
    let displayName: String
    let artworkUrl: String?
    let songs: [Track]
    let albums: [Album]
    let playlistsContainingArtist: [Playlist]
}

@MainActor
final class FireballRepository {
    private static let searchCachePrefix = "v5:"

    private let api: FireballAPIClient
    private let store: LibraryStore
    private var searchCache: [String: [Track]] = [:]

    init(api: FireballAPIClient, store: LibraryStore) {
        self.api = api
        self.store = store
    }

    func loadLibrary() -> LibrarySnapshot {
        store.load()
    }

    func saveLibrary(_ snapshot: LibrarySnapshot) {
        try? store.save(snapshot)
    }

    func resolveArtistForFollow(artistName: String, fallbackArtwork: String? = nil) async -> Artist {
        var artistId = artistName
        var name = artistName
        var artwork = fallbackArtwork
        if let found = try? await api.iTunesFindArtist(artistName) {
            if let id = found["artistId"] {
                artistId = "\(id)"
            }
            if let n = found["artistName"] as? String { name = n }
            if artwork == nil, let idNum = Int(artistId),
               let albums = try? await api.iTunesArtistAlbums(artistId: idNum, limit: 1),
               let url = albums.first?["artworkUrl100"] as? String {
                artwork = url.replacingOccurrences(of: "100x100", with: "600x600")
            }
        }
        return Artist(artistId: artistId, name: name, artwork: artwork, latestReleaseId: nil)
    }

    func fetchTopSongs(countryCode: String, limit: Int = 20) async -> [Track] {
        let cc = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cc.isEmpty else { return [] }
        guard let data = try? await api.iTunesTopSongs(countryCode: cc, limit: limit) else { return [] }
        let entries = ItunesFeedParser.feedEntries(from: data)
        return ItunesFeedParser.topCharts(from: entries).map { entry in
            Track(
                id: entry.id,
                videoId: nil,
                title: entry.title,
                artist: entry.artist,
                artwork: entry.artwork,
                url: nil,
                duration: nil,
                album: nil,
                year: nil
            )
        }
    }

    func checkFollowedArtistNewReleases(
        snapshot: LibrarySnapshot,
        onGotifyNotify: (@Sendable (String, String) async -> Bool)?,
        onDeviceNotify: (@Sendable (String, String) async -> Void)?
    ) async -> LibrarySnapshot? {
        let settings = snapshot.settings
        let wantGotify =
            settings.gotifyEnabled &&
            !settings.gotifyUrl.isEmpty &&
            !settings.gotifyToken.isEmpty &&
            onGotifyNotify != nil
        let wantDevice = settings.notifyArtistReleasesOnDevice && onDeviceNotify != nil
        if !wantGotify && !wantDevice { return nil }

        var artistsChanged = false
        var updatedArtists: [Artist] = []
        for artist in snapshot.artists {
            guard let artistIdNum = Int(artist.artistId) else {
                updatedArtists.append(artist)
                continue
            }
            guard let albums = try? await api.iTunesArtistAlbums(artistId: artistIdNum, limit: 1),
                  let latest = albums.first,
                  let releaseId = Self.stringValue(latest["collectionId"])
            else {
                updatedArtists.append(artist)
                continue
            }
            let releaseName = latest["collectionName"] as? String ?? "New Release"
            if releaseId == artist.latestReleaseId {
                updatedArtists.append(artist)
                continue
            }

            if artist.latestReleaseId != nil {
                let title = "New Release from \(artist.name)"
                let message = "\(releaseName) is out now!"
                if wantGotify {
                    _ = await onGotifyNotify!(title, message)
                }
                if wantDevice {
                    await onDeviceNotify!(title, message)
                }
            }
            artistsChanged = true
            updatedArtists.append(
                Artist(
                    artistId: artist.artistId,
                    name: artist.name,
                    artwork: artist.artwork,
                    latestReleaseId: releaseId
                )
            )
        }

        guard artistsChanged else { return nil }
        var next = snapshot
        next.artists = updatedArtists
        return next
    }

    func searchAlbumsCatalog(query: String, settings: FireballSettings) async -> [Album] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !settings.offlineModeEnabled else { return [] }
        guard let data = try? await api.iTunesSearchAlbums(term: q),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["results"] as? [[String: Any]]
        else {
            return []
        }
        return items.compactMap { Self.jsonCollectionToAlbum($0) }
    }

    func catalogAlbumTracks(collectionId: Int) async -> [Track] {
        guard let rows = try? await api.iTunesAlbumTracks(collectionId: collectionId) else {
            return []
        }
        return rows.compactMap(Self.jsonObjectToCatalogTrack(_:))
    }

    func browseArtist(library: LibrarySnapshot, artistAppleId: Int?, artistName: String?) async -> ArtistBrowseResult? {
        let resolvedId: Int
        if let artistAppleId {
            resolvedId = artistAppleId
        } else {
            let guess = artistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !guess.isEmpty,
                  let found = try? await api.iTunesFindArtist(guess),
                  let sid = Self.stringValue(found["artistId"]),
                  let idNum = Int(sid) else {
                return nil
            }
            resolvedId = idNum
        }

        let meta = try? await api.iTunesArtistDetail(artistId: resolvedId)
        let dnFromMeta = (meta?["artistName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dnFromGuess = artistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = !dnFromMeta.isEmpty ? dnFromMeta : (!dnFromGuess.isEmpty ? dnFromGuess : "Artist")
        var artwork =
            ((meta?["artworkUrl100"] as? String)?
                .replacingOccurrences(of: "100x100", with: "600x600"))
        let songRows =
            ((try? await api.iTunesArtistSongs(artistId: resolvedId, limit: 60)) ?? [])
                .compactMap(Self.jsonObjectToCatalogTrack(_:))

        let albumRows = (try? await api.iTunesArtistAlbums(artistId: resolvedId, limit: 80)) ?? []
        var albumSeen = Set<String>()
        let albums = albumRows.compactMap(Self.jsonCollectionToAlbum(_:)).filter { albumSeen.insert($0.id).inserted }

        if artwork == nil || artwork?.isEmpty == true {
            artwork =
                (albumRows.first?["artworkUrl100"] as? String)?
                .replacingOccurrences(of: "100x100", with: "600x600")
        }

        let needle = displayName.lowercased()
        let playlists =
            library.playlists.filter { pl in
                pl.videos.contains { row in
                    let a = row.artist.lowercased()
                    return a == needle || a.contains(needle) || needle.contains(a)
                }
            }

        return ArtistBrowseResult(
            artistAppleId: resolvedId,
            displayName: displayName,
            artworkUrl: artwork,
            songs: songRows,
            albums: albums,
            playlistsContainingArtist: playlists,
        )
    }

    func searchTracks(query: String, settings: FireballSettings) async -> [Track] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let cacheKey = Self.searchCachePrefix + normalizedQuery
        let downloaded = resolveLocalDownloadedMatches(normalizedQuery: normalizedQuery, settings: settings)
        if !downloaded.isEmpty { return downloaded }

        if settings.offlineModeEnabled {
            return []
        }
        if settings.cacheEnabled, let cached = searchCache[cacheKey], !cached.isEmpty { return cached }

        if let iTunesTracks = await searchITunes(query: query), !iTunesTracks.isEmpty {
            cache(query: cacheKey, tracks: iTunesTracks, settings: settings)
            return iTunesTracks
        }

        let invidiousList = await invidiousInstances(settings: settings)
        for instance in invidiousList {
            if let invidious = await searchInvidious(query: query, instance: instance, sid: settings.invidiousSid), !invidious.isEmpty {
                cache(query: cacheKey, tracks: invidious, settings: settings)
                return invidious
            }
        }

        return []
    }

    func resolvePlayableTracks(source: [Track], settings: FireballSettings) async -> [Track] {
        var resolved: [Track] = []
        resolved.reserveCapacity(source.count)
        for track in source {
            resolved.append(await resolvePlayableTrack(track, settings: settings))
        }
        return resolved
    }

    /// Resolves one track to a stream URL (matches Android / Flutter: no iTunes preview as final URL).
    func resolvePlayableTrack(_ track: Track, settings: FireballSettings) async -> Track {
        if let local = resolveDownloadedPath(for: track, settings: settings) {
            return Track(
                id: track.id,
                videoId: track.videoId,
                title: track.title,
                artist: track.artist,
                artwork: track.artwork,
                url: local,
                duration: track.duration,
                album: track.album,
                year: track.year
            )
        }

        if let url = track.url, !url.isEmpty, !isItunesPreviewUrl(url) {
            return track
        }

        let invidiousList = await invidiousInstances(settings: settings)
        for instance in invidiousList {
            if let resolved = await resolveViaInvidious(track: track, instance: instance, settings: settings),
               let url = resolved.url, !url.isEmpty {
                return resolved
            }
        }

        if let direct = await resolveViaYoutubeDirect(track: track, settings: settings),
           let url = direct.url, !url.isEmpty {
            return direct
        }

        return track
    }

    private func resolveViaYoutubeDirect(track: Track, settings: FireballSettings) async -> Track? {
        let highQuality = settings.highQuality
        if let videoId = track.videoId?.trimmingCharacters(in: .whitespacesAndNewlines), !videoId.isEmpty,
           let url = await YoutubeDirectStreamResolver.resolveAudioUrl(videoId: videoId, highQuality: highQuality) {
            return trackWithUrl(track, url: url, videoId: videoId)
        }
        guard let found = await YoutubeDirectStreamResolver.searchAndResolveAudio(
            artist: track.artist,
            title: track.title,
            highQuality: highQuality
        ) else { return nil }
        return trackWithUrl(track, url: found.1, videoId: found.0)
    }

    // MARK: - Invidious playlist (used by MainViewModel)

    func invidiousLogin(settings: FireballSettings, username: String, password: String) async throws -> (sid: String, username: String) {
        try await api.invidiousLogin(instanceURL: settings.invidiousInstance, username: username, password: password)
    }

    func invidiousAuthPlaylists(settings: FireballSettings) async -> [(id: String, title: String)] {
        guard let sid = settings.invidiousSid, !sid.isEmpty, !settings.invidiousInstance.isEmpty else { return [] }
        guard let data = try? await api.invidiousAuthPlaylists(instanceURL: settings.invidiousInstance, sid: sid),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return arr.compactMap { item in
            guard let id = item["playlistId"] as? String else { return nil }
            let title = item["title"] as? String ?? "Playlist"
            return (id, title)
        }
    }

    func invidiousSyncPlaylist(settings: FireballSettings, playlistId: String) async -> Playlist? {
        guard !settings.invidiousInstance.isEmpty, !playlistId.isEmpty else { return nil }
        guard let data = try? await api.invidiousPlaylistDetail(
            instanceURL: settings.invidiousInstance,
            sid: settings.invidiousSid,
            playlistId: playlistId
        ),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let id = root["playlistId"] as? String ?? playlistId
        let title = root["title"] as? String ?? "Playlist"
        let videoArr = root["videos"] as? [[String: Any]] ?? []
        let videos: [Track] = videoArr.compactMap { obj in
            guard let videoId = obj["videoId"] as? String else { return nil }
            let thumbs = obj["videoThumbnails"] as? [[String: Any]]
            let art = thumbs?.first?["url"] as? String
            return Track(
                id: videoId,
                videoId: videoId,
                title: obj["title"] as? String ?? "Unknown",
                artist: obj["author"] as? String ?? "Unknown",
                artwork: art,
                url: nil,
                duration: nil,
                album: nil,
                year: nil
            )
        }
        return Playlist(id: id, title: title, videos: videos)
    }

    func invidiousPushPlaylist(settings: FireballSettings, local: Playlist, existingInvidiousId: String?) async -> String? {
        guard let sid = settings.invidiousSid, !sid.isEmpty, !settings.invidiousInstance.isEmpty, !local.videos.isEmpty else { return nil }

        var invId = existingInvidiousId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if invId.isEmpty {
            invId = (try? await api.invidiousCreatePlaylist(
                instanceURL: settings.invidiousInstance,
                sid: sid,
                title: local.title,
                privacy: settings.invidiousPlaylistPrivacy
            )) ?? ""
        }
        guard !invId.isEmpty else { return nil }

        for track in local.videos {
            let videoId = track.videoId ?? track.id
            guard !videoId.isEmpty else { continue }
            try? await api.invidiousAddVideoToPlaylist(
                instanceURL: settings.invidiousInstance,
                sid: sid,
                playlistId: invId,
                videoId: videoId
            )
        }
        return invId
    }

    // MARK: - Private

    private func invidiousInstances(settings: FireballSettings) async -> [String] {
        let publicList = await InvidiousInstances.fetchHealthyPublicInstances()
        return InvidiousInstances.ordered(userInstance: settings.invidiousInstance, publicInstances: publicList)
    }

    private func resolveViaInvidious(track: Track, instance: String, settings: FireballSettings) async -> Track? {
        if let videoId = track.videoId,
           let stream = await resolveInvidiousAudioStream(instance: instance, videoId: videoId, settings: settings) {
            return trackWithUrl(track, url: normalizePlaybackUrl(stream, instance: instance), videoId: track.videoId)
        }

        for query in invidiousSearchQueries(track: track) {
            if let searchResult = await searchInvidious(query: query, instance: instance, sid: settings.invidiousSid),
               let first = searchResult.first,
               let firstVideoId = first.videoId,
               let stream = await resolveInvidiousAudioStream(instance: instance, videoId: firstVideoId, settings: settings) {
                return trackWithUrl(track, url: normalizePlaybackUrl(stream, instance: instance), videoId: firstVideoId)
            }
        }
        return nil
    }

    private func invidiousSearchQueries(track: Track) -> [String] {
        [
            "\(track.artist) \(track.title) official audio",
            "\(track.artist) \(track.title) topic",
            "\(track.artist) - \(track.title)",
            "\(track.title) \(track.artist)",
        ]
    }

    private func trackWithUrl(_ track: Track, url: String, videoId: String?) -> Track {
        Track(
            id: videoId ?? track.id,
            videoId: videoId ?? track.videoId,
            title: track.title,
            artist: track.artist,
            artwork: track.artwork,
            url: url,
            duration: track.duration,
            album: track.album,
            year: track.year
        )
    }

    private func normalizePlaybackUrl(_ url: String, instance: String) -> String {
        let base = instance.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if url.hasPrefix(base) { return url }
        return proxyStreamUrl(url, instance: instance)
    }

    private func searchITunes(query: String) async -> [Track]? {
        guard let data = try? await api.iTunesSearch(term: query),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["results"] as? [[String: Any]]
        else { return nil }

        return items.compactMap { item in
            guard let id = item["trackId"] as? Int else { return nil }
            let rawArt = item["artworkUrl100"] as? String
            let artwork = rawArt?.replacingOccurrences(of: "100x100", with: "600x600")
            return Track(
                id: String(id),
                videoId: nil,
                title: item["trackName"] as? String ?? "Unknown",
                artist: item["artistName"] as? String ?? "Unknown",
                artwork: artwork,
                url: nil,
                duration: nil,
                album: item["collectionName"] as? String,
                year: (item["releaseDate"] as? String).map { String($0.prefix(4)) }
            )
        }
    }

    private func searchInvidious(query: String, instance: String, sid: String? = nil) async -> [Track]? {
        guard let data = try? await api.invidiousSearch(instanceURL: instance, query: query, sid: sid),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        return items.compactMap { item in
            guard let videoId = item["videoId"] as? String else { return nil }
            return Track(
                id: videoId,
                videoId: videoId,
                title: item["title"] as? String ?? "Unknown",
                artist: item["author"] as? String ?? "Unknown",
                artwork: ((item["videoThumbnails"] as? [[String: Any]])?.first?["url"] as? String),
                url: nil,
                duration: nil,
                album: nil,
                year: nil
            )
        }
    }

    private func resolveInvidiousAudioStream(instance: String, videoId: String, settings: FireballSettings) async -> String? {
        guard let data = try? await api.invidiousVideo(instanceURL: instance, videoId: videoId, sid: settings.invidiousSid),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let adaptive = root["adaptiveFormats"] as? [[String: Any]]
        if let url = pickUrlFromAdaptive(adaptive, highQuality: settings.highQuality) { return url }

        let formats = root["formatStreams"] as? [[String: Any]]
        if let url = pickUrlFromFormatStreams(formats, highQuality: settings.highQuality) { return url }

        if let hls = root["hlsUrl"] as? String, !hls.isEmpty { return hls }

        return nil
    }

    private func pickUrlFromAdaptive(_ formats: [[String: Any]]?, highQuality: Bool) -> String? {
        guard let formats, !formats.isEmpty else { return nil }
        let audioOnly = formats.filter { ($0["type"] as? String)?.hasPrefix("audio/") == true }
        let bucket = audioOnly.isEmpty ? formats : audioOnly
        let sorted = bucket.sorted { bitrate($0) > bitrate($1) }
        guard let best = highQuality ? sorted.first : sorted.last else { return nil }
        return (best["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func pickUrlFromFormatStreams(_ formats: [[String: Any]]?, highQuality: Bool) -> String? {
        guard let formats, !formats.isEmpty else { return nil }
        let withUrl = formats.filter { ($0["url"] as? String).map { !$0.isEmpty } == true }
        guard !withUrl.isEmpty else { return nil }
        let audioPreferred = withUrl.filter {
            let t = ($0["type"] as? String) ?? ""
            return t.hasPrefix("audio/") || t.localizedCaseInsensitiveContains("audio")
        }
        let bucket = audioPreferred.isEmpty ? withUrl : audioPreferred
        let sorted = bucket.sorted { bitrate($0) > bitrate($1) }
        guard let best = highQuality ? sorted.first : sorted.last else { return nil }
        return (best["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func bitrate(_ format: [String: Any]) -> Int64 {
        if let b = format["bitrate"] as? Int64 { return b }
        if let s = format["bitrate"] as? String { return Int64(s) ?? 0 }
        if let i = format["bitrate"] as? Int { return Int64(i) }
        return 0
    }

    private func isItunesPreviewUrl(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("itunes.apple.com")
            || u.contains("audio-ssl.itunes.apple.com")
            || u.contains("audio.itunes.apple.com")
            || (u.contains("apple.com") && (u.contains(".m4a") || u.contains("/preview")))
    }

    /// Proxies `googlevideo.com` stream URLs through Invidious (same idea as Android).
    private func proxyStreamUrl(_ url: String, instance: String) -> String {
        guard !instance.isEmpty else { return url }
        guard let u = URL(string: url), let host = u.host, host.contains("googlevideo.com") else { return url }
        let base = instance.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hostParam = "host=\(host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host)"
        let existing = u.query ?? ""
        if existing.contains("host=") {
            return url
        }
        let query: String
        if existing.isEmpty {
            query = hostParam
        } else {
            query = "\(existing)&\(hostParam)"
        }
        return "\(base)/videoplayback?\(query)"
    }

    private func resolveLocalDownloadedMatches(normalizedQuery: String, settings: FireballSettings) -> [Track] {
        let library = loadLibrary()
        let merged = Array(Set(library.history + library.favorites + library.playlists.flatMap(\.videos)))
        return merged.compactMap { track in
            let match = track.title.lowercased().contains(normalizedQuery) ||
                track.artist.lowercased().contains(normalizedQuery)
            guard match, let local = resolveDownloadedPath(for: track, settings: settings) else { return nil }
            return Track(
                id: track.id,
                videoId: track.videoId,
                title: track.title,
                artist: track.artist,
                artwork: track.artwork,
                url: local,
                duration: track.duration,
                album: track.album,
                year: track.year
            )
        }
    }

    private func resolveDownloadedPath(for track: Track, settings: FireballSettings) -> String? {
        guard let base = settings.customDownloadPath, !base.isEmpty else { return nil }
        let baseUrl = URL(fileURLWithPath: base, isDirectory: true)
        let candidates = [
            "\(track.effectiveId).m4a",
            "\(track.effectiveId).mp3",
            "\(track.id).m4a",
            "\(track.id).mp3",
            "\(track.title).m4a",
            "\(track.title).mp3",
        ]
        for candidate in candidates {
            let file = baseUrl.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: file.path) {
                return file.absoluteString
            }
        }
        return nil
    }

    private static func millisToSeconds(_ value: Any?) -> Int? {
        switch value {
        case let ms as Int64 where ms > 0: return Int(ms / 1000)
        case let ms as Int where ms > 0: return ms / 1000
        case let ms as Double where ms > 0: return Int(ms / 1000)
        case let s as String where !s.isEmpty:
            guard let iv = Int64(s), iv > 0 else { return nil }
            return Int(iv / 1000)
        default: return nil
        }
    }

    private static func jsonObjectToCatalogTrack(_ e: [String: Any]) -> Track? {
        guard let sid = stringValue(e["trackId"]), !sid.isEmpty else { return nil }
        let rawArt = e["artworkUrl100"] as? String
        let artwork = rawArt?.replacingOccurrences(of: "100x100", with: "600x600")
        let duration = millisToSeconds(e["trackTimeMillis"])
        return Track(
            id: sid,
            videoId: nil,
            title: e["trackName"] as? String ?? "Unknown",
            artist: e["artistName"] as? String ?? "Unknown",
            artwork: artwork,
            url: nil,
            duration: duration,
            album: e["collectionName"] as? String,
            year: (e["releaseDate"] as? String).map { String($0.prefix(4)) },
        )
    }

    private static func jsonCollectionToAlbum(_ e: [String: Any]) -> Album? {
        guard let cid = stringValue(e["collectionId"]), !cid.isEmpty else { return nil }
        let yr = (e["releaseDate"] as? String).flatMap { Int(String($0.prefix(4))) }
        let rawArt = e["artworkUrl100"] as? String
        let art = rawArt?.replacingOccurrences(of: "100x100", with: "600x600")
        return Album(
            id: cid,
            title: e["collectionName"] as? String ?? "Album",
            artist: e["artistName"] as? String ?? "",
            artwork: art,
            year: yr,
            tracks: nil,
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String where !s.isEmpty: return s
        case let n as Int: return "\(n)"
        case let n as Int64: return "\(n)"
        case let n as Double: return "\(Int(n))"
        default: return nil
        }
    }

    private func searchCacheLimit(_ settings: FireballSettings) -> Int {
        if settings.searchCacheMaxEntries > 0 {
            return min(500, max(10, settings.searchCacheMaxEntries))
        }
        return min(200, max(10, settings.localMusicCacheLimit * 10))
    }

    private func cache(query: String, tracks: [Track], settings: FireballSettings) {
        guard settings.cacheEnabled, !query.isEmpty, !tracks.isEmpty else { return }
        searchCache[query] = tracks
        let limit = searchCacheLimit(settings)
        if searchCache.count > limit, let first = searchCache.keys.first {
            searchCache.removeValue(forKey: first)
        }
    }
}

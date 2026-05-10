import Foundation

@MainActor
final class FireballRepository {
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

    func searchTracks(query: String, settings: FireballSettings) async -> [Track] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let downloaded = resolveLocalDownloadedMatches(normalizedQuery: normalizedQuery, settings: settings)
        if !downloaded.isEmpty { return downloaded }
        if let cached = searchCache[normalizedQuery] { return cached }

        if let iTunesTracks = await searchITunes(query: query), !iTunesTracks.isEmpty {
            cache(query: normalizedQuery, tracks: iTunesTracks)
            return iTunesTracks
        }

        guard !settings.invidiousInstance.isEmpty else { return [] }
        if let invidious = await searchInvidious(query: query, instance: settings.invidiousInstance, sid: settings.invidiousSid), !invidious.isEmpty {
            cache(query: normalizedQuery, tracks: invidious)
            return invidious
        }

        if settings.fallbackToPiped && !settings.pipedInstance.isEmpty {
            if let piped = await searchPiped(query: query, instance: settings.pipedInstance), !piped.isEmpty {
                cache(query: normalizedQuery, tracks: piped)
                return piped
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

    private func searchITunes(query: String) async -> [Track]? {
        guard let data = try? await api.iTunesSearch(term: query),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["results"] as? [[String: Any]]
        else { return nil }

        return items.compactMap { item in
            guard let id = item["trackId"] as? Int else { return nil }
            return Track(
                id: String(id),
                videoId: nil,
                title: item["trackName"] as? String ?? "Unknown",
                artist: item["artistName"] as? String ?? "Unknown",
                artwork: item["artworkUrl100"] as? String,
                url: item["previewUrl"] as? String,
                duration: nil,
                album: item["collectionName"] as? String,
                year: (item["releaseDate"] as? String)?.prefix(4).description
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

    private func resolvePlayableTrack(_ track: Track, settings: FireballSettings) async -> Track {
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

        if let url = track.url, !url.isEmpty { return track }
        guard !settings.invidiousInstance.isEmpty else { return track }

        if let videoId = track.videoId,
           let stream = await resolveInvidiousStream(instance: settings.invidiousInstance, videoId: videoId, sid: settings.invidiousSid) {
            return Track(
                id: track.id,
                videoId: track.videoId,
                title: track.title,
                artist: track.artist,
                artwork: track.artwork,
                url: stream,
                duration: track.duration,
                album: track.album,
                year: track.year
            )
        }

        if let searchResult = await searchInvidious(query: "\(track.title) \(track.artist)", instance: settings.invidiousInstance, sid: settings.invidiousSid),
           let first = searchResult.first,
           let firstVideoId = first.videoId,
           let stream = await resolveInvidiousStream(instance: settings.invidiousInstance, videoId: firstVideoId, sid: settings.invidiousSid) {
            return Track(
                id: firstVideoId,
                videoId: firstVideoId,
                title: track.title,
                artist: track.artist,
                artwork: track.artwork,
                url: stream,
                duration: track.duration,
                album: track.album,
                year: track.year
            )
        }

        if settings.fallbackToPiped && !settings.pipedInstance.isEmpty {
            if let videoId = track.videoId,
               let stream = await resolvePipedStream(instance: settings.pipedInstance, videoId: videoId) {
                return Track(
                    id: track.id,
                    videoId: track.videoId,
                    title: track.title,
                    artist: track.artist,
                    artwork: track.artwork,
                    url: stream,
                    duration: track.duration,
                    album: track.album,
                    year: track.year
                )
            }

            if let searchResult = await searchPiped(query: "\(track.title) \(track.artist)", instance: settings.pipedInstance),
               let first = searchResult.first,
               let firstVideoId = first.videoId,
               let stream = await resolvePipedStream(instance: settings.pipedInstance, videoId: firstVideoId) {
                return Track(
                    id: firstVideoId,
                    videoId: firstVideoId,
                    title: track.title,
                    artist: track.artist,
                    artwork: track.artwork,
                    url: stream,
                    duration: track.duration,
                    album: track.album,
                    year: track.year
                )
            }
        }

        return track
    }

    private func resolveInvidiousStream(instance: String, videoId: String, sid: String?) async -> String? {
        guard let data = try? await api.invidiousVideo(instanceURL: instance, videoId: videoId, sid: sid),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let adaptive = root["adaptiveFormats"] as? [[String: Any]]
        if let url = adaptive?.first?["url"] as? String, !url.isEmpty {
            return url
        }
        let formats = root["formatStreams"] as? [[String: Any]]
        if let url = formats?.first?["url"] as? String, !url.isEmpty {
            return url
        }
        return nil
    }

    private func searchPiped(query: String, instance: String) async -> [Track]? {
        guard let data = try? await api.pipedSearch(instanceURL: instance, query: query),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else { return nil }

        return items.compactMap { item in
            guard let url = item["url"] as? String,
                  url.contains("/watch?v="),
                  let id = url.components(separatedBy: "/watch?v=").last else { return nil }
            return Track(
                id: id,
                videoId: id,
                title: item["title"] as? String ?? "Unknown",
                artist: item["uploaderName"] as? String ?? "Unknown",
                artwork: item["thumbnail"] as? String,
                url: nil,
                duration: nil,
                album: nil,
                year: nil
            )
        }
    }

    private func resolvePipedStream(instance: String, videoId: String) async -> String? {
        guard let data = try? await api.pipedStream(instanceURL: instance, videoId: videoId),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let streams = root["audioStreams"] as? [[String: Any]]
        if let url = streams?.first?["url"] as? String, !url.isEmpty {
            return url
        }
        return nil
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

    private func cache(query: String, tracks: [Track]) {
        guard !query.isEmpty else { return }
        searchCache[query] = tracks
        if searchCache.count > 50, let first = searchCache.keys.first {
            searchCache.removeValue(forKey: first)
        }
    }
}

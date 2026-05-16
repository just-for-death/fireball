package com.fireball.nativeapp.data

import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.data.InvidiousInstanceProvider
import com.fireball.nativeapp.core.data.ItunesFeedParser
import com.fireball.nativeapp.core.data.LibraryStore
import com.fireball.nativeapp.core.data.YoutubeDirectStreamResolver
import com.fireball.nativeapp.core.model.Album
import com.fireball.nativeapp.core.model.Artist
import com.fireball.nativeapp.core.model.ArtistReleaseProbe
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import android.net.Uri
import androidx.core.net.toUri

data class ArtistBrowseResult(
    val artistAppleId: Int,
    val displayName: String,
    val artworkUrl: String?,
    val songs: List<Track>,
    val albums: List<Album>,
    val playlistsContainingArtist: List<Playlist>,
)

class FireballRepository(
    private val api: FireballApiClient,
    private val store: LibraryStore
) {
    private companion object {
        private const val SEARCH_CACHE_PREFIX = "v5:"
    }

    private val searchCache = linkedMapOf<String, List<Track>>()

    suspend fun loadLibrary(): LibrarySnapshot = withContext(Dispatchers.IO) {
        store.load()
    }

    suspend fun saveLibrary(snapshot: LibrarySnapshot) = withContext(Dispatchers.IO) {
        store.save(snapshot)
    }

    suspend fun resolveArtistForFollow(artistName: String, fallbackArtwork: String? = null): Artist =
        withContext(Dispatchers.IO) {
            var artistId = artistName
            var name = artistName
            var artwork = fallbackArtwork
            val found = runCatching { api.itunesFindArtist(artistName) }.getOrNull()
            if (found != null) {
                artistId = found["artistId"]?.jsonPrimitive?.content ?: artistName
                name = found["artistName"]?.jsonPrimitive?.content ?: artistName
                if (artwork.isNullOrBlank()) {
                    val idNum = artistId.toIntOrNull()
                    if (idNum != null) {
                        val albums = api.itunesArtistAlbums(idNum, limit = 1)
                        artwork = albums.firstOrNull()
                            ?.get("artworkUrl100")?.jsonPrimitive?.content
                            ?.replace("100x100", "600x600")
                    }
                }
            }
            Artist(artistId = artistId, name = name, artwork = artwork)
        }

    suspend fun fetchTopSongs(countryCode: String, limit: Int = 20): List<Track> = withContext(Dispatchers.IO) {
        if (countryCode.isBlank()) return@withContext emptyList()
        runCatching {
            val feed = api.itunesTopSongs(countryCode, limit)
            ItunesFeedParser.topChartsFromFeed(ItunesFeedParser.feedEntries(feed)).map { entry ->
                Track(
                    id = entry.id,
                    title = entry.title,
                    artist = entry.artist,
                    artwork = entry.artwork,
                    /** No iTunes preview — full tracks resolve via Invidious / on-device YouTube. */
                    url = null,
                )
            }
        }.getOrDefault(emptyList())
    }

    /**
     * Polls followed artists for new iTunes albums. Updates baseline [Artist.latestReleaseId].
     * [onGotifyNotify] fires when Gotify credentials are configured; [onDeviceNotify] when
     * [FireballSettings.notifyArtistReleasesOnDevice] is on. Both may run for the same release.
     */
    suspend fun checkFollowedArtistNewReleases(
        snapshot: LibrarySnapshot,
        onGotifyNotify: (suspend (String, String) -> Boolean)?,
        onDeviceNotify: (suspend (String, String) -> Unit)?,
    ): LibrarySnapshot? = withContext(Dispatchers.IO) {
        val settings = snapshot.settings
        val wantGotify =
            settings.gotifyEnabled &&
                settings.gotifyUrl.isNotBlank() &&
                settings.gotifyToken.isNotBlank() &&
                onGotifyNotify != null
        val wantDevice = settings.notifyArtistReleasesOnDevice && onDeviceNotify != null
        if (!wantGotify && !wantDevice) return@withContext null

        var artistsChanged = false
        val updated = snapshot.artists.map { artist ->
            var lookupId: Int? = null
            if (artist.artistId.toIntOrNull() == null) {
                lookupId =
                    runCatching { api.itunesFindArtist(artist.name) }.getOrNull()
                        ?.get("artistId")?.jsonPrimitive?.content?.toIntOrNull()
            }
            val artistIdNum =
                ArtistReleaseProbe.resolveNumericItunesArtistId(
                    storedArtistId = artist.artistId,
                    artistName = artist.name,
                ) { lookupId } ?: return@map artist

            val albums = runCatching { api.itunesArtistAlbums(artistIdNum, limit = 1) }.getOrDefault(emptyList())
            val latest = albums.firstOrNull()
            val hit =
                latest?.let { row ->
                    val id = row["collectionId"]?.jsonPrimitive?.content ?: return@let null
                    val name = row["collectionName"]?.jsonPrimitive?.content ?: "New Release"
                    ArtistReleaseProbe.AlbumHit(id, name)
                }
            val eval =
                ArtistReleaseProbe.evaluateNewRelease(
                    artist = artist,
                    resolvedArtistId = artistIdNum.toString(),
                    latestAlbum = hit,
                )
            when (eval.outcome) {
                ArtistReleaseProbe.ReleaseOutcome.Unchanged -> eval.artist
                ArtistReleaseProbe.ReleaseOutcome.BaselineStored -> {
                    artistsChanged = true
                    eval.artist
                }
                ArtistReleaseProbe.ReleaseOutcome.NotifyNewRelease -> {
                    val albumName = hit?.collectionName ?: "New Release"
                    val (title, message) = ArtistReleaseProbe.notificationCopy(eval.artist.name, albumName)
                    if (wantGotify) {
                        runCatching { onGotifyNotify!!(title, message) }
                    }
                    if (wantDevice) {
                        runCatching { onDeviceNotify!!(title, message) }
                    }
                    artistsChanged = true
                    eval.artist
                }
            }
        }

        if (!artistsChanged) null else snapshot.copy(artists = updated)
    }

    suspend fun searchAlbumsCatalog(query: String, settings: FireballSettings): List<Album> {
        if (query.isBlank() || settings.offlineModeEnabled) return emptyList()
        return withContext(Dispatchers.IO) {
            runCatching {
                val root = api.itunesSearchAlbums(query)
                val items = root["results"]?.jsonArray ?: return@runCatching emptyList()
                items.mapNotNull { jsonCollectionToAlbum(it.jsonObject) }
            }.getOrDefault(emptyList())
        }
    }

    suspend fun catalogAlbumTracks(collectionId: Int): List<Track> = withContext(Dispatchers.IO) {
        runCatching {
            api.itunesAlbumTracks(collectionId).mapNotNull { jsonObjectToCatalogTrack(it) }
        }.getOrDefault(emptyList())
    }

    suspend fun browseArtist(library: LibrarySnapshot, artistAppleId: Int?, artistName: String?): ArtistBrowseResult? =
        withContext(Dispatchers.IO) {
            val resolvedId =
                artistAppleId ?: run {
                    val guess = artistName?.trim().orEmpty()
                    if (guess.isEmpty()) return@withContext null
                    val row = api.itunesFindArtist(guess) ?: return@withContext null
                    row["artistId"]?.jsonPrimitive?.content?.toIntOrNull() ?: return@withContext null
                }
            val meta = api.itunesArtistDetail(resolvedId)
            val displayName =
                meta?.get("artistName")?.jsonPrimitive?.content?.trim()?.takeIf { it.isNotBlank() }
                    ?: artistName?.trim().orEmpty().ifBlank { "Artist" }
            var artwork =
                meta?.get("artworkUrl100")?.jsonPrimitive?.content
                    ?.replace("100x100", "600x600")
            val songs =
                api.itunesArtistSongs(resolvedId, limit = 60).mapNotNull { jsonObjectToCatalogTrack(it) }
            val albumRows =
                api.itunesArtistAlbums(resolvedId, limit = 80)
            val albums = albumRows.mapNotNull { jsonCollectionToAlbum(it) }.distinctBy { it.id }
            if (artwork.isNullOrBlank()) {
                artwork =
                    albumRows.firstOrNull()
                        ?.get("artworkUrl100")?.jsonPrimitive?.content
                        ?.replace("100x100", "600x600")
            }
            val needle = displayName.lowercase()
            val playlists =
                library.playlists.filter { pl ->
                    pl.videos.any {
                        val a = it.artist.lowercase()
                        a == needle || a.contains(needle) || needle.contains(a)
                    }
                }
            ArtistBrowseResult(
                artistAppleId = resolvedId,
                displayName = displayName,
                artworkUrl = artwork,
                songs = songs,
                albums = albums,
                playlistsContainingArtist = playlists,
            )
        }

    suspend fun searchTracks(query: String, settings: FireballSettings): List<Track> {
        if (query.isBlank()) return emptyList()
        val normalizedQuery = query.trim().lowercase()
        val cacheKey = "$SEARCH_CACHE_PREFIX$normalizedQuery"

        val localMatches = resolveLocalDownloadedMatches(normalizedQuery, settings)
        if (localMatches.isNotEmpty()) {
            cacheSearch(cacheKey, localMatches, settings)
            return localMatches
        }

        if (settings.offlineModeEnabled) {
            return emptyList()
        }

        if (settings.cacheEnabled) {
            searchCache[cacheKey]?.takeIf { it.isNotEmpty() }?.let { return it }
        }

        val itunesResult = runCatching {
            api.itunesSearch(query).let { root ->
                val items = root["results"]?.jsonArray ?: return@let emptyList()
                items.mapNotNull { entry ->
                    val e = entry.jsonObject
                    val id = e["trackId"]?.jsonPrimitive?.content ?: return@mapNotNull null
                    Track(
                        id = id,
                        title = e["trackName"]?.jsonPrimitive?.content ?: "Unknown",
                        artist = e["artistName"]?.jsonPrimitive?.content ?: "Unknown",
                        artwork = e["artworkUrl100"]?.jsonPrimitive?.content
                            ?.replace("100x100", "600x600"),
                        url = null,
                        album = e["collectionName"]?.jsonPrimitive?.content,
                        year = e["releaseDate"]?.jsonPrimitive?.content?.take(4)
                    )
                }
            }
        }.getOrDefault(emptyList())

        if (itunesResult.isNotEmpty()) {
            cacheSearch(cacheKey, itunesResult, settings)
            return itunesResult
        }

        for (instance in invidiousInstances(settings)) {
            val invidiousResult = invidiousSearchOnInstance(instance, query, settings)
            if (invidiousResult.isNotEmpty()) {
                cacheSearch(cacheKey, invidiousResult, settings)
                return invidiousResult
            }
        }

        return emptyList()
    }

    /**
     * True when playback handoff must run [resolvePlayableTrack]: missing URL, or blocked
     * Apple/iTunes sample / preview CDN (prefer Invidious then YouTube fallback).
     */
    fun needsInvidiousStreamResolution(track: Track): Boolean =
        track.url.isNullOrBlank() || isItunesPreviewUrl(track.url)

    /**
     * Resolve a playable stream URL.
     * Order: local → direct URL → Invidious (`local=true`, all mirrors, multi-query)
     * → direct YouTube (NewPipe, on-device).
     */
    suspend fun resolvePlayableTrack(track: Track, settings: FireballSettings): Track {
        resolveDownloadedPath(track, settings)?.let { return track.copy(url = it) }

        if (!track.url.isNullOrBlank() && !isItunesPreviewUrl(track.url)) {
            return track
        }

        for (instance in invidiousInstances(settings)) {
            val resolved = resolveViaInvidious(track, instance, settings)
            if (!resolved.url.isNullOrBlank()) return resolved
        }

        resolveViaYoutubeDirect(track)?.let { if (!it.url.isNullOrBlank()) return it }

        return track
    }

    private suspend fun resolveViaYoutubeDirect(track: Track): Track? {
        val videoId = track.videoId
        if (videoId != null) {
            val url = YoutubeDirectStreamResolver.resolveAudioUrl(videoId) ?: return null
            return track.copy(url = url)
        }
        val found = YoutubeDirectStreamResolver.searchAndResolveAudio(track.artist, track.title)
            ?: return null
        return track.copy(videoId = found.first, url = found.second)
    }

    private suspend fun invidiousInstances(settings: FireballSettings): List<String> =
        InvidiousInstanceProvider.instancesFor(
            settings.invidiousInstance,
            api.healthyInvidiousInstances(),
        )

    private suspend fun invidiousSearchOnInstance(
        instance: String,
        query: String,
        settings: FireballSettings
    ): List<Track> = runCatching {
        api.invidiousSearch(instance, query, settings.invidiousSid).mapNotNull { entry ->
            val e = entry.jsonObject
            val id = e["videoId"]?.jsonPrimitive?.content ?: return@mapNotNull null
            Track(
                id = id,
                videoId = id,
                title = e["title"]?.jsonPrimitive?.content ?: "Unknown",
                artist = e["author"]?.jsonPrimitive?.content ?: "Unknown",
                artwork = e["videoThumbnails"]
                    ?.jsonArray
                    ?.firstOrNull()
                    ?.jsonObject
                    ?.get("url")
                    ?.jsonPrimitive
                    ?.content
            )
        }
    }.getOrDefault(emptyList())

    private suspend fun resolveViaInvidious(
        track: Track,
        instance: String,
        settings: FireballSettings
    ): Track {
        val videoId = track.videoId
        if (videoId != null) {
            val stream = resolveInvidiousAudioStream(instance, videoId, settings)
            if (!stream.isNullOrBlank()) {
                return track.copy(url = normalizePlaybackUrl(stream, instance))
            }
        }

        val searchVideoId = findInvidiousVideoId(track, instance, settings)

        if (!searchVideoId.isNullOrBlank()) {
            val stream = resolveInvidiousAudioStream(instance, searchVideoId, settings)
            if (!stream.isNullOrBlank()) {
                return track.copy(
                    videoId = searchVideoId,
                    url = normalizePlaybackUrl(stream, instance)
                )
            }
        }
        return track
    }

    private suspend fun resolveInvidiousAudioStream(
        instance: String,
        videoId: String,
        settings: FireballSettings
    ): String? {
        return runCatching {
            val root = api.invidiousVideo(instance, videoId, settings.invidiousSid, local = true)

            fun pickUrlFromAdaptive(formats: kotlinx.serialization.json.JsonArray?): String? {
                if (formats == null || formats.isEmpty()) return null
                val audioFormats = formats.filter { format ->
                    val type = format.jsonObject["type"]?.jsonPrimitive?.content ?: ""
                    type.startsWith("audio/")
                }
                val bucket = if (audioFormats.isNotEmpty()) audioFormats else formats
                val sorted = bucket.sortedByDescending { format ->
                    format.jsonObject["bitrate"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
                }
                val best = if (settings.highQuality) sorted.first() else sorted.last()
                return best.jsonObject["url"]?.jsonPrimitive?.content
            }

            fun pickUrlFromFormatStreams(formats: kotlinx.serialization.json.JsonArray?): String? {
                if (formats == null || formats.isEmpty()) return null
                val withUrl = formats.filter {
                    !it.jsonObject["url"]?.jsonPrimitive?.content.isNullOrBlank()
                }
                if (withUrl.isEmpty()) return null
                val audioPreferred = withUrl.filter { format ->
                    val type = format.jsonObject["type"]?.jsonPrimitive?.content ?: ""
                    type.startsWith("audio/") || type.contains("audio", ignoreCase = true)
                }
                val bucket = if (audioPreferred.isNotEmpty()) audioPreferred else withUrl
                val sorted = bucket.sortedByDescending { format ->
                    format.jsonObject["bitrate"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
                }
                val best = if (settings.highQuality) sorted.first() else sorted.last()
                return best.jsonObject["url"]?.jsonPrimitive?.content
            }

            pickUrlFromAdaptive(root["adaptiveFormats"]?.jsonArray)
                ?: pickUrlFromFormatStreams(root["formatStreams"]?.jsonArray)
                ?: root["hlsUrl"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
        }.getOrNull()
    }

    private suspend fun findInvidiousVideoId(
        track: Track,
        instance: String,
        settings: FireballSettings,
    ): String? {
        for (query in invidiousSearchQueries(track)) {
            val id = runCatching {
                api.invidiousSearch(instance, query, settings.invidiousSid)
                    .firstOrNull()
                    ?.jsonObject
                    ?.get("videoId")
                    ?.jsonPrimitive
                    ?.content
            }.getOrNull()
            if (!id.isNullOrBlank()) return id
        }
        return null
    }

    private fun invidiousSearchQueries(track: Track): List<String> = listOf(
        "${track.artist} ${track.title} official audio",
        "${track.artist} ${track.title} topic",
        "${track.artist} - ${track.title}",
        "${track.title} ${track.artist}",
    )

    private fun normalizePlaybackUrl(url: String, instance: String): String {
        val base = instance.trimEnd('/')
        if (url.startsWith(base)) return url
        return proxyStreamUrl(url, instance)
    }

    private fun proxyStreamUrl(url: String, instance: String): String {
        if (instance.isBlank()) return url
        return try {
            val uri = url.toUri()
            val host = uri.host ?: return url
            if (!host.contains("googlevideo.com")) return url

            val base = instance.trimEnd('/')
            val hostParam = "host=${Uri.encode(host)}"
            val existingQuery = uri.query ?: ""
            val hasHost = existingQuery.contains("host=")
            val query = when {
                existingQuery.isEmpty() -> hostParam
                hasHost -> existingQuery
                else -> "$existingQuery&$hostParam"
            }
            "$base/videoplayback?$query"
        } catch (_: Exception) {
            url
        }
    }

    private fun isItunesPreviewUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val u = url.lowercase()
        if (u.contains("mzstatic.com")) {
            return u.contains(".m4a") ||
                u.contains(".mp4") ||
                u.contains("/preview/")
        }
        return u.contains("itunes.apple.com") ||
            u.contains("audio-ssl.itunes.apple.com") ||
            u.contains("audio.itunes.apple.com") ||
            (u.contains("music.apple.com") && (u.contains("/preview") || u.contains(".m4a"))) ||
            (u.contains("apple.com") && (u.contains(".m4a") || u.contains("/preview")))
    }

    private suspend fun resolveLocalDownloadedMatches(
        normalizedQuery: String,
        settings: FireballSettings
    ): List<Track> {
        val library = loadLibrary()
        val allLocal = (library.history + library.favorites + library.playlists.flatMap { it.videos })
            .distinctBy { it.effectiveId }
        return allLocal.mapNotNull { track ->
            val matches = track.title.lowercase().contains(normalizedQuery) ||
                track.artist.lowercase().contains(normalizedQuery)
            if (!matches) return@mapNotNull null
            val localPath = resolveDownloadedPath(track, settings) ?: return@mapNotNull null
            track.copy(url = localPath)
        }
    }

    private fun resolveDownloadedPath(track: Track, settings: FireballSettings): String? {
        val basePath = settings.customDownloadPath ?: return null
        val dir = File(basePath)
        if (!dir.exists() || !dir.isDirectory) return null

        val candidates = listOf(
            "${track.effectiveId}.m4a",
            "${track.effectiveId}.mp3",
            "${track.id}.m4a",
            "${track.id}.mp3",
            "${track.title}.m4a",
            "${track.title}.mp3"
        )
        for (candidate in candidates) {
            val f = File(dir, candidate)
            if (f.exists() && f.isFile) return f.toURI().toString()
        }
        return null
    }

    private fun searchCacheLimit(settings: FireballSettings): Int {
        val explicit = settings.searchCacheMaxEntries
        if (explicit > 0) return explicit.coerceIn(10, 500)
        return settings.localMusicCacheLimit.coerceIn(1, 20) * 10
    }

    private fun jsonObjectToCatalogTrack(e: kotlinx.serialization.json.JsonObject): Track? {
        val id = e["trackId"]?.jsonPrimitive?.content ?: return null
        return Track(
            id = id,
            videoId = null,
            title = e["trackName"]?.jsonPrimitive?.content ?: "Unknown",
            artist = e["artistName"]?.jsonPrimitive?.content ?: "Unknown",
            artwork = e["artworkUrl100"]?.jsonPrimitive?.content
                ?.replace("100x100", "600x600"),
            url = null,
            duration =
                e["trackTimeMillis"]?.jsonPrimitive?.content?.toLongOrNull()
                    ?.div(1000L)?.toInt(),
            album = e["collectionName"]?.jsonPrimitive?.content,
            year = e["releaseDate"]?.jsonPrimitive?.content?.take(4),
        )
    }

    private fun jsonCollectionToAlbum(e: kotlinx.serialization.json.JsonObject): Album? {
        val cid = e["collectionId"]?.jsonPrimitive?.content ?: return null
        val year = e["releaseDate"]?.jsonPrimitive?.content?.take(4)?.toIntOrNull()
        return Album(
            id = cid,
            title = e["collectionName"]?.jsonPrimitive?.content ?: "Album",
            artist = e["artistName"]?.jsonPrimitive?.content ?: "",
            artwork =
                e["artworkUrl100"]?.jsonPrimitive?.content?.replace(
                    "100x100",
                    "600x600",
                ),
            year = year,
            tracks = null,
        )
    }

    private fun cacheSearch(key: String, tracks: List<Track>, settings: FireballSettings) {
        if (!settings.cacheEnabled || key.isBlank() || tracks.isEmpty()) return
        searchCache[key] = tracks
        val limit = searchCacheLimit(settings)
        if (searchCache.size > limit) {
            val firstKey = searchCache.keys.firstOrNull()
            if (firstKey != null) searchCache.remove(firstKey)
        }
    }
}

package com.fireball.nativeapp.data

import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.data.InvidiousInstanceProvider
import com.fireball.nativeapp.core.data.LibraryStore
import com.fireball.nativeapp.core.data.YoutubeDirectStreamResolver
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import com.fireball.nativeapp.core.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import android.net.Uri

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
            val uri = Uri.parse(url)
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
        return url.contains("apple.com") || url.contains("itunes") || url.contains("mzstatic.com")
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

    private fun cacheSearch(key: String, tracks: List<Track>, settings: FireballSettings) {
        if (!settings.cacheEnabled || key.isBlank() || tracks.isEmpty()) return
        searchCache[key] = tracks
        val limit = settings.localMusicCacheLimit.coerceIn(1, 20) * 10
        if (searchCache.size > limit) {
            val firstKey = searchCache.keys.firstOrNull()
            if (firstKey != null) searchCache.remove(firstKey)
        }
    }
}

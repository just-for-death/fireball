package com.fireball.nativeapp.data

import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.data.InvidiousInstanceProvider
import com.fireball.nativeapp.core.data.LibraryStore
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
        private const val SEARCH_CACHE_PREFIX = "v3:"

        /** Optional last resort when Invidious mirrors are all down. */
        private val PUBLIC_PIPED_INSTANCES = listOf(
            "https://pipedapi.kavin.rocks",
            "https://pipedapi.in.projectsegfau.lt",
        )
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

        searchCache[cacheKey]?.takeIf { it.isNotEmpty() }?.let { return it }

        val localMatches = resolveLocalDownloadedMatches(normalizedQuery, settings)
        if (localMatches.isNotEmpty()) {
            cacheSearch(cacheKey, localMatches)
            return localMatches
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
            cacheSearch(cacheKey, itunesResult)
            return itunesResult
        }

        for (instance in invidiousInstances(settings)) {
            val invidiousResult = invidiousSearchOnInstance(instance, query, settings)
            if (invidiousResult.isNotEmpty()) {
                cacheSearch(cacheKey, invidiousResult)
                return invidiousResult
            }
        }

        if (settings.fallbackToPiped) {
            for (pipedInstance in pipedInstances(settings)) {
                val pipedResult = pipedSearchOnInstance(pipedInstance, query)
                if (pipedResult.isNotEmpty()) {
                    cacheSearch(cacheKey, pipedResult)
                    return pipedResult
                }
            }
        }

        return emptyList()
    }

    /**
     * Resolve a playable stream URL.
     * Order: local file → direct URL → Invidious (user + auto public mirrors, `local=true`) → Piped (optional).
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

        if (settings.fallbackToPiped) {
            for (pipedInstance in pipedInstances(settings)) {
                val resolved = resolveViaPiped(track, pipedInstance)
                if (!resolved.url.isNullOrBlank()) return resolved
            }
        }

        return track
    }

    private suspend fun invidiousInstances(settings: FireballSettings): List<String> =
        InvidiousInstanceProvider.instancesFor(
            settings.invidiousInstance,
            api.healthyInvidiousInstances(),
        )

    private fun pipedInstances(settings: FireballSettings): List<String> = buildList {
        settings.pipedInstance.trim().takeIf { it.isNotBlank() }?.let { add(it) }
        addAll(PUBLIC_PIPED_INSTANCES)
    }.distinct()

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

    private suspend fun pipedSearchOnInstance(instance: String, query: String): List<Track> =
        runCatching {
            api.pipedSearch(instance, query).mapNotNull { entry ->
                val e = entry.jsonObject
                val url = e["url"]?.jsonPrimitive?.content ?: return@mapNotNull null
                val id = url.substringAfter("/watch?v=").takeIf { it != url } ?: return@mapNotNull null
                Track(
                    id = id,
                    videoId = id,
                    title = e["title"]?.jsonPrimitive?.content ?: "Unknown",
                    artist = e["uploaderName"]?.jsonPrimitive?.content ?: "Unknown",
                    artwork = e["thumbnail"]?.jsonPrimitive?.content
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

        val searchVideoId = runCatching {
            api.invidiousSearch(
                instance,
                "${track.artist} ${track.title} official audio",
                settings.invidiousSid
            )
                .firstOrNull()
                ?.jsonObject
                ?.get("videoId")
                ?.jsonPrimitive
                ?.content
        }.getOrNull()

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

    private suspend fun resolveViaPiped(track: Track, pipedInstance: String): Track {
        val pipedVideoId = track.videoId
        if (pipedVideoId != null) {
            val stream = resolvePipedAudioStream(pipedInstance, pipedVideoId)
            if (!stream.isNullOrBlank()) return track.copy(url = stream)
        }

        val searchVideoId = runCatching {
            api.pipedSearch(pipedInstance, "${track.title} ${track.artist}")
                .firstOrNull()
                ?.jsonObject
                ?.get("url")
                ?.jsonPrimitive
                ?.content
                ?.substringAfter("/watch?v=")
        }.getOrNull()

        if (!searchVideoId.isNullOrBlank()) {
            val stream = resolvePipedAudioStream(pipedInstance, searchVideoId)
            if (!stream.isNullOrBlank()) {
                return track.copy(videoId = searchVideoId, url = stream)
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
        }.getOrNull()
    }

    private suspend fun resolvePipedAudioStream(instance: String, videoId: String): String? {
        return runCatching {
            val root = api.pipedStream(instance, videoId)
            val streams = root["audioStreams"]?.jsonArray ?: return@runCatching null
            val best = streams.maxByOrNull { stream ->
                stream.jsonObject["bitrate"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
            }
            best?.jsonObject?.get("url")?.jsonPrimitive?.content
        }.getOrNull()
    }

    /** Prefer Invidious-proxied URLs from `local=true`; only re-proxy raw googlevideo links. */
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

    private fun cacheSearch(key: String, tracks: List<Track>) {
        if (key.isBlank() || tracks.isEmpty()) return
        searchCache[key] = tracks
        if (searchCache.size > 50) {
            val firstKey = searchCache.keys.firstOrNull()
            if (firstKey != null) searchCache.remove(firstKey)
        }
    }
}

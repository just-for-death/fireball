package com.fireball.nativeapp.data

import com.fireball.nativeapp.core.data.FireballApiClient
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

        // 1) downloaded/local resolution first
        val downloadedLocal = resolveLocalDownloadedMatches(normalizedQuery, settings)
        if (downloadedLocal.isNotEmpty()) return downloadedLocal

        // 2) in-memory cache
        searchCache[normalizedQuery]?.let { return it }

        // 3) direct URL sources (iTunes)
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
                        // Do NOT store previewUrl as the playable URL — it's a 30-sec preview.
                        // The URL is resolved at play-time via Invidious/Piped.
                        url = null,
                        album = e["collectionName"]?.jsonPrimitive?.content,
                        year = e["releaseDate"]?.jsonPrimitive?.content?.take(4)
                    )
                }
            }
        }.getOrDefault(emptyList())

        if (itunesResult.isNotEmpty()) {
            cacheSearch(normalizedQuery, itunesResult)
            return itunesResult
        }
        if (settings.invidiousInstance.isBlank()) return emptyList()

        // 4) invidious resolution/search fallback
        val invidiousResult = runCatching {
            api.invidiousSearch(settings.invidiousInstance, query).mapNotNull { entry ->
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

        if (invidiousResult.isNotEmpty()) {
            cacheSearch(normalizedQuery, invidiousResult)
            return invidiousResult
        }

        if (settings.fallbackToPiped && settings.pipedInstance.isNotBlank()) {
            val pipedResult = runCatching {
                api.pipedSearch(settings.pipedInstance, query).mapNotNull { entry ->
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

            cacheSearch(normalizedQuery, pipedResult)
            return pipedResult
        }

        return emptyList()
    }

    /**
     * Resolve a single track to a playable stream URL.
     * Matches Flutter Fireball logic exactly:
     *   1. Check local downloads
     *   2. If URL is already a non-iTunes URL, use it
     *   3. If videoId exists, fetch Invidious adaptiveFormats -> find best audio stream
     *   4. If no videoId, search Invidious for "{artist} {title}" -> resolve stream
     *   5. Fallback to Piped API
     *   6. Proxy googlevideo.com CDN URLs through Invidious to avoid 403s
     */
    suspend fun resolvePlayableTrack(track: Track, settings: FireballSettings): Track {
        // downloaded -> cache/local
        resolveDownloadedPath(track, settings)?.let { return track.copy(url = it) }

        // direct URL already available (but NOT an iTunes preview)
        if (!track.url.isNullOrBlank() && !isItunesPreviewUrl(track.url)) {
            return track
        }

        val instance = settings.invidiousInstance

        // invidious resolution
        if (instance.isNotBlank()) {
            // 1) Direct resolution by videoId
            val videoId = track.videoId
            if (videoId != null) {
                val stream = resolveInvidiousAudioStream(instance, videoId, settings)
                if (!stream.isNullOrBlank()) {
                    return track.copy(url = proxyStreamUrl(stream, instance))
                }
            }

            // 2) Search Invidious for the track, then resolve audio
            val searchVideoId = runCatching {
                api.invidiousSearch(instance, "${track.artist} ${track.title} official audio")
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
                        url = proxyStreamUrl(stream, instance)
                    )
                }
            }
        }

        // Piped fallback
        if (settings.fallbackToPiped && settings.pipedInstance.isNotBlank()) {
            val pipedInstance = settings.pipedInstance

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
        }

        return track
    }

    /**
     * Fetches Invidious video details and extracts the best audio-only stream URL.
     * Matches Flutter logic: filters for audio mime type, sorts by bitrate
     * based on quality preference.
     */
    private suspend fun resolveInvidiousAudioStream(
        instance: String,
        videoId: String,
        settings: FireballSettings
    ): String? {
        return runCatching {
            val root = api.invidiousVideo(instance, videoId)
            val formats = root["adaptiveFormats"]?.jsonArray ?: return@runCatching null

            // Filter for audio-only formats (type starts with "audio/")
            val audioFormats = formats.filter { format ->
                val type = format.jsonObject["type"]?.jsonPrimitive?.content ?: ""
                type.startsWith("audio/")
            }

            if (audioFormats.isEmpty()) {
                // Fall back to first available format if no audio-only found
                return@runCatching formats.firstOrNull()
                    ?.jsonObject?.get("url")?.jsonPrimitive?.content
            }

            // Sort by bitrate — high quality = highest bitrate first
            val sorted = audioFormats.sortedByDescending { format ->
                val bitrate = format.jsonObject["bitrate"]?.jsonPrimitive?.content
                bitrate?.toLongOrNull() ?: 0L
            }

            val best = if (settings.highQuality) sorted.first() else sorted.last()
            best.jsonObject["url"]?.jsonPrimitive?.content
        }.getOrNull()
    }

    private suspend fun resolvePipedAudioStream(instance: String, videoId: String): String? {
        return runCatching {
            val root = api.pipedStream(instance, videoId)
            val streams = root["audioStreams"]?.jsonArray ?: return@runCatching null

            // Get highest bitrate audio stream
            val best = streams.maxByOrNull { stream ->
                stream.jsonObject["bitrate"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
            }
            best?.jsonObject?.get("url")?.jsonPrimitive?.content
        }.getOrNull()
    }

    /**
     * Proxies googlevideo.com CDN URLs through Invidious to avoid 403 errors.
     * YouTube ties stream URLs to the server IP that requested them.
     * Matches Flutter's _proxyStreamUrl logic exactly.
     */
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

    private fun cacheSearch(query: String, tracks: List<Track>) {
        if (query.isBlank()) return
        searchCache[query] = tracks
        if (searchCache.size > 50) {
            val firstKey = searchCache.keys.firstOrNull()
            if (firstKey != null) searchCache.remove(firstKey)
        }
    }
}

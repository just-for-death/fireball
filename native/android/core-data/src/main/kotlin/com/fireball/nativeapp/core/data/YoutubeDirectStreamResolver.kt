package com.fireball.nativeapp.core.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.StreamInfo

/**
 * Resolves YouTube audio without a proxy by using [NewPipe Extractor] on-device (v0.26.x).
 * This is the recommended non-proxy fallback on Android when public Invidious mirrors fail.
 */
object YoutubeDirectStreamResolver {

    private val initLock = Any()

    @Volatile
    private var initialized = false

    private fun ensureInit() {
        if (initialized) return
        synchronized(initLock) {
            if (!initialized) {
                NewPipe.init(FireballNewPipeDownloader())
                initialized = true
            }
        }
    }

    /** Best-effort audio URL for a known YouTube video id. */
    suspend fun resolveAudioUrl(videoId: String): String? = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) return@withContext null
        ensureInit()
        runCatching {
            val service = ServiceList.YouTube
            val info = StreamInfo.getInfo(
                service,
                "https://www.youtube.com/watch?v=$videoId",
            )
            pickBestAudioUrl(info.audioStreams)
        }.getOrNull()
    }

    /**
     * Finds a likely music video id via YouTube search (no Invidious).
     * Returns (videoId, audioUrl) when successful.
     */
    suspend fun searchAndResolveAudio(artist: String, title: String): Pair<String, String>? =
        withContext(Dispatchers.IO) {
            ensureInit()
            val service = ServiceList.YouTube
            val queries = listOf(
                "$artist $title official audio",
                "$artist $title audio",
                "$artist - $title",
            )
            for (query in queries) {
                val result = runCatching {
                    val search = SearchInfo.getInfo(
                        service,
                        service.searchQHFactory.fromQuery(query, listOf("videos"), ""),
                    )
                    val first = search.relatedItems.firstOrNull() ?: return@runCatching null
                    val link = first.url ?: return@runCatching null
                    val id = link.substringAfter("v=").substringBefore("&").takeIf { it.length >= 8 }
                        ?: return@runCatching null
                    val audio = resolveAudioUrl(id) ?: return@runCatching null
                    id to audio
                }.getOrNull()
                if (result != null) return@withContext result
            }
            null
        }

    private fun pickBestAudioUrl(streams: List<AudioStream>?): String? {
        if (streams.isNullOrEmpty()) return null
        return streams.maxByOrNull { it.averageBitrate }?.url?.takeIf { it.isNotBlank() }
    }
}

package com.fireball.nativeapp.data

import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.data.LrcParser
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.Track
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

class LyricsAndAiOrchestrator(
    private val api: FireballApiClient
) {
    suspend fun fetchLyrics(track: Track, settings: FireballSettings): String? {
        val lrclib = runCatching { api.lrclibSearch(track.title, track.artist) }.getOrNull()
        val candidates = extractLrclibCandidates(lrclib)
        choosePreferredLyrics(candidates, settings.lyricsPreferEnglishHindi)?.let { return it }

        val search = runCatching { api.neteaseSearch("${track.title} ${track.artist}") }.getOrNull()
        val songs = search?.get("result")?.jsonObject?.get("songs")?.jsonArray
        val firstId = songs?.firstOrNull()?.jsonObject?.get("id")?.jsonPrimitive?.contentOrNull ?: return null
        val lyricResp = runCatching { api.neteaseLyrics(firstId) }.getOrNull()
        return lyricResp?.get("lrc")?.jsonObject?.get("lyric")?.jsonPrimitive?.contentOrNull
    }

    suspend fun generateAiQueue(settings: FireballSettings, seed: Track): List<String> {
        if (!settings.ollamaEnabled || settings.ollamaUrl.isBlank()) return emptyList()
        val prompt = "Suggest 5 songs similar to ${seed.title} by ${seed.artist}. Respond as plain lines: title - artist."
        val response = runCatching {
            api.ollamaGenerate(settings.ollamaUrl, settings.ollamaModel, prompt)
        }.getOrNull() ?: return emptyList()
        val text = response["message"]?.jsonObject?.get("content")?.jsonPrimitive?.content.orEmpty()
        return text.lines().map { it.trim() }.filter { it.isNotBlank() }.take(5)
    }

    private fun extractLrclibCandidates(element: JsonElement?): List<String> {
        if (element == null) return emptyList()
        return when {
            element is kotlinx.serialization.json.JsonArray -> element.mapNotNull { item ->
                item.jsonObject["syncedLyrics"]?.jsonPrimitive?.contentOrNull
                    ?: item.jsonObject["plainLyrics"]?.jsonPrimitive?.contentOrNull
            }
            element is kotlinx.serialization.json.JsonObject -> listOfNotNull(
                element["syncedLyrics"]?.jsonPrimitive?.contentOrNull,
                element["plainLyrics"]?.jsonPrimitive?.contentOrNull
            )
            else -> emptyList()
        }.filter { it.isNotBlank() }
    }

    private fun choosePreferredLyrics(candidates: List<String>, preferEnglishHindi: Boolean): String? {
        if (candidates.isEmpty()) return null
        val synced = candidates.filter { LrcParser.hasSyncedTimestamps(it) }
        val pool = if (synced.isNotEmpty()) synced else candidates
        if (!preferEnglishHindi) return pool.first()
        val hindiRegex = Regex("[\\u0900-\\u097F]")
        val englishRegex = Regex("[A-Za-z]")
        return pool.maxByOrNull { text ->
            val hasHindi = hindiRegex.containsMatchIn(text)
            val hasEnglish = englishRegex.containsMatchIn(text)
            when {
                hasEnglish && hasHindi -> 3
                hasEnglish -> 2
                hasHindi -> 1
                else -> 0
            }
        } ?: pool.first()
    }
}

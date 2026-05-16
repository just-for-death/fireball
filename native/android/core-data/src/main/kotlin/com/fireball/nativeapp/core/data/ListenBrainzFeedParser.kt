package com.fireball.nativeapp.core.data

import com.fireball.nativeapp.core.model.Track
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

object ListenBrainzFeedParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseRecentListens(body: String): List<Track> {
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return emptyList()
        val listens = root["payload"]?.jsonObject?.get("listens")?.jsonArray ?: return emptyList()
        return listens.mapNotNull { parseRecentEntry(it.jsonObject) }
    }

    fun parseTopRecordings(body: String): List<Track> {
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return emptyList()
        val recordings = root["payload"]?.jsonObject?.get("recordings")?.jsonArray ?: return emptyList()
        return recordings.mapNotNull { parseTopEntry(it.jsonObject) }
    }

    private fun parseRecentEntry(listen: JsonObject): Track? {
        val meta = listen["track_metadata"]?.jsonObject ?: return null
        val title = meta["track_name"]?.jsonPrimitive?.content?.trim().orEmpty()
        val artist = meta["artist_name"]?.jsonPrimitive?.content?.trim().orEmpty()
        if (title.isBlank() || artist.isBlank()) return null
        val album = meta["release_name"]?.jsonPrimitive?.content
        return Track(
            id = "$artist::$title",
            title = title,
            artist = artist,
            album = album,
        )
    }

    private fun parseTopEntry(rec: JsonObject): Track? {
        val title = rec["track_name"]?.jsonPrimitive?.content?.trim().orEmpty()
        val artist = rec["artist_name"]?.jsonPrimitive?.content?.trim().orEmpty()
        if (title.isBlank() || artist.isBlank()) return null
        return Track(
            id = "$artist::$title",
            title = title,
            artist = artist,
            album = rec["release_name"]?.jsonPrimitive?.content,
        )
    }
}

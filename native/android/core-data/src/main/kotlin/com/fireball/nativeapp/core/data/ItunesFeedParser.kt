package com.fireball.nativeapp.core.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Parses Apple Music RSS JSON feeds (same shape as Flutter [FireballApi.appleRssFeedEntries]). */
object ItunesFeedParser {
    fun feedEntries(root: JsonObject): List<JsonObject> {
        val entry = root["feed"]?.jsonObject?.get("entry") ?: return emptyList()
        return when (entry) {
            is JsonArray -> entry.mapNotNull { it.jsonObject }
            is JsonObject -> listOf(entry)
            else -> emptyList()
        }
    }

    data class ChartEntry(
        val id: String,
        val title: String,
        val artist: String,
        val artwork: String?,
    )

    fun topChartsFromFeed(entries: List<JsonObject>): List<ChartEntry> =
        entries.mapNotNull { e ->
            val id = e["id"]?.jsonObject
                ?.get("attributes")?.jsonObject
                ?.get("im:id")?.jsonPrimitive?.content
                ?: return@mapNotNull null
            if (id.isBlank()) return@mapNotNull null
            ChartEntry(
                id = id,
                title = e["im:name"]?.jsonObject?.get("label")?.jsonPrimitive?.content ?: "—",
                artist = e["im:artist"]?.jsonObject?.get("label")?.jsonPrimitive?.content ?: "—",
                artwork = e["im:image"]?.jsonArray?.getOrNull(2)?.jsonObject?.get("label")?.jsonPrimitive?.content,
            )
        }
}

package com.fireball.nativeapp.core.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
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
        val previewUrl: String?,
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
                previewUrl = extractPreviewUrl(e["link"]),
            )
        }

    private fun extractPreviewUrl(link: JsonElement?): String? {
        if (link == null) return null
        if (link is JsonArray) {
            for (item in link) {
                val obj = item.jsonObject
                val attrs = obj["attributes"]?.jsonObject ?: continue
                val type = attrs["type"]?.jsonPrimitive?.content
                val title = attrs["title"]?.jsonPrimitive?.content
                if (type == "audio/x-m4a" || title == "Preview") {
                    return attrs["href"]?.jsonPrimitive?.content
                }
            }
            return null
        }
        if (link is JsonObject) {
            return link["attributes"]?.jsonObject?.get("href")?.jsonPrimitive?.content
        }
        return null
    }
}

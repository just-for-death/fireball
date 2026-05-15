package com.fireball.nativeapp.core.data

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Official trusted Invidious instances (May 2026 — docs.invidious.io/instances).
 * Used when [api.invidious.io] is unreachable and as merge seed with live health data.
 */
object InvidiousInstanceProvider {
    private val json = Json { ignoreUnknownKeys = true }

    /** Clearnet instances from https://docs.invidious.io/instances/ (May 2026). */
    val trustedInstances: List<String> = listOf(
        "https://inv.nadeko.net",
        "https://invidious.nerdvpn.de",
        "https://inv.thepixora.com",
        "https://yt.chocolatemoo53.com",
    )

    private var cachedRemote: List<String>? = null
    private var cachedAtMs: Long = 0L
    private const val CACHE_TTL_MS = 60 * 60 * 1000L // 1 hour

    /**
     * Ordered list for resolve/search: user instance first, then healthy public mirrors.
     */
    fun instancesFor(userInstance: String, publicInstances: List<String>): List<String> {
        val user = userInstance.trim().trimEnd('/')
        return buildList {
            if (user.isNotBlank()) add(user)
            (publicInstances + trustedInstances).forEach { uri ->
                val normalized = uri.trim().trimEnd('/')
                if (normalized.isNotBlank() && normalized != user) add(normalized)
            }
        }.distinct()
    }

    suspend fun fetchHealthyInstances(httpClient: HttpClient?): List<String> {
        val now = System.currentTimeMillis()
        cachedRemote?.let { cached ->
            if (now - cachedAtMs < CACHE_TTL_MS) return cached
        }

        val fromApi = if (httpClient != null) {
            runCatching { parseInstancesJson(httpClient) }.getOrDefault(emptyList())
        } else {
            emptyList()
        }

        val merged = (fromApi + trustedInstances).distinct()
        cachedRemote = merged
        cachedAtMs = now
        return merged
    }

    private suspend fun parseInstancesJson(httpClient: HttpClient): List<String> {
        val body = httpClient.get("https://api.invidious.io/instances.json?sort_by=health").bodyAsText()
        val root = json.parseToJsonElement(body)
        if (root !is JsonArray) return emptyList()

        return root.mapNotNull { entry ->
            if (entry !is JsonArray || entry.size < 2) return@mapNotNull null
            val meta = entry[1]
            if (meta !is JsonObject) return@mapNotNull null

            val type = meta["type"]?.jsonPrimitive?.content ?: return@mapNotNull null
            if (type != "https") return@mapNotNull null

            val monitor = meta["monitor"]?.jsonObject
            if (monitor != null) {
                val down = monitor["down"]?.jsonPrimitive?.content?.toBooleanStrictOrNull()
                if (down == true) return@mapNotNull null
            }

            meta["uri"]?.jsonPrimitive?.content?.trim()?.trimEnd('/')
        }
    }
}

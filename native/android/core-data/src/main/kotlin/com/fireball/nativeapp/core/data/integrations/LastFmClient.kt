package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.url
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.security.MessageDigest
import java.util.SortedMap

/**
 * Last.fm Audioscrobbler API. Scrobbling requires [getMobileSession] (API key + shared secret + credentials).
 */
class LastFmClient(private val httpClient: HttpClient) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun validateApiKey(apiKey: String): Boolean {
        if (apiKey.isBlank()) return false
        return runCatching {
            val body = httpClient.get {
                url(BASE)
                parameter("method", "chart.gettopartists")
                parameter("api_key", apiKey)
                parameter("limit", "1")
                parameter("format", "json")
            }.bodyAsText()
            val root = json.parseToJsonElement(body).jsonObject
            !root.containsKey("error")
        }.getOrDefault(false)
    }

    suspend fun getMobileSession(
        apiKey: String,
        apiSecret: String,
        username: String,
        password: String,
    ): String? {
        if (apiKey.isBlank() || apiSecret.isBlank() || username.isBlank() || password.isBlank()) return null
        val params = sortedMapOf(
            "method" to "auth.getMobileSession",
            "username" to username,
            "password" to md5(password),
            "api_key" to apiKey,
        )
        val apiSig = buildSignature(params, apiSecret)
        return runCatching {
            val body = httpClient.get {
                url(BASE)
                params.forEach { entry -> parameter(entry.key, entry.value) }
                parameter("api_sig", apiSig)
                parameter("format", "json")
            }.bodyAsText()
            val root = json.parseToJsonElement(body).jsonObject
            root["session"]?.jsonObject?.get("key")?.jsonPrimitive?.content
        }.getOrNull()
    }

    suspend fun updateNowPlaying(
        apiKey: String,
        apiSecret: String,
        sessionKey: String,
        title: String,
        artist: String,
        album: String? = null,
    ): Boolean {
        if (apiKey.isBlank() || apiSecret.isBlank() || sessionKey.isBlank()) return false
        val params = sortedMapOf(
            "method" to "track.updateNowPlaying",
            "api_key" to apiKey,
            "sk" to sessionKey,
            "artist" to artist,
            "track" to title,
        )
        if (!album.isNullOrBlank()) params["album"] = album
        return postSigned(params, apiSecret)
    }

    suspend fun scrobble(
        apiKey: String,
        apiSecret: String,
        sessionKey: String,
        title: String,
        artist: String,
        timestampEpoch: Long,
        album: String? = null,
    ): Boolean {
        if (apiKey.isBlank() || apiSecret.isBlank() || sessionKey.isBlank()) return false
        val params = sortedMapOf(
            "method" to "track.scrobble",
            "api_key" to apiKey,
            "sk" to sessionKey,
            "artist" to artist,
            "track" to title,
            "timestamp" to timestampEpoch.toString(),
        )
        if (!album.isNullOrBlank()) params["album"] = album
        return postSigned(params, apiSecret)
    }

    private suspend fun postSigned(params: Map<String, String>, apiSecret: String): Boolean {
        val apiSig = buildSignature(params, apiSecret)
        return runCatching {
            val body = httpClient.post {
                url(BASE)
                params.forEach { entry -> parameter(entry.key, entry.value) }
                parameter("api_sig", apiSig)
                parameter("format", "json")
            }.bodyAsText()
            val root = json.parseToJsonElement(body).jsonObject
            !root.containsKey("error")
        }.getOrDefault(false)
    }

    private fun buildSignature(params: Map<String, String>, secret: String): String {
        val concat = params.toSortedMap().entries.joinToString("") { it.key + it.value } + secret
        return md5(concat)
    }

    private fun md5(input: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(input.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    private companion object {
        const val BASE = "https://ws.audioscrobbler.com/2.0/"
    }
}

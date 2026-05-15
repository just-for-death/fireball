package com.fireball.nativeapp.core.data

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.header
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.parameter
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.http.encodeURLParameter
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.net.HttpURLConnection
import java.net.URL

class FireballApiClient(
    private val httpClient: HttpClient,
) {
    suspend fun healthyInvidiousInstances(): List<String> =
        InvidiousInstanceProvider.fetchHealthyInstances(httpClient)
    /** iTunes returns JSON with Content-Type often `application/javascript`; avoid Ktor JSON negotiation missing it. */
    private val looseJson = Json { ignoreUnknownKeys = true; isLenient = true }

    suspend fun itunesSearch(term: String, limit: Int = 25): JsonObject {
        val bodyText = httpClient.get("https://itunes.apple.com/search") {
            parameter("media", "music")
            parameter("entity", "song")
            parameter("term", term)
            parameter("limit", limit)
            parameter("country", "US")
        }.bodyAsText()
        return looseJson.parseToJsonElement(bodyText).jsonObject
    }

    suspend fun invidiousSearch(instanceUrl: String, query: String, sid: String? = null): JsonArray {
        val base = instanceUrl.trimEnd('/')
        return httpClient.get("$base/api/v1/search") {
            parameter("q", query)
            parameter("type", "video")
            if (!sid.isNullOrBlank()) header(HttpHeaders.Cookie, "SID=$sid")
        }.body()
    }

    /**
     * @param local When true, Invidious proxies stream URLs through the instance (recommended for mobile playback).
     * See https://docs.invidious.io/url-parameters/
     */
    suspend fun invidiousVideo(
        instanceUrl: String,
        videoId: String,
        sid: String? = null,
        local: Boolean = true,
    ): JsonObject {
        val base = instanceUrl.trimEnd('/')
        return httpClient.get("$base/api/v1/videos/$videoId") {
            if (local) parameter("local", "true")
            if (!sid.isNullOrBlank()) header(HttpHeaders.Cookie, "SID=$sid")
        }.body()
    }

    /** Lightweight health probe — https://docs.invidious.io/api/#get-apiv1stats */
    suspend fun invidiousPing(instanceUrl: String): Boolean = runCatching {
        val base = instanceUrl.trimEnd('/')
        httpClient.get("$base/api/v1/stats").bodyAsText()
        true
    }.getOrDefault(false)

    suspend fun pipedSearch(instanceUrl: String, query: String): JsonArray {
        val base = instanceUrl.trimEnd('/')
        val response = httpClient.get("$base/search") {
            parameter("q", query)
            parameter("filter", "music_songs")
        }.body<JsonObject>()
        return response["items"]?.jsonArray ?: JsonArray(emptyList())
    }

    suspend fun pipedStream(instanceUrl: String, videoId: String): JsonObject {
        val base = instanceUrl.trimEnd('/')
        return httpClient.get("$base/streams/$videoId").body()
    }

    suspend fun invidiousLogin(instanceUrl: String, username: String, password: String): Pair<String, String> = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val base = instanceUrl.trimEnd('/')
        val loginUrl = URL("$base/login?type=invidious")

        fun tryLogin(body: String): Pair<String, Int> {
            val conn = (loginUrl.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                instanceFollowRedirects = false // Keep 302 response to inspect Set-Cookie SID
                connectTimeout = 15_000
                readTimeout = 15_000
                doOutput = true
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                setRequestProperty("Referer", "$base/login")
                setRequestProperty("Origin", base)
                setRequestProperty("User-Agent", "Mozilla/5.0 (compatible; Fireball/1.0; +https://github.com/fireball)")
                outputStream.use { os -> os.write(body.toByteArray()) }
            }

            val code = conn.responseCode
            val setCookie = buildList {
                conn.headerFields?.forEach { (key, values) ->
                    if (key != null && key.equals("Set-Cookie", ignoreCase = true)) {
                        addAll(values.orEmpty())
                    }
                }
            }
            val sid = setCookie
                .firstNotNullOfOrNull { Regex("""SID=([^;]+)""", RegexOption.IGNORE_CASE).find(it)?.groupValues?.getOrNull(1) }
                ?.trim()
                .orEmpty()
            return sid to code
        }

        var body = "email=${username.encodeURLParameter()}&password=${password.encodeURLParameter()}"
        var (sid, code) = tryLogin(body)

        if (sid.isBlank()) {
            body = "$body&action=signin"
            val retry = tryLogin(body)
            sid = retry.first
            code = retry.second
        }

        if (sid.isBlank()) {
            val reason = when (code) {
                401, 403 -> "wrong credentials"
                else -> "status=$code, captcha required or login disabled"
            }
            error("Invidious login failed ($reason).")
        }
        return@withContext sid to username
    }

    suspend fun invidiousPlaylistDetail(instanceUrl: String, sid: String?, playlistId: String): JsonObject {
        val base = instanceUrl.trimEnd('/')
        return httpClient.get("$base/api/v1/playlists/$playlistId") {
            if (!sid.isNullOrBlank()) header(HttpHeaders.Cookie, "SID=$sid")
        }.body()
    }

    suspend fun invidiousAuthPlaylists(instanceUrl: String, sid: String): JsonArray {
        val base = instanceUrl.trimEnd('/')
        return httpClient.get("$base/api/v1/auth/playlists") {
            header(HttpHeaders.Cookie, "SID=$sid")
        }.body()
    }

    suspend fun invidiousCreatePlaylist(
        instanceUrl: String,
        sid: String,
        title: String,
        privacy: String
    ): String {
        val base = instanceUrl.trimEnd('/')
        val response = httpClient.post("$base/api/v1/auth/playlists") {
            header(HttpHeaders.Cookie, "SID=$sid")
            contentType(ContentType.Application.Json)
            setBody(buildJsonObject {
                put("title", title)
                put("privacy", privacy)
            })
        }.body<JsonObject>()
        return response["playlistId"]?.jsonPrimitive?.content.orEmpty()
    }

    suspend fun invidiousAddVideoToPlaylist(instanceUrl: String, sid: String, playlistId: String, videoId: String) {
        val base = instanceUrl.trimEnd('/')
        httpClient.post("$base/api/v1/auth/playlists/$playlistId/videos") {
            header(HttpHeaders.Cookie, "SID=$sid")
            contentType(ContentType.Application.Json)
            setBody(buildJsonObject { put("videoId", videoId) })
        }.bodyAsText()
    }

    suspend fun lrclibSearch(track: String, artist: String): JsonObject {
        return httpClient.get("https://lrclib.net/api/search") {
            parameter("track_name", track)
            parameter("artist_name", artist)
        }.body()
    }

    suspend fun neteaseSearch(query: String): JsonObject {
        return httpClient.get("https://music.163.com/api/search/get") {
            parameter("s", query)
            parameter("type", 1)
            parameter("limit", 10)
        }.body()
    }

    suspend fun neteaseLyrics(songId: String): JsonObject {
        return httpClient.get("https://music.163.com/api/song/lyric") {
            parameter("id", songId)
            parameter("lv", 1)
            parameter("kv", 1)
            parameter("tv", -1)
        }.body()
    }

    suspend fun ollamaGenerate(ollamaUrl: String, model: String, prompt: String): JsonObject {
        val base = ollamaUrl.trimEnd('/')
        return httpClient.post("$base/api/chat") {
            setBody(
                buildJsonObject {
                    put("model", model)
                    put("stream", false)
                    put("messages", kotlinx.serialization.json.buildJsonArray {
                        add(buildJsonObject {
                            put("role", "user")
                            put("content", prompt)
                        })
                    })
                }
            )
        }.body()
    }
}

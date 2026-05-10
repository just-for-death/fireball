package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.request.url
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class ListenBrainzClient(private val httpClient: HttpClient) {
    suspend fun submitPlayingNow(token: String, title: String, artist: String) {
        submit(
            token = token,
            listenType = "playing_now",
            title = title,
            artist = artist
        )
    }

    suspend fun submitScrobble(token: String, title: String, artist: String, listenedAtEpoch: Long) {
        submit(
            token = token,
            listenType = "single",
            title = title,
            artist = artist,
            listenedAtEpoch = listenedAtEpoch
        )
    }

    private suspend fun submit(
        token: String,
        listenType: String,
        title: String,
        artist: String,
        listenedAtEpoch: Long? = null
    ) {
        if (token.isBlank() || title.isBlank() || artist.isBlank()) return
        val item = buildJsonObject {
            put("track_metadata", buildJsonObject {
                put("track_name", title)
                put("artist_name", artist)
            })
            if (listenedAtEpoch != null) put("listened_at", listenedAtEpoch)
        }
        val body = buildJsonObject {
            put("listen_type", listenType)
            put("payload", buildJsonArray { add(item) })
        }.toString()
        runCatching {
            httpClient.post {
                url("https://api.listenbrainz.org/1/submit-listens")
                header("Authorization", "Token $token")
                contentType(ContentType.Application.Json)
                setBody(body)
            }
        }
    }
}

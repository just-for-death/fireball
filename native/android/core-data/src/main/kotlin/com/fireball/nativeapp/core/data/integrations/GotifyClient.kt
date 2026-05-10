package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class GotifyClient(private val httpClient: HttpClient) {
    suspend fun sendMessage(url: String, token: String, title: String, message: String): Boolean {
        if (url.isBlank() || token.isBlank()) return false
        val endpoint = "${url.trimEnd('/')}/message"
        val body = buildJsonObject {
            put("title", title)
            put("message", message)
            put("priority", 5)
        }.toString()
        return runCatching {
            httpClient.post(endpoint) {
                header("X-Gotify-Key", token)
                contentType(ContentType.Application.Json)
                setBody(body)
            }
            true
        }.getOrDefault(false)
    }
}

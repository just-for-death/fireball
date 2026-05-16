package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.statement.bodyAsText
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import java.util.Base64

class WebDavSyncClient(
    private val httpClient: HttpClient
) {
    suspend fun pullLibraryJson(baseUrl: String, username: String, password: String): String? {
        if (baseUrl.isBlank()) return null
        val target = normalizedLibraryPath(baseUrl)
        return runCatching {
            val response = httpClient.get(target) {
                basicAuthHeader(username, password)?.let { header("Authorization", it) }
            }
            if (response.status.value !in 200..299) return@runCatching null
            response.bodyAsText()
        }.getOrNull()
    }

    suspend fun pushLibraryJson(baseUrl: String, username: String, password: String, json: String): Boolean {
        if (baseUrl.isBlank()) return false
        val target = normalizedLibraryPath(baseUrl)
        return runCatching {
            val response = httpClient.put(target) {
                basicAuthHeader(username, password)?.let { header("Authorization", it) }
                setBody(json)
            }
            response.status.value in 200..299
        }.getOrDefault(false)
    }

    private fun normalizedLibraryPath(baseUrl: String): String {
        val cleaned = baseUrl.trimEnd('/')
        return "$cleaned/fireball/library.json"
    }

    private fun basicAuthHeader(username: String, password: String): String? {
        if (username.isBlank() && password.isBlank()) return null
        val token = Base64.getEncoder().encodeToString("$username:$password".toByteArray())
        return "Basic $token"
    }
}

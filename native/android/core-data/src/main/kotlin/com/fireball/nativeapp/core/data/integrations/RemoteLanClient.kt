package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

class RemoteLanClient(private val httpClient: HttpClient) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchState(host: String, port: Int): JsonObject? {
        val base = normalize(host, port) ?: return null
        return runCatching {
            val text = httpClient.get("$base/state").bodyAsText()
            json.parseToJsonElement(text).jsonObject
        }.getOrNull()
    }

    suspend fun sendCommand(host: String, port: Int, action: String, value: String? = null): Boolean {
        val base = normalize(host, port) ?: return false
        val body = buildJsonObject {
            put("action", action)
            if (value != null) put("value", value)
        }.toString()
        return runCatching {
            httpClient.post("$base/command") {
                contentType(ContentType.Application.Json)
                setBody(body)
            }
            true
        }.getOrDefault(false)
    }

    suspend fun pair(host: String, port: Int, code: String): JsonObject? {
        val base = normalize(host, port) ?: return null
        if (code.isBlank()) return null
        return runCatching {
            val body = buildJsonObject { put("code", code) }.toString()
            val text = httpClient.post("$base/pair") {
                contentType(ContentType.Application.Json)
                setBody(body)
            }.bodyAsText()
            json.parseToJsonElement(text).jsonObject
        }.getOrNull()
    }

    private fun normalize(host: String, port: Int): String? {
        if (host.isBlank()) return null
        val safePort = if (port <= 0) 7771 else port
        return "http://${host.trim()}:$safePort"
    }
}

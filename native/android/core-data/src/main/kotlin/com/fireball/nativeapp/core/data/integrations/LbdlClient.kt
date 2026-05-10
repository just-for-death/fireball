package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.request.basicAuth
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

class LbdlClient(private val httpClient: HttpClient) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun authStatus(baseUrl: String, username: String, password: String): JsonObject? {
        if (baseUrl.isBlank()) return null
        return runCatching {
            val text = httpClient.get("${baseUrl.trimEnd('/')}/api/auth/status") {
                if (username.isNotBlank() || password.isNotBlank()) basicAuth(username, password)
            }.bodyAsText()
            json.parseToJsonElement(text).jsonObject
        }.getOrNull()
    }

    suspend fun createJob(baseUrl: String, username: String, password: String, links: List<String>): JsonObject? {
        if (baseUrl.isBlank() || links.isEmpty()) return null
        return runCatching {
            val body = buildJsonObject {
                put("links", buildJsonArray { links.forEach { add(JsonPrimitive(it)) } })
            }.toString()
            val text = httpClient.post("${baseUrl.trimEnd('/')}/api/jobs") {
                contentType(ContentType.Application.Json)
                if (username.isNotBlank() || password.isNotBlank()) basicAuth(username, password)
                setBody(body)
            }.bodyAsText()
            json.parseToJsonElement(text).jsonObject
        }.getOrNull()
    }

    suspend fun jobStatus(baseUrl: String, username: String, password: String, jobId: String): JsonObject? {
        if (baseUrl.isBlank() || jobId.isBlank()) return null
        return runCatching {
            val text = httpClient.get("${baseUrl.trimEnd('/')}/api/jobs/$jobId") {
                if (username.isNotBlank() || password.isNotBlank()) basicAuth(username, password)
            }.bodyAsText()
            json.parseToJsonElement(text).jsonObject
        }.getOrNull()
    }
}

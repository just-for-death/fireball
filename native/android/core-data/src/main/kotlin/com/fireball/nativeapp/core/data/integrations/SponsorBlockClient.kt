package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.url
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SponsorSegment(
    @SerialName("segment") val segment: List<Double> = emptyList(),
    @SerialName("category") val category: String = "sponsor",
    @SerialName("UUID") val uuid: String = ""
) {
    val start: Double get() = segment.getOrElse(0) { 0.0 }
    val end: Double get() = segment.getOrElse(1) { 0.0 }
}

class SponsorBlockClient(private val httpClient: HttpClient) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun segments(videoId: String, categories: List<String>): List<SponsorSegment> {
        if (videoId.isBlank() || categories.isEmpty()) return emptyList()
        return runCatching {
            val text = httpClient.post {
                url("https://sponsor.ajay.app/api/skipSegments")
                parameter("videoID", videoId)
                parameter("categories", categories.joinToString(prefix = "[\"", postfix = "\"]", separator = "\",\""))
            }.bodyAsText()
            json.decodeFromString(ListSerializer(SponsorSegment.serializer()), text)
        }.getOrDefault(emptyList())
    }

    suspend fun markViewed(uuid: String) {
        if (uuid.isBlank()) return
        runCatching {
            httpClient.post {
                url("https://sponsor.ajay.app/api/viewedVideoSponsorTime")
                parameter("UUID", uuid)
            }
        }
    }
}

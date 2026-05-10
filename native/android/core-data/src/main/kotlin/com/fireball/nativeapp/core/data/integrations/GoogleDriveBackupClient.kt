package com.fireball.nativeapp.core.data.integrations

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.get
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText

class GoogleDriveBackupClient(private val httpClient: HttpClient) {
    suspend fun uploadAppDataJson(accessToken: String, fileName: String, content: String): Boolean {
        if (accessToken.isBlank()) return false
        val metadata = """{"name":"$fileName","parents":["appDataFolder"]}"""
        val boundary = "fireball_native_boundary"
        val multipartBody = buildString {
            append("--$boundary\r\n")
            append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
            append(metadata)
            append("\r\n--$boundary\r\n")
            append("Content-Type: application/json\r\n\r\n")
            append(content)
            append("\r\n--$boundary--")
        }
        return runCatching {
            httpClient.post("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart") {
                header("Authorization", "Bearer $accessToken")
                header("Content-Type", "multipart/related; boundary=$boundary")
                setBody(multipartBody)
            }
            true
        }.getOrDefault(false)
    }

    suspend fun listAppDataFiles(accessToken: String, name: String): String? {
        if (accessToken.isBlank()) return null
        val q = "name='$name' and 'appDataFolder' in parents and trashed=false"
        return runCatching {
            httpClient.get("https://www.googleapis.com/drive/v3/files?q=${java.net.URLEncoder.encode(q, "UTF-8")}&spaces=appDataFolder&fields=files(id,name)") {
                header("Authorization", "Bearer $accessToken")
            }.bodyAsText()
        }.getOrNull()
    }

    suspend fun downloadFile(accessToken: String, fileId: String): String? {
        if (accessToken.isBlank() || fileId.isBlank()) return null
        return runCatching {
            httpClient.get("https://www.googleapis.com/drive/v3/files/$fileId?alt=media") {
                header("Authorization", "Bearer $accessToken")
            }.bodyAsText()
        }.getOrNull()
    }
}

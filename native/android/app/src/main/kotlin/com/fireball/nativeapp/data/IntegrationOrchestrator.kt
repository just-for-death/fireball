package com.fireball.nativeapp.data

import com.fireball.nativeapp.core.data.integrations.LastFmClient
import com.fireball.nativeapp.core.data.integrations.ListenBrainzClient
import com.fireball.nativeapp.core.data.integrations.GoogleDriveBackupClient
import com.fireball.nativeapp.core.data.integrations.GotifyClient
import com.fireball.nativeapp.core.data.integrations.LbdlClient
import com.fireball.nativeapp.core.data.integrations.RemoteLanClient
import com.fireball.nativeapp.core.data.integrations.SponsorBlockClient
import com.fireball.nativeapp.core.data.integrations.SponsorSegment
import com.fireball.nativeapp.core.data.integrations.WebDavSyncClient
import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import kotlinx.coroutines.delay
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class IntegrationOrchestrator(
    private val fireballApiClient: FireballApiClient,
    private val listenBrainzClient: ListenBrainzClient,
    private val lastFmClient: LastFmClient,
    private val sponsorBlockClient: SponsorBlockClient,
    private val webDavSyncClient: WebDavSyncClient,
    private val gotifyClient: GotifyClient,
    private val lbdlClient: LbdlClient,
    private val remoteLanClient: RemoteLanClient,
    private val googleDriveBackupClient: GoogleDriveBackupClient
) {
    private val integrationJson = Json { ignoreUnknownKeys = true }

    private suspend fun <T> withRetry(
        attempts: Int = 2,
        block: suspend () -> T
    ): T {
        var lastError: Throwable? = null
        repeat(attempts) { idx ->
            try {
                return block()
            } catch (t: Throwable) {
                lastError = t
                if (idx < attempts - 1) delay(400)
            }
        }
        throw (lastError ?: IllegalStateException("Unknown integration error"))
    }

    suspend fun listenBrainzRecent(settings: FireballSettings, count: Int = 8): List<Track> {
        if (!settings.listenBrainzEnabled) return emptyList()
        return listenBrainzClient.recentListens(
            username = settings.listenBrainzUsername,
            token = settings.listenBrainzToken,
            count = count,
        )
    }

    suspend fun listenBrainzTop(
        settings: FireballSettings,
        range: String = "month",
        count: Int = 10,
    ): List<Track> {
        if (!settings.listenBrainzEnabled) return emptyList()
        return listenBrainzClient.topRecordings(
            username = settings.listenBrainzUsername,
            token = settings.listenBrainzToken,
            range = range,
            count = count,
        )
    }

    suspend fun submitPlayingNow(settings: FireballSettings, track: Track) {
        if (!settings.listenBrainzEnabled || !settings.listenBrainzPlayingNow) return
        listenBrainzClient.submitPlayingNow(
            token = settings.listenBrainzToken,
            title = track.title,
            artist = track.artist
        )
    }

    suspend fun submitScrobble(settings: FireballSettings, track: Track, listenedAtEpoch: Long) {
        if (!settings.listenBrainzEnabled) return
        listenBrainzClient.submitScrobble(
            token = settings.listenBrainzToken,
            title = track.title,
            artist = track.artist,
            listenedAtEpoch = listenedAtEpoch
        )
    }

    suspend fun validateLastFmApiKey(apiKey: String): Boolean = lastFmClient.validateApiKey(apiKey)

    suspend fun connectLastFm(settings: FireballSettings, password: String): String? =
        lastFmClient.getMobileSession(
            apiKey = settings.lastFmApiKey,
            apiSecret = settings.lastFmApiSecret,
            username = settings.lastFmUsername,
            password = password,
        )

    private fun lastFmReady(settings: FireballSettings): Boolean =
        settings.lastFmApiKey.isNotBlank() &&
            settings.lastFmApiSecret.isNotBlank() &&
            settings.lastFmSessionKey.isNotBlank()

    suspend fun submitLastFmPlayingNow(settings: FireballSettings, track: Track) {
        if (!lastFmReady(settings)) return
        lastFmClient.updateNowPlaying(
            apiKey = settings.lastFmApiKey,
            apiSecret = settings.lastFmApiSecret,
            sessionKey = settings.lastFmSessionKey,
            title = track.title,
            artist = track.artist,
            album = track.album,
        )
    }

    suspend fun submitLastFmScrobble(settings: FireballSettings, track: Track, listenedAtEpoch: Long) {
        if (!lastFmReady(settings)) return
        lastFmClient.scrobble(
            apiKey = settings.lastFmApiKey,
            apiSecret = settings.lastFmApiSecret,
            sessionKey = settings.lastFmSessionKey,
            title = track.title,
            artist = track.artist,
            timestampEpoch = listenedAtEpoch,
            album = track.album,
        )
    }

    suspend fun sponsorSegments(settings: FireballSettings, track: Track): List<SponsorSegment> {
        if (!settings.sponsorBlock || settings.sponsorBlockCategories.isEmpty()) return emptyList()
        val videoId = track.videoId ?: return emptyList()
        return sponsorBlockClient.segments(videoId, settings.sponsorBlockCategories)
    }

    suspend fun markSponsorViewed(uuid: String) {
        sponsorBlockClient.markViewed(uuid)
    }

    suspend fun syncPull(settings: FireballSettings): String? {
        if (settings.webDavUrl.isBlank()) return null
        return webDavSyncClient.pullLibraryJson(
            baseUrl = settings.webDavUrl,
            username = settings.webDavUsername,
            password = settings.webDavPassword
        )
    }

    suspend fun syncPush(settings: FireballSettings, snapshot: LibrarySnapshot): Boolean {
        if (settings.webDavUrl.isBlank()) return false
        val json = integrationJson.encodeToString(LibrarySnapshot.serializer(), snapshot)
        return webDavSyncClient.pushLibraryJson(
            baseUrl = settings.webDavUrl,
            username = settings.webDavUsername,
            password = settings.webDavPassword,
            json = json
        )
    }

    suspend fun gotify(settings: FireballSettings, title: String, message: String): Boolean {
        if (!settings.gotifyEnabled) return false
        return runCatching {
            withRetry { gotifyClient.sendMessage(settings.gotifyUrl, settings.gotifyToken, title, message) }
        }.getOrDefault(false)
    }

    suspend fun lbdlStatus(settings: FireballSettings): Boolean {
        val status = runCatching {
            withRetry { lbdlClient.authStatus(settings.lbdlUrl, settings.lbdlUsername, settings.lbdlPassword) }
        }.getOrNull() ?: return false
        return isLbdlAuthenticated(status)
    }

    private fun isLbdlAuthenticated(status: kotlinx.serialization.json.JsonObject): Boolean {
        val keys = listOf("authenticated", "isAuthenticated", "loggedIn", "logged_in")
        for (key in keys) {
            val el = status[key] ?: continue
            if (el is kotlinx.serialization.json.JsonPrimitive) {
                when (el.content.trim().lowercase()) {
                    "true", "1" -> return true
                }
            }
        }
        return false
    }

    suspend fun lbdlCreateJob(settings: FireballSettings, links: List<String>): String? {
        val result = runCatching {
            withRetry { lbdlClient.createJob(settings.lbdlUrl, settings.lbdlUsername, settings.lbdlPassword, links) }
        }.getOrNull()
        return result?.get("jobId")?.jsonPrimitive?.contentOrNull
    }

    suspend fun remoteCommand(settings: FireballSettings, action: String, value: String? = null): Boolean {
        return runCatching {
            withRetry {
                remoteLanClient.sendCommand(
                    host = settings.remoteHostIp,
                    port = settings.remotePeerPort,
                    action = action,
                    value = value
                )
            }
        }.getOrDefault(false)
    }

    suspend fun remotePair(settings: FireballSettings, code: String): Boolean {
        val resp = runCatching {
            withRetry {
                remoteLanClient.pair(
                    host = settings.remoteHostIp,
                    port = settings.remotePeerPort,
                    code = code
                )
            }
        }.getOrNull()
        return resp != null
    }

    suspend fun gDriveBackup(accessToken: String, snapshot: LibrarySnapshot): Boolean {
        val payload = integrationJson.encodeToString(LibrarySnapshot.serializer(), snapshot)
        return runCatching {
            withRetry { googleDriveBackupClient.uploadAppDataJson(accessToken, "fireball_library.json", payload) }
        }.getOrDefault(false)
    }

    suspend fun invidiousLogin(
        instanceUrl: String,
        username: String,
        password: String
    ): Pair<String, String>? {
        if (instanceUrl.isBlank() || username.isBlank() || password.isBlank()) return null
        return runCatching {
            withRetry { fireballApiClient.invidiousLogin(instanceUrl, username, password) }
        }.getOrNull()
    }

    suspend fun invidiousAuthPlaylists(settings: FireballSettings): List<Pair<String, String>> {
        val sid = settings.invidiousSid ?: return emptyList()
        if (settings.invidiousInstance.isBlank()) return emptyList()
        val data = runCatching {
            withRetry { fireballApiClient.invidiousAuthPlaylists(settings.invidiousInstance, sid) }
        }.getOrNull() ?: return emptyList()

        return data.mapNotNull { item ->
            val obj = item.jsonObject
            val id = obj["playlistId"]?.jsonPrimitive?.content ?: return@mapNotNull null
            val title = obj["title"]?.jsonPrimitive?.content ?: "Playlist"
            id to title
        }
    }

    suspend fun invidiousSyncPlaylist(settings: FireballSettings, playlistId: String): Playlist? {
        if (settings.invidiousInstance.isBlank() || playlistId.isBlank()) return null
        val data = runCatching {
            withRetry {
                fireballApiClient.invidiousPlaylistDetail(
                    instanceUrl = settings.invidiousInstance,
                    sid = settings.invidiousSid,
                    playlistId = playlistId
                )
            }
        }.getOrNull() ?: return null

        val id = data["playlistId"]?.jsonPrimitive?.content ?: playlistId
        val title = data["title"]?.jsonPrimitive?.content ?: "Playlist"
        val videos = data["videos"]?.jsonArray.orEmpty().mapNotNull { item ->
            val obj = item.jsonObject
            val videoId = obj["videoId"]?.jsonPrimitive?.content ?: return@mapNotNull null
            Track(
                id = videoId,
                videoId = videoId,
                title = obj["title"]?.jsonPrimitive?.content ?: "Unknown",
                artist = obj["author"]?.jsonPrimitive?.content ?: "Unknown",
                artwork = obj["videoThumbnails"]
                    ?.jsonArray
                    ?.firstOrNull()
                    ?.jsonObject
                    ?.get("url")
                    ?.jsonPrimitive
                    ?.content
            )
        }
        return Playlist(id = id, title = title, videos = videos)
    }

    suspend fun invidiousPushPlaylist(
        settings: FireballSettings,
        local: Playlist,
        existingInvidiousId: String? = null
    ): String? {
        val sid = settings.invidiousSid ?: return null
        if (settings.invidiousInstance.isBlank() || local.videos.isEmpty()) return null
        var invId = existingInvidiousId.orEmpty()
        if (invId.isBlank()) {
            invId = runCatching {
                withRetry {
                    fireballApiClient.invidiousCreatePlaylist(
                        settings.invidiousInstance,
                        sid,
                        local.title,
                        settings.invidiousPlaylistPrivacy
                    )
                }
            }.getOrDefault("")
        }
        if (invId.isBlank()) return null

        local.videos.forEach { track ->
            val videoId = track.videoId ?: track.id
            if (videoId.isBlank()) return@forEach
            runCatching {
                withRetry {
                    fireballApiClient.invidiousAddVideoToPlaylist(
                        settings.invidiousInstance,
                        sid,
                        invId,
                        videoId
                    )
                }
            }
        }
        return invId
    }
}

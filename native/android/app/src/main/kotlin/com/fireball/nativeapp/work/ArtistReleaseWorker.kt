package com.fireball.nativeapp.work

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.data.LibraryStore
import com.fireball.nativeapp.core.data.integrations.GotifyClient
import com.fireball.nativeapp.data.FireballRepository
import com.fireball.nativeapp.notifications.ArtistReleaseNotifier
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class ArtistReleaseWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val store = LibraryStore(applicationContext.filesDir)
        val snapshot = store.load()
        val settings = snapshot.settings
        val wantGotify =
            settings.gotifyEnabled &&
                settings.gotifyUrl.isNotBlank() &&
                settings.gotifyToken.isNotBlank()
        val wantDevice = settings.notifyArtistReleasesOnDevice
        if (!wantGotify && !wantDevice) return Result.success()

        ArtistReleaseNotifier.ensureChannel(applicationContext)
        val client =
            HttpClient(OkHttp) {
                install(HttpTimeout) {
                    connectTimeoutMillis = 20_000
                    socketTimeoutMillis = 40_000
                }
                install(ContentNegotiation) {
                    json(Json { ignoreUnknownKeys = true })
                }
            }
        try {
            val api = FireballApiClient(httpClient = client)
            val repository = FireballRepository(api = api, store = store)
            val gotify = GotifyClient(client)
            val onGotify: (suspend (String, String) -> Boolean)? =
                if (wantGotify) {
                    { title, message ->
                        gotify.sendMessage(settings.gotifyUrl, settings.gotifyToken, title, message)
                    }
                } else {
                    null
                }
            val onDevice: (suspend (String, String) -> Unit)? =
                if (wantDevice) {
                    { title, message ->
                        ArtistReleaseNotifier.show(applicationContext, title, message)
                    }
                } else {
                    null
                }
            val updated =
                repository.checkFollowedArtistNewReleases(
                    snapshot = snapshot,
                    onGotifyNotify = onGotify,
                    onDeviceNotify = onDevice,
                )
            if (updated != null) repository.saveLibrary(updated)
        } finally {
            client.close()
        }
        return Result.success()
    }
}

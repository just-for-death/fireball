package com.fireball.nativeapp

import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.util.Locale
import com.fireball.nativeapp.app.FireballNativeApp
import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.data.LibraryStore
import com.fireball.nativeapp.core.data.integrations.ListenBrainzClient
import com.fireball.nativeapp.core.data.integrations.GoogleDriveBackupClient
import com.fireball.nativeapp.core.data.integrations.GotifyClient
import com.fireball.nativeapp.core.data.integrations.LbdlClient
import com.fireball.nativeapp.core.data.integrations.RemoteLanClient
import com.fireball.nativeapp.core.data.integrations.SponsorBlockClient
import com.fireball.nativeapp.core.data.integrations.WebDavSyncClient
import com.fireball.nativeapp.data.FireballRepository
import com.fireball.nativeapp.data.IntegrationOrchestrator
import com.fireball.nativeapp.data.LyricsAndAiOrchestrator
import com.fireball.nativeapp.player.PlayerManager
import com.fireball.nativeapp.player.PlaybackController
import com.fireball.nativeapp.ui.MainViewModel
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class MainActivity : ComponentActivity() {
    private var bluetoothReceiver: BroadcastReceiver? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsCollectorJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val httpClient = HttpClient(OkHttp) {
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                    coerceInputValues = true
                })
            }
        }
        val apiClient = FireballApiClient(httpClient)
        val store = LibraryStore(filesDir)
        val repository = FireballRepository(apiClient, store)
        val playerManager = PlayerManager()
        val playbackController = PlaybackController(this)
        val integrations = IntegrationOrchestrator(
            fireballApiClient = apiClient,
            listenBrainzClient = ListenBrainzClient(httpClient),
            sponsorBlockClient = SponsorBlockClient(httpClient),
            webDavSyncClient = WebDavSyncClient(httpClient),
            gotifyClient = GotifyClient(httpClient),
            lbdlClient = LbdlClient(httpClient),
            remoteLanClient = RemoteLanClient(httpClient),
            googleDriveBackupClient = GoogleDriveBackupClient(httpClient)
        )
        val lyricsAndAi = LyricsAndAiOrchestrator(apiClient)
        val viewModel = MainViewModel(
            repository,
            playerManager,
            integrations,
            playbackController,
            lyricsAndAi
        )

        setupBluetoothAutoplay(viewModel)
        setupSongAnnounceTts(viewModel)

        setContent { FireballNativeApp(viewModel = viewModel) }
    }

    private fun setupBluetoothAutoplay(viewModel: MainViewModel) {
        // Best-effort: resume when a Bluetooth A2DP profile connects.
        bluetoothReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED) return
                val state = intent.getIntExtra(BluetoothProfile.EXTRA_STATE, BluetoothProfile.STATE_DISCONNECTED)
                if (state != BluetoothProfile.STATE_CONNECTED) return

                val settings = viewModel.uiState.value.library.settings
                if (!settings.bluetoothAutoplayEnabled) return

                val ps = viewModel.playbackState.value
                if (ps.queue.isEmpty()) return
                if (ps.currentTrack == null) return
                if (ps.isPlaying) return

                // Resume playback from the engine's current position.
                viewModel.togglePlayPause()
            }
        }

        registerReceiver(bluetoothReceiver, IntentFilter(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED))
    }

    private fun setupSongAnnounceTts(viewModel: MainViewModel) {
        textToSpeech = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech?.language = Locale.getDefault()
            }
        }

        ttsCollectorJob?.cancel()
        ttsCollectorJob = lifecycleScope.launch {
            var lastSpokenId: String? = null
            viewModel.playbackState.collectLatest { ps ->
                val settings = viewModel.uiState.value.library.settings
                val enabled = settings.speakSongDetailsEnabled
                if (!enabled) {
                    textToSpeech?.stop()
                    lastSpokenId = null
                    return@collectLatest
                }

                val track = ps.currentTrack ?: return@collectLatest
                if (track.effectiveId == lastSpokenId) return@collectLatest
                lastSpokenId = track.effectiveId

                val toSpeak = "${track.title} by ${track.artist}"
                textToSpeech?.speak(
                    toSpeak,
                    TextToSpeech.QUEUE_FLUSH,
                    null,
                    "track_${track.effectiveId}"
                )
            }
        }
    }

    override fun onDestroy() {
        bluetoothReceiver?.let { unregisterReceiver(it) }
        bluetoothReceiver = null

        ttsCollectorJob?.cancel()
        ttsCollectorJob = null

        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }
}

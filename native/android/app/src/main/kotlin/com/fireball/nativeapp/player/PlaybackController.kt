package com.fireball.nativeapp.player

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

data class EnginePlaybackState(
    val currentIndex: Int = -1,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L
)

class PlaybackController(private val context: Context) {
    private var controller: MediaController? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var pollingJob: Job? = null
    private val _state = MutableStateFlow(EnginePlaybackState())
    val state: StateFlow<EnginePlaybackState> = _state

    fun connect(onConnected: (() -> Unit)? = null) {
        if (controller != null) return
        val token = SessionToken(context, ComponentName(context, NativePlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            controller = future.get()
            startPolling()
            onConnected?.invoke()
        }, MoreExecutors.directExecutor())
    }

    fun playQueue(items: List<MediaItem>, startIndex: Int) {
        val c = controller ?: return
        c.setMediaItems(items, startIndex, 0L)
        c.prepare()
        c.play()
    }

    fun togglePlayPause() {
        controller?.let { if (it.isPlaying) it.pause() else it.play() }
    }

    fun next() = controller?.seekToNext()
    fun previous() = controller?.seekToPrevious()
    fun seekTo(positionMs: Long) {
        controller?.seekTo(positionMs)
    }

    fun setRepeatMode(mode: RepeatMode) {
        controller?.repeatMode = when (mode) {
            RepeatMode.OFF -> Player.REPEAT_MODE_OFF
            RepeatMode.ALL -> Player.REPEAT_MODE_ALL
            RepeatMode.ONE -> Player.REPEAT_MODE_ONE
        }
    }

    fun setShuffle(enabled: Boolean) {
        controller?.shuffleModeEnabled = enabled
    }

    fun release() {
        pollingJob?.cancel()
        pollingJob = null
        controller?.release()
        controller = null
    }

    private fun startPolling() {
        pollingJob?.cancel()
        pollingJob = scope.launch {
            while (true) {
                val c = controller
                if (c != null) {
                    val duration = if (c.duration < 0) 0L else c.duration
                    _state.value = EnginePlaybackState(
                        currentIndex = c.currentMediaItemIndex,
                        isPlaying = c.isPlaying,
                        positionMs = c.currentPosition.coerceAtLeast(0L),
                        durationMs = duration
                    )
                }
                delay(500)
            }
        }
    }
}

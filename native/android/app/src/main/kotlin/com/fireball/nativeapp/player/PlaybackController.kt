package com.fireball.nativeapp.player

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
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
import java.util.concurrent.atomic.AtomicReference

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

    var onPlaybackError: ((String) -> Unit)? = null
    var onPlaybackEnded: (() -> Unit)? = null
    var onConnectFailed: ((String) -> Unit)? = null
    /** Fired when the active [MediaItem.mediaId] changes (for logical queue index mapping). */
    var onActiveMediaIdChanged: ((String?) -> Unit)? = null

    val isConnected: Boolean get() = controller != null

    private val engineEventsListener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            scope.launch {
                val c = controller ?: return@launch
                if (events.contains(Player.EVENT_MEDIA_ITEM_TRANSITION)) {
                    onActiveMediaIdChanged?.invoke(c.currentMediaItem?.mediaId)
                }
                if (events.contains(Player.EVENT_PLAYBACK_STATE_CHANGED) &&
                    player.playbackState == Player.STATE_ENDED
                ) {
                    onPlaybackEnded?.invoke()
                }
                if (events.hasEngineRelevantFlag()) {
                    pushControllerState(c)
                }
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            val msg = error.cause?.message ?: error.errorCodeName
            scope.launch { onPlaybackError?.invoke(msg) }
        }
    }

    private data class PendingPlay(val items: List<MediaItem>, val startIndex: Int)
    private val pendingPlay = AtomicReference<PendingPlay?>(null)
    private var pendingToggleOnConnect = false

    private fun ensurePlaybackServiceStarted() {
        val intent = Intent(context, NativePlaybackService::class.java)
        ContextCompat.startForegroundService(context, intent)
    }

    fun connect(onConnected: (() -> Unit)? = null) {
        if (controller != null) {
            onConnected?.invoke()
            return
        }
        ensurePlaybackServiceStarted()
        val token = SessionToken(context, ComponentName(context, NativePlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            try {
                controller = future.get()
                controller?.addListener(engineEventsListener)
                startPolling()
                pendingPlay.getAndSet(null)?.let { pending ->
                    applyPlayQueue(pending.items, pending.startIndex, startPositionMs = 0L)
                }
                onConnected?.invoke()
            } catch (t: Throwable) {
                controller = null
                pendingToggleOnConnect = false
                scope.launch {
                    onConnectFailed?.invoke(
                        t.message ?: "Could not connect to the playback service"
                    )
                }
            }
        }, MoreExecutors.directExecutor())
    }

    fun playQueue(items: List<MediaItem>, startIndex: Int) {
        applyPlayQueue(items, startIndex, startPositionMs = 0L, autoPlay = true)
    }

    /** Loads media into Exo without starting playback (session restore). */
    fun prepareQueue(items: List<MediaItem>, startIndex: Int) {
        applyPlayQueue(items, startIndex, startPositionMs = 0L, autoPlay = false)
    }

    /**
     * Replaces the Exo timeline, optionally keeping playback position (for background queue expand).
     */
    fun replaceMediaItems(items: List<MediaItem>, startIndex: Int, preservePosition: Boolean = false) {
        if (items.isEmpty()) return
        val c = controller
        if (c == null) {
            pendingPlay.set(PendingPlay(items, startIndex.coerceIn(0, items.lastIndex)))
            return
        }
        val position = if (preservePosition) c.currentPosition.coerceAtLeast(0L) else 0L
        applyPlayQueue(items, startIndex, position)
    }

    fun seekToMediaIndex(index: Int) {
        controller?.let { c ->
            if (index in 0 until c.mediaItemCount) {
                c.seekTo(index, 0L)
                c.play()
                pushControllerState(c)
            }
        }
    }

    /** Appends items to the Exo timeline without restarting the current track. */
    fun appendMediaItems(items: List<MediaItem>) {
        if (items.isEmpty()) return
        val c = controller ?: run {
            val last = pendingPlay.get()
            if (last != null) {
                pendingPlay.set(
                    PendingPlay(last.items + items, last.startIndex)
                )
            }
            return
        }
        c.addMediaItems(items)
        pushControllerState(c)
    }

    private fun applyPlayQueue(items: List<MediaItem>, startIndex: Int, startPositionMs: Long, autoPlay: Boolean) {
        val c = controller ?: run {
            pendingPlay.set(PendingPlay(items, startIndex.coerceIn(0, items.lastIndex)))
            return
        }
        val safeIndex = startIndex.coerceIn(0, items.lastIndex)
        c.setMediaItems(items, safeIndex, startPositionMs)
        c.prepare()
        if (autoPlay) c.play() else c.pause()
        pushControllerState(c)
        onActiveMediaIdChanged?.invoke(c.currentMediaItem?.mediaId)
    }

    private fun applyPlayQueue(items: List<MediaItem>, startIndex: Int, startPositionMs: Long) {
        applyPlayQueue(items, startIndex, startPositionMs, autoPlay = true)
    }

    private fun pushControllerState(c: MediaController) {
        val duration = if (c.duration < 0) 0L else c.duration
        _state.value = EnginePlaybackState(
            currentIndex = c.currentMediaItemIndex,
            isPlaying = c.isPlaying,
            positionMs = c.currentPosition.coerceAtLeast(0L),
            durationMs = duration
        )
    }

    fun togglePlayPause(): Boolean {
        val c = controller
        if (c == null) {
            if (!pendingToggleOnConnect) {
                pendingToggleOnConnect = true
                connect {
                    pendingToggleOnConnect = false
                    togglePlayPause()
                }
            }
            return false
        }
        if (c.isPlaying) c.pause() else c.play()
        pushControllerState(c)
        return true
    }

    fun pause() {
        controller?.let { c ->
            c.pause()
            pushControllerState(c)
        }
    }

    fun next() {
        controller?.let { c ->
            c.seekToNext()
            pushControllerState(c)
        }
    }

    fun previous() {
        controller?.let { c ->
            c.seekToPrevious()
            pushControllerState(c)
        }
    }

    fun seekTo(positionMs: Long) {
        controller?.let { c ->
            c.seekTo(positionMs)
            pushControllerState(c)
        }
    }

    fun setRepeatMode(mode: RepeatMode) {
        controller?.repeatMode = when (mode) {
            RepeatMode.OFF -> Player.REPEAT_MODE_OFF
            RepeatMode.ALL -> Player.REPEAT_MODE_ALL
            RepeatMode.ONE -> Player.REPEAT_MODE_ONE
        }
    }

    /** Shuffle order is handled in [MainViewModel]; Exo shuffle must stay off to avoid index skew. */
    fun setShuffle(@Suppress("UNUSED_PARAMETER") enabled: Boolean) {
        controller?.shuffleModeEnabled = false
    }

    fun release() {
        pollingJob?.cancel()
        pollingJob = null
        controller?.removeListener(engineEventsListener)
        controller?.release()
        controller = null
        pendingPlay.set(null)
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

private fun Player.Events.hasEngineRelevantFlag(): Boolean =
    contains(Player.EVENT_MEDIA_ITEM_TRANSITION) ||
        contains(Player.EVENT_PLAYBACK_STATE_CHANGED) ||
        contains(Player.EVENT_IS_PLAYING_CHANGED) ||
        contains(Player.EVENT_TIMELINE_CHANGED) ||
        contains(Player.EVENT_POSITION_DISCONTINUITY) ||
        contains(Player.EVENT_REPEAT_MODE_CHANGED) ||
        contains(Player.EVENT_SHUFFLE_MODE_ENABLED_CHANGED)

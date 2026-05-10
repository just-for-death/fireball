package com.fireball.nativeapp.player

import com.fireball.nativeapp.core.model.Track
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlin.random.Random

enum class RepeatMode { OFF, ALL, ONE }

data class PlaybackState(
    val queue: List<Track> = emptyList(),
    val currentIndex: Int = -1,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val shuffled: Boolean = false,
    val repeatMode: RepeatMode = RepeatMode.OFF,
    val sleepTimerEndEpochMs: Long? = null,
    val sleepAfterCurrent: Boolean = false
) {
    val currentTrack: Track?
        get() = queue.getOrNull(currentIndex)
}

class PlayerManager {
    private val _state = MutableStateFlow(PlaybackState())
    val state: StateFlow<PlaybackState> = _state

    fun playTracks(tracks: List<Track>, startIndex: Int = 0) {
        if (tracks.isEmpty()) return
        _state.value = PlaybackState(
            queue = tracks,
            currentIndex = startIndex.coerceIn(0, tracks.lastIndex),
            isPlaying = true
        )
    }

    fun togglePlayPause() {
        _state.update { it.copy(isPlaying = !it.isPlaying) }
    }

    fun next() {
        _state.update {
            if (it.queue.isEmpty()) return@update it
            if (it.repeatMode == RepeatMode.ONE) return@update it.copy(isPlaying = true)
            val nextIndex = when {
                it.shuffled -> Random.nextInt(it.queue.size)
                it.currentIndex < it.queue.lastIndex -> it.currentIndex + 1
                it.repeatMode == RepeatMode.ALL -> 0
                else -> it.currentIndex
            }
            val stillPlaying = nextIndex != it.currentIndex || it.repeatMode == RepeatMode.ALL
            it.copy(currentIndex = nextIndex, isPlaying = stillPlaying)
        }
    }

    fun previous() {
        _state.update {
            if (it.queue.isEmpty()) return@update it
            val previousIndex = (it.currentIndex - 1).coerceAtLeast(0)
            it.copy(currentIndex = previousIndex, isPlaying = true)
        }
    }

    fun toggleShuffle() {
        _state.update { it.copy(shuffled = !it.shuffled) }
    }

    fun toggleRepeatMode() {
        _state.update {
            val next = when (it.repeatMode) {
                RepeatMode.OFF -> RepeatMode.ALL
                RepeatMode.ALL -> RepeatMode.ONE
                RepeatMode.ONE -> RepeatMode.OFF
            }
            it.copy(repeatMode = next)
        }
    }

    fun setSleepTimer(minutes: Int?) {
        _state.update {
            it.copy(
                sleepTimerEndEpochMs = minutes?.let { m -> System.currentTimeMillis() + (m * 60_000L) },
                sleepAfterCurrent = false
            )
        }
    }

    fun setSleepAfterCurrent(enabled: Boolean) {
        _state.update { it.copy(sleepAfterCurrent = enabled, sleepTimerEndEpochMs = null) }
    }

    fun syncFromEngine(
        currentIndex: Int? = null,
        isPlaying: Boolean? = null,
        positionMs: Long? = null,
        durationMs: Long? = null
    ) {
        _state.update {
            it.copy(
                currentIndex = currentIndex ?: it.currentIndex,
                isPlaying = isPlaying ?: it.isPlaying,
                positionMs = positionMs ?: it.positionMs,
                durationMs = durationMs ?: it.durationMs
            )
        }
    }

    fun appendToQueue(tracks: List<Track>) {
        if (tracks.isEmpty()) return
        _state.update { current ->
            val merged = (current.queue + tracks).distinctBy { it.effectiveId }
            current.copy(queue = merged)
        }
    }
}

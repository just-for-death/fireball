package com.fireball.nativeapp.player

import com.fireball.nativeapp.core.model.Track
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

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
    val sleepTimerPresetMinutes: Int? = null,
    val sleepAfterCurrent: Boolean = false,
) {
    val currentTrack: Track?
        get() = queue.getOrNull(currentIndex)
}

class PlayerManager {
    private val _state = MutableStateFlow(PlaybackState())
    val state: StateFlow<PlaybackState> = _state

    fun restoreSession(
        queue: List<Track>,
        currentIndex: Int,
        shuffled: Boolean,
        repeatMode: RepeatMode,
    ) {
        if (queue.isEmpty()) return
        val safeIndex =
            if (currentIndex < 0) {
                -1
            } else {
                currentIndex.coerceIn(0, queue.lastIndex)
            }
        _state.value = PlaybackState(
            queue = queue,
            currentIndex = safeIndex,
            shuffled = shuffled,
            repeatMode = repeatMode,
            isPlaying = false,
        )
    }

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
            // Shuffle order is owned by ExoPlayer; [MainViewModel] advances the controller and
            // [syncFromEngine] updates currentIndex from the engine.
            if (it.shuffled) return@update it
            val nextIndex = when {
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
            if (it.shuffled) return@update it
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
                sleepTimerPresetMinutes = minutes,
                sleepAfterCurrent = false,
            )
        }
    }

    fun setSleepAfterCurrent(enabled: Boolean) {
        _state.update {
            it.copy(
                sleepAfterCurrent = enabled,
                sleepTimerEndEpochMs = null,
                sleepTimerPresetMinutes = null,
            )
        }
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

    fun insertTracksAt(insertIndex: Int, tracks: List<Track>) {
        if (tracks.isEmpty()) return
        _state.update { st ->
            val idx = insertIndex.coerceIn(0, st.queue.size)
            val merged = st.queue.toMutableList()
            merged.addAll(idx, tracks)
            st.copy(queue = merged)
        }
    }

    /** Appends tracks to the end of the queue (allows duplicates). */
    fun appendToQueue(tracks: List<Track>) {
        if (tracks.isEmpty()) return
        _state.update { current ->
            current.copy(queue = current.queue + tracks)
        }
    }

    /** Replaces the logical queue (e.g. after resolving URLs) while preserving shuffle/repeat/sleep. */
    fun replaceQueue(tracks: List<Track>, currentIndex: Int) {
        if (tracks.isEmpty()) return
        _state.update { old ->
            old.copy(
                queue = tracks,
                currentIndex = currentIndex.coerceIn(0, tracks.lastIndex),
                isPlaying = true
            )
        }
    }

    /** Maps Exo [mediaId] (track effectiveId) back to the logical queue index. */
    fun setCurrentIndexByMediaId(mediaId: String?) {
        if (mediaId.isNullOrBlank()) return
        _state.update { st ->
            val idx = st.queue.indexOfFirst { it.effectiveId == mediaId || it.id == mediaId }
            if (idx < 0) st else st.copy(currentIndex = idx, isPlaying = true)
        }
    }

    fun updateTrackAt(index: Int, track: Track) {
        _state.update { st ->
            if (index !in st.queue.indices) return@update st
            val updated = st.queue.toMutableList()
            updated[index] = track
            st.copy(queue = updated)
        }
    }

    /** Updates logical index without replacing the queue list. */
    fun setCurrentIndex(index: Int) {
        _state.update { st ->
            if (index !in st.queue.indices) return@update st
            st.copy(currentIndex = index, isPlaying = true)
        }
    }

    /** Replaces queue entries with resolved tracks (same order / size). */
    fun updateQueueTracks(tracks: List<Track>, currentIndex: Int) {
        if (tracks.isEmpty()) return
        _state.update { old ->
            old.copy(
                queue = tracks,
                currentIndex = currentIndex.coerceIn(0, tracks.lastIndex),
            )
        }
    }

    /** Stops playback and clears the logical queue (mini-player close / quit). */
    fun clearPlaybackSession() {
        _state.value = PlaybackState()
    }
}

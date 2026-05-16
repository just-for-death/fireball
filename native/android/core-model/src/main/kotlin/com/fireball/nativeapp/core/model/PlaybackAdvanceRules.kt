package com.fireball.nativeapp.core.model

/**
 * Shared queue advance decisions for native players (parity with iOS [PlaybackAdvanceRules]).
 */
enum class PlaybackRepeatMode {
    OFF,
    ALL,
    ONE,
    ;

    companion object {
        fun fromPersisted(value: String): PlaybackRepeatMode =
            when (value.trim().uppercase()) {
                "ALL" -> ALL
                "ONE" -> ONE
                else -> OFF
            }
    }
}

sealed class PlaybackAdvanceDecision {
    data object RestartCurrent : PlaybackAdvanceDecision()

    data class JumpToIndex(val index: Int) : PlaybackAdvanceDecision()

    data object StopPlayback : PlaybackAdvanceDecision()

    /** Next pressed at tail with no wrap (no-op). */
    data object NoOp : PlaybackAdvanceDecision()
}

object PlaybackAdvanceRules {
    fun afterTrackFinished(
        currentIndex: Int,
        queueSize: Int,
        repeatMode: PlaybackRepeatMode,
        shuffled: Boolean,
        queueModeRepeat: Boolean,
        pickShuffleIndex: (List<Int>) -> Int?,
    ): PlaybackAdvanceDecision {
        if (currentIndex < 0 || queueSize <= 0) return PlaybackAdvanceDecision.NoOp
        if (repeatMode == PlaybackRepeatMode.ONE) return PlaybackAdvanceDecision.RestartCurrent
        if (shuffled && queueSize > 1) {
            val choices = (0 until queueSize).filter { it != currentIndex }
            val next = pickShuffleIndex(choices)
            return if (next != null) PlaybackAdvanceDecision.JumpToIndex(next) else PlaybackAdvanceDecision.NoOp
        }
        if (currentIndex + 1 < queueSize) return PlaybackAdvanceDecision.JumpToIndex(currentIndex + 1)
        if (repeatMode == PlaybackRepeatMode.ALL) return PlaybackAdvanceDecision.JumpToIndex(0)
        if (queueModeRepeat) return PlaybackAdvanceDecision.JumpToIndex(0)
        return PlaybackAdvanceDecision.StopPlayback
    }

    fun userPressedNext(
        currentIndex: Int,
        queueSize: Int,
        repeatMode: PlaybackRepeatMode,
        shuffled: Boolean,
        queueModeRepeat: Boolean,
        pickShuffleIndex: (List<Int>) -> Int?,
    ): PlaybackAdvanceDecision {
        if (currentIndex < 0 || queueSize <= 0) return PlaybackAdvanceDecision.NoOp
        if (repeatMode == PlaybackRepeatMode.ONE) return PlaybackAdvanceDecision.RestartCurrent
        if (shuffled && queueSize > 1) {
            val choices = (0 until queueSize).filter { it != currentIndex }
            val next = pickShuffleIndex(choices)
            return if (next != null) PlaybackAdvanceDecision.JumpToIndex(next) else PlaybackAdvanceDecision.NoOp
        }
        if (currentIndex + 1 < queueSize) return PlaybackAdvanceDecision.JumpToIndex(currentIndex + 1)
        if (repeatMode == PlaybackRepeatMode.ALL) return PlaybackAdvanceDecision.JumpToIndex(0)
        if (queueModeRepeat) return PlaybackAdvanceDecision.JumpToIndex(0)
        return PlaybackAdvanceDecision.NoOp
    }

    fun userPressedPrevious(
        currentIndex: Int,
        positionSeconds: Double,
        repeatMode: PlaybackRepeatMode,
        shuffled: Boolean,
        queueSize: Int,
        pickShuffleIndex: (List<Int>) -> Int?,
    ): PlaybackAdvanceDecision {
        if (currentIndex < 0 || queueSize <= 0) return PlaybackAdvanceDecision.NoOp
        if (repeatMode == PlaybackRepeatMode.ONE) return PlaybackAdvanceDecision.RestartCurrent
        if (positionSeconds > 3.0) return PlaybackAdvanceDecision.RestartCurrent
        if (shuffled && queueSize > 1) {
            val choices = (0 until queueSize).filter { it != currentIndex }
            val pick = pickShuffleIndex(choices)
            return if (pick != null) PlaybackAdvanceDecision.JumpToIndex(pick) else PlaybackAdvanceDecision.NoOp
        }
        return PlaybackAdvanceDecision.JumpToIndex((currentIndex - 1).coerceAtLeast(0))
    }
}

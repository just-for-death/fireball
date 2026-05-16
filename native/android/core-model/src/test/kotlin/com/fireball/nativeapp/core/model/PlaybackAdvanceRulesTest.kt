package com.fireball.nativeapp.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackAdvanceRulesTest {
    @Test
    fun afterTrackFinished_repeatOneRestarts() {
        val decision = PlaybackAdvanceRules.afterTrackFinished(
            currentIndex = 2,
            queueSize = 5,
            repeatMode = PlaybackRepeatMode.ONE,
            shuffled = false,
            queueModeRepeat = false,
            pickShuffleIndex = { null },
        )
        assertEquals(PlaybackAdvanceDecision.RestartCurrent, decision)
    }

    @Test
    fun afterTrackFinished_shufflePicksOtherIndex() {
        val decision = PlaybackAdvanceRules.afterTrackFinished(
            currentIndex = 0,
            queueSize = 3,
            repeatMode = PlaybackRepeatMode.OFF,
            shuffled = true,
            queueModeRepeat = false,
            pickShuffleIndex = { choices -> choices.first { it == 2 } },
        )
        assertEquals(PlaybackAdvanceDecision.JumpToIndex(2), decision)
    }

    @Test
    fun afterTrackFinished_queueModeRepeatWrapsAtTail() {
        val decision = PlaybackAdvanceRules.afterTrackFinished(
            currentIndex = 2,
            queueSize = 3,
            repeatMode = PlaybackRepeatMode.OFF,
            shuffled = false,
            queueModeRepeat = true,
            pickShuffleIndex = { null },
        )
        assertEquals(PlaybackAdvanceDecision.JumpToIndex(0), decision)
    }

    @Test
    fun afterTrackFinished_stopsAtTailWhenNoRepeat() {
        val decision = PlaybackAdvanceRules.afterTrackFinished(
            currentIndex = 2,
            queueSize = 3,
            repeatMode = PlaybackRepeatMode.OFF,
            shuffled = false,
            queueModeRepeat = false,
            pickShuffleIndex = { null },
        )
        assertEquals(PlaybackAdvanceDecision.StopPlayback, decision)
    }

    @Test
    fun userPressedNext_repeatAllWrapsAtTail() {
        val decision = PlaybackAdvanceRules.userPressedNext(
            currentIndex = 4,
            queueSize = 5,
            repeatMode = PlaybackRepeatMode.ALL,
            shuffled = false,
            queueModeRepeat = false,
            pickShuffleIndex = { null },
        )
        assertEquals(PlaybackAdvanceDecision.JumpToIndex(0), decision)
    }

    @Test
    fun userPressedNext_noOpAtTailWithoutWrap() {
        val decision = PlaybackAdvanceRules.userPressedNext(
            currentIndex = 4,
            queueSize = 5,
            repeatMode = PlaybackRepeatMode.OFF,
            shuffled = false,
            queueModeRepeat = false,
            pickShuffleIndex = { null },
        )
        assertTrue(decision is PlaybackAdvanceDecision.NoOp)
    }

    @Test
    fun userPressedPrevious_repeatOneRestarts() {
        val decision = PlaybackAdvanceRules.userPressedPrevious(
            currentIndex = 1,
            positionSeconds = 10.0,
            repeatMode = PlaybackRepeatMode.ONE,
            shuffled = false,
            queueSize = 5,
            pickShuffleIndex = { null },
        )
        assertEquals(PlaybackAdvanceDecision.RestartCurrent, decision)
    }

    @Test
    fun userPressedPrevious_goesToEarlierTrackWhenNearStart() {
        val decision = PlaybackAdvanceRules.userPressedPrevious(
            currentIndex = 2,
            positionSeconds = 1.0,
            repeatMode = PlaybackRepeatMode.OFF,
            shuffled = false,
            queueSize = 5,
            pickShuffleIndex = { null },
        )
        assertEquals(PlaybackAdvanceDecision.JumpToIndex(1), decision)
    }

    @Test
    fun userPressedPrevious_restartsWhenPastThreeSeconds() {
        val decision = PlaybackAdvanceRules.userPressedPrevious(
            currentIndex = 2,
            positionSeconds = 4.0,
            repeatMode = PlaybackRepeatMode.OFF,
            shuffled = false,
            queueSize = 5,
            pickShuffleIndex = { null },
        )
        assertEquals(PlaybackAdvanceDecision.RestartCurrent, decision)
    }
}

package com.fireball.nativeapp.core.model

/**
 * Client-side scrobble timing (ListenBrainz + Last.fm).
 *
 * Fires when **either** [percent] of the track or [maxSeconds] elapsed is reached first.
 * Tracks shorter than [minTrackSeconds] are never scrobbled (Last.fm minimum; common LB clients).
 *
 * ListenBrainz documents submission at half the track or 4 minutes (whichever is lower);
 * Fireball defaults (25% / 40s) are more conservative and user-tunable in settings.
 */
object ScrobbleRules {
    fun shouldScrobble(
        positionMs: Long,
        durationMs: Long,
        percent: Int,
        maxSeconds: Int,
        minTrackSeconds: Int = DEFAULT_MIN_TRACK_SECONDS,
    ): Boolean {
        if (durationMs <= 0L) return false
        val minMs = minTrackSeconds.coerceAtLeast(1) * 1000L
        if (durationMs < minMs) return false
        val pct = percent.coerceIn(0, 100)
        val maxSec = maxSeconds.coerceAtLeast(0)
        val byPercent = pct > 0 && positionMs >= (durationMs * pct / 100.0).toLong()
        val byMaxSec = maxSec > 0 && positionMs >= maxSec * 1000L
        return byPercent || byMaxSec
    }

    const val DEFAULT_MIN_TRACK_SECONDS = 30
    const val DEFAULT_PERCENT = 25
    const val DEFAULT_MAX_SECONDS = 40
}

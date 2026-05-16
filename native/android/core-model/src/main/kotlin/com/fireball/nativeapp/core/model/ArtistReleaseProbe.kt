package com.fireball.nativeapp.core.model

/**
 * Pure helpers for followed-artist iTunes release polling (Android + iOS parity).
 */
object ArtistReleaseProbe {
    data class AlbumHit(
        val collectionId: String,
        val collectionName: String,
    )

    enum class ReleaseOutcome {
        /** No library row change. */
        Unchanged,
        /** First baseline stored (no user notification). */
        BaselineStored,
        /** New release detected; notify channels. */
        NotifyNewRelease,
    }

    data class ReleaseEvaluation(
        val artist: Artist,
        val outcome: ReleaseOutcome,
    )

    fun resolveNumericItunesArtistId(
        storedArtistId: String,
        artistName: String,
        lookupByName: (String) -> Int?,
    ): Int? =
        storedArtistId.toIntOrNull() ?: lookupByName(artistName.trim())

    fun evaluateNewRelease(
        artist: Artist,
        resolvedArtistId: String,
        latestAlbum: AlbumHit?,
    ): ReleaseEvaluation {
        var working = artist
        if (resolvedArtistId != artist.artistId) {
            working = artist.copy(artistId = resolvedArtistId)
        }
        val hit = latestAlbum ?: return ReleaseEvaluation(working, ReleaseOutcome.Unchanged)
        if (hit.collectionId == working.latestReleaseId) {
            return ReleaseEvaluation(working, ReleaseOutcome.Unchanged)
        }
        val updated = working.copy(latestReleaseId = hit.collectionId)
        return if (working.latestReleaseId == null) {
            ReleaseEvaluation(updated, ReleaseOutcome.BaselineStored)
        } else {
            ReleaseEvaluation(updated, ReleaseOutcome.NotifyNewRelease)
        }
    }

    fun notificationCopy(artistName: String, albumName: String): Pair<String, String> {
        val title = "New Release from $artistName"
        val message = "$albumName is out now!"
        return title to message
    }
}

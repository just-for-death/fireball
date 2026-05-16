package com.fireball.nativeapp.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ArtistReleaseProbeTest {
    @Test
    fun resolveNumericId_prefersStoredNumeric() {
        val id = ArtistReleaseProbe.resolveNumericItunesArtistId(
            storedArtistId = "12345",
            artistName = "Artist",
            lookupByName = { error("should not call") },
        )
        assertEquals(12345, id)
    }

    @Test
    fun resolveNumericId_fallsBackToLookup() {
        val id = ArtistReleaseProbe.resolveNumericItunesArtistId(
            storedArtistId = "Taylor Swift",
            artistName = "Taylor Swift",
            lookupByName = { 999 },
        )
        assertEquals(999, id)
    }

    @Test
    fun resolveNumericId_returnsNullWhenLookupFails() {
        val id = ArtistReleaseProbe.resolveNumericItunesArtistId(
            storedArtistId = "unknown",
            artistName = "Nobody",
            lookupByName = { null },
        )
        assertNull(id)
    }

    @Test
    fun evaluateNewRelease_storesBaselineWithoutNotify() {
        val artist = Artist(artistId = "1", name = "A", artwork = null, latestReleaseId = null)
        val eval = ArtistReleaseProbe.evaluateNewRelease(
            artist = artist,
            resolvedArtistId = "1",
            latestAlbum = ArtistReleaseProbe.AlbumHit("album-1", "First Album"),
        )
        assertEquals(ArtistReleaseProbe.ReleaseOutcome.BaselineStored, eval.outcome)
        assertEquals("album-1", eval.artist.latestReleaseId)
    }

    @Test
    fun evaluateNewRelease_notifiesWhenReleaseChanges() {
        val artist = Artist(artistId = "1", name = "A", artwork = null, latestReleaseId = "old")
        val eval = ArtistReleaseProbe.evaluateNewRelease(
            artist = artist,
            resolvedArtistId = "1",
            latestAlbum = ArtistReleaseProbe.AlbumHit("new", "New Album"),
        )
        assertEquals(ArtistReleaseProbe.ReleaseOutcome.NotifyNewRelease, eval.outcome)
        assertEquals("new", eval.artist.latestReleaseId)
    }

    @Test
    fun evaluateNewRelease_unchangedWhenSameRelease() {
        val artist = Artist(artistId = "1", name = "A", artwork = null, latestReleaseId = "same")
        val eval = ArtistReleaseProbe.evaluateNewRelease(
            artist = artist,
            resolvedArtistId = "1",
            latestAlbum = ArtistReleaseProbe.AlbumHit("same", "Same Album"),
        )
        assertEquals(ArtistReleaseProbe.ReleaseOutcome.Unchanged, eval.outcome)
    }

    @Test
    fun evaluateNewRelease_updatesStoredIdWhenResolved() {
        val artist = Artist(artistId = "name-only", name = "A", artwork = null, latestReleaseId = null)
        val eval = ArtistReleaseProbe.evaluateNewRelease(
            artist = artist,
            resolvedArtistId = "42",
            latestAlbum = ArtistReleaseProbe.AlbumHit("album-1", "Album"),
        )
        assertEquals("42", eval.artist.artistId)
        assertEquals(ArtistReleaseProbe.ReleaseOutcome.BaselineStored, eval.outcome)
    }
}

package com.fireball.nativeapp.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

class ArtistNameParserTest {
    @Test
    fun singleArtist_unchanged() {
        assertEquals(listOf("Taylor Swift"), ArtistNameParser.splitArtists("Taylor Swift"))
    }

    @Test
    fun ampersand_and_comma() {
        assertEquals(
            listOf("Ella Langley", "Riley Green"),
            ArtistNameParser.splitArtists("Ella Langley & Riley Green"),
        )
        assertEquals(
            listOf("A", "B", "C"),
            ArtistNameParser.splitArtists("A, B, C"),
        )
    }

    @Test
    fun feat_variants() {
        assertEquals(
            listOf("Post Malone", "Swae Lee"),
            ArtistNameParser.splitArtists("Post Malone feat. Swae Lee"),
        )
        assertEquals(
            listOf("Artist One", "Artist Two"),
            ArtistNameParser.splitArtists("Artist One featuring Artist Two"),
        )
    }

    @Test
    fun x_separator_requires_spaces() {
        assertEquals(
            listOf("John", "Jane"),
            ArtistNameParser.splitArtists("John x Jane"),
        )
        assertEquals(listOf("Gen X"), ArtistNameParser.splitArtists("Gen X"))
    }
}

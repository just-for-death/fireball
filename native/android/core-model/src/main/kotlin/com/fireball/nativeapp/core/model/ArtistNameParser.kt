package com.fireball.nativeapp.core.model

/**
 * Splits a display artist line (e.g. "A feat. B & C") into individual artist names.
 */
object ArtistNameParser {
    private val SEPARATOR =
        Regex(
            """(?i)\s*(?:,|&|/|\||;|\+)\s*|\s+(?:feat\.?|ft\.?|featuring|with|vs\.?)\s+|\s+x\s+""",
        )

    fun splitArtists(raw: String): List<String> {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return emptyList()
        return SEPARATOR.split(trimmed)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinctBy { it.lowercase() }
    }
}

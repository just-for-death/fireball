package com.fireball.nativeapp.core.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LrcParserTest {
    @Test
    fun parseSingleTimestampLine() {
        val lines = LrcParser.parse("[00:12.50] Hello world")
        assertEquals(1, lines.size)
        assertEquals(12_500L, lines[0].timeMs)
        assertEquals("Hello world", lines[0].text)
    }

    @Test
    fun parseMultipleTimestampsOnOneLine() {
        val lines = LrcParser.parse("[00:01.00][00:05.00] Same lyric")
        assertEquals(2, lines.size)
        assertEquals("Same lyric", lines[0].text)
        assertEquals("Same lyric", lines[1].text)
        assertEquals(1_000L, lines[0].timeMs)
        assertEquals(5_000L, lines[1].timeMs)
    }

    @Test
    fun skipsMetadataTags() {
        val lines = LrcParser.parse("[ar:Artist]\n[00:10.00] Sing")
        assertEquals(1, lines.size)
        assertEquals("Sing", lines[0].text)
    }

    @Test
    fun hasSyncedTimestamps() {
        assertTrue(LrcParser.hasSyncedTimestamps("[00:00.00] Start"))
    }
}

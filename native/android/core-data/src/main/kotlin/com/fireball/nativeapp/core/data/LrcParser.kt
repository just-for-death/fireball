package com.fireball.nativeapp.core.data

/**
 * Parses LRC synced lyrics ([mm:ss.xx] lines) for auto-scroll during playback.
 */
data class LrcLine(val timeMs: Long, val text: String)

object LrcParser {
    private val lineRegex = Regex("""\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?]\s*(.*)""")

    fun parse(raw: String): List<LrcLine> {
        val lines = raw.lineSequence()
            .mapNotNull { line ->
                val match = lineRegex.matchEntire(line.trim()) ?: return@mapNotNull null
                val min = match.groupValues[1].toLongOrNull() ?: return@mapNotNull null
                val sec = match.groupValues[2].toLongOrNull() ?: return@mapNotNull null
                val frac = match.groupValues[3]
                val msFrac = when {
                    frac.isBlank() -> 0L
                    frac.length == 2 -> frac.toLongOrNull()?.times(10) ?: 0L
                    else -> frac.take(3).padEnd(3, '0').toLongOrNull() ?: 0L
                }
                val timeMs = (min * 60_000) + (sec * 1_000) + msFrac
                LrcLine(timeMs = timeMs, text = match.groupValues[4].trim())
            }
            .filter { it.text.isNotBlank() }
            .toList()
        return lines.sortedBy { it.timeMs }
    }

    fun hasSyncedTimestamps(raw: String): Boolean = parse(raw).isNotEmpty()

    fun activeLineIndex(lines: List<LrcLine>, positionMs: Long): Int {
        if (lines.isEmpty()) return -1
        var idx = -1
        for (i in lines.indices) {
            if (lines[i].timeMs <= positionMs) idx = i else break
        }
        return idx
    }
}

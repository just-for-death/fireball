package com.fireball.nativeapp.core.data

/**
 * Parses LRC synced lyrics ([mm:ss.xx] lines) for auto-scroll during playback.
 */
data class LrcLine(val timeMs: Long, val text: String)

object LrcParser {
    private val timestampRegex = Regex("""\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?]""")

    fun parse(raw: String): List<LrcLine> {
        val out = mutableListOf<LrcLine>()
        for (line in raw.lineSequence()) {
            out.addAll(parseLine(line))
        }
        return out.sortedBy { it.timeMs }
    }

    private fun parseLine(line: String): List<LrcLine> {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) return emptyList()
        val matches = timestampRegex.findAll(trimmed).toList()
        if (matches.isEmpty()) return emptyList()
        val last = matches.last()
        val text = trimmed.substring(last.range.last + 1).trim()
        if (text.isEmpty()) return emptyList()
        return matches.mapNotNull { match ->
            val min = match.groupValues[1].toLongOrNull() ?: return@mapNotNull null
            val sec = match.groupValues[2].toLongOrNull() ?: return@mapNotNull null
            val frac = match.groupValues[3]
            val msFrac =
                when {
                    frac.isBlank() -> 0L
                    frac.length == 2 -> frac.toLongOrNull()?.times(10) ?: 0L
                    else -> frac.take(3).padEnd(3, '0').toLongOrNull() ?: 0L
                }
            LrcLine(timeMs = (min * 60_000) + (sec * 1_000) + msFrac, text = text)
        }
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

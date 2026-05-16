package com.fireball.nativeapp.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.core.data.LrcParser

@Composable
fun SyncedLyricsView(
    lyrics: String,
    positionMs: Long,
    autoScroll: Boolean,
    reducedMotion: Boolean,
    textColor: Color,
    accentColor: Color,
    modifier: Modifier = Modifier,
    /** When set (e.g. tablet split-pane), expands the synced lyrics viewport. */
    maxContentHeight: Dp? = null,
) {
    val lines = remember(lyrics) { LrcParser.parse(lyrics) }
    val synced = lines.isNotEmpty()
    val activeIndex = remember(lines, positionMs) {
        if (synced) LrcParser.activeLineIndex(lines, positionMs) else -1
    }
    val listState = rememberLazyListState()

    LaunchedEffect(activeIndex, autoScroll, reducedMotion) {
        if (!synced || !autoScroll || reducedMotion || activeIndex < 0) return@LaunchedEffect
        listState.animateScrollToItem(activeIndex)
    }

    val cap = maxContentHeight
        ?: if (reducedMotion) 80.dp else 140.dp
    LazyColumn(
        state = listState,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(max = cap),
    ) {
        if (synced) {
            itemsIndexed(lines, key = { index, line -> "$index-${line.timeMs}" }) { index, line ->
                Text(
                    text = line.text,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (index == activeIndex) FontWeight.Bold else FontWeight.Normal,
                    color = if (index == activeIndex) accentColor else textColor.copy(alpha = 0.75f),
                )
            }
        } else {
            item(key = "plain") {
                Text(
                    text = lyrics,
                    style = MaterialTheme.typography.bodySmall,
                    color = textColor.copy(alpha = 0.85f),
                )
            }
        }
    }
}

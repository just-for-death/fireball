package com.fireball.nativeapp.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fireball.nativeapp.core.data.LrcParser
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first

@Composable
fun SyncedLyricsView(
    lyrics: String,
    positionMs: Long,
    autoScroll: Boolean,
    reducedMotion: Boolean,
    textColor: Color,
    accentColor: Color,
    modifier: Modifier = Modifier,
    maxContentHeight: Dp? = null,
) {
    val lines = remember(lyrics) { LrcParser.parse(lyrics) }
    val synced = lines.isNotEmpty()
    val activeIndex = remember(lines, positionMs) {
        if (synced) LrcParser.activeLineIndex(lines, positionMs) else -1
    }
    val listState = rememberLazyListState()

    LaunchedEffect(activeIndex, autoScroll, reducedMotion, synced) {
        if (!synced || !autoScroll || reducedMotion || activeIndex < 0) return@LaunchedEffect
        snapshotFlow { listState.layoutInfo.totalItemsCount }
            .filter { it > activeIndex }
            .first()
        val layout = listState.layoutInfo
        val viewport = (layout.viewportEndOffset - layout.viewportStartOffset).coerceAtLeast(1)
        val item = layout.visibleItemsInfo.find { it.index == activeIndex }
        val itemHeight = item?.size ?: (viewport / 6)
        val centerOffset = ((viewport - itemHeight) / 2).coerceAtLeast(0)
        listState.animateScrollToItem(activeIndex, scrollOffset = -centerOffset)
    }

    val cap = maxContentHeight ?: if (reducedMotion) 80.dp else 140.dp
    val heightMod =
        if (maxContentHeight != null && maxContentHeight >= 200.dp) {
            Modifier.fillMaxSize()
        } else {
            Modifier.heightIn(max = cap)
        }

    Box(
        modifier = modifier.then(heightMod),
        contentAlignment = Alignment.Center,
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 12.dp),
        ) {
            if (synced) {
                itemsIndexed(lines, key = { index, line -> "$index-${line.timeMs}" }) { index, line ->
                    val distance = if (activeIndex < 0) 3 else kotlin.math.abs(index - activeIndex)
                    val targetAlpha =
                        when {
                            index == activeIndex -> 1f
                            distance == 1 -> 0.62f
                            distance == 2 -> 0.45f
                            else -> 0.28f
                        }
                    val alpha by animateFloatAsState(
                        targetValue = targetAlpha,
                        animationSpec = tween(durationMillis = if (reducedMotion) 0 else 220),
                        label = "lyricAlpha",
                    )
                    val isActive = index == activeIndex
                    Text(
                        text = line.text,
                        style =
                            if (isActive) {
                                MaterialTheme.typography.titleMedium
                            } else {
                                MaterialTheme.typography.bodyMedium
                            },
                        fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (isActive) accentColor else textColor,
                        textAlign = TextAlign.Center,
                        lineHeight = if (isActive) 26.sp else 20.sp,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .alpha(alpha)
                                .padding(vertical = 6.dp, horizontal = 4.dp),
                    )
                }
            } else {
                item(key = "plain") {
                    Text(
                        text = lyrics,
                        style = MaterialTheme.typography.bodyMedium,
                        color = textColor.copy(alpha = 0.88f),
                        textAlign = TextAlign.Center,
                        lineHeight = 22.sp,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 8.dp, vertical = 8.dp),
                    )
                }
            }
        }
    }
}

package com.fireball.nativeapp.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fireball.nativeapp.core.data.LrcParser
import com.fireball.nativeapp.ui.theme.MotionTokens
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlin.math.abs

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
    onSeekToMs: ((Long) -> Unit)? = null,
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
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 20.dp),
        ) {
            if (synced) {
                itemsIndexed(lines, key = { index, line -> "$index-${line.timeMs}" }) { index, line ->
                    CascadeLyricLine(
                        text = line.text,
                        index = index,
                        activeIndex = activeIndex,
                        reducedMotion = reducedMotion,
                        textColor = textColor,
                        accentColor = accentColor,
                        onSeek = onSeekToMs?.let { seek -> { seek(line.timeMs) } },
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

@Composable
private fun CascadeLyricLine(
    text: String,
    index: Int,
    activeIndex: Int,
    reducedMotion: Boolean,
    textColor: Color,
    accentColor: Color,
    onSeek: (() -> Unit)?,
) {
    val distance = if (activeIndex < 0) 3 else index - activeIndex
    val absDistance = abs(distance)
    val isActive = distance == 0 && activeIndex >= 0

    val targetAlpha =
        when {
            isActive -> 1f
            absDistance == 1 -> 0.48f
            absDistance == 2 -> 0.32f
            else -> 0.2f
        }
    val targetOffsetY =
        if (reducedMotion || activeIndex < 0) 0f else distance * 18f
    val targetScale =
        when {
            reducedMotion || activeIndex < 0 -> 1f
            isActive -> 1.08f
            else -> (1f - absDistance * 0.045f).coerceIn(0.8f, 0.94f)
        }
    val staggerMs = if (reducedMotion) 0 else absDistance * 40

    val alpha by animateFloatAsState(
        targetValue = targetAlpha,
        animationSpec =
            tween(
                durationMillis = if (reducedMotion) 0 else 280,
                delayMillis = staggerMs,
                easing = MotionTokens.EmphasizedDecelerate,
            ),
        label = "lyricAlpha",
    )
    val offsetY by animateFloatAsState(
        targetValue = targetOffsetY,
        animationSpec =
            tween(
                durationMillis = if (reducedMotion) 0 else 320,
                delayMillis = staggerMs,
                easing = MotionTokens.EmphasizedDecelerate,
            ),
        label = "lyricOffset",
    )
    val scale by animateFloatAsState(
        targetValue = targetScale,
        animationSpec =
            tween(
                durationMillis = if (reducedMotion) 0 else 320,
                delayMillis = staggerMs,
                easing = MotionTokens.EmphasizedDecelerate,
            ),
        label = "lyricScale",
    )

    val lineModifier =
        Modifier
            .fillMaxWidth()
            .graphicsLayer {
                translationY = offsetY
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
            }
            .padding(vertical = 3.dp, horizontal = 4.dp)
            .then(
                if (onSeek != null) Modifier.clickable(onClick = onSeek) else Modifier,
            )

    if (isActive) {
        Box(
            modifier =
                lineModifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(accentColor.copy(alpha = 0.2f))
                    .padding(vertical = 10.dp, horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = accentColor,
                textAlign = TextAlign.Center,
                lineHeight = 32.sp,
            )
        }
    } else {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (absDistance == 1) FontWeight.Medium else FontWeight.Normal,
            color = textColor,
            textAlign = TextAlign.Center,
            lineHeight = 22.sp,
            modifier = lineModifier.padding(vertical = 6.dp, horizontal = 10.dp),
        )
    }
}

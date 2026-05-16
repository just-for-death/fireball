@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.fireball.nativeapp.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.ui.theme.DominantColors
import com.fireball.nativeapp.ui.components.AlbumArt
import com.fireball.nativeapp.util.ImageUtils
import com.fireball.nativeapp.core.model.Track

/** Layout mode for phones, tablets, and icon-only navigation rails (iPad-style). */
enum class PillMiniPlayerLayout {
    /** Standard bottom bar horizontal pill. */
    Phone,

    /** Wider typography and larger art inside the sidebar. */
    TabletRail,

    /**
     * Stack art + compact controls vertically for narrow icon-only rails
     * so content does not clip.
     */
    NarrowRailStack,
}

/**
 * Pill-shaped mini-player with a circular dashed-arc progress ring around
 * the album art. Port of
 * `app/.../ui/components/player/miniplayer/PillMiniPlayer.kt`.
 *
 * Same `PlayerState` → `isPlaying: Boolean` simplification as
 * [StandardMiniPlayer]. See the docstring there for rationale.
 */
@Composable
fun PillMiniPlayer(
    song: Track,
    isPlaying: Boolean,
    dominantColors: DominantColors,
    progress: Float,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onClose: () -> Unit,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
    onPrevious: () -> Unit = {},
    onLongPressMenu: () -> Unit = {},
    layout: PillMiniPlayerLayout = PillMiniPlayerLayout.Phone,
    isLoading: Boolean = false,
    userAlpha: Float = 0f,
    artworkShape: String = "ROUNDED_SQUARE",
) {
    val effectiveAlpha = 1f - userAlpha

    val artShape: Shape = when (artworkShape) {
        "CIRCLE", "VINYL" -> CircleShape
        "SQUARE" -> RectangleShape
        else -> RoundedCornerShape(32.dp)
    }

    val highResThumbnail = remember(song.artwork) {
        ImageUtils.getHighResThumbnailUrl(song.artwork, size = 544)
    }

    val artOuter = when (layout) {
        PillMiniPlayerLayout.Phone -> 48.dp
        PillMiniPlayerLayout.TabletRail -> 56.dp
        PillMiniPlayerLayout.NarrowRailStack -> 44.dp
    }
    val horizontalPad = when (layout) {
        PillMiniPlayerLayout.TabletRail -> 14.dp
        PillMiniPlayerLayout.NarrowRailStack -> 8.dp
        else -> 12.dp
    }

    Surface(
        modifier = modifier
            .padding(horizontal = horizontalPad, vertical = if (layout == PillMiniPlayerLayout.NarrowRailStack) 6.dp else 4.dp)
            .clip(RoundedCornerShape(32.dp)),
        color = Color.Transparent,
        shape = RoundedCornerShape(32.dp),
        tonalElevation = when (layout) {
            PillMiniPlayerLayout.Phone -> 4.dp
            else -> 8.dp
        },
        shadowElevation = when (layout) {
            PillMiniPlayerLayout.Phone -> 6.dp
            else -> 10.dp
        },
    ) {
        Box(
            modifier = Modifier.background(
                brush = Brush.horizontalGradient(
                    colors = listOf(
                        dominantColors.primary.copy(alpha = effectiveAlpha),
                        dominantColors.secondary.copy(alpha = effectiveAlpha),
                    ),
                ),
            ),
        ) {
            @Composable
            fun ArtRing() {
                Box(
                    modifier = Modifier
                        .size(artOuter)
                        .padding(2.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    val activeColor = dominantColors.accent
                    val trackColor = dominantColors.onBackground.copy(alpha = 0.2f)

                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val strokeWidth = 2.dp.toPx()
                        val dashSize = 2.dp.toPx()
                        val gapSize = 3.dp.toPx()

                        drawArc(
                            color = trackColor,
                            startAngle = -90f,
                            sweepAngle = 360f,
                            useCenter = false,
                            style = Stroke(
                                width = strokeWidth,
                                cap = StrokeCap.Round,
                                pathEffect = PathEffect.dashPathEffect(
                                    floatArrayOf(dashSize, gapSize),
                                    0f,
                                ),
                            ),
                        )

                        drawArc(
                            color = activeColor,
                            startAngle = -90f,
                            sweepAngle = progress * 360f,
                            useCenter = false,
                            style = Stroke(
                                width = strokeWidth,
                                cap = StrokeCap.Round,
                                pathEffect = PathEffect.dashPathEffect(
                                    floatArrayOf(dashSize, gapSize),
                                    0f,
                                ),
                            ),
                        )
                    }

                    AlbumArt(
                        thumbnailUrl = highResThumbnail,
                        contentDescription = song.title,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(4.dp)
                            .clip(artShape),
                    )
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .align(Alignment.Center)
                                .size(22.dp),
                            color = dominantColors.accent,
                            strokeWidth = 2.dp,
                        )
                    }
                }
            }

            val hostView = LocalView.current
            val artMenuModifier = Modifier.miniPlayerMenuGestures(
                hostView = hostView,
                onTap = onTap,
                onLongPressMenu = onLongPressMenu,
            )
            val titleMenuModifier = Modifier.miniPlayerMenuGestures(
                hostView = hostView,
                onTap = onTap,
                onLongPressMenu = onLongPressMenu,
            )

            when (layout) {
                PillMiniPlayerLayout.NarrowRailStack -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 4.dp, vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Box(modifier = artMenuModifier) {
                            ArtRing()
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            MiniPlayerButton(
                                onClick = onPlayPause,
                                onBackgroundColor = dominantColors.onBackground,
                                size = 38.dp,
                            ) {
                                Icon(
                                    imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                    contentDescription = if (isPlaying) "Pause" else "Play",
                                    tint = dominantColors.onBackground,
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                            MiniPlayerButton(
                                onClick = onNext,
                                onBackgroundColor = dominantColors.onBackground,
                                size = 38.dp,
                            ) {
                                Icon(
                                    imageVector = Icons.Default.SkipNext,
                                    contentDescription = "Next",
                                    tint = dominantColors.onBackground,
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                        }
                        if (!isPlaying) {
                            Spacer(modifier = Modifier.height(4.dp))
                            MiniPlayerButton(
                                onClick = onClose,
                                onBackgroundColor = dominantColors.onBackground,
                                size = 32.dp,
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = "Close",
                                    tint = dominantColors.onBackground,
                                    modifier = Modifier.size(16.dp),
                                )
                            }
                        }
                    }
                }
                PillMiniPlayerLayout.Phone,
                PillMiniPlayerLayout.TabletRail,
                -> {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(modifier = artMenuModifier) {
                            ArtRing()
                        }
                        Spacer(modifier = Modifier.width(8.dp))

                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .then(titleMenuModifier),
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Text(
                                text = song.title,
                                style = when (layout) {
                                    PillMiniPlayerLayout.TabletRail -> MaterialTheme.typography.titleMedium
                                    else -> MaterialTheme.typography.titleSmall
                                },
                                color = dominantColors.onBackground,
                                maxLines = if (layout == PillMiniPlayerLayout.TabletRail) 2 else 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = if (layout == PillMiniPlayerLayout.TabletRail) Modifier else Modifier.basicMarquee(),
                            )
                            Text(
                                text = song.artist,
                                style = if (layout == PillMiniPlayerLayout.TabletRail) {
                                    MaterialTheme.typography.bodyMedium
                                } else {
                                    MaterialTheme.typography.bodySmall
                                },
                                color = dominantColors.onBackground.copy(alpha = 0.7f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }

                        if (layout == PillMiniPlayerLayout.TabletRail) {
                            MiniPlayerButton(
                                onClick = onPrevious,
                                onBackgroundColor = dominantColors.onBackground,
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.SkipPrevious,
                                    contentDescription = "Previous",
                                    tint = dominantColors.onBackground,
                                    modifier = Modifier.size(22.dp),
                                )
                            }
                        }

                        MiniPlayerButton(
                            onClick = onPlayPause,
                            onBackgroundColor = dominantColors.onBackground,
                        ) {
                            AnimatedContent(
                                targetState = isPlaying,
                                transitionSpec = {
                                    (scaleIn(spring(Spring.DampingRatioMediumBouncy)) + fadeIn()) togetherWith
                                        (scaleOut() + fadeOut())
                                },
                                label = "miniPlayPause",
                            ) { playing ->
                                Icon(
                                    imageVector = if (playing) Icons.Default.Pause else Icons.Default.PlayArrow,
                                    contentDescription = if (playing) "Pause" else "Play",
                                    tint = dominantColors.onBackground,
                                    modifier = Modifier.size(24.dp),
                                )
                            }
                        }

                        MiniPlayerButton(
                            onClick = onNext,
                            onBackgroundColor = dominantColors.onBackground,
                        ) {
                            Icon(
                                imageVector = Icons.Default.SkipNext,
                                contentDescription = "Next",
                                tint = dominantColors.onBackground,
                                modifier = Modifier.size(24.dp),
                            )
                        }

                        if (!isPlaying) {
                            MiniPlayerButton(
                                onClick = onClose,
                                onBackgroundColor = dominantColors.onBackground,
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = "Close",
                                    tint = dominantColors.onBackground,
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                        }

                        Spacer(modifier = Modifier.width(4.dp))
                    }
                }
            }
        }
    }
}

/**
 * Small bouncy circular IconButton used inside the pill. Hoisted out of
 * [PillMiniPlayer] for re-use and so the inner @Composable function isn't
 * defined inside another Composable (which works but is harder to read).
 */
@Composable
private fun MiniPlayerButton(
    onClick: () -> Unit,
    onBackgroundColor: Color,
    size: Dp = 36.dp,
    content: @Composable () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.78f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioLowBouncy,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "miniPlayerBtnScale",
    )

    val bgAlpha by animateFloatAsState(
        targetValue = if (isPressed) 0.15f else 0f,
        animationSpec = spring(Spring.DampingRatioNoBouncy, Spring.StiffnessMedium),
        label = "miniPlayerBtnBg",
    )

    Box(
        modifier = Modifier
            .size(size)
            .scale(scale)
            .clip(CircleShape)
            .background(onBackgroundColor.copy(alpha = bgAlpha))
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

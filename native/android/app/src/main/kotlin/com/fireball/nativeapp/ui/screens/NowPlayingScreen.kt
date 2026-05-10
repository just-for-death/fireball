package com.fireball.nativeapp.ui.screens

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.player.PlaybackState
import com.fireball.nativeapp.player.RepeatMode
import com.fireball.nativeapp.ui.components.AlbumArt
import com.fireball.nativeapp.ui.components.seekbar.Seekbar
import com.fireball.nativeapp.ui.components.seekbar.SeekbarStyle
import com.fireball.nativeapp.ui.theme.rememberDominantColors

@Composable
fun NowPlayingScreen(
    playbackState: PlaybackState,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onSeek: (Float) -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleRepeatMode: () -> Unit,
    onCollapse: () -> Unit,
) {
    val currentSong = playbackState.currentTrack
    val isPlaying = playbackState.isPlaying
    val positionMs = playbackState.positionMs
    val durationMs = playbackState.durationMs
    val repeatMode = playbackState.repeatMode
    val shuffleEnabled = playbackState.shuffled

    val isDark = isSystemInDarkTheme()
    val dominant = rememberDominantColors(currentSong?.artwork, isSystemInDarkTheme())

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        dominant.primary,
                        dominant.secondary,
                        MaterialTheme.colorScheme.background,
                    ),
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Top bar — collapse button.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onCollapse) {
                    Icon(
                        Icons.Filled.KeyboardArrowDown,
                        contentDescription = "Collapse player",
                        modifier = Modifier.size(32.dp),
                        tint = dominant.onBackground
                    )
                }
                Text(
                    text = "Now Playing",
                    style = MaterialTheme.typography.titleMedium,
                    color = dominant.onBackground.copy(alpha = 0.8f),
                    modifier = Modifier.padding(start = 8.dp),
                )
            }

            Spacer(Modifier.height(24.dp))

            AlbumArt(
                thumbnailUrl = currentSong?.artwork,
                contentDescription = currentSong?.title,
                onClick = onPlayPause,
                modifier = Modifier
                    .widthIn(max = 360.dp)
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .clip(RoundedCornerShape(16.dp)),
            )

            Spacer(Modifier.height(32.dp))

            // Track metadata.
            Text(
                text = currentSong?.title ?: "Nothing playing",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = dominant.onBackground,
                modifier = Modifier.widthIn(max = 480.dp),
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = currentSong?.artist.orEmpty(),
                style = MaterialTheme.typography.bodyLarge,
                color = dominant.onBackground.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 480.dp),
            )

            Spacer(Modifier.height(24.dp))

            // Seek bar + time labels.
            Column(modifier = Modifier.widthIn(max = 480.dp).fillMaxWidth()) {
                val progress = if (durationMs > 0) positionMs.toFloat() / durationMs.toFloat() else 0f
                Seekbar(
                    progress = progress,
                    isPlaying = isPlaying,
                    style = SeekbarStyle.WAVEFORM, // Hardcoded to WAVEFORM for the beautiful expressive UI
                    onSeek = onSeek,
                    activeColor = dominant.accent,
                    inactiveColor = dominant.onBackground.copy(alpha = 0.3f),
                    modifier = Modifier.fillMaxWidth()
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = formatMs(positionMs),
                        style = MaterialTheme.typography.labelMedium,
                        color = dominant.onBackground.copy(alpha = 0.7f),
                    )
                    Text(
                        text = formatMs(durationMs),
                        style = MaterialTheme.typography.labelMedium,
                        color = dominant.onBackground.copy(alpha = 0.7f),
                    )
                }
            }

            Spacer(Modifier.height(24.dp))

            // Transport controls — shuffle | prev | play/pause | next | repeat.
            Row(
                modifier = Modifier.widthIn(max = 480.dp).fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ShuffleButton(
                    enabled = shuffleEnabled,
                    activeColor = dominant.accent,
                    inactiveColor = dominant.onBackground.copy(alpha = 0.5f),
                    onToggle = onToggleShuffle,
                )

                IconButton(
                    onClick = onPrevious,
                    enabled = currentSong != null,
                ) {
                    Icon(
                        Icons.Filled.SkipPrevious,
                        contentDescription = "Previous",
                        modifier = Modifier.size(36.dp),
                        tint = dominant.onBackground
                    )
                }

                FilledIconButton(
                    onClick = onPlayPause,
                    enabled = currentSong != null,
                    modifier = Modifier.size(72.dp),
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = dominant.accent,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ),
                ) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (isPlaying) "Pause" else "Play",
                        modifier = Modifier.size(40.dp),
                    )
                }

                IconButton(
                    onClick = onNext,
                    enabled = currentSong != null,
                ) {
                    Icon(
                        Icons.Filled.SkipNext,
                        contentDescription = "Next",
                        modifier = Modifier.size(36.dp),
                        tint = dominant.onBackground
                    )
                }

                RepeatButton(
                    mode = repeatMode,
                    activeColor = dominant.accent,
                    inactiveColor = dominant.onBackground.copy(alpha = 0.5f),
                    onToggle = onToggleRepeatMode,
                )
            }
        }
    }
}

@Composable
private fun ShuffleButton(enabled: Boolean, activeColor: androidx.compose.ui.graphics.Color, inactiveColor: androidx.compose.ui.graphics.Color, onToggle: () -> Unit) {
    val tint by animateColorAsState(
        targetValue = if (enabled) activeColor else inactiveColor,
    )
    IconButton(onClick = onToggle) {
        Icon(
            Icons.Filled.Shuffle,
            contentDescription = if (enabled) "Shuffle on" else "Shuffle off",
            tint = tint,
        )
    }
}

@Composable
private fun RepeatButton(mode: RepeatMode, activeColor: androidx.compose.ui.graphics.Color, inactiveColor: androidx.compose.ui.graphics.Color, onToggle: () -> Unit) {
    val tint by animateColorAsState(
        targetValue = if (mode == RepeatMode.OFF) inactiveColor else activeColor,
    )
    val icon = if (mode == RepeatMode.ONE) Icons.Filled.RepeatOne else Icons.Filled.Repeat
    IconButton(onClick = onToggle) {
        Icon(
            icon,
            contentDescription = "Repeat: $mode",
            tint = tint,
        )
    }
}

private fun formatMs(ms: Long): String {
    val totalSeconds = ms / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return String.format("%02d:%02d", minutes, seconds)
}

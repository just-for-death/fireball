@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.fireball.nativeapp.ui.screens

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics
import android.view.HapticFeedbackConstants
import java.util.Locale
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.player.PlaybackState
import com.fireball.nativeapp.player.RepeatMode
import com.fireball.nativeapp.ui.components.AlbumArt
import com.fireball.nativeapp.ui.components.SyncedLyricsView
import com.fireball.nativeapp.ui.components.seekbar.Seekbar
import com.fireball.nativeapp.ui.components.seekbar.SeekbarStyle
import com.fireball.nativeapp.ui.theme.DominantColors
import com.fireball.nativeapp.ui.theme.defaultDominantColors
import com.fireball.nativeapp.ui.theme.rememberDominantColors

private val PlayerSplitBreakpoint = 840.dp

@Composable
fun NowPlayingScreen(
    playbackState: PlaybackState,
    currentLyrics: String?,
    lyricsAutoScroll: Boolean = true,
    lyricsReducedMotion: Boolean = false,
    pinnedLyricsPanel: Boolean = false,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onSeek: (Float) -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleRepeatMode: () -> Unit,
    onPlayQueueIndex: (Int) -> Unit = {},
    onFollowArtist: (String, String?) -> Unit = { _, _ -> },
    onOpenArtistSearch: (String, String?) -> Unit = { _, _ -> },
    onOverflowQueueTrackMenu: (Track) -> Unit = {},
    onCollapse: () -> Unit,
    onOpenTrackMenu: () -> Unit = {},
    isCurrentTrackFavorite: Boolean = false,
    onPlayNextFromMenu: () -> Unit = {},
    onAddToQueueFromMenu: () -> Unit = {},
    onToggleFavoriteFromMenu: () -> Unit = {},
    onSeeArtistFromMenu: () -> Unit = {},
    isArtistFollowed: Boolean = false,
    onFollowArtistFromMenu: () -> Unit = {},
    onUnfollowArtistFromMenu: () -> Unit = {},
    appearanceChrome: String = "music",
) {
    var queueExpanded by remember { mutableStateOf(false) }
    var trackMenuExpanded by remember { mutableStateOf(false) }
    val currentSong = playbackState.currentTrack
    val showLyricsInArtSlot = !currentLyrics.isNullOrBlank()
    val isPlaying = playbackState.isPlaying
    val positionMs = playbackState.positionMs
    val durationMs = playbackState.durationMs
    val repeatMode = playbackState.repeatMode
    val shuffleEnabled = playbackState.shuffled

    val isDark = isSystemInDarkTheme()
    val dominant =
        when (appearanceChrome) {
            "music" -> rememberDominantColors(currentSong?.artwork, isDark)
            else -> remember(isDark) { defaultDominantColors(isDark) }
        }
    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs.toFloat() else 0f

    Box(modifier = Modifier.fillMaxSize()) {
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
        )
        BoxWithConstraints(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
            val useSplit = maxWidth >= PlayerSplitBreakpoint
            val sidePad = 24.dp

            Column(Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = sidePad)
                        .padding(horizontal = sidePad),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onCollapse) {
                        Icon(
                            Icons.Filled.KeyboardArrowDown,
                            contentDescription = "Collapse player",
                            modifier = Modifier.size(32.dp),
                            tint = dominant.onBackground,
                        )
                    }
                    Text(
                        text = "Now Playing",
                        style = MaterialTheme.typography.titleMedium,
                        color = dominant.onBackground.copy(alpha = 0.8f),
                        modifier = Modifier
                            .padding(start = 8.dp)
                            .weight(1f),
                    )
                    Box {
                        IconButton(onClick = { trackMenuExpanded = true }) {
                            Icon(
                                Icons.Default.MoreVert,
                                contentDescription = "Track options",
                                tint = dominant.onBackground,
                            )
                        }
                        DropdownMenu(
                            expanded = trackMenuExpanded,
                            onDismissRequest = { trackMenuExpanded = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Play next") },
                                onClick = {
                                    trackMenuExpanded = false
                                    onPlayNextFromMenu()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Add to queue") },
                                onClick = {
                                    trackMenuExpanded = false
                                    onAddToQueueFromMenu()
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        if (isCurrentTrackFavorite) {
                                            "Remove from favorites"
                                        } else {
                                            "Add to favorites"
                                        },
                                    )
                                },
                                onClick = {
                                    trackMenuExpanded = false
                                    onToggleFavoriteFromMenu()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("View artist catalog") },
                                onClick = {
                                    trackMenuExpanded = false
                                    onSeeArtistFromMenu()
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(if (isArtistFollowed) "Unfollow artist" else "Follow artist")
                                },
                                onClick = {
                                    trackMenuExpanded = false
                                    if (isArtistFollowed) {
                                        onUnfollowArtistFromMenu()
                                    } else {
                                        onFollowArtistFromMenu()
                                    }
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("More options…") },
                                onClick = {
                                    trackMenuExpanded = false
                                    onOpenTrackMenu()
                                },
                            )
                        }
                    }
                }

                if (useSplit) {
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .padding(horizontal = sidePad)
                            .padding(bottom = sidePad),
                        horizontalArrangement = Arrangement.spacedBy(32.dp),
                    ) {
                        val scrollLeft = rememberScrollState()
                        Column(
                            modifier = Modifier
                                .weight(0.42f)
                                .fillMaxHeight()
                                .verticalScroll(scrollLeft),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Spacer(Modifier.height(8.dp))
                            ArtworkOrLyricsSlot(
                                thumbnailUrl = currentSong?.artwork,
                                title = currentSong?.title,
                                lyrics = if (showLyricsInArtSlot) currentLyrics else null,
                                positionMs = positionMs,
                                lyricsAutoScroll = lyricsAutoScroll,
                                lyricsReducedMotion = lyricsReducedMotion,
                                dominant = dominant,
                                cornerRadius = 20.dp,
                                lyricsMaxHeight = if (lyricsReducedMotion) 320.dp else 420.dp,
                                onPlayPause = onPlayPause,
                                onOpenTrackMenu = onOpenTrackMenu,
                                modifier =
                                    Modifier
                                        .widthIn(max = 420.dp)
                                        .fillMaxWidth(),
                            )
                            Spacer(Modifier.height(24.dp))
                            TrackMetadata(
                                currentSong = currentSong,
                                dominant = dominant,
                                titleStyle = MaterialTheme.typography.headlineMedium,
                                artistStyle = MaterialTheme.typography.titleMedium,
                                onOpenTrackMenu = onOpenTrackMenu,
                                onArtistClick = {
                                    currentSong?.artist?.takeIf { it.isNotBlank() }?.let { a ->
                                        onOpenArtistSearch(a, currentSong.artwork)
                                    }
                                },
                            )
                            Spacer(Modifier.height(20.dp))
                            SeekSection(
                                progress = progress,
                                isPlaying = isPlaying,
                                positionMs = positionMs,
                                durationMs = durationMs,
                                dominant = dominant,
                                onSeek = onSeek,
                                fillMax = false,
                            )
                            Spacer(Modifier.height(24.dp))
                            TransportRow(
                                shuffleEnabled = shuffleEnabled,
                                repeatMode = repeatMode,
                                isPlaying = isPlaying,
                                currentSong = currentSong,
                                dominant = dominant,
                                onPlayPause = onPlayPause,
                                onNext = onNext,
                                onPrevious = onPrevious,
                                onToggleShuffle = onToggleShuffle,
                                onToggleRepeatMode = onToggleRepeatMode,
                            )
                        }

                        val scrollRight = rememberScrollState()
                        val lyricsCap = if (lyricsReducedMotion) 120.dp else 440.dp
                        Column(
                            modifier = Modifier
                                .weight(0.58f)
                                .fillMaxHeight()
                                .verticalScroll(scrollRight),
                        ) {
                            Spacer(Modifier.height(8.dp))
                            if (pinnedLyricsPanel && !currentLyrics.isNullOrBlank()) {
                                Text(
                                    text = "Lyrics",
                                    style = MaterialTheme.typography.labelLarge,
                                    color = dominant.onBackground.copy(alpha = 0.55f),
                                    modifier = Modifier.padding(bottom = 8.dp),
                                )
                                SyncedLyricsView(
                                    lyrics = currentLyrics,
                                    positionMs = positionMs,
                                    autoScroll = lyricsAutoScroll,
                                    reducedMotion = lyricsReducedMotion,
                                    textColor = dominant.onBackground,
                                    accentColor = dominant.accent,
                                    modifier = Modifier.widthIn(max = 520.dp),
                                    maxContentHeight = lyricsCap,
                                )
                            }

                            QueueSection(
                                playbackState = playbackState,
                                queueExpanded = queueExpanded,
                                dominant = dominant,
                                onExpandedChange = { queueExpanded = it },
                                onPlayQueueIndex = onPlayQueueIndex,
                                onOpenArtistSearch = onOpenArtistSearch,
                                onOverflowQueueTrackMenu = onOverflowQueueTrackMenu,
                            )
                            Spacer(Modifier.height(sidePad))
                        }
                    }
                } else {
                    val scrollAll = rememberScrollState()
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .verticalScroll(scrollAll)
                            .padding(horizontal = sidePad),
                    ) {
                        Spacer(Modifier.height(16.dp))

                        ArtworkOrLyricsSlot(
                            thumbnailUrl = currentSong?.artwork,
                            title = currentSong?.title,
                            lyrics = if (showLyricsInArtSlot) currentLyrics else null,
                            positionMs = positionMs,
                            lyricsAutoScroll = lyricsAutoScroll,
                            lyricsReducedMotion = lyricsReducedMotion,
                            dominant = dominant,
                            cornerRadius = 16.dp,
                            lyricsMaxHeight = if (lyricsReducedMotion) 300.dp else 380.dp,
                            onPlayPause = onPlayPause,
                            onOpenTrackMenu = onOpenTrackMenu,
                            modifier =
                                Modifier
                                    .widthIn(max = 380.dp)
                                    .fillMaxWidth(),
                        )

                        Spacer(Modifier.height(24.dp))

                        TrackMetadata(
                            currentSong = currentSong,
                            dominant = dominant,
                            titleStyle = MaterialTheme.typography.headlineSmall,
                            artistStyle = MaterialTheme.typography.bodyLarge,
                            onOpenTrackMenu = onOpenTrackMenu,
                            onArtistClick = {
                                currentSong?.artist?.takeIf { it.isNotBlank() }?.let { a ->
                                    onOpenArtistSearch(a, currentSong.artwork)
                                }
                            },
                        )

                        Spacer(Modifier.height(20.dp))

                        SeekSection(
                            progress = progress,
                            isPlaying = isPlaying,
                            positionMs = positionMs,
                            durationMs = durationMs,
                            dominant = dominant,
                            onSeek = onSeek,
                            fillMax = true,
                        )

                        if (pinnedLyricsPanel && showLyricsInArtSlot) {
                            Spacer(Modifier.height(12.dp))
                            Text(
                                text = "Lyrics (expanded)",
                                style = MaterialTheme.typography.labelLarge,
                                color = dominant.onBackground.copy(alpha = 0.55f),
                            )
                            Spacer(Modifier.height(8.dp))
                            SyncedLyricsView(
                                lyrics = currentLyrics!!,
                                positionMs = positionMs,
                                autoScroll = lyricsAutoScroll,
                                reducedMotion = lyricsReducedMotion,
                                textColor = dominant.onBackground,
                                accentColor = dominant.accent,
                                modifier = Modifier.widthIn(max = 480.dp),
                                maxContentHeight = if (lyricsReducedMotion) 120.dp else 160.dp,
                            )
                        }

                        Spacer(Modifier.height(20.dp))

                        TransportRow(
                            shuffleEnabled = shuffleEnabled,
                            repeatMode = repeatMode,
                            isPlaying = isPlaying,
                            currentSong = currentSong,
                            dominant = dominant,
                            onPlayPause = onPlayPause,
                            onNext = onNext,
                            onPrevious = onPrevious,
                            onToggleShuffle = onToggleShuffle,
                            onToggleRepeatMode = onToggleRepeatMode,
                        )

                        QueueSection(
                            playbackState = playbackState,
                            queueExpanded = queueExpanded,
                            dominant = dominant,
                            onExpandedChange = { queueExpanded = it },
                            onPlayQueueIndex = onPlayQueueIndex,
                            onOpenArtistSearch = onOpenArtistSearch,
                            onOverflowQueueTrackMenu = onOverflowQueueTrackMenu,
                        )

                        Spacer(modifier = Modifier.height(sidePad + 24.dp))
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ArtworkOrLyricsSlot(
    thumbnailUrl: String?,
    title: String?,
    lyrics: String?,
    positionMs: Long,
    lyricsAutoScroll: Boolean,
    lyricsReducedMotion: Boolean,
    dominant: DominantColors,
    cornerRadius: Dp,
    lyricsMaxHeight: Dp,
    onPlayPause: () -> Unit,
    onOpenTrackMenu: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(cornerRadius)
    if (!lyrics.isNullOrBlank()) {
        Box(
            modifier =
                modifier
                    .aspectRatio(1f)
                    .clip(shape)
                    .background(dominant.secondary.copy(alpha = 0.55f))
                    .combinedClickable(
                        onClick = onPlayPause,
                        onLongClick = onOpenTrackMenu,
                    )
                    .padding(horizontal = 16.dp, vertical = 12.dp),
        ) {
            SyncedLyricsView(
                lyrics = lyrics,
                positionMs = positionMs,
                autoScroll = lyricsAutoScroll,
                reducedMotion = lyricsReducedMotion,
                textColor = dominant.onBackground,
                accentColor = dominant.accent,
                modifier = Modifier.fillMaxSize(),
                maxContentHeight = lyricsMaxHeight,
            )
        }
    } else {
        AlbumArt(
            thumbnailUrl = thumbnailUrl,
            contentDescription = title,
            onClick = onPlayPause,
            onLongClick = onOpenTrackMenu,
            modifier =
                modifier
                    .aspectRatio(1f)
                    .clip(shape),
        )
    }
}

@Composable
private fun TrackMetadata(
    currentSong: Track?,
    dominant: DominantColors,
    titleStyle: TextStyle,
    artistStyle: TextStyle,
    onOpenTrackMenu: () -> Unit = {},
    onArtistClick: () -> Unit = {},
) {
    val view = LocalView.current
    val titleLongPressModifier = if (currentSong != null) {
        Modifier
            .semantics {
                onLongClick("Track options") {
                    onOpenTrackMenu()
                    true
                }
            }
            .pointerInput(onOpenTrackMenu, view) {
                detectTapGestures(
                    onLongPress = {
                        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                        onOpenTrackMenu()
                    },
                )
            }
    } else {
        Modifier
    }
    Column(
        modifier = Modifier.widthIn(max = 520.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            modifier = Modifier.then(titleLongPressModifier),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = currentSong?.title ?: "Nothing playing",
                style = titleStyle,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = dominant.onBackground,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = currentSong?.artist.orEmpty(),
            style = artistStyle,
            color = dominant.onBackground.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = !currentSong?.artist.isNullOrBlank()) {
                    onArtistClick()
                },
        )
    }
}

@Composable
private fun SeekSection(
    progress: Float,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    dominant: DominantColors,
    onSeek: (Float) -> Unit,
    fillMax: Boolean,
) {
    val mod = if (fillMax) {
        Modifier.widthIn(max = 480.dp).fillMaxWidth()
    } else {
        Modifier.widthIn(max = 420.dp).fillMaxWidth()
    }
    Column(modifier = mod) {
        Seekbar(
            progress = progress,
            isPlaying = isPlaying,
            style = SeekbarStyle.WAVEFORM,
            onSeek = onSeek,
            activeColor = dominant.accent,
            inactiveColor = dominant.onBackground.copy(alpha = 0.3f),
            modifier = Modifier.fillMaxWidth(),
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
}

@Composable
private fun TransportRow(
    shuffleEnabled: Boolean,
    repeatMode: RepeatMode,
    isPlaying: Boolean,
    currentSong: Track?,
    dominant: DominantColors,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleRepeatMode: () -> Unit,
) {
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
                tint = dominant.onBackground,
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
                tint = dominant.onBackground,
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

@Composable
private fun QueueSection(
    playbackState: PlaybackState,
    queueExpanded: Boolean,
    dominant: DominantColors,
    onExpandedChange: (Boolean) -> Unit,
    onPlayQueueIndex: (Int) -> Unit,
    onOpenArtistSearch: (String, String?) -> Unit,
    onOverflowQueueTrackMenu: (Track) -> Unit,
) {
    val view = LocalView.current
    if (playbackState.queue.size <= 1) return

    Spacer(Modifier.height(16.dp))
    androidx.compose.material3.TextButton(onClick = { onExpandedChange(!queueExpanded) }) {
        Text(
            if (queueExpanded) "Hide queue (${playbackState.queue.size})"
            else "Show queue (${playbackState.queue.size})",
            color = dominant.onBackground,
        )
    }
    if (queueExpanded) {
        Column(
            modifier = Modifier
                .widthIn(max = 520.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            playbackState.queue.forEachIndexed { index, track ->
                val selected = index == playbackState.currentIndex
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(
                            if (selected) dominant.accent.copy(alpha = 0.25f)
                            else dominant.secondary.copy(alpha = 0.2f),
                        )
                        .combinedClickable(
                            onClick = { onPlayQueueIndex(index) },
                            onLongClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                                onOverflowQueueTrackMenu(track)
                            },
                        )
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            track.title,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            color = dominant.onBackground,
                            maxLines = 1,
                        )
                        Text(
                            track.artist,
                            style = MaterialTheme.typography.bodySmall,
                            color = dominant.onBackground.copy(alpha = 0.7f),
                            maxLines = 1,
                            modifier = Modifier.clickable {
                                onOpenArtistSearch(track.artist, track.artwork)
                            },
                        )
                    }
                }
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
    return String.format(Locale.US, "%02d:%02d", minutes, seconds)
}

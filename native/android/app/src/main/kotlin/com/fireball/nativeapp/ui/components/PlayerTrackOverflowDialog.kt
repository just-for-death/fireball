package com.fireball.nativeapp.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import java.util.Locale
import kotlin.math.max

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerTrackOverflowDialog(
    track: Track,
    isFavorite: Boolean,
    isArtistFollowed: Boolean,
    playlists: List<Playlist>,
    sleepTimerEndEpochMs: Long?,
    sleepTimerPresetMinutes: Int? = null,
    sleepAfterCurrent: Boolean,
    onDismiss: () -> Unit,
    onPlayNext: () -> Unit,
    onAddToQueue: () -> Unit,
    onToggleFavorite: () -> Unit,
    onAddToPlaylist: (String) -> Unit,
    onSeeArtist: () -> Unit,
    onFollowArtist: () -> Unit,
    onUnfollowArtist: () -> Unit = {},
    onSetSleepTimer: (Int?) -> Unit,
    onSetSleepAfterCurrent: (Boolean) -> Unit,
    artistImageUrl: String? = null,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var tickMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(sleepTimerEndEpochMs) {
        while (sleepTimerEndEpochMs != null) {
            delay(1_000)
            tickMs = System.currentTimeMillis()
            if ((sleepTimerEndEpochMs ?: 0L) <= tickMs) break
        }
    }
    val sleepStatus =
        remember(sleepTimerEndEpochMs, tickMs) {
            val end = sleepTimerEndEpochMs ?: return@remember null
            val remainingMs = max(0L, end - tickMs)
            if (remainingMs <= 0L) return@remember null
            val totalSec = (remainingMs / 1000).toInt()
            val mins = totalSec / 60
            val secs = totalSec % 60
            String.format(Locale.getDefault(), "Stops in %d:%02d", mins, secs)
        }
    val selectedSleepLabel =
        remember(sleepTimerEndEpochMs, sleepTimerPresetMinutes, tickMs) {
            if (sleepTimerEndEpochMs == null) return@remember null
            when (sleepTimerPresetMinutes) {
                15 -> "15m"
                30 -> "30m"
                45 -> "45m"
                60 -> "60m"
                else -> null
            }
        }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDragHandle() },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(ActionSheetSectionSpacing),
        ) {
            Text(
                text = "Track options",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 4.dp),
            )

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
            ) {
                Row(
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AlbumArt(
                        thumbnailUrl = track.artwork,
                        contentDescription = track.title,
                        modifier =
                            Modifier
                                .size(64.dp)
                                .clip(RoundedCornerShape(12.dp)),
                    )
                    Column(
                        modifier =
                            Modifier
                                .padding(start = 14.dp)
                                .weight(1f),
                    ) {
                        Text(
                            text = track.title,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = track.artist,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }

            ActionSheetSectionCard {
                ActionSheetRow(Icons.Default.SkipNext, "Play next", onPlayNext, inset = true)
                ActionSheetRow(Icons.AutoMirrored.Filled.QueueMusic, "Add to queue", onAddToQueue, inset = true)
                ActionSheetRow(
                    if (isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                    if (isFavorite) "Remove from favorites" else "Add to favorites",
                    onToggleFavorite,
                    inset = true,
                )
            }

            Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                ActionSheetSectionLabel("Sleep", modifier = Modifier.padding(top = 0.dp))
                if (sleepStatus != null) {
                    Text(
                        text = sleepStatus,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
                ActionSheetSectionCard {
                    ActionSheetChipRow(
                        labels = listOf("15m", "30m", "45m", "60m", "Clear"),
                        selectedLabel = selectedSleepLabel,
                        onSelect = { label ->
                            when (label) {
                                "15m" -> onSetSleepTimer(15)
                                "30m" -> onSetSleepTimer(30)
                                "45m" -> onSetSleepTimer(45)
                                "60m" -> onSetSleepTimer(60)
                                "Clear" -> onSetSleepTimer(null)
                            }
                        },
                        inset = true,
                    )
                    ActionSheetToggleRow(
                        title = "Sleep after current track",
                        subtitle = "Pause when this song ends",
                        checked = sleepAfterCurrent,
                        onCheckedChange = onSetSleepAfterCurrent,
                        inset = true,
                    )
                }
            }

            ActionSheetSectionCard {
                ActionSheetRowWithAvatar(
                    imageUrl = artistImageUrl ?: track.artwork,
                    label = "View artist catalog",
                    onClick = onSeeArtist,
                    inset = true,
                )
                ActionSheetRow(
                    Icons.Default.PersonAdd,
                    if (isArtistFollowed) "Unfollow artist" else "Follow artist",
                    if (isArtistFollowed) onUnfollowArtist else onFollowArtist,
                    inset = true,
                )
            }

            if (playlists.isNotEmpty()) {
                Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                    ActionSheetSectionLabel("Add to playlist", modifier = Modifier.padding(top = 0.dp))
                    ActionSheetSectionCard {
                        playlists.forEachIndexed { index, pl ->
                            val alreadyInPlaylist = pl.videos.any { it.effectiveId == track.effectiveId }
                            ActionSheetRow(
                                Icons.AutoMirrored.Filled.PlaylistAdd,
                                pl.title,
                                onClick = { if (!alreadyInPlaylist) onAddToPlaylist(pl.id) },
                                enabled = !alreadyInPlaylist,
                                subtitle = if (alreadyInPlaylist) "Already in playlist" else null,
                                inset = true,
                            )
                            if (index < playlists.lastIndex) {
                                Box(
                                    modifier =
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 8.dp)
                                            .height(1.dp)
                                            .background(
                                                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f),
                                            ),
                                )
                            }
                        }
                    }
                }
            }

            ActionSheetPrimaryButton(
                label = "Done",
                icon = Icons.Default.Close,
                onClick = onDismiss,
            )
        }
    }
}

@Composable
fun BottomSheetDragHandle(modifier: Modifier = Modifier) {
    Box(
        modifier =
            modifier
                .fillMaxWidth()
                .padding(top = 10.dp, bottom = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Spacer(
            modifier =
                Modifier
                    .size(width = 40.dp, height = 4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f)),
        )
    }
}

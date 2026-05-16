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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.ui.theme.MotionTokens

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerTrackOverflowDialog(
    track: Track,
    isFavorite: Boolean,
    isArtistFollowed: Boolean,
    playlists: List<Playlist>,
    onDismiss: () -> Unit,
    onPlayNext: () -> Unit,
    onAddToQueue: () -> Unit,
    onToggleFavorite: () -> Unit,
    onAddToPlaylist: (String) -> Unit,
    onSeeArtist: () -> Unit,
    onFollowArtist: () -> Unit,
    onUnfollowArtist: () -> Unit = {},
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
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
                .padding(bottom = 28.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AlbumArt(
                    thumbnailUrl = track.artwork,
                    contentDescription = track.title,
                    modifier =
                        Modifier
                            .size(56.dp)
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
            Spacer(Modifier.height(16.dp))
            SuvFadeSlideIn(delayMs = 0) {
                ActionSheetRow(Icons.Default.SkipNext, "Play next", onPlayNext)
            }
            SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3) {
                ActionSheetRow(Icons.Default.QueueMusic, "Add to queue", onAddToQueue)
            }
            SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * 2) {
                ActionSheetRow(
                    if (isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                    if (isFavorite) "Remove from favorites" else "Add to favorites",
                    onToggleFavorite,
                )
            }
            ActionSheetDivider()
            SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * 3) {
                ActionSheetRow(Icons.Default.Person, "View artist catalog", onSeeArtist)
            }
            SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * 4) {
                ActionSheetRow(
                    Icons.Default.PersonAdd,
                    if (isArtistFollowed) "Unfollow artist" else "Follow artist",
                    if (isArtistFollowed) onUnfollowArtist else onFollowArtist,
                )
            }
            if (playlists.isNotEmpty()) {
                ActionSheetDivider()
                ActionSheetSectionLabel("Add to playlist")
                playlists.forEachIndexed { index, pl ->
                    val alreadyInPlaylist = pl.videos.any { it.effectiveId == track.effectiveId }
                    SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * (5 + index.coerceAtMost(4))) {
                        ActionSheetRow(
                            Icons.AutoMirrored.Filled.PlaylistAdd,
                            pl.title,
                            onClick = { if (!alreadyInPlaylist) onAddToPlaylist(pl.id) },
                            enabled = !alreadyInPlaylist,
                            subtitle = if (alreadyInPlaylist) "Already in playlist" else null,
                        )
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * 2) {
                ActionSheetRow(Icons.Default.Close, "Done", onDismiss)
            }
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

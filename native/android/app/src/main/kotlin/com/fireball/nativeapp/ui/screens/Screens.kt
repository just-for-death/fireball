@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.fireball.nativeapp.ui.screens

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForwardIos
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.HeadsetMic
import androidx.compose.material.icons.filled.Lyrics
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PictureInPicture
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider as M3HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.IconButton
import androidx.compose.material3.TextButton
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.fireball.nativeapp.core.model.Album
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.player.PlaybackState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    library: LibrarySnapshot,
    playbackState: PlaybackState,
    currentLyrics: String?,
    homeCountries: List<String> = emptyList(),
    chartCountryCode: String = "us",
    trendingTracks: List<Track> = emptyList(),
    trendingLoading: Boolean = false,
    lbRecentTracks: List<Track> = emptyList(),
    lbTopTracks: List<Track> = emptyList(),
    lbTopRange: String = "month",
    lbHomeLoading: Boolean = false,
    onSelectChartCountry: (String) -> Unit = {},
    onSelectLbTopRange: (String) -> Unit = {},
    onFollowArtist: (String, String?) -> Unit = { _, _ -> },
    onRefreshHome: () -> Unit = {},
    onOpenPlaylist: (Playlist) -> Unit = {},
    onOverflowTrack: (Track) -> Unit = {},
    onPlay: (Track, List<Track>) -> Unit,
    onTogglePlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
) {
    val scrollState = androidx.compose.foundation.lazy.rememberLazyListState()
    val pullRefreshState = androidx.compose.material3.pulltorefresh.rememberPullToRefreshState()
    var isRefreshing by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    LaunchedEffect(trendingLoading, lbHomeLoading) {
        if (isRefreshing && !trendingLoading && !lbHomeLoading) {
            isRefreshing = false
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                onRefreshHome()
                scope.launch {
                    kotlinx.coroutines.delay(4500)
                    if (isRefreshing) isRefreshing = false
                }
            },
            state = pullRefreshState,
            modifier = Modifier.fillMaxSize(),
        ) {
        LazyColumn(
            state = scrollState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 120.dp)
        ) {
            // Greeting header
            item {
                Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)) {
                    val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
                    val greeting = when (hour) {
                        in 5..11 -> "Good Morning"
                        in 12..16 -> "Good Afternoon"
                        else -> "Good Evening"
                    }
                    Text(
                        greeting,
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Bold
                    )
                    val track = playbackState.currentTrack
                    if (track != null) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.GraphicEq,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                "Now Playing: ${track.title} — ${track.artist}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.primary,
                                maxLines = 1,
                                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }

            if (homeCountries.isNotEmpty()) {
                item {
                    Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                        Text(
                            "Top Charts",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(homeCountries) { code ->
                                val label = com.fireball.nativeapp.ui.HomeCountries.all
                                    .firstOrNull { it.first.equals(code, ignoreCase = true) }
                                    ?.second
                                    ?: code
                                FilterChip(
                                    selected = code.equals(chartCountryCode, ignoreCase = true),
                                    onClick = { onSelectChartCountry(code) },
                                    label = { Text(label) },
                                )
                            }
                        }
                    }
                }
            }

            if (trendingLoading && trendingTracks.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(32.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        androidx.compose.material3.CircularProgressIndicator()
                    }
                }
            } else if (trendingTracks.isNotEmpty()) {
                item {
                    Text(
                        "Trending",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                    androidx.compose.foundation.lazy.LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp),
                    ) {
                        itemsIndexed(trendingTracks, key = { _, t -> t.effectiveId }) { idx, track ->
                            com.fireball.nativeapp.ui.components.SuvFadeSlideInStaggered(index = idx) {
                            Column(
                                modifier = Modifier
                                    .width(140.dp)
                                    .combinedClickable(
                                        onClick = { onPlay(track, trendingTracks) },
                                        onLongClick = { onOverflowTrack(track) },
                                    ),
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(140.dp)
                                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                                        .background(MaterialTheme.colorScheme.surfaceVariant),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (!track.artwork.isNullOrBlank()) {
                                        coil.compose.AsyncImage(
                                            model = track.artwork,
                                            contentDescription = track.title,
                                            modifier = Modifier.fillMaxSize(),
                                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                        )
                                    } else {
                                        Icon(
                                            Icons.Default.MusicNote,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                            modifier = Modifier.size(40.dp),
                                        )
                                    }
                                }
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    track.title,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                )
                                Text(
                                    track.artist,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                )
                            }
                            }
                        }
                    }
                }
            }

            if (lbRecentTracks.isNotEmpty()) {
                item {
                    Text(
                        "ListenBrainz — Recent",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                    androidx.compose.foundation.lazy.LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp),
                    ) {
                        items(lbRecentTracks, key = { "lb-recent-${it.effectiveId}" }) { track ->
                            HomeTrackCarouselCard(
                                track = track,
                                onPlay = { onPlay(track, lbRecentTracks) },
                                onFollowArtist = { onFollowArtist(track.artist, track.artwork) },
                                onLongPressMenu = { onOverflowTrack(track) },
                            )
                        }
                    }
                }
            }

            if (lbTopTracks.isNotEmpty() || lbHomeLoading) {
                item {
                    Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                        Text(
                            "ListenBrainz — Top",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(listOf("week", "month", "year", "all_time")) { range ->
                                FilterChip(
                                    selected = lbTopRange.equals(range, ignoreCase = true),
                                    onClick = { onSelectLbTopRange(range) },
                                    label = {
                                        Text(
                                            when (range) {
                                                "all_time" -> "All time"
                                                else -> range.replaceFirstChar { it.uppercase() }
                                            },
                                        )
                                    },
                                )
                            }
                        }
                    }
                    if (lbHomeLoading && lbTopTracks.isEmpty()) {
                        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                            androidx.compose.material3.CircularProgressIndicator()
                        }
                    } else {
                        androidx.compose.foundation.lazy.LazyRow(
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                            contentPadding = PaddingValues(horizontal = 20.dp),
                        ) {
                            items(lbTopTracks, key = { "lb-top-${it.effectiveId}" }) { track ->
                                HomeTrackCarouselCard(
                                    track = track,
                                    onPlay = { onPlay(track, lbTopTracks) },
                                    onFollowArtist = { onFollowArtist(track.artist, track.artwork) },
                                    onLongPressMenu = { onOverflowTrack(track) },
                                )
                            }
                        }
                    }
                }
            }

            val listenBrainzReady = library.settings.listenBrainzEnabled &&
                library.settings.listenBrainzUsername.isNotBlank() &&
                library.settings.listenBrainzToken.isNotBlank()
            if (!library.settings.offlineModeEnabled && !listenBrainzReady && !lbHomeLoading &&
                lbRecentTracks.isEmpty() && lbTopTracks.isEmpty()
            ) {
                item {
                    Text(
                        "Connect ListenBrainz in Settings to see your recent listens and top tracks.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
                    )
                }
            }

            val isEmptyDashboard = library.history.isEmpty() && library.favorites.isEmpty() &&
                library.playlists.isEmpty() && library.albums.isEmpty() && trendingTracks.isEmpty() &&
                lbRecentTracks.isEmpty() && lbTopTracks.isEmpty()

            if (isEmptyDashboard) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 60.dp, start = 32.dp, end = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(120.dp)
                                .background(
                                    MaterialTheme.colorScheme.primaryContainer,
                                    androidx.compose.foundation.shape.CircleShape
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                Icons.Default.LibraryMusic,
                                contentDescription = null,
                                modifier = Modifier.size(56.dp),
                                tint = MaterialTheme.colorScheme.onPrimaryContainer
                            )
                        }
                        Text(
                            "Welcome to Fireball",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onBackground
                        )
                        Text(
                            "Your dashboard is empty.\nUse the Search tab to find music\nand start building your library!",
                            style = MaterialTheme.typography.bodyLarge,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            // Recently Played — horizontal carousel with artwork
            if (library.history.isNotEmpty()) {
                item {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Jump Back In",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                    androidx.compose.foundation.lazy.LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp)
                    ) {
                        items(
                            items = library.history.take(20),
                            key = { it.effectiveId },
                        ) { track ->
                            Column(
                                modifier = Modifier
                                    .width(140.dp)
                                    .combinedClickable(
                                        onClick = { onPlay(track, library.history) },
                                        onLongClick = { onOverflowTrack(track) },
                                    )
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(140.dp)
                                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                                        .background(MaterialTheme.colorScheme.surfaceVariant),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (!track.artwork.isNullOrBlank()) {
                                        coil.compose.AsyncImage(
                                            model = track.artwork,
                                            contentDescription = track.title,
                                            modifier = Modifier.fillMaxSize(),
                                            contentScale = androidx.compose.ui.layout.ContentScale.Crop
                                        )
                                    } else {
                                        Icon(
                                            Icons.Default.MusicNote,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                            modifier = Modifier.size(40.dp)
                                        )
                                    }
                                }
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    track.title,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                )
                                Text(
                                    track.artist,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }

            // Favorites — list with artwork thumbnails
            if (library.favorites.isNotEmpty()) {
                item {
                    Spacer(modifier = Modifier.height(24.dp))
                    Text(
                        "Your Favorites",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                    Column(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        library.favorites.take(8).forEach { track ->
                            ListItem(
                                headlineContent = {
                                    Text(
                                        track.title,
                                        maxLines = 1,
                                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                        fontWeight = FontWeight.Medium
                                    )
                                },
                                supportingContent = {
                                    Text(
                                        track.artist,
                                        maxLines = 1,
                                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                    )
                                },
                                leadingContent = {
                                    Box(
                                        modifier = Modifier
                                            .size(48.dp)
                                            .clip(androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
                                            .background(MaterialTheme.colorScheme.surfaceVariant),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        if (!track.artwork.isNullOrBlank()) {
                                            coil.compose.AsyncImage(
                                                model = track.artwork,
                                                contentDescription = track.title,
                                                modifier = Modifier.fillMaxSize(),
                                                contentScale = androidx.compose.ui.layout.ContentScale.Crop
                                            )
                                        } else {
                                            Icon(
                                                Icons.Default.MusicNote,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                                modifier = Modifier.size(24.dp)
                                            )
                                        }
                                    }
                                },
                                modifier = Modifier
                                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                                    .combinedClickable(
                                        onClick = { onPlay(track, library.favorites) },
                                        onLongClick = { onOverflowTrack(track) },
                                    ),
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            )
                        }
                    }
                }
            }

            // Playlists
            if (library.playlists.isNotEmpty()) {
                item {
                    Spacer(modifier = Modifier.height(24.dp))
                    Text(
                        "Your Playlists",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                    androidx.compose.foundation.lazy.LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp)
                    ) {
                        items(
                            items = library.playlists,
                            key = { it.id },
                        ) { playlist ->
                            Card(
                                modifier = Modifier
                                    .widthIn(min = 160.dp)
                                    .clickable { onOpenPlaylist(playlist) },
                                shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
                                colors = androidx.compose.material3.CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.secondaryContainer
                                )
                            ) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Icon(
                                        Icons.Default.LibraryMusic,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSecondaryContainer,
                                        modifier = Modifier.size(28.dp)
                                    )
                                    Spacer(modifier = Modifier.height(8.dp))
                                    Text(
                                        playlist.title,
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                        maxLines = 1,
                                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                    )
                                    Text(
                                        "${playlist.videos.size} tracks",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f)
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Albums
            if (library.albums.isNotEmpty()) {
                item {
                    Spacer(modifier = Modifier.height(24.dp))
                    Text(
                        "Saved Albums",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                    androidx.compose.foundation.lazy.LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp)
                    ) {
                        items(
                            items = library.albums,
                            key = { it.id },
                        ) { album ->
                            Column(
                                modifier = Modifier
                                    .width(130.dp)
                                    .combinedClickable(
                                        onClick = {
                                            val tracks = album.tracks
                                            if (!tracks.isNullOrEmpty()) {
                                                onPlay(tracks.first(), tracks)
                                            }
                                        },
                                        onLongClick = {
                                            val first = album.tracks?.firstOrNull()
                                            if (first != null) {
                                                onOverflowTrack(first)
                                            }
                                        },
                                    )
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(130.dp)
                                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                                        .background(MaterialTheme.colorScheme.tertiaryContainer),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        Icons.Default.LibraryMusic,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onTertiaryContainer,
                                        modifier = Modifier.size(36.dp)
                                    )
                                }
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    album.title,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                )
                                Text(
                                    album.artist,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }
        }

        // Quick Mix FAB
        if (library.history.isNotEmpty()) {
            androidx.compose.material3.ExtendedFloatingActionButton(
                onClick = { onPlay(library.history.random(), library.history) },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .navigationBarsPadding()
                    .padding(end = 20.dp, bottom = 92.dp),
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                icon = { Icon(Icons.Default.Shuffle, contentDescription = null) },
                text = { Text("Quick Mix") }
            )
        }
    }
}

@Composable
private fun HomeTrackCarouselCard(
    track: Track,
    onPlay: () -> Unit,
    onFollowArtist: () -> Unit,
    onLongPressMenu: () -> Unit = {},
) {
    Column(
        modifier = Modifier
            .width(140.dp)
            .combinedClickable(
                onClick = onPlay,
                onLongClick = onLongPressMenu,
            ),
    ) {
        Box(
            modifier = Modifier
                .size(140.dp)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            if (!track.artwork.isNullOrBlank()) {
                coil.compose.AsyncImage(
                    model = track.artwork,
                    contentDescription = track.title,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                )
            } else {
                Icon(Icons.Default.MusicNote, contentDescription = null, modifier = Modifier.size(40.dp))
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(track.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
        Text(
            track.artist,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            modifier = Modifier.clickable(onClick = onFollowArtist),
        )
    }
}

@Composable
fun SearchScreen(
    query: String,
    results: List<Track>,
    albumResults: List<Album> = emptyList(),
    searchSuggestions: List<Track>,
    isSearching: Boolean,
    isPlaybackLoading: Boolean,
    isFavorite: (Track) -> Boolean,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onRefreshSuggestions: () -> Unit,
    onPlay: (Track, List<Track>) -> Unit,
    onToggleFavorite: (Track) -> Unit,
    onOpenTrackMenu: (Track) -> Unit,
    onPlayAlbum: (Album) -> Unit = {},
) {
    LaunchedEffect(Unit) {
        onRefreshSuggestions()
    }
    var searchResultsTab by remember { mutableStateOf(0) }
    LaunchedEffect(results, albumResults, query.isNotBlank()) {
        if (!query.isNotBlank()) {
            searchResultsTab = 0
            return@LaunchedEffect
        }
        searchResultsTab =
            when {
                results.isNotEmpty() -> 0
                albumResults.isNotEmpty() -> 1
                else -> 0
            }
    }
    Column(modifier = Modifier.fillMaxSize()) {
        if (isPlaybackLoading) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
        // Search bar area
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChange,
                label = { Text("Search music") },
                modifier = Modifier.weight(1f),
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSearch() }),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(28.dp),
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.MusicNote,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            )
            androidx.compose.material3.FilledTonalButton(
                onClick = onSearch,
                enabled = !isSearching
            ) {
                if (isSearching) {
                    androidx.compose.material3.CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                } else {
                    Text("Search")
                }
            }
        }

        if (searchSuggestions.isNotEmpty()) {
            Text(
                "Suggestions",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            Spacer(modifier = Modifier.height(6.dp))
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f, fill = false)
                    .heightIn(max = 220.dp),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 0.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(searchSuggestions, key = { it.effectiveId + it.title }) { track ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
                        colors = androidx.compose.material3.CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.65f),
                        ),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .combinedClickable(
                                    onClick = {
                                        onQueryChange("${track.artist} ${track.title}".trim())
                                        onSearch()
                                    },
                                    onLongClick = { onOpenTrackMenu(track) },
                                )
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                "${track.title} · ${track.artist}",
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 2,
                                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            M3HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
        }

        val hasSongHits = results.isNotEmpty()
        val hasAlbumHits = albumResults.isNotEmpty()
        val showResultTabs =
            query.isNotBlank() && !isSearching && (hasSongHits || hasAlbumHits)

        if (showResultTabs) {
            TabRow(selectedTabIndex = searchResultsTab) {
                Tab(
                    selected = searchResultsTab == 0,
                    onClick = { searchResultsTab = 0 },
                    text = { Text("Songs (${results.size})") },
                    enabled = hasSongHits,
                )
                Tab(
                    selected = searchResultsTab == 1,
                    onClick = { searchResultsTab = 1 },
                    text = { Text("Albums (${albumResults.size})") },
                    enabled = hasAlbumHits,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
        }

        if (!isSearching && query.isNotBlank() && !hasSongHits && !hasAlbumHits) {
            Box(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "No results. Try another query or check Invidious / network.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(24.dp),
                )
            }
        }

        if (!isSearching && searchResultsTab == 0 && hasSongHits) {
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(results) { track ->
                    val idx = results.indexOfFirst { it.effectiveId == track.effectiveId }
                    com.fireball.nativeapp.ui.components.SuvFadeSlideInStaggered(index = idx) {
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
                            colors = androidx.compose.material3.CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                            ),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .combinedClickable(
                                        onClick = { onPlay(track, results) },
                                        onLongClick = { onOpenTrackMenu(track) },
                                    )
                                    .padding(10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(56.dp)
                                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                                        .background(MaterialTheme.colorScheme.surfaceVariant),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (!track.artwork.isNullOrBlank()) {
                                        coil.compose.AsyncImage(
                                            model = track.artwork,
                                            contentDescription = track.title,
                                            modifier = Modifier.fillMaxSize(),
                                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                        )
                                    } else {
                                        Icon(
                                            Icons.Default.MusicNote,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                            modifier = Modifier.size(28.dp),
                                        )
                                    }
                                }

                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        track.title,
                                        style = MaterialTheme.typography.titleSmall,
                                        maxLines = 1,
                                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        track.artist,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                    )
                                    if (!track.album.isNullOrBlank()) {
                                        Text(
                                            track.album!!,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            maxLines = 1,
                                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                        )
                                    }
                                }

                                val fav = isFavorite(track)
                                androidx.compose.material3.IconButton(onClick = { onToggleFavorite(track) }) {
                                    Icon(
                                        imageVector = if (fav) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                                        contentDescription = if (fav) {
                                            "Remove from favorites"
                                        } else {
                                            "Add to favorites"
                                        },
                                        tint = if (fav) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        } else if (!isSearching && searchResultsTab == 1 && hasAlbumHits) {
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(albumResults, key = { it.id }) { album ->
                    Card(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .clickable(onClick = { onPlayAlbum(album) }),
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
                        colors = androidx.compose.material3.CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                        ),
                    ) {
                        Row(
                            modifier =
                                Modifier
                                    .fillMaxWidth()
                                    .padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(56.dp)
                                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                                    .background(MaterialTheme.colorScheme.surfaceVariant),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (!album.artwork.isNullOrBlank()) {
                                    coil.compose.AsyncImage(
                                        model = album.artwork,
                                        contentDescription = album.title,
                                        modifier = Modifier.fillMaxSize(),
                                        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                    )
                                } else {
                                    Icon(
                                        Icons.Default.LibraryMusic,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(28.dp),
                                    )
                                }
                            }
                            Column(Modifier.weight(1f)) {
                                Text(album.title, style = MaterialTheme.typography.titleSmall, maxLines = 2)
                                Text(
                                    "${album.year ?: "—"} · ${album.artist}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun LibraryScreen(
    library: LibrarySnapshot,
    useGrid: Boolean,
    onPlay: (Track, List<Track>) -> Unit,
    onOpenPlaylist: (Playlist) -> Unit,
    onUnfollowArtist: (String) -> Unit = {},
    onCreatePlaylist: (String) -> Unit = {},
    onFollowArtistByName: (String) -> Unit = {},
    onOpenTrackMenu: (Track) -> Unit = {},
) {
    var creatingPlaylist by remember { mutableStateOf(false) }
    var newPlaylistTitle by remember { mutableStateOf("") }
    var followDialog by remember { mutableStateOf(false) }
    var followArtistName by remember { mutableStateOf("") }

    if (creatingPlaylist) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { creatingPlaylist = false },
            title = { Text("Create playlist") },
            text = {
                OutlinedTextField(
                    value = newPlaylistTitle,
                    onValueChange = { newPlaylistTitle = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onCreatePlaylist(newPlaylistTitle)
                        creatingPlaylist = false
                        newPlaylistTitle = ""
                    },
                    enabled = newPlaylistTitle.isNotBlank(),
                ) {
                    Text("Create")
                }
            },
            dismissButton = {
                TextButton(onClick = { creatingPlaylist = false }) { Text("Cancel") }
            },
        )
    }

    if (followDialog) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { followDialog = false },
            title = { Text("Follow artist") },
            text = {
                OutlinedTextField(
                    value = followArtistName,
                    onValueChange = { followArtistName = it },
                    label = { Text("Artist name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onFollowArtistByName(followArtistName)
                        followDialog = false
                        followArtistName = ""
                    },
                    enabled = followArtistName.isNotBlank(),
                ) {
                    Text("Follow")
                }
            },
            dismissButton = {
                TextButton(onClick = { followDialog = false }) { Text("Cancel") }
            },
        )
    }

    val libraryActions: @Composable () -> Unit = {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = { creatingPlaylist = true }) {
                Text("New playlist")
            }
            TextButton(onClick = { followDialog = true }) {
                Text("Follow artist")
            }
        }
    }

    if (useGrid) {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            libraryActions()
            if (library.playlists.isNotEmpty()) {
                Text("Playlists", style = MaterialTheme.typography.headlineSmall)
                library.playlists.forEach { pl ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenPlaylist(pl) },
                    ) {
                        Row(
                            Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(pl.title, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                            Text("${pl.videos.size}", style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }
            Text("Favorites", style = MaterialTheme.typography.headlineSmall)
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f)
            ) {
                gridItems(library.favorites) { track ->
                    TrackRow(
                        track = track,
                        onClick = { onPlay(track, library.favorites) },
                        onLongClick = { onOpenTrackMenu(track) },
                    )
                }
            }
            if (library.artists.isNotEmpty()) {
                Text("Followed artists", style = MaterialTheme.typography.headlineSmall)
                library.artists.forEach { artist ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(artist.name, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                            androidx.compose.material3.TextButton(onClick = { onUnfollowArtist(artist.artistId) }) {
                                Text("Unfollow")
                            }
                        }
                    }
                }
            }
        }
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                libraryActions()
            }
            if (library.playlists.isNotEmpty()) {
                item { Text("Playlists", style = MaterialTheme.typography.headlineSmall) }
                items(library.playlists, key = { it.id }) { pl ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenPlaylist(pl) },
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(pl.title, style = MaterialTheme.typography.titleMedium)
                            Text("${pl.videos.size}", style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }
            item { Text("Favorites", style = MaterialTheme.typography.headlineSmall) }
            if (library.favorites.isEmpty()) {
                item {
                    Text(
                        "No favorites yet — tap the heart in Search.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            items(library.favorites) { track ->
                TrackRow(
                    track = track,
                    onClick = { onPlay(track, library.favorites) },
                    onLongClick = { onOpenTrackMenu(track) },
                )
            }
            if (library.history.isNotEmpty()) {
                item { Text("History", style = MaterialTheme.typography.headlineSmall) }
                items(library.history.take(30)) { track ->
                    TrackRow(
                        track = track,
                        onClick = { onPlay(track, library.history) },
                        onLongClick = { onOpenTrackMenu(track) },
                    )
                }
            }
            if (library.artists.isNotEmpty()) {
                item { Text("Followed artists", style = MaterialTheme.typography.headlineSmall) }
                items(library.artists, key = { it.artistId }) { artist ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(artist.name, style = MaterialTheme.typography.titleMedium)
                            androidx.compose.material3.TextButton(onClick = { onUnfollowArtist(artist.artistId) }) {
                                Text("Unfollow")
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistDetailScreen(
    playlist: Playlist,
    isFavorite: (Track) -> Boolean,
    onBack: () -> Unit,
    onPlayAllFromPlaylist: () -> Unit,
    onPlayPlaylistUpNext: () -> Unit,
    onAddPlaylistToQueue: () -> Unit,
    onPlaySingleTrackFromPlaylist: (Track) -> Unit,
    onToggleFavorite: (Track) -> Unit,
    onOpenTrackMenu: (Track) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                Text(
                    playlist.title,
                    style = MaterialTheme.typography.titleLarge,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
            },
            navigationIcon = {
                androidx.compose.material3.IconButton(onClick = onBack) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                    )
                }
            },
        )
        if (playlist.videos.isEmpty()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "This playlist is empty. Add tracks from Search (long-press a song, then Add to playlist).",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(24.dp),
                )
            }
        } else {
            Row(
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Button(onClick = onPlayAllFromPlaylist) {
                    Text("Play")
                }
                OutlinedButton(onClick = onPlayPlaylistUpNext) {
                    Text("Play next")
                }
                OutlinedButton(onClick = onAddPlaylistToQueue) {
                    Text("Add to queue")
                }
            }

            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(playlist.videos, key = { it.effectiveId + it.title }) { track ->
                    Card(
                        colors = androidx.compose.material3.CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                        ),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .combinedClickable(
                                    onClick = { onPlaySingleTrackFromPlaylist(track) },
                                    onLongClick = { onOpenTrackMenu(track) },
                                )
                                .padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(52.dp)
                                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                                    .background(MaterialTheme.colorScheme.surfaceVariant),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (!track.artwork.isNullOrBlank()) {
                                    coil.compose.AsyncImage(
                                        model = track.artwork,
                                        contentDescription = track.title,
                                        modifier = Modifier.fillMaxSize(),
                                        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                    )
                                } else {
                                    Icon(
                                        Icons.Default.MusicNote,
                                        contentDescription = null,
                                        modifier = Modifier.size(24.dp),
                                    )
                                }
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    track.title,
                                    style = MaterialTheme.typography.titleSmall,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                )
                                Text(
                                    track.artist,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                                )
                            }
                            val fav = isFavorite(track)
                            IconButton(onClick = { onToggleFavorite(track) }) {
                                Icon(
                                    imageVector = if (fav) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                                    contentDescription = null,
                                    tint = if (fav) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsScreen(
    settings: FireballSettings,
    playbackState: PlaybackState,
    integrationStatus: String?,
    onSettingsChange: (FireballSettings) -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleRepeatMode: () -> Unit,
    onSetSleepTimer: (Int?) -> Unit,
    onSetSleepAfterCurrent: (Boolean) -> Unit,
    onWebDavPull: () -> Unit,
    onWebDavPush: () -> Unit,
    onGotifyTest: () -> Unit,
    onLbdlStatus: () -> Unit,
    onLbdlCreateJob: () -> Unit,
    onRemoteToggle: () -> Unit,
    onRemotePair: (String) -> Unit,
    onInvidiousLogin: (String, String) -> Unit,
    onInvidiousSyncPlaylist: (String) -> Unit,
    onInvidiousPushPlaylist: (String, String?) -> Unit,
    onInvidiousSignOut: () -> Unit,
    invidiousPlaylists: List<Pair<String, String>>,
    onGoogleDriveBackup: (String) -> Unit,
    onValidateLastFm: () -> Unit,
    onConnectLastFm: (String) -> Unit,
) {
    var page by remember { mutableStateOf(SettingsPage.Root) }

    when (page) {
        SettingsPage.Root -> SettingsRoot(
            settings = settings,
            integrationStatus = integrationStatus,
            onNavigate = { page = it },
        )

        SettingsPage.Playback -> SettingsPlayback(
            settings = settings,
            playbackState = playbackState,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
            onToggleShuffle = onToggleShuffle,
            onToggleRepeatMode = onToggleRepeatMode,
            onSetSleepTimer = onSetSleepTimer,
            onSetSleepAfterCurrent = onSetSleepAfterCurrent,
        )

        SettingsPage.Appearance -> SettingsAppearance(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
        )

        SettingsPage.General -> SettingsGeneral(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
        )

        SettingsPage.BugReproduction -> SettingsBugReproduction(
            onBack = { page = SettingsPage.Root },
        )

        SettingsPage.Bluetooth -> SettingsBluetooth(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
        )

        SettingsPage.Integrations -> SettingsIntegrations(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
            onInvidiousLogin = onInvidiousLogin,
            onInvidiousSyncPlaylist = onInvidiousSyncPlaylist,
            onInvidiousPushPlaylist = onInvidiousPushPlaylist,
            onInvidiousSignOut = onInvidiousSignOut,
            invidiousPlaylists = invidiousPlaylists
        )

        SettingsPage.Sync -> SettingsSync(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
            onWebDavPull = onWebDavPull,
            onWebDavPush = onWebDavPush,
            onGoogleDriveBackup = onGoogleDriveBackup,
        )

        SettingsPage.Advanced -> SettingsAdvanced(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
            onValidateLastFm = onValidateLastFm,
            onConnectLastFm = onConnectLastFm,
        )

        SettingsPage.RemoteAndNotifications -> SettingsRemoteAndNotifications(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
            onRemoteToggle = onRemoteToggle,
            onRemotePair = onRemotePair,
            onGotifyTest = onGotifyTest,
        )

        SettingsPage.Lbdl -> SettingsLbdl(
            settings = settings,
            onBack = { page = SettingsPage.Root },
            onSettingsChange = onSettingsChange,
            onLbdlStatus = onLbdlStatus,
            onLbdlCreateJob = onLbdlCreateJob,
        )
    }
}

private enum class SettingsPage {
    Root,
    Playback,
    Appearance,
    General,
    BugReproduction,
    Bluetooth,
    Integrations,
    Sync,
    RemoteAndNotifications,
    Lbdl,
    Advanced,
}

@Composable
private fun SettingsRoot(
    settings: FireballSettings,
    integrationStatus: String?,
    onNavigate: (SettingsPage) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .widthIn(max = 640.dp),
        contentPadding = PaddingValues(bottom = 96.dp),
    ) {
        item {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 20.dp),
            )
        }

        item {
            SettingsSectionTitle("Player & Audio")
            SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                SettingsNavigationRow(
                    icon = Icons.Default.GraphicEq,
                    title = "Playback",
                    subtitle = "Quality, queue, sleep timer",
                    onClick = { onNavigate(SettingsPage.Playback) },
                )
                ThinDivider()
                SettingsNavigationRow(
                    icon = Icons.Default.DarkMode,
                    title = "Appearance",
                    subtitle = "Theme, colors, lyrics motion",
                    onClick = { onNavigate(SettingsPage.Appearance) },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        item {
            SettingsSectionTitle("General")
            SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                SettingsNavigationRow(
                    icon = Icons.Default.WifiOff,
                    title = "General",
                    subtitle = "Offline, privacy, PiP & logs",
                    onClick = { onNavigate(SettingsPage.General) },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        item {
            SettingsSectionTitle("Bug Reproduction")
            SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                SettingsNavigationRow(
                    icon = Icons.Default.GraphicEq,
                    title = "Bug Reproduction",
                    subtitle = "SuvMusic session logs",
                    onClick = { onNavigate(SettingsPage.BugReproduction) },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        item {
            SettingsSectionTitle("Bluetooth")
            SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                SettingsNavigationRow(
                    icon = Icons.Default.HeadsetMic,
                    title = "Bluetooth",
                    subtitle = "Autoplay & announce songs",
                    onClick = { onNavigate(SettingsPage.Bluetooth) },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        item {
            SettingsSectionTitle("Integrations")
            SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                SettingsNavigationRow(
                    icon = Icons.Default.FastForward,
                    title = "Integrations",
                    subtitle = "SponsorBlock, ListenBrainz, Invidious, AI",
                    onClick = { onNavigate(SettingsPage.Integrations) },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        item {
            SettingsSectionTitle("Storage & Sync")
            SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                SettingsNavigationRow(
                    icon = Icons.Default.Sync,
                    title = "Sync & Backup",
                    subtitle = "WebDAV, Google Drive",
                    onClick = { onNavigate(SettingsPage.Sync) },
                )
                ThinDivider()
                SettingsNavigationRow(
                    icon = Icons.Default.Tune,
                    title = "Advanced",
                    subtitle = "Experimental + Suv extras",
                    onClick = { onNavigate(SettingsPage.Advanced) },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        item {
            SettingsSectionTitle("Remote")
            SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                SettingsNavigationRow(
                    icon = Icons.Default.Tune,
                    title = "Remote & Notifications",
                    subtitle = "LAN remote, Gotify",
                    onClick = { onNavigate(SettingsPage.RemoteAndNotifications) },
                )
                ThinDivider()
                SettingsNavigationRow(
                    icon = Icons.Default.Backup,
                    title = "LBDL",
                    subtitle = "Download helper",
                    onClick = { onNavigate(SettingsPage.Lbdl) },
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        if (!integrationStatus.isNullOrBlank()) {
            item {
                SettingsSectionTitle("Status")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    ListItem(
                        headlineContent = { Text("Integration status", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text(integrationStatus) },
                        leadingContent = { LeadingIconBox(Icons.Default.Info) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsScaffold(title: String, onBack: () -> Unit, content: @Composable () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text(title) },
            navigationIcon = {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    modifier = Modifier
                        .padding(horizontal = 12.dp)
                        .clickable(onClick = onBack),
                )
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
        )
        content()
    }
}

@Composable
private fun SettingsPlayback(
    settings: FireballSettings,
    playbackState: PlaybackState,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleRepeatMode: () -> Unit,
    onSetSleepTimer: (Int?) -> Unit,
    onSetSleepAfterCurrent: (Boolean) -> Unit,
) {
    SettingsScaffold(title = "Playback", onBack = onBack) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 96.dp),
        ) {
            item {
                SettingsSectionTitle("Audio")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.GraphicEq,
                        title = "High quality playback",
                        subtitle = "Prefer higher bitrate streams",
                        checked = settings.highQuality,
                        onCheckedChange = { onSettingsChange(settings.copy(highQuality = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Sync,
                        title = "Cache search results",
                        subtitle = "Keep recent search queries in memory",
                        checked = settings.cacheEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(cacheEnabled = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = if (settings.searchCacheMaxEntries > 0) {
                            settings.searchCacheMaxEntries.toString()
                        } else {
                            ""
                        },
                        onValueChange = { value ->
                            val n = value.toIntOrNull()
                            onSettingsChange(
                                settings.copy(searchCacheMaxEntries = n ?: 0)
                            )
                        },
                        label = { Text("Search cache max entries (0 = auto)") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Sync,
                        title = "Cache streams on disk",
                        subtitle = "ExoPlayer disk cache (Android)",
                        checked = settings.streamCacheEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(streamCacheEnabled = it)) },
                    )
                    ThinDivider()
                    Text(
                        text = "Queue mode at end",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        listOf("off" to "Off", "repeat" to "Repeat", "ai" to "AI").forEach { (key, label) ->
                            FilterChip(
                                selected = settings.queueMode.equals(key, ignoreCase = true),
                                onClick = { onSettingsChange(settings.copy(queueMode = key)) },
                                label = { Text(label) },
                            )
                        }
                    }
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.localMusicCacheLimit.toString(),
                        onValueChange = { value ->
                            value.toIntOrNull()?.let { onSettingsChange(settings.copy(localMusicCacheLimit = it)) }
                        },
                        label = { Text("Stream disk cache size (GB)") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }

            item {
                SettingsSectionTitle("Queue & Sleep")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    ListItem(
                        headlineContent = { Text("Repeat mode", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text(playbackState.repeatMode.name) },
                        leadingContent = { LeadingIconBox(Icons.Default.Tune) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Shuffle", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text(if (playbackState.shuffled) "On" else "Off") },
                        leadingContent = { LeadingIconBox(Icons.Default.Tune) },
                        trailingContent = {
                            Button(onClick = onToggleShuffle) { Text(if (playbackState.shuffled) "Unshuffle" else "Shuffle") }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Repeat", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Cycle repeat mode") },
                        leadingContent = { LeadingIconBox(Icons.Default.Tune) },
                        trailingContent = { Button(onClick = onToggleRepeatMode) { Text("Cycle") } },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Tune,
                        title = "Sleep after current track",
                        subtitle = "Stop playback when this track ends",
                        checked = playbackState.sleepAfterCurrent,
                        onCheckedChange = onSetSleepAfterCurrent,
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Sleep timer", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Set or clear sleep timer") },
                        leadingContent = { LeadingIconBox(Icons.Default.Tune) },
                        trailingContent = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = { onSetSleepTimer(15) }) { Text("15m") }
                                Button(onClick = { onSetSleepTimer(null) }) { Text("Clear") }
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SettingsAppearance(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
) {
    SettingsScaffold(title = "Appearance", onBack = onBack) {
        LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                SettingsSectionTitle("Theme")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    val effectiveChrome =
                        settings.appearanceColorSource.trim().lowercase().ifBlank {
                            if (settings.useDynamicColorWhenAvailable) "material_you" else "scheme"
                        }
                    Text(
                        text = "Chrome color source",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    LazyRow(
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        val modes =
                            listOf(
                                "material_you" to "Material You",
                                "music" to "Album art",
                                "scheme" to "Preset scheme",
                            )
                        items(modes.size) { idx ->
                            val (key, label) = modes[idx]
                            FilterChip(
                                selected = effectiveChrome == key,
                                onClick = {
                                    onSettingsChange(
                                        settings.copy(
                                            appearanceColorSource = key,
                                            useDynamicColorWhenAvailable = key == "material_you",
                                        ),
                                    )
                                },
                                label = { Text(label) },
                            )
                        }
                    }
                    Text(
                        text = "Persists as appearanceColorSource (music | scheme | material_you).",
                        style = MaterialTheme.typography.bodySmall,
                        modifier =
                            Modifier
                                .padding(horizontal = 16.dp)
                                .padding(bottom = 8.dp),
                    )
                    ThinDivider()
                    Text(
                        text = "Theme mode",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        listOf("system", "light", "dark").forEach { mode ->
                            FilterChip(
                                selected = settings.themeMode.equals(mode, ignoreCase = true),
                                onClick = { onSettingsChange(settings.copy(themeMode = mode)) },
                                label = { Text(mode.replaceFirstChar { it.uppercase() }) },
                            )
                        }
                    }
                    ThinDivider()
                    Text(
                        text = "Color scheme",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    LazyRow(
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        val schemes = listOf(
                            "deepPurple" to "Purple",
                            "ocean" to "Ocean",
                            "sunset" to "Sunset",
                            "nature" to "Nature",
                            "mandyRed" to "Love",
                        )
                        items(schemes.size) { index ->
                            val (key, label) = schemes[index]
                            FilterChip(
                                selected = settings.flexScheme.equals(key, ignoreCase = true) ||
                                    (key == "deepPurple" && settings.flexScheme.isBlank()),
                                onClick = { onSettingsChange(settings.copy(flexScheme = key)) },
                                label = { Text(label) },
                            )
                        }
                    }
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.accentSeedColor?.let { "0x${it.toUInt().toString(16)}" } ?: "",
                        onValueChange = { raw ->
                            val trimmed = raw.trim().removePrefix("0x").removePrefix("#")
                            val parsed = if (trimmed.isBlank()) {
                                null
                            } else {
                                trimmed.toULongOrNull(16)?.toInt()
                            }
                            onSettingsChange(settings.copy(accentSeedColor = parsed))
                        },
                        label = { Text("Accent seed color (ARGB hex, optional)") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }

            item {
                SettingsSectionTitle("Lyrics")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.Tune,
                        title = "Auto-scroll lyrics",
                        subtitle = "Scroll synced lyrics automatically",
                        checked = settings.lyricsAutoScroll,
                        onCheckedChange = { onSettingsChange(settings.copy(lyricsAutoScroll = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Tune,
                        title = "Reduce lyrics motion",
                        subtitle = "Fewer animations in lyrics view",
                        checked = settings.lyricsReducedMotion,
                        onCheckedChange = { onSettingsChange(settings.copy(lyricsReducedMotion = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Tune,
                        title = "Prefer English/Hindi lyrics",
                        subtitle = "Prefer these when multiple options exist",
                        checked = settings.lyricsPreferEnglishHindi,
                        onCheckedChange = { onSettingsChange(settings.copy(lyricsPreferEnglishHindi = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Lyrics,
                        title = "Always show lyrics panel",
                        subtitle = "Extra lyrics strip below seek when lyrics replace artwork",
                        checked = settings.alwaysShowLyricsPanel,
                        onCheckedChange = { onSettingsChange(settings.copy(alwaysShowLyricsPanel = it)) },
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SettingsGeneral(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
) {
    var localStatus by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    SettingsScaffold(title = "General", onBack = onBack) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 96.dp),
        ) {
            item {
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.WifiOff,
                        title = "Offline Mode",
                        subtitle = "Only play downloaded songs",
                        checked = settings.offlineModeEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(offlineModeEnabled = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.VisibilityOff,
                        title = "Privacy Mode",
                        subtitle = "Stop history & activity sharing",
                        checked = settings.privacyModeEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(privacyModeEnabled = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.PictureInPicture,
                        title = "Picture-in-Picture",
                        subtitle = "Show mini player when backgrounded",
                        checked = settings.dynamicIslandEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(dynamicIslandEnabled = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Warning,
                        title = "Crash Reporting & Logging",
                        subtitle = "Help developer fix issues by sharing logs",
                        checked = settings.loggingEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(loggingEnabled = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Tune,
                        title = "Collapse tablet sidebar",
                        subtitle = "Icon-only navigation rail on large screens",
                        checked = settings.ipadSidebarCollapsed,
                        onCheckedChange = { onSettingsChange(settings.copy(ipadSidebarCollapsed = it)) },
                    )
                    ThinDivider()
                    Text(
                        text = "Home chart regions",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    LazyRow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        val selected = settings.homeCountries.toSet()
                        items(com.fireball.nativeapp.ui.HomeCountries.all.size) { index ->
                            val (code, name) = com.fireball.nativeapp.ui.HomeCountries.all[index]
                            val isOn = selected.contains(code)
                            FilterChip(
                                selected = isOn,
                                onClick = {
                                    val next = if (isOn) selected - code else selected + code
                                    onSettingsChange(settings.copy(homeCountries = next.toList()))
                                },
                                label = { Text(name) },
                            )
                        }
                    }

                    if (settings.loggingEnabled) {
                        ThinDivider()
                        ListItem(
                            headlineContent = { Text("Share App Logs", fontWeight = FontWeight.Medium) },
                            supportingContent = { Text("Captures filtered Fireball logs from logcat") },
                            leadingContent = { LeadingIconBox(Icons.Default.Info) },
                            trailingContent = {},
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    localStatus = "Capturing logs..."
                                    scope.launch {
                                        val logs = captureFireballLogcat()
                                        shareText(
                                            context = context,
                                            subject = "Fireball logs",
                                            body = logs
                                        )
                                        localStatus = "Logs captured. Share sheet opened."
                                    }
                                }
                                .clip(androidx.compose.foundation.shape.RoundedCornerShape(28.dp)),
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        )
                    }
                }

                if (localStatus != null) {
                    Text(
                        text = localStatus.orEmpty(),
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsBluetooth(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
) {
    SettingsScaffold(title = "Bluetooth", onBack = onBack) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 96.dp),
        ) {
            item {
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.HeadsetMic,
                        title = "Bluetooth Autoplay",
                        subtitle = "Resume when connecting to devices",
                        checked = settings.bluetoothAutoplayEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(bluetoothAutoplayEnabled = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Lyrics,
                        title = "Announce Songs",
                        subtitle = "Speak title when song changes (TTS)",
                        checked = settings.speakSongDetailsEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(speakSongDetailsEnabled = it)) },
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsBugReproduction(
    onBack: () -> Unit,
) {
    var sessionActive by remember { mutableStateOf(false) }
    var localStatus by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    SettingsScaffold(title = "Bug Reproduction", onBack = onBack) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 96.dp),
        ) {
            item {
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    ListItem(
                        headlineContent = { Text("SuvMusic Session", fontWeight = FontWeight.SemiBold) },
                        supportingContent = {
                            Text(
                                if (sessionActive) "Recording logs... Reproduce the bug now"
                                else "Start a session to capture logs for debugging"
                            )
                        },
                        leadingContent = { LeadingIconBox(if (sessionActive) Icons.Default.GraphicEq else Icons.Default.MusicNote) },
                        trailingContent = {
                            Button(onClick = {
                                if (!sessionActive) {
                                    sessionActive = true
                                    localStatus = "Recording... (will capture logcat dump on stop)"
                                } else {
                                    localStatus = "Capturing logs..."
                                    sessionActive = false
                                    scope.launch {
                                        val logs = captureFireballLogcat()
                                        shareText(
                                            context = context,
                                            subject = "Fireball bug logs",
                                            body = logs
                                        )
                                        localStatus = "Logs captured. Share sheet opened."
                                    }
                                }
                            }) {
                                Text(if (sessionActive) "Stop & Share" else "Start")
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(androidx.compose.foundation.shape.RoundedCornerShape(28.dp)),
                    )
                }

                if (localStatus != null) {
                    Text(
                        text = localStatus.orEmpty(),
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsIntegrations(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
    onInvidiousLogin: (String, String) -> Unit,
    onInvidiousSyncPlaylist: (String) -> Unit,
    onInvidiousPushPlaylist: (String, String?) -> Unit,
    onInvidiousSignOut: () -> Unit,
    invidiousPlaylists: List<Pair<String, String>>
) {
    var invidiousUser by remember(settings.invidiousUsername) {
        mutableStateOf(settings.invidiousUsername.orEmpty())
    }
    var invidiousPass by remember { mutableStateOf("") }
    var syncPlaylistId by remember { mutableStateOf("") }
    var localPlaylistId by remember { mutableStateOf("") }
    var remotePlaylistId by remember { mutableStateOf("") }

    SettingsScaffold(title = "Integrations", onBack = onBack) {
        LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                SettingsSectionTitle("SponsorBlock")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.FastForward,
                        title = "Enable SponsorBlock",
                        subtitle = "Skip non-music segments",
                        checked = settings.sponsorBlock,
                        onCheckedChange = { enabled ->
                            val categories = if (enabled && settings.sponsorBlockCategories.isEmpty()) {
                                listOf("sponsor", "music_offtopic")
                            } else {
                                settings.sponsorBlockCategories
                            }
                            onSettingsChange(
                                settings.copy(sponsorBlock = enabled, sponsorBlockCategories = categories)
                            )
                        },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.sponsorBlockCategories.joinToString(","),
                        onValueChange = {
                            val categories = it.split(",").map(String::trim).filter(String::isNotBlank)
                            onSettingsChange(settings.copy(sponsorBlockCategories = categories))
                        },
                        label = { Text("Skip categories (csv)") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
            item {
                SettingsSectionTitle("ListenBrainz")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.Sync,
                        title = "Enable ListenBrainz",
                        subtitle = "Scrobble and now playing updates",
                        checked = settings.listenBrainzEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(listenBrainzEnabled = it)) },
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Sync,
                        title = "Submit now playing",
                        subtitle = "Send currently playing updates",
                        checked = settings.listenBrainzPlayingNow,
                        onCheckedChange = { onSettingsChange(settings.copy(listenBrainzPlayingNow = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.listenBrainzToken,
                        onValueChange = { onSettingsChange(settings.copy(listenBrainzToken = it)) },
                        label = { Text("ListenBrainz token") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.listenBrainzUsername,
                        onValueChange = { onSettingsChange(settings.copy(listenBrainzUsername = it)) },
                        label = { Text("ListenBrainz username") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Sync,
                        title = "Enable scrobbling",
                        subtitle = "ListenBrainz + Last.fm when configured",
                        checked = settings.scrobbleEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(scrobbleEnabled = it)) },
                    )
                    ThinDivider()
                    Text(
                        "Scrobble when either threshold is reached first. " +
                            "Tracks shorter than ${settings.listenBrainzScrobbleMinTrackSeconds}s are skipped " +
                            "(Last.fm rule). ListenBrainz recommends half the track or 4 min (whichever is lower).",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    Text(
                        "At ${settings.listenBrainzScrobblePercent}% of track",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Slider(
                        value = settings.listenBrainzScrobblePercent.toFloat().coerceIn(5f, 95f),
                        onValueChange = {
                            onSettingsChange(
                                settings.copy(listenBrainzScrobblePercent = it.roundToInt().coerceIn(5, 95))
                            )
                        },
                        valueRange = 5f..95f,
                        steps = 17,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Text(
                        "Or after ${settings.listenBrainzScrobbleMaxSeconds}s",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Slider(
                        value = settings.listenBrainzScrobbleMaxSeconds.toFloat().coerceIn(10f, 240f),
                        onValueChange = {
                            onSettingsChange(
                                settings.copy(listenBrainzScrobbleMaxSeconds = it.roundToInt().coerceIn(10, 240))
                            )
                        },
                        valueRange = 10f..240f,
                        steps = 22,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Text(
                        "Minimum track length: ${settings.listenBrainzScrobbleMinTrackSeconds}s",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Slider(
                        value = settings.listenBrainzScrobbleMinTrackSeconds.toFloat().coerceIn(15f, 120f),
                        onValueChange = {
                            onSettingsChange(
                                settings.copy(
                                    listenBrainzScrobbleMinTrackSeconds = it.roundToInt().coerceIn(15, 120)
                                )
                            )
                        },
                        valueRange = 15f..120f,
                        steps = 20,
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .padding(bottom = 8.dp),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
            item {
                SettingsSectionTitle("YouTube / Invidious")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    // Instance URL
                    OutlinedTextField(
                        value = settings.invidiousInstance,
                        onValueChange = { onSettingsChange(settings.copy(invidiousInstance = it)) },
                        label = { Text("Instance URL") },
                        placeholder = { Text("https://invidious.example.com") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("New playlist privacy", fontWeight = FontWeight.Medium) },
                        supportingContent = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf("public", "unlisted", "private").forEach { value ->
                                    FilterChip(
                                        selected = settings.invidiousPlaylistPrivacy.equals(value, ignoreCase = true),
                                        onClick = { onSettingsChange(settings.copy(invidiousPlaylistPrivacy = value)) },
                                        label = { Text(value.replaceFirstChar { it.uppercase() }) },
                                    )
                                }
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    ThinDivider()

                    // Logged-in state — exactly like Flutter
                    if (!settings.invidiousUsername.isNullOrBlank()) {
                        ListItem(
                            headlineContent = { Text("Logged in as", fontWeight = FontWeight.Medium) },
                            supportingContent = {
                                Text(
                                    settings.invidiousUsername ?: "",
                                    color = MaterialTheme.colorScheme.primary
                                )
                            },
                            leadingContent = { LeadingIconBox(Icons.Default.AccountCircle) },
                            trailingContent = {
                                androidx.compose.material3.TextButton(onClick = onInvidiousSignOut) {
                                    Text("Sign out", color = MaterialTheme.colorScheme.error)
                                }
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        )
                    } else {
                        // Login form — only when not logged in
                        ListItem(
                            headlineContent = { Text("Login (optional)", fontWeight = FontWeight.Medium) },
                            supportingContent = { Text("Sign in to sync playlists") },
                            leadingContent = { LeadingIconBox(Icons.AutoMirrored.Filled.Login) },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        )
                        OutlinedTextField(
                            value = invidiousUser,
                            onValueChange = { invidiousUser = it },
                            label = { Text("Username") },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 4.dp)
                        )
                        OutlinedTextField(
                            value = invidiousPass,
                            onValueChange = { invidiousPass = it },
                            label = { Text("Password") },
                            visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 4.dp)
                        )
                        Button(
                            onClick = { onInvidiousLogin(invidiousUser, invidiousPass) },
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        ) {
                            Icon(Icons.AutoMirrored.Filled.Login, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Login")
                        }
                    }

                    if (!settings.invidiousUsername.isNullOrBlank() && invidiousPlaylists.isNotEmpty()) {
                        ThinDivider()
                        Text("My Playlists", modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp), fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                        invidiousPlaylists.forEach { pl ->
                            ListItem(
                                headlineContent = { Text(pl.second, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) },
                                supportingContent = { Text(pl.first) },
                                leadingContent = { LeadingIconBox(Icons.AutoMirrored.Filled.PlaylistPlay) },
                                trailingContent = {
                                    androidx.compose.material3.TextButton(onClick = {
                                        onInvidiousSyncPlaylist(pl.first)
                                    }) {
                                        Text("Sync")
                                    }
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
                    }

                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Sync,
                        title = "Auto-push mapped playlists",
                        subtitle = "Push local updates to mapped Invidious playlists",
                        checked = settings.invidiousAutoPush,
                        onCheckedChange = { onSettingsChange(settings.copy(invidiousAutoPush = it)) },
                    )
                    val favoritesRemoteId = settings.invidiousPlaylistMappings["favorites"].orEmpty()
                    OutlinedTextField(
                        value = favoritesRemoteId,
                        onValueChange = { remote ->
                            val next = settings.invidiousPlaylistMappings.toMutableMap()
                            if (remote.isBlank()) next.remove("favorites") else next["favorites"] = remote.trim()
                            onSettingsChange(settings.copy(invidiousPlaylistMappings = next))
                        },
                        label = { Text("Invidious favorites playlist ID") },
                        placeholder = { Text("Remote playlist id for auto-push") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    Text(
                        text = "Stream resolution uses your Invidious instance (optional), public mirrors, then on-device YouTube extract. No separate proxy is required.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                Spacer(modifier = Modifier.height(16.dp))
                SettingsSectionTitle("Playlist Sync")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    OutlinedTextField(
                        value = syncPlaylistId,
                        onValueChange = { syncPlaylistId = it },
                        label = { Text("Remote playlist ID to sync") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Sync remote playlist", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Pull playlist into local library") },
                        leadingContent = { LeadingIconBox(Icons.Default.Sync) },
                        trailingContent = { Button(onClick = { onInvidiousSyncPlaylist(syncPlaylistId) }) { Text("Sync") } },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = localPlaylistId,
                        onValueChange = { localPlaylistId = it },
                        label = { Text("Local playlist ID to push") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = remotePlaylistId,
                        onValueChange = { remotePlaylistId = it },
                        label = { Text("Existing remote playlist ID (optional)") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Push local playlist", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Creates or appends to remote playlist") },
                        leadingContent = { LeadingIconBox(Icons.Default.Backup) },
                        trailingContent = {
                            Button(onClick = { onInvidiousPushPlaylist(localPlaylistId, remotePlaylistId.ifBlank { null }) }) { Text("Push") }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
            item {
                SettingsSectionTitle("AI Queue (Ollama)")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.AutoAwesome,
                        title = "Enable AI queue",
                        subtitle = "Append recommendations when queue ends",
                        checked = settings.ollamaEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(ollamaEnabled = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.ollamaUrl,
                        onValueChange = { onSettingsChange(settings.copy(ollamaUrl = it)) },
                        label = { Text("Ollama URL") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.ollamaModel,
                        onValueChange = { onSettingsChange(settings.copy(ollamaModel = it)) },
                        label = { Text("Ollama model") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
            item {
                SettingsSectionTitle("Suv Extras")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    OutlinedTextField(
                        value = settings.startTab,
                        onValueChange = {
                            onSettingsChange(settings.copy(startTab = it.lowercase().trim()))
                        },
                        label = { Text("Start tab (home/search/library/settings)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.LibraryMusic,
                        title = "Library grid layout",
                        subtitle = "Show favorites in a grid",
                        checked = settings.libraryUseGrid,
                        onCheckedChange = { onSettingsChange(settings.copy(libraryUseGrid = it)) },
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SettingsSync(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
    onWebDavPull: () -> Unit,
    onWebDavPush: () -> Unit,
    onGoogleDriveBackup: (String) -> Unit,
) {
    var gDriveToken by remember { mutableStateOf("") }
    SettingsScaffold(title = "Sync & Backup", onBack = onBack) {
        LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                SettingsSectionTitle("WebDAV")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.Sync,
                        title = "WebDAV live sync",
                        subtitle = "Sync library automatically",
                        checked = settings.webDavLiveSync,
                        onCheckedChange = { onSettingsChange(settings.copy(webDavLiveSync = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.webDavUrl,
                        onValueChange = { onSettingsChange(settings.copy(webDavUrl = it)) },
                        label = { Text("WebDAV URL") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.webDavUsername,
                        onValueChange = { onSettingsChange(settings.copy(webDavUsername = it)) },
                        label = { Text("WebDAV username") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.webDavPassword,
                        onValueChange = { onSettingsChange(settings.copy(webDavPassword = it)) },
                        label = { Text("WebDAV password") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Manual sync", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Pull or push library JSON") },
                        leadingContent = { LeadingIconBox(Icons.Default.Sync) },
                        trailingContent = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = onWebDavPull) { Text("Pull") }
                                Button(onClick = onWebDavPush) { Text("Push") }
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
            item {
                SettingsSectionTitle("Google Drive")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.Backup,
                        title = "Google Drive backup",
                        subtitle = "Sync backup JSON to Drive",
                        checked = settings.gDriveEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(gDriveEnabled = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.lastBackupAt ?: "",
                        onValueChange = {},
                        enabled = false,
                        label = { Text("Last backup timestamp") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = gDriveToken,
                        onValueChange = { gDriveToken = it },
                        label = { Text("Google Drive access token") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    Button(
                        onClick = {
                            onGoogleDriveBackup(gDriveToken.trim())
                            gDriveToken = ""
                        },
                        enabled = settings.gDriveEnabled && gDriveToken.isNotBlank(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        Text("Backup library to Google Drive")
                    }
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SettingsRemoteAndNotifications(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
    onRemoteToggle: () -> Unit,
    onRemotePair: (String) -> Unit,
    onGotifyTest: () -> Unit,
) {
    var pairCode by remember { mutableStateOf("") }
    SettingsScaffold(title = "Remote & Notifications", onBack = onBack) {
        LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                SettingsSectionTitle("Remote")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.Tune,
                        title = "Remote control (client)",
                        subtitle = "Send commands to another Fireball device on the LAN (this app does not host a server)",
                        checked = settings.remoteServerEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(remoteServerEnabled = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.remoteHostIp,
                        onValueChange = { onSettingsChange(settings.copy(remoteHostIp = it)) },
                        label = { Text("Remote LAN host") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.remotePeerPort.toString(),
                        onValueChange = { value ->
                            value.toIntOrNull()?.let { onSettingsChange(settings.copy(remotePeerPort = it)) }
                        },
                        label = { Text("Remote LAN port") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = pairCode,
                        onValueChange = { pairCode = it },
                        label = { Text("Remote pair code") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Remote actions", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Toggle or pair a remote") },
                        leadingContent = { LeadingIconBox(Icons.Default.Tune) },
                        trailingContent = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = onRemoteToggle) { Text("Toggle") }
                                Button(onClick = { onRemotePair(pairCode) }) { Text("Pair") }
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }

            item {
                SettingsSectionTitle("Artist releases")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.Notifications,
                        title = "Device notifications",
                        subtitle = "Ping when followed artists publish a new iTunes album row (runs with Gotify when enabled)",
                        checked = settings.notifyArtistReleasesOnDevice,
                        onCheckedChange = { onSettingsChange(settings.copy(notifyArtistReleasesOnDevice = it)) },
                    )
                    Text(
                        text = "POST_NOTIFICATIONS is requested when the toggle turns on or at launch on Android 13+.",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }

            item {
                SettingsSectionTitle("Gotify")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingsSwitchRow(
                        icon = Icons.Default.Info,
                        title = "Enable Gotify",
                        subtitle = "Notifications integration",
                        checked = settings.gotifyEnabled,
                        onCheckedChange = { onSettingsChange(settings.copy(gotifyEnabled = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.gotifyUrl,
                        onValueChange = { onSettingsChange(settings.copy(gotifyUrl = it)) },
                        label = { Text("Gotify URL") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.gotifyToken,
                        onValueChange = { onSettingsChange(settings.copy(gotifyToken = it)) },
                        label = { Text("Gotify token") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Send test message", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Verify Gotify configuration") },
                        leadingContent = { LeadingIconBox(Icons.Default.Info) },
                        trailingContent = { Button(onClick = onGotifyTest) { Text("Test") } },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SettingsLbdl(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
    onLbdlStatus: () -> Unit,
    onLbdlCreateJob: () -> Unit,
) {
    SettingsScaffold(title = "LBDL", onBack = onBack) {
        LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                SettingsSectionTitle("Download helper")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    OutlinedTextField(
                        value = settings.lbdlUrl,
                        onValueChange = { onSettingsChange(settings.copy(lbdlUrl = it)) },
                        label = { Text("LBDL URL") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.lbdlUsername,
                        onValueChange = { onSettingsChange(settings.copy(lbdlUsername = it)) },
                        label = { Text("LBDL username") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.lbdlPassword,
                        onValueChange = { onSettingsChange(settings.copy(lbdlPassword = it)) },
                        label = { Text("LBDL password") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Status", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Check LBDL auth") },
                        leadingContent = { LeadingIconBox(Icons.Default.Info) },
                        trailingContent = { Button(onClick = onLbdlStatus) { Text("Check") } },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    ThinDivider()
                    ListItem(
                        headlineContent = { Text("Queue job", fontWeight = FontWeight.Medium) },
                        supportingContent = { Text("Create a job from current queue") },
                        leadingContent = { LeadingIconBox(Icons.Default.Backup) },
                        trailingContent = { Button(onClick = onLbdlCreateJob) { Text("Create") } },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SettingsAdvanced(
    settings: FireballSettings,
    onBack: () -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
    onValidateLastFm: () -> Unit,
    onConnectLastFm: (String) -> Unit,
) {
    var lastFmPassword by remember { mutableStateOf("") }
    SettingsScaffold(title = "Advanced", onBack = onBack) {
        LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                SettingsSectionTitle("Experimental")
                SettingsCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                    OutlinedTextField(
                        value = settings.customDownloadPath ?: "",
                        onValueChange = {
                            onSettingsChange(
                                settings.copy(customDownloadPath = it.ifBlank { null })
                            )
                        },
                        label = { Text("Custom download path") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    SettingsSwitchRow(
                        icon = Icons.Default.Tune,
                        title = "Analytics",
                        subtitle = "Enable analytics events",
                        checked = settings.analytics,
                        onCheckedChange = { onSettingsChange(settings.copy(analytics = it)) },
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.lastFmApiKey,
                        onValueChange = { onSettingsChange(settings.copy(lastFmApiKey = it)) },
                        label = { Text("Last.fm API key") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.lastFmApiSecret,
                        onValueChange = { onSettingsChange(settings.copy(lastFmApiSecret = it)) },
                        label = { Text("Last.fm shared secret") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = settings.lastFmUsername,
                        onValueChange = { onSettingsChange(settings.copy(lastFmUsername = it)) },
                        label = { Text("Last.fm username") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    ThinDivider()
                    OutlinedTextField(
                        value = lastFmPassword,
                        onValueChange = { lastFmPassword = it },
                        label = { Text("Last.fm password (not saved)") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                    if (settings.lastFmSessionKey.isNotBlank()) {
                        ThinDivider()
                        Text(
                            text = "Last.fm session active",
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        TextButton(onClick = onValidateLastFm) { Text("Validate key") }
                        TextButton(onClick = { onConnectLastFm(lastFmPassword) }) { Text("Connect") }
                    }
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SettingsSectionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
    )
}

@Composable
private fun SettingsCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.8f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        border = androidx.compose.foundation.BorderStroke(
            width = 1.dp,
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
        ),
        tonalElevation = 1.dp,
    ) {
        Column(modifier = Modifier.padding(vertical = 8.dp)) { content() }
    }
}

@Composable
private fun ThinDivider() {
    M3HorizontalDivider(
        modifier = Modifier.padding(horizontal = 16.dp),
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.2f),
    )
}

@Composable
private fun LeadingIconBox(icon: ImageVector) {
    Box(
        modifier = Modifier
            .size(40.dp)
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(28.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun SettingsNavigationRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title, fontWeight = FontWeight.Medium) },
        supportingContent = subtitle?.let { { Text(it, maxLines = 1) } },
        leadingContent = { LeadingIconBox(icon) },
        trailingContent = {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForwardIos,
                contentDescription = null,
                modifier = Modifier.size(12.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
        },
        modifier = Modifier
            .clickable(onClick = onClick)
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(28.dp)),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@Composable
private fun SettingsSwitchRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    ListItem(
        headlineContent = { Text(title, fontWeight = FontWeight.Medium) },
        supportingContent = subtitle?.let { { Text(it, maxLines = 1) } },
        leadingContent = { LeadingIconBox(icon) },
        trailingContent = {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = MaterialTheme.colorScheme.onPrimary,
                    checkedTrackColor = MaterialTheme.colorScheme.primary,
                ),
            )
        },
        modifier = Modifier
            .clickable { onCheckedChange(!checked) }
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(28.dp)),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

private suspend fun captureFireballLogcat(
    maxLines: Int = 2500,
    maxChars: Int = 250_000,
): String = withContext(Dispatchers.IO) {
    val process = runCatching {
        Runtime.getRuntime().exec(arrayOf("sh", "-c", "logcat -d -v time"))
    }.getOrNull() ?: return@withContext "Failed to run logcat."

    val reader = process.inputStream.bufferedReader()
    val sb = StringBuilder()
    var matched = 0

    try {
        while (true) {
            val line = reader.readLine() ?: break
            val isRelevant =
                line.contains("com.fireball.nativeapp") ||
                line.contains("AndroidRuntime") ||
                line.contains("FATAL EXCEPTION")
            if (!isRelevant) continue

            sb.append(line).append('\n')
            matched++
            if (matched >= maxLines || sb.length >= maxChars) break
        }
    } catch (_: Throwable) {
        // Best-effort only; still allow sharing what we got so far.
    } finally {
        runCatching { reader.close() }
        runCatching { process.destroy() }
    }

    if (sb.isBlank()) {
        "No Fireball-specific log lines found in logcat dump. Try reproducing the issue again, then share logs."
    } else {
        sb.toString()
    }
}

private fun shareText(
    context: android.content.Context,
    subject: String,
    body: String
) {
    val safeBody = if (body.length > 50_000) body.take(50_000) + "\n\n[truncated]" else body
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, subject)
        putExtra(Intent.EXTRA_TEXT, safeBody)
    }
    context.startActivity(Intent.createChooser(intent, "Share"))
}

@Composable
private fun TrackRow(
    track: Track,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
) {
    val cardModifier =
        Modifier
            .fillMaxWidth()
            .then(
                if (onLongClick != null) {
                    Modifier.combinedClickable(
                        onClick = onClick,
                        onLongClick = onLongClick,
                    )
                } else {
                    Modifier.clickable(onClick = onClick)
                },
            )
    Card(
        modifier = cardModifier,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
        colors = androidx.compose.material3.CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        )
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center
            ) {
                if (!track.artwork.isNullOrBlank()) {
                    coil.compose.AsyncImage(
                        model = track.artwork,
                        contentDescription = track.title,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = androidx.compose.ui.layout.ContentScale.Crop
                    )
                } else {
                    Icon(
                        Icons.Default.MusicNote,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(24.dp)
                    )
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    track.title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                )
                Text(
                    track.artist,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                )
            }
        }
    }
}

package com.fireball.nativeapp.ui.screens

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.material3.TextButton
import com.fireball.nativeapp.core.model.FireballSettings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.fireball.nativeapp.data.ArtistBrowseResult
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.ui.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ArtistDetailRoute(
    parsedKey: String,
    encodedName: String,
    library: com.fireball.nativeapp.core.model.LibrarySnapshot,
    viewModel: MainViewModel,
    onBack: () -> Unit,
    onOverflowTrack: (Track) -> Unit,
    onSettingsChange: (FireballSettings) -> Unit,
) {
    val fallbackDisplay = Uri.decode(encodedName).ifBlank { "Artist" }
    val appleId =
        if (parsedKey.startsWith("i")) parsedKey.drop(1).toIntOrNull()
        else null

    var browse by remember { mutableStateOf<ArtistBrowseResult?>(null) }
    var loading by remember { mutableStateOf(true) }
    var albumLoadingId by remember { mutableStateOf<String?>(null) }
    var albumTracksPick by remember { mutableStateOf<List<Track>?>(null) }
    var tab by remember { mutableIntStateOf(0) }
    val titles = listOf("Songs", "Albums")
    val scope = rememberCoroutineScope()

    LaunchedEffect(parsedKey, encodedName, library.artists.size, library.playlists.size) {
        loading = true
        browse =
            try {
                withContext(Dispatchers.IO) {
                    viewModel.browseArtistPage(appleId, fallbackDisplay)
                }
            } catch (_: Exception) {
                null
            }
        loading = false
    }

    albumTracksPick?.let { picks ->
        AlertDialog(
            onDismissRequest = { albumTracksPick = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (picks.isNotEmpty()) viewModel.play(picks.first(), picks)
                        albumTracksPick = null
                    },
                ) {
                    Text("Play album")
                }
            },
            dismissButton = {
                TextButton(onClick = { albumTracksPick = null }) {
                    Text("Cancel")
                }
            },
            title = { Text("Album tracks") },
            text = {
                Text(
                    if (picks.isEmpty()) {
                        "No tracks found."
                    } else {
                        picks.joinToString(separator = "\n") { "· ${it.title}" }.take(800).let {
                            if (it.length >= 800) "$it…" else it
                        }
                    },
                )
            },
        )
    }

    when {
        loading ->
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator()
            }

        browse == null ->
            Column(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Could not load \"$fallbackDisplay\". Check your network.",
                    style = MaterialTheme.typography.bodyLarge,
                )
                Spacer(Modifier.height(16.dp))
                TextButton(onClick = onBack) { Text("Back") }
            }

        else -> {
            val b = browse!!
            Scaffold(
                topBar = {
                    Row(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                        Text(
                            text = b.displayName,
                            style = MaterialTheme.typography.titleLarge,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                },
            ) { inner ->
                LazyColumn(
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .padding(inner)
                            .padding(horizontal = 16.dp),
                ) {
                    item {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            AsyncImage(
                                model = b.artworkUrl,
                                contentDescription = null,
                                modifier =
                                    Modifier
                                        .size(160.dp)
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(MaterialTheme.colorScheme.surfaceVariant),
                                contentScale = ContentScale.Crop,
                            )
                        }
                        Spacer(Modifier.height(12.dp))
                        val matchedArtist =
                            library.artists.firstOrNull { artist ->
                                artist.name.equals(b.displayName, ignoreCase = true) ||
                                    (appleId != null && artist.artistId == appleId.toString())
                            }
                        val isFollowed = matchedArtist != null
                        Button(
                            onClick = {
                                if (isFollowed) {
                                    matchedArtist?.artistId?.let { viewModel.unfollowArtist(it) }
                                } else {
                                    viewModel.followArtist(b.displayName, b.artworkUrl)
                                }
                            },
                            modifier =
                                Modifier
                                    .fillMaxWidth()
                                    .padding(bottom = 12.dp),
                        ) {
                            Text(if (isFollowed) "Unfollow artist" else "Follow artist")
                        }
                        if (isFollowed) {
                            Row(
                                modifier =
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(bottom = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        text = "Device release alerts (all artists)",
                                        style = MaterialTheme.typography.titleSmall,
                                    )
                                    Text(
                                        text = "Applies to every artist you follow. Gotify is configured in Settings.",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Switch(
                                    checked = library.settings.notifyArtistReleasesOnDevice,
                                    onCheckedChange = { enabled ->
                                        onSettingsChange(
                                            library.settings.copy(
                                                notifyArtistReleasesOnDevice = enabled,
                                            ),
                                        )
                                    },
                                )
                            }
                        }
                        TabRow(selectedTabIndex = tab) {
                            titles.forEachIndexed { i, title ->
                                Tab(
                                    selected = tab == i,
                                    onClick = { tab = i },
                                    text = { Text(title) },
                                )
                            }
                        }
                        Spacer(Modifier.height(12.dp))
                    }
                    when (tab) {
                        0 -> {
                            items(b.songs, key = { it.effectiveId }) { track ->
                                ArtistTrackRow(
                                    track = track,
                                    onPlay = { viewModel.play(track, b.songs) },
                                    onMenu = onOverflowTrack,
                                )
                            }
                        }
                        else -> {
                            items(b.albums, key = { it.id }) { album ->
                                Row(
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 8.dp),
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    AsyncImage(
                                        model = album.artwork,
                                        contentDescription = null,
                                        modifier =
                                            Modifier
                                                .size(52.dp)
                                                .clip(RoundedCornerShape(8.dp))
                                                .background(MaterialTheme.colorScheme.surfaceVariant),
                                        contentScale = ContentScale.Crop,
                                    )
                                    Column(Modifier.weight(1f)) {
                                        Text(album.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(
                                            "${album.year ?: "—"} · ${album.artist}",
                                            style = MaterialTheme.typography.bodySmall,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    TextButton(
                                        onClick = {
                                            val cid = album.id.toIntOrNull() ?: return@TextButton
                                            albumLoadingId = album.id
                                            scope.launch {
                                                val loaded =
                                                    try {
                                                        withContext(Dispatchers.IO) {
                                                            viewModel.albumTracksCatalog(cid)
                                                        }
                                                    } catch (_: Exception) {
                                                        emptyList()
                                                    }
                                                albumLoadingId = null
                                                albumTracksPick = loaded
                                            }
                                        },
                                    ) {
                                        Text(if (albumLoadingId == album.id) "…" else "Tracks")
                                    }
                                }
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ArtistTrackRow(
    track: Track,
    onPlay: () -> Unit,
    onMenu: (Track) -> Unit,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = track.artwork,
            contentDescription = null,
            modifier =
                Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(10.dp)),
            contentScale = ContentScale.Crop,
        )
        Column(
            modifier =
                Modifier
                    .weight(1f)
                    .clickable(onClick = onPlay),
        ) {
            Text(track.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                track.album ?: track.artist,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        TextButton(onClick = onPlay) {
            Text("Play")
        }
        TextButton(onClick = { onMenu(track) }) {
            Text("•••")
        }
    }
    HorizontalDivider()
}

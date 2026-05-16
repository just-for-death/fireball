package com.fireball.nativeapp.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.NavType
import androidx.navigation.navArgument
import android.net.Uri
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.ui.screens.PlaylistDetailScreen
import com.fireball.nativeapp.navigation.Destination
import com.fireball.nativeapp.ui.components.PlayerTrackOverflowDialog
import com.fireball.nativeapp.ui.components.PillMiniPlayerLayout
import com.fireball.nativeapp.ui.MainViewModel
import com.fireball.nativeapp.ui.screens.HomeScreen
import com.fireball.nativeapp.ui.screens.LibraryScreen
import com.fireball.nativeapp.ui.screens.SearchScreen
import com.fireball.nativeapp.ui.screens.SettingsScreen
import com.fireball.nativeapp.ui.theme.SuvMusicTheme
import com.fireball.nativeapp.ui.theme.flexSchemeToAppTheme
import com.fireball.nativeapp.ui.theme.rememberAlbumArtColors
import com.fireball.nativeapp.ui.theme.rememberDominantColors
import com.fireball.nativeapp.ui.theme.themeModeToDark

private data class RootNavItem(
    val route: String,
    val label: String,
    val destination: Destination,
    val icon: @Composable () -> Unit
)

@Composable
fun FireballNativeApp(viewModel: MainViewModel) {
    val navController = rememberNavController()
    val uiState by viewModel.uiState.collectAsState()
    val playback by viewModel.playbackState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val settings = uiState.library.settings

    LaunchedEffect(uiState.error) {
        val msg = uiState.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message = msg)
        viewModel.dismissError()
    }

    LaunchedEffect(uiState.searchFocusRequest) {
        val q = uiState.searchFocusRequest ?: return@LaunchedEffect
        navController.navigate("search") {
            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
        viewModel.updateQuery(q)
        viewModel.search()
        viewModel.consumeSearchFocusRequest()
    }

    val isTablet = LocalConfiguration.current.smallestScreenWidthDp >= 700
    val startRoute = when (settings.startTab.trim().lowercase()) {
        "search", "library", "settings" -> settings.startTab.trim().lowercase()
        else -> "home"
    }
    var startTabNavReady by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    LaunchedEffect(settings.startTab) {
        if (!startTabNavReady) {
            startTabNavReady = true
            return@LaunchedEffect
        }
        val route = when (settings.startTab.trim().lowercase()) {
            "search", "library", "settings" -> settings.startTab.trim().lowercase()
            else -> "home"
        }
        navController.navigate(route) {
            popUpTo(navController.graph.startDestinationId) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    var isPlayerOpen by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    var overflowTrack by remember { mutableStateOf<Track?>(null) }
    var artistPickerNames by remember { mutableStateOf<List<String>?>(null) }

    LaunchedEffect(uiState.artistOpenRequest) {
        val req = uiState.artistOpenRequest ?: return@LaunchedEffect
        isPlayerOpen = false
        val keyPart =
            when (val id = req.appleId) {
                null -> "n"
                else -> "i$id"
            }
        navController.navigate("artist_detail/$keyPart/" + Uri.encode(req.fallbackName))
        viewModel.consumeArtistOpenRequest()
    }

    val items = listOf(
        RootNavItem("home", "Home", Destination.Home, { Icon(Icons.Default.Home, contentDescription = null) }),
        RootNavItem("search", "Search", Destination.Search, { Icon(Icons.Default.Search, contentDescription = null) }),
        RootNavItem("library", "Library", Destination.Library, { Icon(Icons.Default.LibraryMusic, contentDescription = null) }),
        RootNavItem("settings", "Settings", Destination.Settings, { Icon(Icons.Default.Settings, contentDescription = null) })
    )
    val currentTrack = playback.currentTrack
    val systemDark = isSystemInDarkTheme()

    fun closeMiniPlayerAndSession() {
        isPlayerOpen = false
        viewModel.stopPlaybackAndDismissMiniPlayer()
    }

    fun openArtistFromDisplayLine(line: String) {
        val names = com.fireball.nativeapp.core.model.ArtistNameParser.splitArtists(line)
        when {
            names.isEmpty() -> return
            names.size == 1 -> viewModel.requestArtistDetail(names.first())
            else -> artistPickerNames = names
        }
    }

    val darkTheme = themeModeToDark(settings.themeMode, systemDark)
    val appearanceChrome =
        remember(settings.appearanceColorSource, settings.useDynamicColorWhenAvailable) {
            val raw = settings.appearanceColorSource.trim().lowercase()
            when {
                raw == "music" || raw == "scheme" || raw == "material_you" -> raw
                settings.useDynamicColorWhenAvailable -> "material_you"
                else -> "scheme"
            }
        }
    val albumArtColors =
        if (appearanceChrome == "music") {
            rememberAlbumArtColors(currentTrack?.artwork, darkTheme)
        } else {
            null
        }
    val dominantColors =
        when (appearanceChrome) {
            "music" -> albumArtColors ?: rememberDominantColors(currentTrack?.artwork, darkTheme)
            else ->
                remember(darkTheme) {
                    com.fireball.nativeapp.ui.theme.defaultDominantColors(darkTheme)
                }
        }

    val railCollapsed = isTablet && settings.ipadSidebarCollapsed
    val miniPlayerLayout = when {
        !isTablet -> PillMiniPlayerLayout.Phone
        railCollapsed -> PillMiniPlayerLayout.NarrowRailStack
        else -> PillMiniPlayerLayout.TabletRail
    }

    SuvMusicTheme(
        darkTheme = darkTheme,
        dynamicColor = appearanceChrome == "material_you",
        appTheme = flexSchemeToAppTheme(settings.flexScheme),
        albumArtColors = albumArtColors,
        accentSeedArgb = settings.accentSeedColor,
    ) {
        com.fireball.nativeapp.ui.components.PremiumBackground {
            Row(modifier = Modifier.fillMaxSize()) {
                if (isTablet) {
                    val navBackStackEntry by navController.currentBackStackEntryAsState()
                    val currentDestination = navBackStackEntry?.destination
                    NavigationRail(
                        modifier = Modifier
                            .fillMaxHeight()
                            .windowInsetsPadding(WindowInsets.statusBars)
                            .windowInsetsPadding(WindowInsets.navigationBars)
                    ) {
                        items.forEach { item ->
                            val routeStr =
                                navBackStackEntry?.destination?.route
                                    ?: currentDestination?.route.orEmpty()
                            val selected =
                                when (item.route) {
                                    "library" -> routeStr.startsWith("library")
                                    else -> routeStr == item.route
                                }
                            NavigationRailItem(
                                selected = selected,
                                onClick = {
                                    navController.navigate(item.route) {
                                        popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                },
                                icon = item.icon,
                                label = if (railCollapsed) {
                                    {}
                                } else {
                                    { Text(item.label) }
                                },
                            )
                        }
                        androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                        if (currentTrack != null) {
                            com.fireball.nativeapp.ui.components.PillMiniPlayer(
                                song = currentTrack,
                                isPlaying = playback.isPlaying,
                                dominantColors = dominantColors,
                                progress = if (playback.durationMs > 0) {
                                    playback.positionMs.toFloat() / playback.durationMs.toFloat()
                                } else {
                                    0f
                                },
                                onPlayPause = viewModel::togglePlayPause,
                                onNext = viewModel::next,
                                onPrevious = viewModel::previous,
                                onClose = { closeMiniPlayerAndSession() },
                                onTap = { isPlayerOpen = true },
                                onArtistClick = {
                                    currentTrack.artist.takeIf { it.isNotBlank() }
                                        ?.let { openArtistFromDisplayLine(it) }
                                },
                                onLongPressMenu = { overflowTrack = currentTrack },
                                layout = miniPlayerLayout,
                                isLoading = uiState.isPlaybackLoading,
                            )
                        }
                    }
                }

                Scaffold(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight(),
                    snackbarHost = { SnackbarHost(snackbarHostState) },
                    bottomBar = {
                        if (!isTablet) {
                            androidx.compose.foundation.layout.Column(
                                modifier = Modifier.navigationBarsPadding(),
                            ) {
                                androidx.compose.animation.AnimatedVisibility(
                                    visible = currentTrack != null,
                                    enter = androidx.compose.animation.slideInVertically(
                                        initialOffsetY = { it / 2 },
                                    ) + androidx.compose.animation.fadeIn(),
                                    exit = androidx.compose.animation.slideOutVertically(
                                        targetOffsetY = { it / 2 },
                                    ) + androidx.compose.animation.fadeOut(),
                                ) {
                                    val track = currentTrack ?: return@AnimatedVisibility
                                    com.fireball.nativeapp.ui.components.PillMiniPlayer(
                                        song = track,
                                        isPlaying = playback.isPlaying,
                                        dominantColors = dominantColors,
                                        progress = if (playback.durationMs > 0) {
                                            playback.positionMs.toFloat() / playback.durationMs.toFloat()
                                        } else {
                                            0f
                                        },
                                        onPlayPause = viewModel::togglePlayPause,
                                        onNext = viewModel::next,
                                        onPrevious = viewModel::previous,
                                        onClose = { closeMiniPlayerAndSession() },
                                        onTap = { isPlayerOpen = true },
                                        onArtistClick = {
                                            track.artist.takeIf { it.isNotBlank() }
                                                ?.let { openArtistFromDisplayLine(it) }
                                        },
                                        onLongPressMenu = { overflowTrack = track },
                                        layout = PillMiniPlayerLayout.Phone,
                                        isLoading = uiState.isPlaybackLoading,
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                                val navBackStackEntry by navController.currentBackStackEntryAsState()
                                val currentDestination = navBackStackEntry?.destination
                                NavigationBar {
                                    items.forEach { item ->
                                        val routeStr =
                                            navBackStackEntry?.destination?.route
                                                ?: currentDestination?.route.orEmpty()
                                        val selected =
                                            when (item.route) {
                                                "library" -> routeStr.startsWith("library")
                                                else -> routeStr == item.route
                                            }
                                        NavigationBarItem(
                                            selected = selected,
                                            onClick = {
                                                navController.navigate(item.route) {
                                                    popUpTo(navController.graph.findStartDestination().id) {
                                                        saveState = true
                                                    }
                                                    launchSingleTop = true
                                                    restoreState = true
                                                }
                                            },
                                            icon = item.icon,
                                            label = { Text(item.label) },
                                        )
                                    }
                                }
                            }
                        }
                    }
                ) { innerPadding ->
                    NavHost(
                        navController = navController,
                        startDestination = startRoute,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding)
                    ) {
                        composable("home") {
                            HomeScreen(
                                library = uiState.library,
                                playbackState = playback,
                                currentLyrics = uiState.currentLyrics,
                                homeCountries = com.fireball.nativeapp.ui.HomeCountries.visibleCodes(
                                    settings.homeCountries
                                ),
                                chartCountryCode = uiState.chartCountryCode,
                                trendingTracks = uiState.trendingTracks,
                                trendingLoading = uiState.trendingLoading,
                                onSelectChartCountry = viewModel::selectChartCountry,
                                lbRecentTracks = uiState.lbRecentTracks,
                                lbTopTracks = uiState.lbTopTracks,
                                lbTopRange = uiState.lbTopRange,
                                lbHomeLoading = uiState.lbHomeLoading,
                                onSelectLbTopRange = viewModel::selectLbTopRange,
                                onFollowArtist = viewModel::followArtist,
                                onOpenPlaylist = { pl ->
                                    navController.navigate(
                                        "library/playlist/" + Uri.encode(pl.id),
                                    )
                                },
                                onOverflowTrack = { overflowTrack = it },
                                onRefreshHome = { viewModel.refreshHome() },
                                onPlay = viewModel::play,
                                onTogglePlayPause = viewModel::togglePlayPause,
                                onNext = viewModel::next,
                                onPrevious = viewModel::previous,
                            )
                        }
                        composable("search") {
                            SearchScreen(
                                query = uiState.query,
                                results = uiState.searchResults,
                                albumResults = uiState.searchAlbumResults,
                                searchSuggestions = uiState.searchSuggestions,
                                isSearching = uiState.isSearching,
                                isPlaybackLoading = uiState.isPlaybackLoading,
                                isFavorite = viewModel::isFavorite,
                                onQueryChange = viewModel::updateQuery,
                                onSearch = viewModel::search,
                                onRefreshSuggestions = viewModel::refreshSearchSuggestionsNow,
                                onPlay = viewModel::play,
                                onToggleFavorite = viewModel::toggleFavorite,
                                onOpenTrackMenu = { overflowTrack = it },
                                onPlayAlbum = viewModel::playCatalogAlbum,
                            )
                        }
                        composable("library") {
                            LibraryScreen(
                                library = uiState.library,
                                useGrid = settings.libraryUseGrid,
                                onPlay = viewModel::play,
                                onOpenPlaylist = { pl ->
                                    navController.navigate(
                                        "library/playlist/" + Uri.encode(pl.id),
                                    )
                                },
                                onUnfollowArtist = viewModel::unfollowArtist,
                                onCreatePlaylist = viewModel::createPlaylist,
                                onFollowArtistByName = { name ->
                                    viewModel.followArtist(name.trim())
                                },
                                onOpenTrackMenu = { overflowTrack = it },
                            )
                        }
                        composable(
                            route = "library/playlist/{playlistId}",
                            arguments = listOf(
                                navArgument("playlistId") { type = NavType.StringType },
                            ),
                        ) { entry ->
                            val rawId = entry.arguments?.getString("playlistId").orEmpty()
                            val id = Uri.decode(rawId)
                            val pl = uiState.library.playlists.firstOrNull { it.id == id }
                            if (pl == null) {
                                LaunchedEffect(Unit) {
                                    navController.popBackStack()
                                }
                            } else {
                                PlaylistDetailScreen(
                                    playlist = pl,
                                    isFavorite = viewModel::isFavorite,
                                    onBack = { navController.popBackStack() },
                                    onPlayAllFromPlaylist = {
                                        pl.videos.firstOrNull()?.let { first ->
                                            viewModel.playFromPlaylist(first, pl.videos)
                                            isPlayerOpen = true
                                        }
                                    },
                                    onPlayPlaylistUpNext = {
                                        viewModel.appendTracksUpNext(pl.videos)
                                    },
                                    onAddPlaylistToQueue = {
                                        viewModel.appendTracksToQueue(pl.videos)
                                    },
                                    onPlaySingleTrackFromPlaylist = { track ->
                                        viewModel.playFromPlaylist(track, listOf(track))
                                        isPlayerOpen = true
                                    },
                                    onToggleFavorite = viewModel::toggleFavorite,
                                    onOpenTrackMenu = { overflowTrack = it },
                                )
                            }
                        }
                        composable(
                            route = "artist_detail/{artistKey}/{artistNameEncoded}",
                            arguments =
                                listOf(
                                    navArgument("artistKey") { type = NavType.StringType },
                                    navArgument("artistNameEncoded") { type = NavType.StringType },
                                ),
                        ) { entry ->
                            val keyArg = entry.arguments?.getString("artistKey").orEmpty()
                            val nameEnc =
                                entry.arguments?.getString("artistNameEncoded").orEmpty()
                            com.fireball.nativeapp.ui.screens.ArtistDetailRoute(
                                parsedKey = keyArg,
                                encodedName = nameEnc,
                                library = uiState.library,
                                viewModel = viewModel,
                                onBack = { navController.popBackStack() },
                                onOverflowTrack = { overflowTrack = it },
                                onSettingsChange = { updated ->
                                    viewModel.updateSettings { _ -> updated }
                                },
                            )
                        }
                        composable("settings") {
                            SettingsScreen(
                                settings = settings,
                                playbackState = playback,
                                integrationStatus = uiState.integrationStatus,
                                onSettingsChange = { updated -> viewModel.updateSettings { updated } },
                                onToggleShuffle = viewModel::toggleShuffle,
                                onToggleRepeatMode = viewModel::toggleRepeatMode,
                                onSetSleepTimer = viewModel::setSleepTimer,
                                onSetSleepAfterCurrent = viewModel::sleepAfterCurrent,
                                onWebDavPull = viewModel::webDavPullMerge,
                                onWebDavPush = viewModel::webDavPush,
                                onGotifyTest = viewModel::sendGotifyTest,
                                onLbdlStatus = viewModel::checkLbdlStatus,
                                onLbdlCreateJob = viewModel::createLbdlJobFromQueue,
                                onRemoteToggle = viewModel::remoteTogglePlay,
                                onRemotePair = viewModel::remotePair,
                                onInvidiousLogin = viewModel::invidiousLogin,
                                onInvidiousSyncPlaylist = viewModel::invidiousSyncPlaylist,
                                onInvidiousPushPlaylist = viewModel::invidiousPushPlaylist,
                                onInvidiousSignOut = viewModel::signOutInvidious,
                                invidiousPlaylists = uiState.invidiousPlaylists,
                                onGoogleDriveBackup = viewModel::backupToGoogleDrive,
                                onValidateLastFm = {
                                    viewModel.validateLastFmKey { /* status via integrationStatus */ }
                                },
                                onConnectLastFm = { password ->
                                    viewModel.connectLastFm(password) { /* status via integrationStatus */ }
                                },
                            )
                        }
                    }
                }
            }

            androidx.compose.animation.AnimatedVisibility(
                visible = isPlayerOpen,
                modifier = Modifier.fillMaxSize(),
                enter = androidx.compose.animation.slideInVertically(
                    initialOffsetY = { it },
                    animationSpec = com.fireball.nativeapp.ui.theme.MotionTokens.springGentle(),
                ) + androidx.compose.animation.fadeIn(
                    animationSpec = com.fireball.nativeapp.ui.theme.MotionTokens.tweenStandard(),
                ),
                exit = androidx.compose.animation.slideOutVertically(
                    targetOffsetY = { it },
                    animationSpec = com.fireball.nativeapp.ui.theme.MotionTokens.tweenEmphasized(),
                ) + androidx.compose.animation.fadeOut(),
            ) {
                com.fireball.nativeapp.ui.screens.NowPlayingScreen(
                    playbackState = playback,
                    currentLyrics = uiState.currentLyrics,
                    lyricsAutoScroll = settings.lyricsAutoScroll,
                    lyricsReducedMotion = settings.lyricsReducedMotion,
                    pinnedLyricsPanel = settings.alwaysShowLyricsPanel,
                    appearanceChrome = appearanceChrome,
                    onPlayPause = viewModel::togglePlayPause,
                    onNext = viewModel::next,
                    onPrevious = viewModel::previous,
                    onSeek = { ratio ->
                        val dur = playback.durationMs
                        if (dur > 0) {
                            viewModel.seekTo((ratio * dur).toLong())
                        }
                    },
                    onToggleShuffle = viewModel::toggleShuffle,
                    onToggleRepeatMode = viewModel::toggleRepeatMode,
                    onPlayQueueIndex = viewModel::playQueueIndex,
                    onOpenArtistSearch = { name, _ -> openArtistFromDisplayLine(name) },
                    onOverflowQueueTrackMenu = { overflowTrack = it },
                    onCollapse = { isPlayerOpen = false },
                    onOpenTrackMenu = { playback.currentTrack?.let { overflowTrack = it } },
                )
            }

            artistPickerNames?.let { names ->
                com.fireball.nativeapp.ui.components.ArtistPickerSheet(
                    artists = names,
                    onDismiss = { artistPickerNames = null },
                    onSelect = { viewModel.requestArtistDetail(it) },
                )
            }

            overflowTrack?.let { t ->
                PlayerTrackOverflowDialog(
                    track = t,
                    isFavorite = viewModel.isFavorite(t),
                    isArtistFollowed = viewModel.isArtistFollowed(t.artist),
                    playlists = viewModel.userPlaylistsForPicker(),
                    onDismiss = { overflowTrack = null },
                    onPlayNext = {
                        viewModel.playTrackUpNext(t)
                        overflowTrack = null
                    },
                    onAddToQueue = {
                        viewModel.appendTrackToQueue(t)
                        overflowTrack = null
                    },
                    onToggleFavorite = {
                        viewModel.toggleFavorite(t)
                        overflowTrack = null
                    },
                    onAddToPlaylist = { id ->
                        viewModel.addTrackToPlaylist(t, id)
                    },
                    onSeeArtist = {
                        viewModel.requestArtistDetail(t.artist)
                        overflowTrack = null
                    },
                    onFollowArtist = {
                        viewModel.followArtist(t.artist, t.artwork)
                        overflowTrack = null
                    },
                    onUnfollowArtist = {
                        viewModel.unfollowArtistByName(t.artist)
                        overflowTrack = null
                    },
                )
            }
        }
    }
}

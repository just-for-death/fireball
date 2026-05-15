package com.fireball.nativeapp.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import com.fireball.nativeapp.navigation.Destination
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
    val isTablet = LocalConfiguration.current.smallestScreenWidthDp >= 700
    val startRoute = when (settings.startTab) {
        "search", "library", "settings" -> settings.startTab
        else -> "home"
    }
    var isPlayerOpen by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }

    val items = listOf(
        RootNavItem("home", "Home", Destination.Home, { Icon(Icons.Default.Home, contentDescription = null) }),
        RootNavItem("search", "Search", Destination.Search, { Icon(Icons.Default.Search, contentDescription = null) }),
        RootNavItem("library", "Library", Destination.Library, { Icon(Icons.Default.LibraryMusic, contentDescription = null) }),
        RootNavItem("settings", "Settings", Destination.Settings, { Icon(Icons.Default.Settings, contentDescription = null) })
    )
    val currentTrack = playback.currentTrack
    val systemDark = isSystemInDarkTheme()
    val darkTheme = themeModeToDark(settings.themeMode, systemDark)
    val albumArtColors = rememberAlbumArtColors(currentTrack?.artwork, darkTheme)
    val dominantColors = albumArtColors ?: rememberDominantColors(currentTrack?.artwork, darkTheme)

    SuvMusicTheme(
        darkTheme = darkTheme,
        dynamicColor = settings.useDynamicColorWhenAvailable,
        appTheme = flexSchemeToAppTheme(settings.flexScheme),
        albumArtColors = albumArtColors,
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Row(modifier = Modifier.fillMaxSize()) {
                if (isTablet) {
                    val navBackStackEntry by navController.currentBackStackEntryAsState()
                    val currentDestination = navBackStackEntry?.destination
                    NavigationRail(
                        modifier = Modifier
                            .fillMaxHeight()
                            .windowInsetsPadding(WindowInsets.statusBars)
                    ) {
                        items.forEach { item ->
                            NavigationRailItem(
                                selected = currentDestination?.hierarchy?.any { it.route == item.route } == true,
                                onClick = {
                                    navController.navigate(item.route) {
                                        popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                },
                                icon = item.icon,
                                label = { Text(item.label) }
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
                                onClose = { isPlayerOpen = false },
                                onTap = { isPlayerOpen = true },
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
                            androidx.compose.foundation.layout.Column {
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
                                        onClose = { isPlayerOpen = false },
                                        onTap = { isPlayerOpen = true },
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                                val navBackStackEntry by navController.currentBackStackEntryAsState()
                                val currentDestination = navBackStackEntry?.destination
                                NavigationBar {
                                    items.forEach { item ->
                                        NavigationBarItem(
                                            selected = currentDestination?.hierarchy?.any { it.route == item.route } == true,
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
                                            label = { Text(item.label) }
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
                                onPlay = viewModel::play,
                                onTogglePlayPause = viewModel::togglePlayPause,
                                onNext = viewModel::next,
                                onPrevious = viewModel::previous
                            )
                        }
                        composable("search") {
                            SearchScreen(
                                query = uiState.query,
                                results = uiState.searchResults,
                                isSearching = uiState.isSearching,
                                isPlaybackLoading = uiState.isPlaybackLoading,
                                isFavorite = viewModel::isFavorite,
                                onQueryChange = viewModel::updateQuery,
                                onSearch = viewModel::search,
                                onPlay = viewModel::play,
                                onToggleFavorite = viewModel::toggleFavorite
                            )
                        }
                        composable("library") {
                            LibraryScreen(
                                library = uiState.library,
                                useGrid = settings.libraryUseGrid,
                                onPlay = viewModel::play
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
                enter = androidx.compose.animation.slideInVertically(initialOffsetY = { it }),
                exit = androidx.compose.animation.slideOutVertically(targetOffsetY = { it })
            ) {
                com.fireball.nativeapp.ui.screens.NowPlayingScreen(
                    playbackState = playback,
                    currentLyrics = uiState.currentLyrics,
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
                    onCollapse = { isPlayerOpen = false }
                )
            }
        }
    }
}

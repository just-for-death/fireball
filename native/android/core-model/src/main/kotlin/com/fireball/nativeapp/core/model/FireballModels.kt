package com.fireball.nativeapp.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Track(
    val id: String,
    val videoId: String? = null,
    val title: String,
    val artist: String,
    val artwork: String? = null,
    val url: String? = null,
    val duration: Int? = null,
    val album: String? = null,
    val year: String? = null
) {
    val effectiveId: String get() = videoId ?: id
}

@Serializable
data class Playlist(
    val id: String,
    val title: String,
    val videos: List<Track> = emptyList()
)

@Serializable
data class Artist(
    val artistId: String,
    val name: String,
    val artwork: String? = null,
    val latestReleaseId: String? = null
)

@Serializable
data class Album(
    val id: String,
    val title: String,
    val artist: String,
    val artwork: String? = null,
    val year: Int? = null,
    val tracks: List<Track>? = null
)

@Serializable
data class FireballSettings(
    val ollamaEnabled: Boolean = false,
    val ollamaUrl: String = "",
    val ollamaModel: String = "llama3.2:3b",
    val lastFmApiKey: String = "",
    val listenBrainzToken: String = "",
    val listenBrainzUsername: String = "",
    val highQuality: Boolean = false,
    val cacheEnabled: Boolean = true,
    val localMusicCacheLimit: Int = 10,
    val queueMode: String = "off",
    val invidiousInstance: String = "",
    val invidiousSid: String? = null,
    val invidiousUsername: String? = null,
    val sponsorBlock: Boolean = false,
    val sponsorBlockCategories: List<String> = emptyList(),
    val analytics: Boolean = false,
    val customDownloadPath: String? = null,
    val listenBrainzEnabled: Boolean = false,
    val listenBrainzPlayingNow: Boolean = false,
    val listenBrainzScrobblePercent: Int = 25,
    val listenBrainzScrobbleMaxSeconds: Int = 40,
    val invidiousPlaylistPrivacy: String = "private",
    val invidiousAutoPush: Boolean = false,
    val invidiousPlaylistMappings: Map<String, String> = emptyMap(),
    val webDavUrl: String = "",
    val webDavUsername: String = "",
    val webDavPassword: String = "",
    val gDriveEnabled: Boolean = false,
    val lastBackupAt: String? = null,
    val webDavLiveSync: Boolean = false,
    val remoteServerEnabled: Boolean = false,
    val remoteHostIp: String = "",
    val remotePeerPort: Int = 7771,
    val homeCountries: List<String> = emptyList(),
    val lyricsAutoScroll: Boolean = true,
    val lyricsReducedMotion: Boolean = false,
    val lyricsPreferEnglishHindi: Boolean = true,
    val themeMode: String = "system",
    val flexScheme: String = "deepPurple",
    val useDynamicColorWhenAvailable: Boolean = true,
    val accentSeedColor: Int? = null,
    val ipadSidebarCollapsed: Boolean = false,
    val gotifyEnabled: Boolean = false,
    val gotifyUrl: String = "",
    val gotifyToken: String = "",
    val lbdlUrl: String = "",
    val lbdlUsername: String = "",
    val lbdlPassword: String = "",
    val startTab: String = "home",
    val libraryUseGrid: Boolean = false,
    val offlineModeEnabled: Boolean = false,
    val privacyModeEnabled: Boolean = false,
    val dynamicIslandEnabled: Boolean = false,
    val loggingEnabled: Boolean = false,
    val bluetoothAutoplayEnabled: Boolean = false,
    val speakSongDetailsEnabled: Boolean = false
)

@Serializable
data class PlaybackSession(
    val queue: List<Track> = emptyList(),
    val currentIndex: Int = 0,
    val shuffled: Boolean = false,
    val repeatMode: String = "off",
)

@Serializable
data class LibrarySnapshot(
    val version: Int = 2,
    val settings: FireballSettings = FireballSettings(),
    val history: List<Track> = emptyList(),
    val favorites: List<Track> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
    val artists: List<Artist> = emptyList(),
    val albums: List<Album> = emptyList(),
    val playbackSession: PlaybackSession = PlaybackSession(),
)

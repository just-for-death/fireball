package com.fireball.nativeapp.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fireball.nativeapp.data.IntegrationOrchestrator
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.data.FireballRepository
import com.fireball.nativeapp.data.LyricsAndAiOrchestrator
import com.fireball.nativeapp.player.PlayerManager
import com.fireball.nativeapp.player.PlaybackState
import com.fireball.nativeapp.player.NativePlaybackService
import com.fireball.nativeapp.player.PlaybackController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

data class MainUiState(
    val library: LibrarySnapshot = LibrarySnapshot(),
    val query: String = "",
    val searchResults: List<Track> = emptyList(),
    val isSearching: Boolean = false,
    val error: String? = null,
    val currentLyrics: String? = null,
    val integrationStatus: String? = null,
    val invidiousPlaylists: List<Pair<String, String>> = emptyList()
)

class MainViewModel(
    private val repository: FireballRepository,
    private val playerManager: PlayerManager,
    private val integrations: IntegrationOrchestrator,
    private val playbackController: PlaybackController,
    private val lyricsAndAi: LyricsAndAiOrchestrator
) : ViewModel() {
    private companion object {
        const val STATUS_GOTIFY_OK = "gotify: success"
        const val STATUS_GOTIFY_FAIL = "gotify: failed"
        const val STATUS_LBDL_AUTH_OK = "lbdl auth: success"
        const val STATUS_LBDL_AUTH_FAIL = "lbdl auth: failed"
        const val STATUS_LBDL_JOB_OK_PREFIX = "lbdl job: success"
        const val STATUS_LBDL_JOB_FAIL = "lbdl job: failed"
        const val STATUS_REMOTE_CMD_OK = "remote command: success"
        const val STATUS_REMOTE_CMD_FAIL = "remote command: failed"
        const val STATUS_REMOTE_PAIR_OK = "remote pair: success"
        const val STATUS_REMOTE_PAIR_FAIL = "remote pair: failed"
        const val STATUS_GDRIVE_OK = "gdrive backup: success"
        const val STATUS_GDRIVE_FAIL = "gdrive backup: failed"
        const val STATUS_INVIDIOUS_LOGIN_OK = "invidious login: success"
        const val STATUS_INVIDIOUS_LOGIN_FAIL = "invidious login: failed"
        const val STATUS_INVIDIOUS_SYNC_OK = "invidious playlist sync: success"
        const val STATUS_INVIDIOUS_SYNC_FAIL = "invidious playlist sync: failed"
        const val STATUS_INVIDIOUS_PUSH_OK = "invidious playlist push: success"
        const val STATUS_INVIDIOUS_PUSH_FAIL = "invidious playlist push: failed"
    }

    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()
    val playbackState: StateFlow<PlaybackState> = playerManager.state
    private val scrobbledTrackIds = mutableSetOf<String>()
    private val aiQueueExpandedForTrackIds = mutableSetOf<String>()

    init {
        playbackController.connect()
        viewModelScope.launch {
            var lastIndex = -1
            playbackController.state.collectLatest { engine ->
                playerManager.syncFromEngine(
                    currentIndex = if (engine.currentIndex >= 0) engine.currentIndex else null,
                    isPlaying = engine.isPlaying,
                    positionMs = engine.positionMs,
                    durationMs = engine.durationMs
                )
                val current = playbackState.value
                val currentIndex = current.currentIndex
                val atQueueEnd = currentIndex >= 0 && currentIndex >= current.queue.lastIndex
                if (current.sleepAfterCurrent && atQueueEnd && lastIndex == currentIndex && !engine.isPlaying) {
                    playerManager.setSleepAfterCurrent(false)
                }
                lastIndex = currentIndex
            }
        }
        viewModelScope.launch {
            while (true) {
                val sleepAt = playbackState.value.sleepTimerEndEpochMs
                if (sleepAt != null && System.currentTimeMillis() >= sleepAt) {
                    playerManager.setSleepTimer(null)
                    if (playbackState.value.isPlaying) {
                        playerManager.togglePlayPause()
                        playbackController.togglePlayPause()
                    }
                }
                val state = playbackState.value
                if (state.sleepAfterCurrent &&
                    state.isPlaying &&
                    state.durationMs > 0 &&
                    state.positionMs >= state.durationMs - 1000
                ) {
                    playerManager.togglePlayPause()
                    playbackController.togglePlayPause()
                    playerManager.setSleepAfterCurrent(false)
                }
                maybeScrobbleCurrent(state)
                maybeAppendAiQueue(state)
                delay(1000)
            }
        }
        viewModelScope.launch {
            val lib = repository.loadLibrary()
            _uiState.update { it.copy(library = lib) }
            fetchInvidiousPlaylists()
        }
    }

    fun updateQuery(query: String) {
        _uiState.update { it.copy(query = query) }
    }

    fun search() {
        val query = _uiState.value.query
        if (query.isBlank()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSearching = true, error = null) }

            val settings = _uiState.value.library.settings
            if (settings.offlineModeEnabled) {
                val q = query.trim().lowercase()
                val local = (_uiState.value.library.history + _uiState.value.library.favorites)
                    .distinctBy { it.effectiveId }
                val filtered = local.filter {
                    it.title.lowercase().contains(q) || it.artist.lowercase().contains(q)
                }
                _uiState.update { current ->
                    current.copy(
                        isSearching = false,
                        searchResults = filtered,
                    )
                }
                return@launch
            }

            val tracks = runCatching {
                repository.searchTracks(query, _uiState.value.library.settings)
            }.getOrElse {
                _uiState.update { current ->
                    current.copy(isSearching = false, error = it.message ?: "Search failed")
                }
                return@launch
            }
            _uiState.update { it.copy(isSearching = false, searchResults = tracks) }
        }
    }

    fun play(track: Track, source: List<Track>) {
        val settings = _uiState.value.library.settings
        viewModelScope.launch {
            // Resolve ONLY the clicked track (not the entire list).
            // Matches Flutter behavior — other tracks resolve when ExoPlayer advances.
            val resolvedTrack = repository.resolvePlayableTrack(track, settings)

            // Build the queue: put the resolved track at the right position
            val queue = source.map {
                if (it.effectiveId == track.effectiveId) resolvedTrack else it
            }
            val index = queue.indexOfFirst { it.effectiveId == track.effectiveId }.coerceAtLeast(0)

            playerManager.playTracks(queue, index)

            val playableUrl = resolvedTrack.url
            if (!playableUrl.isNullOrBlank()) {
                val mediaItem = NativePlaybackService.mediaItem(
                    id = resolvedTrack.effectiveId,
                    title = resolvedTrack.title,
                    artist = resolvedTrack.artist,
                    url = playableUrl,
                    artworkUrl = resolvedTrack.artwork
                )
                playbackController.playQueue(listOf(mediaItem), 0)
            }

            val offline = settings.offlineModeEnabled
            val privacy = settings.privacyModeEnabled

            if (!privacy) {
                val history = listOf(resolvedTrack) + _uiState.value.library.history.filterNot { it.effectiveId == resolvedTrack.effectiveId }
                persist(_uiState.value.library.copy(history = history.take(200)))
            }

            if (offline) {
                _uiState.update { it.copy(currentLyrics = null) }
            } else {
                viewModelScope.launch {
                    val lyrics = lyricsAndAi.fetchLyrics(resolvedTrack, settings)
                    _uiState.update { it.copy(currentLyrics = lyrics) }
                }
            }

            if (!offline && !privacy) {
                viewModelScope.launch {
                    integrations.submitPlayingNow(settings, resolvedTrack)
                }
            }
        }
    }

    fun toggleFavorite(track: Track) {
        val library = _uiState.value.library
        val exists = library.favorites.any { it.effectiveId == track.effectiveId }
        val favorites = if (exists) {
            library.favorites.filterNot { it.effectiveId == track.effectiveId }
        } else {
            library.favorites + track
        }
        persist(library.copy(favorites = favorites))
        if (!exists) {
            autoPushFavoriteTrack(track)
        }
    }

    fun updateSettings(transform: (FireballSettings) -> FireballSettings) {
        val updated = transform(_uiState.value.library.settings)
        persist(_uiState.value.library.copy(settings = updated))
    }

    fun togglePlayPause() {
        playerManager.togglePlayPause()
        playbackController.togglePlayPause()
    }

    fun next() {
        playerManager.next()
        playbackController.next()
    }

    fun previous() {
        playerManager.previous()
        playbackController.previous()
    }

    fun seekTo(positionMs: Long) {
        playbackController.seekTo(positionMs)
    }

    fun toggleShuffle() {
        playerManager.toggleShuffle()
        playbackController.setShuffle(playbackState.value.shuffled)
    }

    fun toggleRepeatMode() {
        playerManager.toggleRepeatMode()
        playbackController.setRepeatMode(playbackState.value.repeatMode)
    }
    fun setSleepTimer(minutes: Int?) = playerManager.setSleepTimer(minutes)
    fun sleepAfterCurrent(enabled: Boolean) = playerManager.setSleepAfterCurrent(enabled)

    private fun persist(library: LibrarySnapshot) {
        _uiState.update { it.copy(library = library) }
        viewModelScope.launch { repository.saveLibrary(library) }
    }

    private fun maybeScrobbleCurrent(state: PlaybackState) {
        val track = state.currentTrack ?: return
        val settings = _uiState.value.library.settings
        if (settings.offlineModeEnabled || settings.privacyModeEnabled) return
        if (!settings.listenBrainzEnabled || settings.listenBrainzToken.isBlank()) return
        if (state.durationMs <= 0) return

        val thresholdByPercent = (state.durationMs * settings.listenBrainzScrobblePercent / 100.0).toLong()
        val thresholdByMaxSeconds = settings.listenBrainzScrobbleMaxSeconds * 1000L
        val thresholdMs = minOf(thresholdByPercent, thresholdByMaxSeconds).coerceAtLeast(1_000L)
        if (state.positionMs < thresholdMs) return

        if (!scrobbledTrackIds.add(track.effectiveId)) return
        viewModelScope.launch {
            integrations.submitScrobble(
                settings = settings,
                track = track,
                listenedAtEpoch = System.currentTimeMillis() / 1000L
            )
        }
    }

    private fun maybeAppendAiQueue(state: PlaybackState) {
        val current = state.currentTrack ?: return
        val atTail = state.currentIndex >= 0 && state.currentIndex >= state.queue.lastIndex - 1
        if (!atTail) return
        val settings = _uiState.value.library.settings
        if (settings.offlineModeEnabled || settings.privacyModeEnabled) return
        if (!settings.ollamaEnabled) return
        if (!aiQueueExpandedForTrackIds.add(current.effectiveId)) return

        viewModelScope.launch {
            val suggestions = lyricsAndAi.generateAiQueue(settings, current)
            if (suggestions.isEmpty()) return@launch
            val generatedTracks = suggestions.mapIndexed { idx, line ->
                val parts = line.split(" - ")
                Track(
                    id = "ai_${current.effectiveId}_$idx",
                    title = parts.getOrNull(0)?.trim().orEmpty().ifBlank { line },
                    artist = parts.getOrNull(1)?.trim().orEmpty().ifBlank { "AI suggestion" }
                )
            }
            playerManager.appendToQueue(generatedTracks)
            persistAiQueue(generatedTracks)
        }
    }

    private fun persistAiQueue(generatedTracks: List<Track>) {
        if (generatedTracks.isEmpty()) return
        val library = _uiState.value.library
        val existing = library.playlists.firstOrNull { it.id == "ai_queue" }
        val mergedVideos = ((existing?.videos ?: emptyList()) + generatedTracks)
            .distinctBy { it.effectiveId }
            .takeLast(200)
        val aiPlaylist = Playlist(id = "ai_queue", title = "AI Queue", videos = mergedVideos)
        val updatedPlaylists = library.playlists.filterNot { it.id == "ai_queue" } + aiPlaylist
        persist(library.copy(playlists = updatedPlaylists))
    }

    override fun onCleared() {
        playbackController.release()
        super.onCleared()
    }

    fun webDavPullMerge() {
        viewModelScope.launch {
            val remote = integrations.syncPull(_uiState.value.library.settings) ?: return@launch
            val merged = runCatching {
                Json { ignoreUnknownKeys = true }.decodeFromString<LibrarySnapshot>(remote)
            }.getOrNull() ?: return@launch
            val local = _uiState.value.library
            val combined = local.copy(
                history = (local.history + merged.history).distinctBy { it.effectiveId }.take(200),
                favorites = (local.favorites + merged.favorites).distinctBy { it.effectiveId },
                playlists = (local.playlists + merged.playlists).distinctBy { it.id },
                artists = (local.artists + merged.artists).distinctBy { it.artistId },
                albums = (local.albums + merged.albums).distinctBy { it.id }
            )
            persist(combined)
        }
    }

    fun webDavPush() {
        viewModelScope.launch {
            integrations.syncPush(_uiState.value.library.settings, _uiState.value.library)
        }
    }

    fun sendGotifyTest() {
        viewModelScope.launch {
            val ok = integrations.gotify(
                settings = _uiState.value.library.settings,
                title = "Fireball Native",
                message = "Gotify integration works."
            )
            _uiState.update { it.copy(integrationStatus = if (ok) STATUS_GOTIFY_OK else STATUS_GOTIFY_FAIL) }
        }
    }

    fun checkLbdlStatus() {
        viewModelScope.launch {
            val ok = integrations.lbdlStatus(_uiState.value.library.settings)
            _uiState.update { it.copy(integrationStatus = if (ok) STATUS_LBDL_AUTH_OK else STATUS_LBDL_AUTH_FAIL) }
        }
    }

    fun createLbdlJobFromQueue() {
        viewModelScope.launch {
            val links = playbackState.value.queue.mapNotNull { it.url }
            val jobId = integrations.lbdlCreateJob(_uiState.value.library.settings, links)
            _uiState.update {
                it.copy(integrationStatus = if (jobId != null) "$STATUS_LBDL_JOB_OK_PREFIX ($jobId)" else STATUS_LBDL_JOB_FAIL)
            }
        }
    }

    fun remoteTogglePlay() {
        viewModelScope.launch {
            val ok = integrations.remoteCommand(_uiState.value.library.settings, action = "toggle")
            _uiState.update { it.copy(integrationStatus = if (ok) STATUS_REMOTE_CMD_OK else STATUS_REMOTE_CMD_FAIL) }
        }
    }

    fun remotePair(code: String) {
        if (code.isBlank()) return
        viewModelScope.launch {
            val ok = integrations.remotePair(_uiState.value.library.settings, code)
            _uiState.update { it.copy(integrationStatus = if (ok) STATUS_REMOTE_PAIR_OK else STATUS_REMOTE_PAIR_FAIL) }
        }
    }

    fun backupToGoogleDrive(accessToken: String) {
        if (accessToken.isBlank()) return
        viewModelScope.launch {
            val ok = integrations.gDriveBackup(accessToken, _uiState.value.library)
            _uiState.update { it.copy(integrationStatus = if (ok) STATUS_GDRIVE_OK else STATUS_GDRIVE_FAIL) }
        }
    }

    fun invidiousLogin(username: String, password: String) {
        val settings = _uiState.value.library.settings
        if (settings.invidiousInstance.isBlank() || username.isBlank() || password.isBlank()) return
        viewModelScope.launch {
            val result = runCatching {
                integrations.invidiousLogin(settings.invidiousInstance, username.trim(), password)
            }.getOrElse { err ->
                _uiState.update { state ->
                    state.copy(integrationStatus = "$STATUS_INVIDIOUS_LOGIN_FAIL (${err.message ?: "unknown error"})")
                }
                return@launch
            }
            if (result == null) {
                _uiState.update { it.copy(integrationStatus = "$STATUS_INVIDIOUS_LOGIN_FAIL (empty SID)") }
                return@launch
            }
            val updatedSettings = settings.copy(invidiousSid = result.first, invidiousUsername = result.second)
            persist(_uiState.value.library.copy(settings = updatedSettings))
            _uiState.update { it.copy(integrationStatus = STATUS_INVIDIOUS_LOGIN_OK) }
            fetchInvidiousPlaylists()
        }
    }

    fun fetchInvidiousPlaylists() {
        val settings = _uiState.value.library.settings
        if (settings.invidiousSid.isNullOrBlank() || settings.invidiousInstance.isBlank()) return
        viewModelScope.launch {
            val playlists = integrations.invidiousAuthPlaylists(settings)
            _uiState.update { it.copy(invidiousPlaylists = playlists) }
        }
    }

    fun invidiousSyncPlaylist(playlistId: String) {
        if (playlistId.isBlank()) return
        viewModelScope.launch {
            val settings = _uiState.value.library.settings
            val synced = integrations.invidiousSyncPlaylist(settings, playlistId.trim())
            if (synced == null) {
                _uiState.update { it.copy(integrationStatus = STATUS_INVIDIOUS_SYNC_FAIL) }
                return@launch
            }
            val library = _uiState.value.library
            val playlists = library.playlists.filterNot { it.id == synced.id } + synced
            persist(library.copy(playlists = playlists))
            _uiState.update { it.copy(integrationStatus = STATUS_INVIDIOUS_SYNC_OK) }
        }
    }

    fun invidiousPushPlaylist(localPlaylistId: String, existingInvidiousId: String?) {
        if (localPlaylistId.isBlank()) return
        viewModelScope.launch {
            val library = _uiState.value.library
            val local = library.playlists.firstOrNull { it.id == localPlaylistId.trim() } ?: run {
                _uiState.update { it.copy(integrationStatus = STATUS_INVIDIOUS_PUSH_FAIL) }
                return@launch
            }
            val settings = library.settings
            val remoteId = integrations.invidiousPushPlaylist(settings, local, existingInvidiousId?.ifBlank { null })
            if (remoteId.isNullOrBlank()) {
                _uiState.update { it.copy(integrationStatus = STATUS_INVIDIOUS_PUSH_FAIL) }
                return@launch
            }
            val mappings = settings.invidiousPlaylistMappings + (local.id to remoteId)
            persist(library.copy(settings = settings.copy(invidiousPlaylistMappings = mappings)))
            _uiState.update { it.copy(integrationStatus = STATUS_INVIDIOUS_PUSH_OK) }
        }
    }

    private fun autoPushFavoriteTrack(track: Track) {
        val library = _uiState.value.library
        val settings = library.settings
        if (!settings.invidiousAutoPush || settings.invidiousInstance.isBlank() || settings.invidiousSid.isNullOrBlank()) return
        val existing = settings.invidiousPlaylistMappings["favorites"] ?: return
        viewModelScope.launch {
            val local = Playlist(id = "favorites", title = "Favorites", videos = listOf(track))
            integrations.invidiousPushPlaylist(settings, local, existing)
        }
    }

}

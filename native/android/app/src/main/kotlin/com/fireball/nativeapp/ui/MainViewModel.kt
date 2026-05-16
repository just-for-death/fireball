package com.fireball.nativeapp.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fireball.nativeapp.data.IntegrationOrchestrator
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import com.fireball.nativeapp.core.model.Album
import com.fireball.nativeapp.core.model.PlaybackSession
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.data.ArtistBrowseResult
import com.fireball.nativeapp.data.FireballRepository
import com.fireball.nativeapp.data.LyricsAndAiOrchestrator
import com.fireball.nativeapp.player.PlayerManager
import com.fireball.nativeapp.player.PlaybackState
import com.fireball.nativeapp.player.NativePlaybackService
import android.content.Intent
import com.fireball.nativeapp.player.PlaybackCommandBridge
import com.fireball.nativeapp.player.PlaybackController
import com.fireball.nativeapp.player.RepeatMode
import com.fireball.nativeapp.core.data.FireballAnalytics
import com.fireball.nativeapp.core.data.PlaybackPreferences
import com.fireball.nativeapp.core.data.integrations.SponsorSegment
import android.content.Context
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlin.random.Random
import androidx.media3.common.MediaItem
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import java.util.Locale

data class ArtistOpenRequest(
    val appleId: Int?,
    val fallbackName: String,
)

data class MainUiState(
    val library: LibrarySnapshot = LibrarySnapshot(),
    val query: String = "",
    val searchResults: List<Track> = emptyList(),
    /** Lightweight matches while typing (debounced; not replacing full Search results until user searches). */
    val searchSuggestions: List<Track> = emptyList(),
    val searchAlbumResults: List<Album> = emptyList(),
    val isSearching: Boolean = false,
    /** Resolving streams / handing off to ExoPlayer */
    val isPlaybackLoading: Boolean = false,
    val error: String? = null,
    val currentLyrics: String? = null,
    val integrationStatus: String? = null,
    val invidiousPlaylists: List<Pair<String, String>> = emptyList(),
    val chartCountryCode: String = "us",
    val trendingTracks: List<Track> = emptyList(),
    val trendingLoading: Boolean = false,
    val lbRecentTracks: List<Track> = emptyList(),
    val lbTopTracks: List<Track> = emptyList(),
    val lbTopRange: String = "month",
    val lbHomeLoading: Boolean = false,
    /** When non-null, root should navigate to Search and run a query once (artist / discovery). */
    val searchFocusRequest: String? = null,
    /** Navigate to Artist detail route; consumed by root. */
    val artistOpenRequest: ArtistOpenRequest? = null,
)

class MainViewModel(
    private val appContext: Context,
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

    private val libraryJson = Json { ignoreUnknownKeys = true }

    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()
    val playbackState: StateFlow<PlaybackState> = playerManager.state
    private val scrobbledTrackIds = mutableSetOf<String>()
    private val aiQueueExpandedForTrackIds = mutableSetOf<String>()
    private val sponsorSkippedUuids = mutableSetOf<String>()
    private var sponsorSegments: List<SponsorSegment> = emptyList()
    private var sponsorSegmentsVideoId: String? = null

    /** Set from [MainActivity] to request POST_NOTIFICATIONS when enabling on-device artist alerts (API 33+). */
    private var requestPostNotificationsPermission: (() -> Unit)? = null

    fun configurePostNotificationsRequest(handler: () -> Unit) {
        requestPostNotificationsPermission = handler
    }

    /** Cancels overlapping [play] work; only the latest play wins. */
    private var activePlayJob: Job? = null

    /** Serializes logical queue + Exo handoff vs [resyncEntireExoQueueFromLogicalState]. */
    private val engineHandoffMutex = Mutex()

    private var expandQueueJob: Job? = null

    /** Exo timeline (subset of logical queue with resolved URLs). */
    private var exoMediaItems: List<MediaItem> = emptyList()

    /** Invalidates in-flight [expandExoQueueInBackground] after a new [play]. */
    private var playGeneration: Int = 0

    private var suggestionJob: Job? = null

    private val resolveSemaphore = Semaphore(4)

    /** Avoid duplicate history/lyrics when the same Exo media id is reported twice. */
    private var lastStartedMediaId: String? = null

    private var advanceAfterTrackJob: kotlinx.coroutines.Job? = null

    init {
        playbackController.onPlaybackError = { msg ->
            _uiState.update { it.copy(error = "Playback failed: $msg") }
        }
        playbackController.onConnectFailed = { msg ->
            _uiState.update { it.copy(error = msg) }
        }
        playbackController.onPlaybackEnded = {
            val st = playbackState.value
            if (!(st.shuffled && exoMediaItems.size > 1)) {
                scheduleAdvanceAfterTrackFinished()
            }
        }
        playbackController.onActiveMediaIdChanged = { mediaId ->
            val st = playbackState.value
            val expectedId = st.currentTrack?.effectiveId
            val shuffleLinearSkip = st.shuffled && exoMediaItems.size > 1 &&
                !expectedId.isNullOrBlank() && !mediaId.isNullOrBlank() && mediaId != expectedId
            if (shuffleLinearSkip) {
                viewModelScope.launch {
                    val exoIdx = exoMediaItems.indexOfFirst { it.mediaId == expectedId }
                    if (exoIdx >= 0) playbackController.seekToMediaIndex(exoIdx)
                    scheduleAdvanceAfterTrackFinished()
                }
            } else {
                playerManager.setCurrentIndexByMediaId(mediaId)
                persistPlaybackSessionDebounced()
                if (!mediaId.isNullOrBlank() && mediaId != lastStartedMediaId) {
                    lastStartedMediaId = mediaId
                    val track = playbackState.value.currentTrack
                    if (track != null) {
                        val settings = _uiState.value.library.settings
                        viewModelScope.launch {
                            refreshSponsorForTrack(track, settings)
                            onTrackStarted(track, settings)
                        }
                    }
                }
            }
        }
        playbackController.connect()
        com.fireball.nativeapp.player.NativePlaybackService.reconfigureListener = {
            playbackController.release()
            playbackController.connect()
        }
        PlaybackCommandBridge.onSkipToNext = {
            viewModelScope.launch { userPressedNext() }
        }
        PlaybackCommandBridge.onSkipToPrevious = {
            viewModelScope.launch { userPressedPrevious() }
        }
        com.fireball.nativeapp.player.PlaybackEngineBridge.onIsPlayingChanged = { playing ->
            playerManager.syncFromEngine(isPlaying = playing)
        }
        viewModelScope.launch {
            var lastIndex = -1
            playbackController.state.collectLatest { engine ->
                playerManager.syncFromEngine(
                    currentIndex = null,
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
                    pausePlaybackForSleep()
                }
                val state = playbackState.value
                if (state.sleepAfterCurrent &&
                    state.isPlaying &&
                    state.durationMs > 0 &&
                    state.positionMs >= state.durationMs - 1000
                ) {
                    pausePlaybackForSleep()
                    playerManager.setSleepAfterCurrent(false)
                }
                maybeScrobbleCurrent(state)
                maybeAppendAiQueue(state)
                maybeSkipSponsor(state)
                if (state.isPlaying && state.currentIndex >= 0) {
                    persistPlaybackSessionDebounced()
                }
                delay(1000)
            }
        }
        viewModelScope.launch {
            val lib = repository.loadLibrary()
            PlaybackPreferences.save(appContext, lib.settings)
            _uiState.update { it.copy(library = lib) }
            val session = lib.playbackSession
            if (session.queue.isNotEmpty()) {
                val repeat = runCatching {
                    RepeatMode.valueOf(session.repeatMode.uppercase())
                }.getOrDefault(RepeatMode.OFF)
                playerManager.restoreSession(
                    queue = session.queue,
                    currentIndex = session.currentIndex,
                    shuffled = session.shuffled,
                    repeatMode = repeat,
                )
                bootstrapRestoredPlayback()
            }
            fetchInvidiousPlaylists()
            val chartCodes = HomeCountries.visibleCodes(lib.settings.homeCountries)
            val initialChart = chartCodes.firstOrNull()?.lowercase() ?: "us"
            _uiState.update { it.copy(chartCountryCode = initialChart) }
            refreshHome()
            checkFollowedArtistReleasesAsync()
            com.fireball.nativeapp.work.ArtistReleaseScheduler.schedule(appContext)
        }
    }

    fun refreshHome() {
        refreshHomeCharts()
        refreshListenBrainzHome()
    }

    fun selectLbTopRange(range: String) {
        val normalized = range.trim().lowercase()
        if (normalized.isBlank() || normalized == _uiState.value.lbTopRange) return
        _uiState.update { it.copy(lbTopRange = normalized) }
        refreshListenBrainzHome(topOnly = true)
    }

    private fun refreshListenBrainzHome(topOnly: Boolean = false) {
        viewModelScope.launch {
            val settings = _uiState.value.library.settings
            val lbReady = settings.listenBrainzEnabled &&
                settings.listenBrainzUsername.isNotBlank() &&
                settings.listenBrainzToken.isNotBlank()
            if (!lbReady) {
                _uiState.update { it.copy(lbRecentTracks = emptyList(), lbTopTracks = emptyList(), lbHomeLoading = false) }
                return@launch
            }
            _uiState.update { it.copy(lbHomeLoading = true) }
            val recent = if (topOnly) {
                _uiState.value.lbRecentTracks
            } else {
                integrations.listenBrainzRecent(settings, count = 8)
            }
            val top = integrations.listenBrainzTop(settings, range = _uiState.value.lbTopRange, count = 10)
            _uiState.update {
                it.copy(lbRecentTracks = recent, lbTopTracks = top, lbHomeLoading = false)
            }
        }
    }

    fun followArtist(artistName: String, artwork: String? = null) {
        if (artistName.isBlank()) return
        viewModelScope.launch {
            val artist = repository.resolveArtistForFollow(artistName, artwork)
            val library = _uiState.value.library
            if (library.artists.any { it.artistId == artist.artistId }) return@launch
            persist(library.copy(artists = library.artists + artist))
        }
    }

    fun unfollowArtist(artistId: String) {
        if (artistId.isBlank()) return
        val library = _uiState.value.library
        if (library.artists.none { it.artistId == artistId }) return
        persist(library.copy(artists = library.artists.filterNot { it.artistId == artistId }))
    }

    fun playQueueIndex(index: Int) {
        viewModelScope.launch { openQueueIndex(index) }
    }

    fun selectChartCountry(code: String) {
        val normalized = code.trim().lowercase()
        if (normalized.isBlank() || normalized == _uiState.value.chartCountryCode) return
        _uiState.update { it.copy(chartCountryCode = normalized) }
        refreshHomeCharts(normalized)
    }

    fun refreshHomeCharts(countryCode: String? = null) {
        val cc = countryCode?.trim()?.lowercase()
            ?: _uiState.value.chartCountryCode
        viewModelScope.launch {
            _uiState.update { it.copy(trendingLoading = true) }
            val tracks = repository.fetchTopSongs(cc, limit = 20)
            _uiState.update { it.copy(trendingTracks = tracks, trendingLoading = false) }
        }
    }

    fun refreshFollowedArtistReleasesOnForeground() {
        checkFollowedArtistReleasesAsync()
    }

    private fun checkFollowedArtistReleasesAsync() {
        viewModelScope.launch {
            val snapshot = _uiState.value.library
            com.fireball.nativeapp.notifications.ArtistReleaseNotifier.ensureChannel(appContext)
            val onGotify: (suspend (String, String) -> Boolean)? =
                if (snapshot.settings.gotifyEnabled &&
                    snapshot.settings.gotifyUrl.isNotBlank() &&
                    snapshot.settings.gotifyToken.isNotBlank()
                ) {
                    { title, message -> integrations.gotify(snapshot.settings, title, message) }
                } else {
                    null
                }
            val onDevice: (suspend (String, String) -> Unit)? =
                if (snapshot.settings.notifyArtistReleasesOnDevice) {
                    { title, message ->
                        com.fireball.nativeapp.notifications.ArtistReleaseNotifier.show(
                            appContext,
                            title,
                            message,
                        )
                    }
                } else {
                    null
                }
            val updated =
                repository.checkFollowedArtistNewReleases(
                    snapshot = snapshot,
                    onGotifyNotify = onGotify,
                    onDeviceNotify = onDevice,
                ) ?: return@launch
            repository.saveLibrary(updated)
            _uiState.update { it.copy(library = updated) }
        }
    }

    private fun bootstrapRestoredPlayback() {
        viewModelScope.launch {
            val idx = playbackState.value.currentIndex
            if (idx < 0) return@launch
            val settings = _uiState.value.library.settings
            var track = playbackState.value.queue.getOrNull(idx) ?: return@launch
            if (repository.needsInvidiousStreamResolution(track)) {
                track = runCatching {
                    repository.resolvePlayableTrack(track, settings)
                }.getOrNull() ?: return@launch
                playerManager.updateTrackAt(idx, track)
            }
            if (repository.needsInvidiousStreamResolution(track)) return@launch
            val item = toMediaItem(track)
            exoMediaItems = listOf(item)
            engineHandoffMutex.withLock {
                playbackController.prepareQueue(listOf(item), 0)
                playbackController.setRepeatMode(playbackState.value.repeatMode)
            }
            playerManager.syncFromEngine(isPlaying = false)
        }
    }

    fun consumeSearchFocusRequest() {
        _uiState.update { it.copy(searchFocusRequest = null) }
    }

    /** Jump to Search tab with this query (e.g. artist name); consumed by Root UI. */
    fun requestSearchForArtist(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        _uiState.update { it.copy(searchFocusRequest = q, error = null) }
    }

    /** Navigate to Artist catalog screen; resolves Apple id from followed-artists when names match. */
    fun requestArtistDetail(artistDisplayName: String) {
        val trimmed = artistDisplayName.trim()
        if (trimmed.isEmpty()) return
        val appleId =
            _uiState.value.library.artists.firstOrNull { it.name.equals(trimmed, ignoreCase = true) }
                ?.artistId
                ?.toIntOrNull()
        navigateArtistDetailInternal(appleId, trimmed)
    }

    fun requestArtistDetail(appleArtistId: Int?, fallbackDisplayName: String) {
        val trimmed = fallbackDisplayName.trim().ifBlank { "Artist" }
        navigateArtistDetailInternal(appleArtistId, trimmed)
    }

    private fun navigateArtistDetailInternal(artistAppleId: Int?, fallbackDisplayName: String) {
        _uiState.update {
            it.copy(artistOpenRequest = ArtistOpenRequest(artistAppleId, fallbackDisplayName))
        }
    }

    fun consumeArtistOpenRequest() {
        _uiState.update { it.copy(artistOpenRequest = null) }
    }

    suspend fun browseArtistPage(artistAppleId: Int?, fallbackName: String): ArtistBrowseResult? =
        repository.browseArtist(_uiState.value.library, artistAppleId, fallbackName.takeIf { it.isNotBlank() })

    suspend fun albumTracksCatalog(collectionId: Int): List<Track> =
        repository.catalogAlbumTracks(collectionId)

    fun playCatalogAlbum(album: com.fireball.nativeapp.core.model.Album) {
        viewModelScope.launch {
            val cid = album.id.toIntOrNull() ?: return@launch
            val tracks =
                try {
                    repository.catalogAlbumTracks(cid)
                } catch (_: Exception) {
                    emptyList()
                }
            if (tracks.isEmpty()) {
                _uiState.update { it.copy(error = "No tracks resolved for album.") }
                return@launch
            }
            play(tracks.first(), tracks)
        }
    }

    /** Insert a resolved copy of [track] after the current item without interrupting playback. */
    fun playTrackUpNext(track: Track) {
        viewModelScope.launch {
            val settings = _uiState.value.library.settings
            val snapshot = playbackState.value
            if (snapshot.queue.isEmpty() || snapshot.currentIndex < 0) {
                play(track, listOf(track))
                return@launch
            }
            val resolved = runCatching { repository.resolvePlayableTrack(track, settings) }.getOrElse { track }
            if (resolved.url.isNullOrBlank()) {
                _uiState.update { it.copy(error = "Could not resolve audio for Play next.") }
                return@launch
            }
            playerManager.insertTracksAt(snapshot.currentIndex + 1, listOf(resolved))
            persistPlaybackSessionDebounced()
            resyncEntireExoQueueFromLogicalState(preservePlaybackPosition = true)
        }
    }

    /** Append a resolved copy of [track] to the tail of the queue. */
    fun appendTrackToQueue(track: Track) {
        viewModelScope.launch {
            val settings = _uiState.value.library.settings
            val snapshot = playbackState.value
            if (snapshot.queue.isEmpty() || snapshot.currentIndex < 0) {
                play(track, listOf(track))
                return@launch
            }
            val resolved = runCatching { repository.resolvePlayableTrack(track, settings) }.getOrElse { track }
            if (resolved.url.isNullOrBlank()) {
                _uiState.update { it.copy(error = "Could not resolve audio.") }
                return@launch
            }
            playerManager.appendToQueue(listOf(resolved))
            persistPlaybackSessionDebounced()
            appendResolvedTracksToExo(listOf(resolved), settings)
        }
    }

    /** Adds [track] to a user playlist ([playlistId]); does not duplicate by [Track.effectiveId]. */
    fun addTrackToPlaylist(track: Track, playlistId: String) {
        val id = playlistId.trim()
        if (id.isEmpty()) return
        val library = _uiState.value.library
        val idx = library.playlists.indexOfFirst { it.id == id }
        if (idx < 0) return
        val pl = library.playlists[idx]
        if (pl.videos.any { it.effectiveId == track.effectiveId }) return
        val updated = library.playlists.mapIndexed { i, p ->
            if (i == idx) p.copy(videos = p.videos + track) else p
        }
        persist(library.copy(playlists = updated))
    }

    /** User playlists suitable for overflow (exclude internal AI stash). */
    fun userPlaylistsForPicker(): List<Playlist> =
        _uiState.value.library.playlists.filter { it.id != "ai_queue" }

    /**
     * Stops audio, clears the queue and persisted session, and hides the mini player.
     * Used when the user taps Close on the pill player.
     */
    fun stopPlaybackAndDismissMiniPlayer() {
        viewModelScope.launch {
            activePlayJob?.cancel()
            advanceAfterTrackJob?.cancel()
            expandQueueJob?.cancel()
            playGeneration++
            exoMediaItems = emptyList()
            clearSponsorState()
            lastStartedMediaId = null
            scrobbledTrackIds.clear()
            aiQueueExpandedForTrackIds.clear()

            engineHandoffMutex.withLock {
                playbackController.stopAndClearMedia()
            }
            playerManager.clearPlaybackSession()
            _uiState.update { it.copy(currentLyrics = null) }
            persist(
                _uiState.value.library.copy(
                    playbackSession = PlaybackSession(),
                ),
            )
        }
    }

    fun createPlaylist(title: String) {
        val raw = title.trim()
        if (raw.isBlank()) return
        val library = _uiState.value.library
        val slug =
            Regex("[^a-zA-Z0-9]+")
                .replace(raw.lowercase(Locale.US).trim(), "_")
                .trim('_')
                .ifBlank { "playlist" }
                .take(48)
        val id = "local_${slug}_${System.nanoTime().toString(36)}"
        val pl = Playlist(id = id, title = raw, videos = emptyList())
        persist(library.copy(playlists = library.playlists + pl))
    }

    /** Play [tracks] starting at [startIndex]; same handoff semantics as search tap-to-play. */
    fun playFromPlaylist(track: Track, tracks: List<Track>) {
        play(track, tracks)
    }

    /** Inserts resolved copies after the current queue item (entire playlist in order). */
    fun appendTracksUpNext(tracks: List<Track>) {
        if (tracks.isEmpty()) return
        viewModelScope.launch {
            val settings = _uiState.value.library.settings
            val snapshot = playbackState.value
            if (snapshot.queue.isEmpty() || snapshot.currentIndex < 0) {
                play(tracks.first(), tracks)
                return@launch
            }
            val resolved = tracks.mapNotNull { t ->
                val r = runCatching { repository.resolvePlayableTrack(t, settings) }.getOrElse { t }
                if (r.url.isNullOrBlank()) null else r
            }
            if (resolved.isEmpty()) {
                _uiState.update { it.copy(error = "Could not resolve tracks for Play next.") }
                return@launch
            }
            playerManager.insertTracksAt(snapshot.currentIndex + 1, resolved)
            persistPlaybackSessionDebounced()
            resyncEntireExoQueueFromLogicalState(preservePlaybackPosition = true)
        }
    }

    /** Appends resolved playable tracks to the end of the queue. */
    fun appendTracksToQueue(tracks: List<Track>) {
        if (tracks.isEmpty()) return
        viewModelScope.launch {
            val settings = _uiState.value.library.settings
            val snapshot = playbackState.value
            if (snapshot.queue.isEmpty() || snapshot.currentIndex < 0) {
                play(tracks.first(), tracks)
                return@launch
            }
            val resolved = tracks.mapNotNull { t ->
                val r = runCatching { repository.resolvePlayableTrack(t, settings) }.getOrElse { t }
                if (r.url.isNullOrBlank()) null else r
            }
            if (resolved.isEmpty()) {
                _uiState.update { it.copy(error = "Could not resolve tracks for queue.") }
                return@launch
            }
            playerManager.appendToQueue(resolved)
            persistPlaybackSessionDebounced()
            appendResolvedTracksToExo(resolved, settings)
        }
    }

    fun updateQuery(query: String) {
        _uiState.update { it.copy(query = query, searchSuggestions = if (query.isBlank()) emptyList() else it.searchSuggestions) }
        suggestionJob?.cancel()
        suggestionJob = viewModelScope.launch {
            val q = _uiState.value.query.trim()
            if (q.isBlank() || q.length < 2) {
                _uiState.update { it.copy(searchSuggestions = emptyList()) }
                return@launch
            }
            delay(340)
            if (_uiState.value.query.trim() != q) return@launch
            refreshSearchSuggestionsLocked(q)
        }
    }

    private suspend fun refreshSearchSuggestionsLocked(q: String) {
        val settings = _uiState.value.library.settings
        val localSources = mutableListOf<Track>()
        if (settings.offlineModeEnabled) {
            val needle = q.lowercase()
            val pooled = (_uiState.value.library.favorites + _uiState.value.library.history)
                .distinctBy { it.effectiveId }
            localSources.addAll(
                pooled.filter {
                    it.title.lowercase().contains(needle) || it.artist.lowercase().contains(needle)
                }.take(8),
            )
            _uiState.update { it.copy(searchSuggestions = localSources.distinctBy { it.effectiveId }.take(8)) }
            return
        }

        val needle = q.lowercase(Locale.US)
        val pooled =
            (_uiState.value.library.favorites + _uiState.value.library.history + _uiState.value.library.artists.map { a ->
                Track(id = a.artistId, title = "Artist · ${a.name}", artist = a.name, artwork = a.artwork)
            })
                .distinctBy { it.effectiveId }
        localSources.addAll(pooled.filter { it.title.lowercase().contains(needle) || it.artist.lowercase().contains(needle) })

        val remote =
            runCatching { repository.searchTracks(q, settings) }.getOrElse { emptyList() }.take(8)
        val merged =
            (localSources + remote).distinctBy { it.effectiveId }.take(12)
        _uiState.update { it.copy(searchSuggestions = merged.take(10)) }
    }

    /** Run suggestion fetch when Search screen mounts with existing query. */
    fun refreshSearchSuggestionsNow() {
        suggestionJob?.cancel()
        suggestionJob = viewModelScope.launch {
            val q = _uiState.value.query.trim()
            if (q.length < 2) {
                _uiState.update { it.copy(searchSuggestions = emptyList()) }
            } else {
                refreshSearchSuggestionsLocked(q)
            }
        }
    }

    fun dismissError() {
        _uiState.update { it.copy(error = null) }
    }

    fun search() {
        val query = _uiState.value.query
        if (query.isBlank()) return
        viewModelScope.launch {
            _uiState.update {
                it.copy(isSearching = true, error = null, searchSuggestions = emptyList())
            }

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
                        searchAlbumResults = emptyList(),
                    )
                }
                return@launch
            }

            coroutineScope {
                val tracksDeferred = async {
                    runCatching {
                        repository.searchTracks(query, _uiState.value.library.settings)
                    }
                }
                val albumsDeferred = async {
                    runCatching {
                        repository.searchAlbumsCatalog(query, settings)
                    }.getOrDefault(emptyList())
                }
                val tracks = tracksDeferred.await().getOrElse {
                    _uiState.update { current ->
                        current.copy(isSearching = false, error = it.message ?: "Search failed")
                    }
                    return@coroutineScope
                }
                val albums = albumsDeferred.await()
                _uiState.update {
                    it.copy(
                        isSearching = false,
                        searchResults = tracks,
                        searchAlbumResults = albums,
                        error = if (tracks.isEmpty() && albums.isEmpty()) {
                            "No results. Try another query or check Invidious / network."
                        } else {
                            it.error
                        },
                    )
                }
            }
        }
    }

    fun play(track: Track, source: List<Track>) {
        val settings = _uiState.value.library.settings
        val generation = ++playGeneration
        activePlayJob?.cancel()
        activePlayJob = viewModelScope.launch {
            _uiState.update { it.copy(isPlaybackLoading = true, error = null) }
            try {
                val resolvedTrack = repository.resolvePlayableTrack(track, settings)
                val startIndex = source.indexOfFirst { it.effectiveId == track.effectiveId }
                    .let { if (it < 0) 0 else it }
                val logicalQueue = source.map {
                    if (it.effectiveId == track.effectiveId) resolvedTrack else it
                }
                lastStartedMediaId = null
                scrobbledTrackIds.clear()

                val playableUrl = resolvedTrack.url
                if (playableUrl.isNullOrBlank()) {
                    clearSponsorState()
                    val hint =
                        "Could not resolve audio. Tried Invidious mirrors and on-device YouTube extract. Check network or set a custom Invidious instance in Settings."
                    _uiState.update { it.copy(error = hint) }
                    return@launch
                }

                val repeatMode = playbackState.value.repeatMode
                val shuffle = playbackState.value.shuffled
                val bootstrapItem = NativePlaybackService.mediaItem(
                    id = resolvedTrack.effectiveId,
                    title = resolvedTrack.title,
                    artist = resolvedTrack.artist,
                    url = playableUrl,
                    artworkUrl = resolvedTrack.artwork
                )

                exoMediaItems = listOf(bootstrapItem)
                engineHandoffMutex.withLock {
                    playerManager.replaceQueue(logicalQueue, startIndex)
                    playbackController.setRepeatMode(repeatMode)
                    playbackController.setShuffle(false)
                    playbackController.playQueue(listOf(bootstrapItem), 0)
                }

                val nowPlaying = logicalQueue[startIndex]
                refreshSponsorForTrack(nowPlaying, settings)
                onTrackStarted(nowPlaying, settings)
                lastStartedMediaId = nowPlaying.effectiveId

                expandQueueJob?.cancel()
                expandQueueJob = viewModelScope.launch {
                    expandExoQueueInBackground(logicalQueue, resolvedTrack, settings, generation)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(error = e.message ?: "Playback failed")
                }
            } finally {
                _uiState.update { it.copy(isPlaybackLoading = false) }
            }
        }
    }

    private fun clearSponsorState() {
        sponsorSegments = emptyList()
        sponsorSegmentsVideoId = null
        sponsorSkippedUuids.clear()
    }

    private suspend fun onTrackStarted(nowPlaying: Track, settings: FireballSettings) {
        val offline = settings.offlineModeEnabled
        val privacy = settings.privacyModeEnabled

        if (!privacy) {
            val history = listOf(nowPlaying) + _uiState.value.library.history
                .filterNot { it.effectiveId == nowPlaying.effectiveId }
            persist(_uiState.value.library.copy(history = history.take(200)))
        }

        if (offline) {
            _uiState.update { it.copy(currentLyrics = null) }
        } else {
            val trackId = nowPlaying.effectiveId
            viewModelScope.launch {
                val lyrics = lyricsAndAi.fetchLyrics(nowPlaying, settings)
                if (playbackState.value.currentTrack?.effectiveId == trackId) {
                    _uiState.update { it.copy(currentLyrics = lyrics) }
                }
            }
        }

        if (!offline && !privacy) {
            viewModelScope.launch {
                integrations.submitPlayingNow(settings, nowPlaying)
                integrations.submitLastFmPlayingNow(settings, nowPlaying)
            }
        }
        if (!privacy) {
            FireballAnalytics.log(
                "track_started",
                settings,
                mapOf("id" to nowPlaying.effectiveId, "title" to nowPlaying.title),
            )
        }
    }

    /** Resolves the rest of the queue and extends the Exo timeline without restarting playback. */
    private suspend fun expandExoQueueInBackground(
        logicalQueue: List<Track>,
        anchor: Track,
        settings: FireballSettings,
        generation: Int,
    ) {
        if (generation != playGeneration) return
        if (logicalQueue.size <= 1) return
        if (playbackState.value.shuffled) return

        val fullyResolved = resolveQueueTracksParallel(logicalQueue, settings)
        if (generation != playGeneration) return
        val playable = fullyResolved.filter { !it.url.isNullOrBlank() }
        if (playable.isEmpty()) return

        val currentIdx = playbackState.value.currentIndex.coerceAtLeast(0)
        playerManager.updateQueueTracks(fullyResolved, currentIdx)

        val items = playable.map { t -> toMediaItem(t) }
        val anchorId = anchor.effectiveId
        val exoStart = playable.indexOfFirst { it.effectiveId == anchorId }.let { if (it < 0) 0 else it }

        exoMediaItems = items
        engineHandoffMutex.withLock {
            if (generation != playGeneration) return@withLock
            playbackController.setRepeatMode(playbackState.value.repeatMode)
            playbackController.setShuffle(false)
            playbackController.replaceMediaItems(items, exoStart, preservePosition = true)
        }
    }

    private fun toMediaItem(t: Track): MediaItem {
        val url = t.url?.trim().orEmpty()
        require(url.isNotEmpty()) {
            "Missing playback URL for track ${t.title} (${t.effectiveId})"
        }
        return NativePlaybackService.mediaItem(
            id = t.effectiveId,
            title = t.title,
            artist = t.artist,
            url = url,
            artworkUrl = t.artwork
        )
    }

    private suspend fun openQueueIndex(index: Int) {
        val settings = _uiState.value.library.settings
        var queue = playbackState.value.queue
        if (queue.isEmpty() || index !in queue.indices) return

        scrobbledTrackIds.clear()
        _uiState.update { it.copy(isPlaybackLoading = true, error = null) }
        try {
            var track = queue[index]
            if (repository.needsInvidiousStreamResolution(track)) {
                track = repository.resolvePlayableTrack(track, settings)
                playerManager.updateTrackAt(index, track)
                queue = playbackState.value.queue
            }

            if (repository.needsInvidiousStreamResolution(track)) {
                _uiState.update {
                    it.copy(
                        error = "No stream URL for this track. Invidious mirrors and on-device YouTube were tried; Apple preview samples are not used for playback."
                    )
                }
                return
            }

            playerManager.setCurrentIndex(index)
            persistPlaybackSessionDebounced()
            lastStartedMediaId = null

            val item = toMediaItem(track)
            val exoIdx = exoMediaItems.indexOfFirst { it.mediaId == track.effectiveId }
            engineHandoffMutex.withLock {
                playbackController.setRepeatMode(playbackState.value.repeatMode)
                playbackController.setShuffle(false)
                if (exoIdx >= 0) {
                    playbackController.seekToMediaIndex(exoIdx)
                } else {
                    exoMediaItems = listOf(item)
                    playbackController.playQueue(listOf(item), 0)
                }
            }
            refreshSponsorForTrack(track, settings)
            onTrackStarted(track, settings)
            lastStartedMediaId = track.effectiveId
        } finally {
            _uiState.update { it.copy(isPlaybackLoading = false) }
        }
    }

    private fun scheduleAdvanceAfterTrackFinished() {
        advanceAfterTrackJob?.cancel()
        advanceAfterTrackJob = viewModelScope.launch {
            kotlinx.coroutines.delay(80)
            advanceAfterTrackFinished()
        }
    }

    private suspend fun advanceAfterTrackFinished() {
        val st = playbackState.value
        val idx = st.currentIndex
        if (idx < 0) return
        when {
            st.repeatMode == RepeatMode.ONE -> playbackController.seekTo(0L)
            st.shuffled && st.queue.size > 1 -> {
                val choices = st.queue.indices.filter { it != idx }
                if (choices.isNotEmpty()) openQueueIndex(choices[Random.nextInt(choices.size)])
            }
            idx + 1 < st.queue.size -> openQueueIndex(idx + 1)
            st.repeatMode == RepeatMode.ALL -> openQueueIndex(0)
            _uiState.value.library.settings.queueMode.trim().lowercase() == "repeat" -> openQueueIndex(0)
            else -> playerManager.syncFromEngine(isPlaying = false)
        }
    }

    private suspend fun userPressedNext() {
        val st = playbackState.value
        val idx = st.currentIndex
        if (idx < 0) return
        if (st.shuffled && st.queue.size > 1) {
            val choices = st.queue.indices.filter { it != idx }
            if (choices.isNotEmpty()) openQueueIndex(choices[Random.nextInt(choices.size)])
            return
        }
        if (idx + 1 < st.queue.size) {
            openQueueIndex(idx + 1)
        } else if (st.repeatMode == RepeatMode.ALL) {
            openQueueIndex(0)
        } else if (_uiState.value.library.settings.queueMode.trim().lowercase() == "repeat") {
            openQueueIndex(0)
        }
    }

    private fun pausePlaybackForSleep() {
        if (playbackController.isConnected) {
            playbackController.pause()
        }
        playerManager.syncFromEngine(isPlaying = false)
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

    fun isFavorite(track: Track): Boolean =
        _uiState.value.library.favorites.any { it.effectiveId == track.effectiveId }

    fun updateSettings(transform: (FireballSettings) -> FireballSettings) {
        val previous = _uiState.value.library.settings
        val updated = transform(previous)
        PlaybackPreferences.save(appContext, updated)
        persist(_uiState.value.library.copy(settings = updated))
        if (!previous.notifyArtistReleasesOnDevice &&
            updated.notifyArtistReleasesOnDevice &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        ) {
            requestPostNotificationsPermission?.invoke()
        }
        if (previous.streamCacheEnabled != updated.streamCacheEnabled ||
            previous.localMusicCacheLimit != updated.localMusicCacheLimit
        ) {
            com.fireball.nativeapp.player.NativePlaybackService.requestReconfigureStreamCache(appContext)
        }
        val lbChanged = previous.listenBrainzEnabled != updated.listenBrainzEnabled ||
            previous.listenBrainzToken != updated.listenBrainzToken ||
            previous.listenBrainzUsername != updated.listenBrainzUsername
        if (lbChanged) {
            refreshListenBrainzHome()
        }
        if (previous.homeCountries != updated.homeCountries) {
            val visible = HomeCountries.visibleCodes(updated.homeCountries)
            val current = _uiState.value.chartCountryCode
            if (visible.none { it.equals(current, ignoreCase = true) }) {
                val next = visible.firstOrNull()?.lowercase() ?: "us"
                _uiState.update { it.copy(chartCountryCode = next) }
                refreshHomeCharts(next)
            }
        }
    }

    fun signOutInvidious() {
        updateSettings { it.copy(invidiousSid = null, invidiousUsername = null) }
        _uiState.update { it.copy(invidiousPlaylists = emptyList()) }
    }

    fun validateLastFmKey(onResult: (Boolean) -> Unit) {
        val key = _uiState.value.library.settings.lastFmApiKey
        viewModelScope.launch {
            val ok = integrations.validateLastFmApiKey(key)
            onResult(ok)
            _uiState.update {
                it.copy(integrationStatus = if (ok) "last.fm: api key valid" else "last.fm: api key invalid")
            }
        }
    }

    fun connectLastFm(password: String, onResult: (Boolean) -> Unit) {
        val settings = _uiState.value.library.settings
        viewModelScope.launch {
            val session = integrations.connectLastFm(settings, password)
            if (session.isNullOrBlank()) {
                onResult(false)
                _uiState.update { it.copy(integrationStatus = "last.fm: login failed") }
                return@launch
            }
            updateSettings { it.copy(lastFmSessionKey = session) }
            onResult(true)
            _uiState.update { it.copy(integrationStatus = "last.fm: connected") }
        }
    }

    fun togglePlayPause() {
        if (!playbackController.togglePlayPause()) return
        val enginePlaying = playbackController.state.value.isPlaying
        playerManager.syncFromEngine(isPlaying = enginePlaying)
    }

    fun next() {
        if (playbackState.value.repeatMode == RepeatMode.ONE) {
            playbackController.seekTo(0L)
            return
        }
        viewModelScope.launch { userPressedNext() }
    }

    fun previous() {
        if (playbackState.value.repeatMode == RepeatMode.ONE) {
            playbackController.seekTo(0L)
            return
        }
        viewModelScope.launch { userPressedPrevious() }
    }

    private suspend fun userPressedPrevious() {
        val st = playbackState.value
        val idx = st.currentIndex
        if (idx < 0) return
        if (st.positionMs > 3_000L) {
            playbackController.seekTo(0L)
            return
        }
        if (st.shuffled && st.queue.size > 1) {
            val choices = st.queue.indices.filter { it != idx }
            if (choices.isNotEmpty()) {
                openQueueIndex(choices[Random.nextInt(choices.size)])
                return
            }
        }
        openQueueIndex((idx - 1).coerceAtLeast(0))
    }

    fun seekTo(positionMs: Long) {
        playbackController.seekTo(positionMs)
    }

    fun toggleShuffle() {
        playerManager.toggleShuffle()
        playbackController.setShuffle(false)
    }

    fun toggleRepeatMode() {
        playerManager.toggleRepeatMode()
        playbackController.setRepeatMode(playbackState.value.repeatMode)
    }
    fun setSleepTimer(minutes: Int?) = playerManager.setSleepTimer(minutes)
    fun sleepAfterCurrent(enabled: Boolean) = playerManager.setSleepAfterCurrent(enabled)

    private var lastPlaybackPersistAtMs: Long = 0L

    private fun persistPlaybackSessionDebounced() {
        val now = System.currentTimeMillis()
        if (now - lastPlaybackPersistAtMs < 2_000L) return
        lastPlaybackPersistAtMs = now
        persist(_uiState.value.library)
    }

    private fun persist(library: LibrarySnapshot) {
        val ps = playbackState.value
        val sessionIndex =
            when {
                ps.queue.isEmpty() -> -1
                ps.currentIndex < 0 -> 0
                else -> ps.currentIndex.coerceIn(0, ps.queue.lastIndex)
            }
        val withPlayback = library.copy(
            playbackSession = PlaybackSession(
                queue = ps.queue,
                currentIndex = sessionIndex,
                shuffled = ps.shuffled,
                repeatMode = ps.repeatMode.name.lowercase(),
            ),
        )
        _uiState.update { it.copy(library = withPlayback) }
        viewModelScope.launch {
            repository.saveLibrary(withPlayback)
            scheduleWebDavLivePushIfNeeded(withPlayback)
        }
    }

    private suspend fun scheduleWebDavLivePushIfNeeded(snapshot: LibrarySnapshot) {
        val settings = snapshot.settings
        if (!settings.webDavLiveSync) return
        if (settings.webDavUrl.isBlank()) return
        integrations.syncPush(settings, snapshot)
    }

    private suspend fun maybeSkipSponsor(state: PlaybackState) {
        val settings = _uiState.value.library.settings
        if (!settings.sponsorBlock || settings.sponsorBlockCategories.isEmpty()) return
        val track = state.currentTrack ?: return
        val vid = track.videoId ?: return
        if (vid != sponsorSegmentsVideoId) return
        if (sponsorSegments.isEmpty()) return
        if (!state.isPlaying || state.durationMs <= 0L) return
        val posSec = state.positionMs / 1000.0
        for (seg in sponsorSegments) {
            if (posSec < seg.start + 0.04) continue
            if (posSec >= seg.end - 0.04) continue
            if (!sponsorSkippedUuids.add(seg.uuid)) continue
            runCatching { integrations.markSponsorViewed(seg.uuid) }
            val targetMs = (seg.end * 1000.0).toLong().coerceIn(0L, state.durationMs)
            playbackController.seekTo(targetMs)
            break
        }
    }

    private fun maybeScrobbleCurrent(state: PlaybackState) {
        val track = state.currentTrack ?: return
        val settings = _uiState.value.library.settings
        if (!settings.scrobbleEnabled) return
        if (settings.offlineModeEnabled || settings.privacyModeEnabled) return
        val lbEnabled = settings.listenBrainzEnabled && settings.listenBrainzToken.isNotBlank()
        val lastFmEnabled = settings.lastFmApiKey.isNotBlank() &&
            settings.lastFmApiSecret.isNotBlank() &&
            settings.lastFmSessionKey.isNotBlank()
        if (!lbEnabled && !lastFmEnabled) return
        if (!state.isPlaying) return
        if (!com.fireball.nativeapp.core.model.ScrobbleRules.shouldScrobble(
                positionMs = state.positionMs,
                durationMs = state.durationMs,
                percent = settings.listenBrainzScrobblePercent,
                maxSeconds = settings.listenBrainzScrobbleMaxSeconds,
                minTrackSeconds = settings.listenBrainzScrobbleMinTrackSeconds,
            )
        ) {
            return
        }

        if (!scrobbledTrackIds.add(track.effectiveId)) return
        val listenedAt = System.currentTimeMillis() / 1000L
        viewModelScope.launch {
            if (settings.listenBrainzEnabled && settings.listenBrainzToken.isNotBlank()) {
                integrations.submitScrobble(
                    settings = settings,
                    track = track,
                    listenedAtEpoch = listenedAt,
                )
            }
            integrations.submitLastFmScrobble(settings, track, listenedAt)
            FireballAnalytics.log("scrobble", settings, mapOf("id" to track.effectiveId))
        }
    }

    private fun maybeAppendAiQueue(state: PlaybackState) {
        val current = state.currentTrack ?: return
        val atTail = state.currentIndex >= 0 && state.currentIndex == state.queue.lastIndex
        if (!atTail) return
        val settings = _uiState.value.library.settings
        if (settings.offlineModeEnabled || settings.privacyModeEnabled) return
        if (settings.queueMode.trim().lowercase() != "ai") return
        if (!settings.ollamaEnabled) return
        if (settings.ollamaUrl.isBlank() || settings.ollamaModel.isBlank()) return
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
            appendResolvedTracksToExo(generatedTracks, settings)
        }
    }

    private suspend fun appendResolvedTracksToExo(tracks: List<Track>, settings: FireballSettings) {
        if (tracks.isEmpty()) return
        val resolved = resolveQueueTracksParallel(tracks, settings)
        val playable = resolved.filter { !it.url.isNullOrBlank() }
        if (playable.isEmpty()) {
            if (resolved.any { it.url.isNullOrBlank() }) {
                resyncEntireExoQueueFromLogicalState()
            }
            return
        }
        val items = playable.map { toMediaItem(it) }
        engineHandoffMutex.withLock {
            playbackController.appendMediaItems(items)
            exoMediaItems = exoMediaItems + items
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

    private suspend fun resolveQueueTracksParallel(
        queue: List<Track>,
        settings: FireballSettings
    ): List<Track> = coroutineScope {
        queue.map { t ->
            async {
                resolveSemaphore.acquire()
                try {
                    runCatching { repository.resolvePlayableTrack(t, settings) }.getOrElse { t }
                } finally {
                    resolveSemaphore.release()
                }
            }
        }.awaitAll()
    }

    private suspend fun refreshSponsorForTrack(track: Track, settings: FireballSettings) {
        sponsorSkippedUuids.clear()
        sponsorSegmentsVideoId = track.videoId
        sponsorSegments = if (settings.sponsorBlock && !track.videoId.isNullOrBlank()) {
            integrations.sponsorSegments(settings, track)
        } else {
            emptyList()
        }
    }

    /**
     * Rebuilds the ExoPlayer queue from [PlayerManager] after URLs were missing (e.g. AI suggestions)
     * or the logical list was compacted to playable-only tracks.
     */
    private suspend fun resyncEntireExoQueueFromLogicalState(preservePlaybackPosition: Boolean = false) {
        val settings = _uiState.value.library.settings
        val snapshot = playbackState.value
        if (snapshot.queue.isEmpty()) return

        val resolved = resolveQueueTracksParallel(snapshot.queue, settings)
        if (resolved.isEmpty()) return

        val playable = resolved.filter { !it.url.isNullOrBlank() }
        if (playable.isEmpty()) {
            _uiState.update {
                it.copy(
                    error = "Could not get streams for tracks in the queue. Check Invidious settings or network."
                )
            }
            return
        }

        val logicalIndex = snapshot.currentIndex.coerceIn(0, resolved.lastIndex)
        fun firstPlayableResolvedIndexFrom(start: Int): Int? {
            for (i in start until resolved.size) {
                if (!resolved[i].url.isNullOrBlank()) return i
            }
            for (i in start downTo 0) {
                if (!resolved[i].url.isNullOrBlank()) return i
            }
            return null
        }

        val chosenResolvedIdx = firstPlayableResolvedIndexFrom(logicalIndex) ?: return
        val chosenTrack = resolved[chosenResolvedIdx]
        val newIdx = playable.indexOfFirst { it.effectiveId == chosenTrack.effectiveId }
            .let { if (it < 0) 0 else it }

        val repeatMode = playbackState.value.repeatMode
        val items = playable.map { t ->
            val url = t.url?.trim().orEmpty()
            require(url.isNotEmpty()) {
                "Missing playback URL for track ${t.title} (${t.effectiveId})"
            }
            NativePlaybackService.mediaItem(
                id = t.effectiveId,
                title = t.title,
                artist = t.artist,
                url = url,
                artworkUrl = t.artwork
            )
        }
        exoMediaItems = items
        engineHandoffMutex.withLock {
            playerManager.updateQueueTracks(resolved, chosenResolvedIdx)
            playbackController.setRepeatMode(repeatMode)
            playbackController.setShuffle(false)
            playbackController.replaceMediaItems(items, newIdx, preservePosition = preservePlaybackPosition)
        }
        refreshSponsorForTrack(chosenTrack, settings)
    }

    override fun onCleared() {
        activePlayJob?.cancel()
        expandQueueJob?.cancel()
        PlaybackCommandBridge.onSkipToNext = null
        PlaybackCommandBridge.onSkipToPrevious = null
        playbackController.release()
        super.onCleared()
    }

    fun webDavPullMerge() {
        viewModelScope.launch {
            val remote = integrations.syncPull(_uiState.value.library.settings)
            if (remote == null) {
                _uiState.update { it.copy(integrationStatus = "webdav pull: failed") }
                return@launch
            }
            val merged = runCatching {
                libraryJson.decodeFromString<LibrarySnapshot>(remote)
            }.getOrNull()
            if (merged == null) {
                _uiState.update { it.copy(integrationStatus = "webdav pull: decode failed") }
                return@launch
            }
            val local = _uiState.value.library
            val combined = local.copy(
                history = (local.history + merged.history).distinctBy { it.effectiveId }.take(200),
                favorites = (local.favorites + merged.favorites).distinctBy { it.effectiveId },
                playlists = (local.playlists + merged.playlists).distinctBy { it.id },
                artists = (local.artists + merged.artists).distinctBy { it.artistId },
                albums = (local.albums + merged.albums).distinctBy { it.id }
            )
            persist(combined)
            _uiState.update { it.copy(integrationStatus = "webdav pull: success") }
        }
    }

    fun webDavPush() {
        viewModelScope.launch {
            val ok = integrations.syncPush(_uiState.value.library.settings, _uiState.value.library)
            _uiState.update {
                it.copy(integrationStatus = if (ok) "webdav push: success" else "webdav push: failed")
            }
        }
    }

    fun sendGotifyTest() {
        viewModelScope.launch {
            val settings = _uiState.value.library.settings
            if (!settings.gotifyEnabled) {
                _uiState.update { it.copy(integrationStatus = "gotify: disabled") }
                return@launch
            }
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
            val links = playbackState.value.queue.mapNotNull { track ->
                track.url?.takeIf { it.isNotBlank() }
                    ?: track.videoId?.takeIf { it.isNotBlank() }?.let { "https://www.youtube.com/watch?v=$it" }
            }
            if (links.isEmpty()) {
                _uiState.update { it.copy(integrationStatus = "lbdl job: no URLs in queue") }
                return@launch
            }
            val jobId = integrations.lbdlCreateJob(_uiState.value.library.settings, links)
            _uiState.update {
                it.copy(integrationStatus = if (jobId != null) "$STATUS_LBDL_JOB_OK_PREFIX ($jobId)" else STATUS_LBDL_JOB_FAIL)
            }
        }
    }

    fun remoteTogglePlay() {
        viewModelScope.launch {
            if (!_uiState.value.library.settings.remoteServerEnabled) {
                _uiState.update { it.copy(integrationStatus = "remote: disabled") }
                return@launch
            }
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
            val settings = _uiState.value.library.settings
            if (!settings.gDriveEnabled) {
                _uiState.update { it.copy(integrationStatus = "gdrive: disabled") }
                return@launch
            }
            val ok = integrations.gDriveBackup(accessToken, _uiState.value.library)
            if (ok) {
                val stamp = java.time.Instant.now().toString()
                persist(_uiState.value.library.copy(settings = settings.copy(lastBackupAt = stamp)))
            }
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

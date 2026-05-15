package com.fireball.nativeapp.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fireball.nativeapp.data.IntegrationOrchestrator
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import com.fireball.nativeapp.core.model.PlaybackSession
import com.fireball.nativeapp.core.model.Playlist
import com.fireball.nativeapp.core.model.Track
import com.fireball.nativeapp.data.FireballRepository
import com.fireball.nativeapp.data.LyricsAndAiOrchestrator
import com.fireball.nativeapp.player.PlayerManager
import com.fireball.nativeapp.player.PlaybackState
import com.fireball.nativeapp.player.NativePlaybackService
import com.fireball.nativeapp.player.PlaybackController
import com.fireball.nativeapp.player.RepeatMode
import com.fireball.nativeapp.core.data.FireballAnalytics
import com.fireball.nativeapp.core.data.PlaybackPreferences
import com.fireball.nativeapp.core.data.integrations.SponsorSegment
import android.content.Context
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

data class MainUiState(
    val library: LibrarySnapshot = LibrarySnapshot(),
    val query: String = "",
    val searchResults: List<Track> = emptyList(),
    val isSearching: Boolean = false,
    /** Resolving streams / handing off to ExoPlayer */
    val isPlaybackLoading: Boolean = false,
    val error: String? = null,
    val currentLyrics: String? = null,
    val integrationStatus: String? = null,
    val invidiousPlaylists: List<Pair<String, String>> = emptyList()
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

    /** Cancels overlapping [play] work; only the latest play wins. */
    private var activePlayJob: Job? = null

    /** Serializes logical queue + Exo handoff vs [resyncEntireExoQueueFromLogicalState]. */
    private val engineHandoffMutex = Mutex()

    private var expandQueueJob: Job? = null

    /** Exo timeline (subset of logical queue with resolved URLs). */
    private var exoMediaItems: List<MediaItem> = emptyList()

    private val resolveSemaphore = Semaphore(4)

    /** Avoid duplicate history/lyrics when the same Exo media id is reported twice. */
    private var lastStartedMediaId: String? = null

    init {
        playbackController.onPlaybackError = { msg ->
            _uiState.update { it.copy(error = "Playback failed: $msg") }
        }
        playbackController.onConnectFailed = { msg ->
            _uiState.update { it.copy(error = msg) }
        }
        playbackController.onPlaybackEnded = {
            viewModelScope.launch { advanceAfterTrackFinished() }
        }
        playbackController.onActiveMediaIdChanged = { mediaId ->
            playerManager.setCurrentIndexByMediaId(mediaId)
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
        playbackController.connect()
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
                    if (playbackState.value.isPlaying) {
                        togglePlayPause()
                    }
                }
                val state = playbackState.value
                if (state.sleepAfterCurrent &&
                    state.isPlaying &&
                    state.durationMs > 0 &&
                    state.positionMs >= state.durationMs - 1000
                ) {
                    togglePlayPause()
                    playerManager.setSleepAfterCurrent(false)
                }
                maybeScrobbleCurrent(state)
                maybeAppendAiQueue(state)
                maybeSkipSponsor(state)
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
            }
            fetchInvidiousPlaylists()
        }
    }

    fun isFavorite(track: Track): Boolean =
        _uiState.value.library.favorites.any { it.effectiveId == track.effectiveId }

    fun updateQuery(query: String) {
        _uiState.update { it.copy(query = query) }
    }

    fun dismissError() {
        _uiState.update { it.copy(error = null) }
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
            _uiState.update {
                it.copy(
                    isSearching = false,
                    searchResults = tracks,
                    error = if (tracks.isEmpty()) {
                        "No results. Try another query or check Invidious / network."
                    } else {
                        it.error
                    },
                )
            }
        }
    }

    fun play(track: Track, source: List<Track>) {
        val settings = _uiState.value.library.settings
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
                    expandExoQueueInBackground(logicalQueue, resolvedTrack, settings)
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
            viewModelScope.launch {
                val lyrics = lyricsAndAi.fetchLyrics(nowPlaying, settings)
                _uiState.update { it.copy(currentLyrics = lyrics) }
            }
        }

        if (!offline && !privacy) {
            viewModelScope.launch {
                integrations.submitPlayingNow(settings, nowPlaying)
                integrations.submitLastFmPlayingNow(settings, nowPlaying)
            }
        }
        FireballAnalytics.log(
            "track_started",
            settings,
            mapOf("id" to nowPlaying.effectiveId, "title" to nowPlaying.title),
        )
    }

    /** Resolves the rest of the queue and extends the Exo timeline without restarting playback. */
    private suspend fun expandExoQueueInBackground(
        logicalQueue: List<Track>,
        anchor: Track,
        settings: FireballSettings
    ) {
        if (logicalQueue.size <= 1) return

        val fullyResolved = resolveQueueTracksParallel(logicalQueue, settings)
        val playable = fullyResolved.filter { !it.url.isNullOrBlank() }
        if (playable.isEmpty()) return

        val currentIdx = playbackState.value.currentIndex.coerceAtLeast(0)
        playerManager.updateQueueTracks(fullyResolved, currentIdx)

        val items = playable.map { t -> toMediaItem(t) }
        val anchorId = anchor.effectiveId
        val exoStart = playable.indexOfFirst { it.effectiveId == anchorId }.let { if (it < 0) 0 else it }

        exoMediaItems = items
        engineHandoffMutex.withLock {
            playbackController.setRepeatMode(playbackState.value.repeatMode)
            playbackController.setShuffle(false)
            playbackController.replaceMediaItems(items, exoStart, preservePosition = true)
        }
    }

    private fun toMediaItem(t: Track): MediaItem =
        NativePlaybackService.mediaItem(
            id = t.effectiveId,
            title = t.title,
            artist = t.artist,
            url = t.url!!,
            artworkUrl = t.artwork
        )

    private suspend fun openQueueIndex(index: Int) {
        val settings = _uiState.value.library.settings
        var queue = playbackState.value.queue
        if (queue.isEmpty() || index !in queue.indices) return

        _uiState.update { it.copy(isPlaybackLoading = true, error = null) }
        try {
            var track = queue[index]
            if (track.url.isNullOrBlank()) {
                track = repository.resolvePlayableTrack(track, settings)
                playerManager.updateTrackAt(index, track)
                queue = playbackState.value.queue
            }

            if (track.url.isNullOrBlank()) {
                _uiState.update {
                    it.copy(
                        error = "No stream URL for this track. Public Invidious mirrors were tried automatically."
                    )
                }
                return
            }

            playerManager.setCurrentIndex(index)
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
        PlaybackPreferences.save(appContext, updated)
        persist(_uiState.value.library.copy(settings = updated))
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
        viewModelScope.launch {
            val idx = playbackState.value.currentIndex.coerceAtLeast(0)
            openQueueIndex((idx - 1).coerceAtLeast(0))
        }
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

    private fun persist(library: LibrarySnapshot) {
        val ps = playbackState.value
        val withPlayback = library.copy(
            playbackSession = PlaybackSession(
                queue = ps.queue,
                currentIndex = ps.currentIndex.coerceAtLeast(0),
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
        if (settings.offlineModeEnabled || settings.privacyModeEnabled) return
        val lbEnabled = settings.listenBrainzEnabled && settings.listenBrainzToken.isNotBlank()
        val lastFmEnabled = settings.lastFmApiKey.isNotBlank() &&
            settings.lastFmApiSecret.isNotBlank() &&
            settings.lastFmSessionKey.isNotBlank()
        if (!lbEnabled && !lastFmEnabled) return
        if (state.durationMs <= 0) return

        val thresholdByPercent = (state.durationMs * settings.listenBrainzScrobblePercent / 100.0).toLong()
        val thresholdByMaxSeconds = settings.listenBrainzScrobbleMaxSeconds * 1000L
        val thresholdMs = minOf(thresholdByPercent, thresholdByMaxSeconds).coerceAtLeast(1_000L)
        if (state.positionMs < thresholdMs) return

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
            resyncEntireExoQueueFromLogicalState()
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
    private suspend fun resyncEntireExoQueueFromLogicalState() {
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
            NativePlaybackService.mediaItem(
                id = t.effectiveId,
                title = t.title,
                artist = t.artist,
                url = t.url!!,
                artworkUrl = t.artwork
            )
        }
        exoMediaItems = items
        engineHandoffMutex.withLock {
            playerManager.updateQueueTracks(resolved, chosenResolvedIdx)
            playbackController.setRepeatMode(repeatMode)
            playbackController.setShuffle(false)
            playbackController.replaceMediaItems(items, newIdx, preservePosition = false)
        }
        refreshSponsorForTrack(chosenTrack, settings)
    }

    override fun onCleared() {
        activePlayJob?.cancel()
        expandQueueJob?.cancel()
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

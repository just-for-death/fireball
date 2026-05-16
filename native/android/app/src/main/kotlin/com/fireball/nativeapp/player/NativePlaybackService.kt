package com.fireball.nativeapp.player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionResult
import com.fireball.nativeapp.MainActivity
import com.fireball.nativeapp.R
import androidx.core.net.toUri
import com.fireball.nativeapp.core.data.PlaybackPreferences

import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory

private object PlaybackNotification {
    /** Must match DefaultMediaNotificationProvider channel id wiring. */
    const val CHANNEL_ID = "fireball_media_playback"
}

@UnstableApi
class NativePlaybackService : MediaSessionService() {
    private var mediaSession: MediaSession? = null
    private var player: ExoPlayer? = null
    private var simpleCache: SimpleCache? = null
    private var databaseProvider: StandaloneDatabaseProvider? = null

    override fun onCreate() {
        super.onCreate()
        ensurePlaybackNotificationChannel()
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider.Builder(this)
                .setChannelId(PlaybackNotification.CHANNEL_ID)
                .build(),
        )
        buildPlayerAndSession()
    }

    private fun ensurePlaybackNotificationChannel() {
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        if (mgr.getNotificationChannel(PlaybackNotification.CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            PlaybackNotification.CHANNEL_ID,
            getString(R.string.playback_notification_channel),
            NotificationManager.IMPORTANCE_LOW,
        )
        mgr.createNotificationChannel(channel)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_RECONFIGURE_CACHE) {
            reconfigureStreamCache()
        }
        return super.onStartCommand(intent, flags, startId)
    }

    private fun reconfigureStreamCache() {
        val oldPlayer = player ?: return
        val items = buildList {
            for (i in 0 until oldPlayer.mediaItemCount) {
                add(oldPlayer.getMediaItemAt(i))
            }
        }
        val index = oldPlayer.currentMediaItemIndex.coerceAtLeast(0)
        val positionMs = oldPlayer.currentPosition.coerceAtLeast(0L)
        val playWhenReady = oldPlayer.playWhenReady

        mediaSession?.let { session ->
            removeSession(session)
            session.release()
        }
        oldPlayer.release()
        simpleCache?.release()
        simpleCache = null
        databaseProvider?.close()
        databaseProvider = null
        mediaSession = null
        player = null

        buildPlayerAndSession()

        val newPlayer = player ?: return
        if (items.isNotEmpty()) {
            val safeIndex = index.coerceIn(0, items.lastIndex)
            newPlayer.setMediaItems(items, safeIndex, positionMs)
            newPlayer.prepare()
            newPlayer.playWhenReady = playWhenReady
        }
        reconfigureListener?.invoke()
    }

    private fun buildPlayerAndSession() {
        PlaybackPreferences.load(this)

        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(STREAM_USER_AGENT)
            .setAllowCrossProtocolRedirects(true)

        val playbackDataSourceFactory: DataSource.Factory = if (PlaybackPreferences.streamCacheEnabled) {
            val mediaCacheDir = java.io.File(cacheDir, "media_cache")
            val evictor = LeastRecentlyUsedCacheEvictor(PlaybackPreferences.cacheLimitBytes)
            val dbProvider = StandaloneDatabaseProvider(this)
            databaseProvider = dbProvider
            val cache = SimpleCache(mediaCacheDir, evictor, dbProvider)
            simpleCache = cache
            CacheDataSource.Factory()
                .setCache(cache)
                .setUpstreamDataSourceFactory(httpDataSourceFactory)
                .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        } else {
            httpDataSourceFactory
        }

        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(playbackDataSourceFactory)

        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .setWakeMode(C.WAKE_MODE_LOCAL)
            .build().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                        .build(),
                    true,
                )
                setHandleAudioBecomingNoisy(true)
                repeatMode = Player.REPEAT_MODE_OFF
                addListener(object : Player.Listener {
                    override fun onPlayerError(error: PlaybackException) {
                        Log.e(TAG, "ExoPlayer error: ${error.errorCodeName} cause=${error.cause?.message}", error)
                    }

                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        PlaybackEngineBridge.onIsPlayingChanged?.invoke(isPlaying)
                    }
                })
            }
        mediaSession = MediaSession.Builder(this, player!!)
            .setSessionActivity(sessionActivityIntent())
            .setCallback(
                object : MediaSession.Callback {
                    @Suppress("DEPRECATION") // Migrate via player/MediaSession command availability APIs when refactoring session controls.
                    override fun onPlayerCommandRequest(
                        session: MediaSession,
                        controller: MediaSession.ControllerInfo,
                        playerCommand: Int,
                    ): Int {
                        when (playerCommand) {
                            Player.COMMAND_SEEK_TO_NEXT,
                            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> {
                                PlaybackCommandBridge.onSkipToNext?.invoke()
                                return SessionResult.RESULT_SUCCESS
                            }
                            Player.COMMAND_SEEK_TO_PREVIOUS,
                            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> {
                                PlaybackCommandBridge.onSkipToPrevious?.invoke()
                                return SessionResult.RESULT_SUCCESS
                            }
                        }
                        return super.onPlayerCommandRequest(session, controller, playerCommand)
                    }
                },
            )
            .build()
        addSession(mediaSession!!)
    }

    override fun onDestroy() {
        mediaSession?.let { session ->
            removeSession(session)
            session.player.release()
            session.release()
        }
        mediaSession = null
        player = null
        simpleCache?.release()
        simpleCache = null
        databaseProvider?.close()
        databaseProvider = null
        super.onDestroy()
    }

    private fun sessionActivityIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java)
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    companion object {
        private const val TAG = "FireballPlayback"
        const val ACTION_RECONFIGURE_CACHE = "com.fireball.nativeapp.action.RECONFIGURE_CACHE"

        @Volatile
        var reconfigureListener: (() -> Unit)? = null

        fun requestReconfigureStreamCache(context: Context) {
            val intent = Intent(context, NativePlaybackService::class.java).apply {
                action = ACTION_RECONFIGURE_CACHE
            }
            context.startService(intent)
        }

        /** Match OkHttp UA in [com.fireball.nativeapp.MainActivity] for CDN / Invidious proxy compatibility. */
        const val STREAM_USER_AGENT =
            "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 FireballNative/1.0"

        fun mediaItem(
            id: String,
            title: String,
            artist: String,
            url: String,
            artworkUrl: String? = null
        ): MediaItem {
            val metadata = MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .apply {
                    if (!artworkUrl.isNullOrBlank()) {
                        setArtworkUri(artworkUrl.toUri())
                    }
                }
                .build()
            return MediaItem.Builder()
                .setMediaId(id)
                .setUri(url)
                .setMediaMetadata(metadata)
                .build()
        }
    }
}

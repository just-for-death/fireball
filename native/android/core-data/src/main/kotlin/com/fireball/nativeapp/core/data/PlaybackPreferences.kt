package com.fireball.nativeapp.core.data

import android.content.Context
import com.fireball.nativeapp.core.model.FireballSettings

/**
 * Persists playback-related settings for [com.fireball.nativeapp.player.NativePlaybackService].
 */
object PlaybackPreferences {
    private const val PREFS = "fireball_playback_prefs"
    private const val KEY_STREAM_CACHE_ENABLED = "stream_cache_enabled"
    private const val KEY_CACHE_GB = "cache_gb"
    private const val KEY_PIP_ENABLED = "pip_enabled"

    @Volatile
    var streamCacheEnabled: Boolean = true
        private set

    @Volatile
    var cacheLimitBytes: Long = 1L shl 30
        private set

    @Volatile
    var pictureInPictureEnabled: Boolean = false
        private set

    fun apply(settings: FireballSettings) {
        streamCacheEnabled = settings.streamCacheEnabled
        val gb = settings.localMusicCacheLimit.coerceIn(1, 20)
        cacheLimitBytes = gb.toLong() * 1024L * 1024L * 1024L
        pictureInPictureEnabled = settings.dynamicIslandEnabled
    }

    fun save(context: Context, settings: FireballSettings) {
        apply(settings)
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_STREAM_CACHE_ENABLED, streamCacheEnabled)
            .putInt(KEY_CACHE_GB, settings.localMusicCacheLimit.coerceIn(1, 20))
            .putBoolean(KEY_PIP_ENABLED, pictureInPictureEnabled)
            .apply()
    }

    fun load(context: Context) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        streamCacheEnabled = prefs.getBoolean(KEY_STREAM_CACHE_ENABLED, true)
        val gb = prefs.getInt(KEY_CACHE_GB, 10).coerceIn(1, 20)
        cacheLimitBytes = gb.toLong() * 1024L * 1024L * 1024L
        pictureInPictureEnabled = prefs.getBoolean(KEY_PIP_ENABLED, false)
    }
}

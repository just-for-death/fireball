package com.fireball.nativeapp.core.data

import android.util.Log
import com.fireball.nativeapp.core.model.FireballSettings

/** Lightweight analytics gated by settings (no third-party SDK). */
object FireballAnalytics {
    private const val TAG = "FireballAnalytics"

    fun log(event: String, settings: FireballSettings, properties: Map<String, String> = emptyMap()) {
        if (!settings.analytics && !settings.loggingEnabled) return
        val props = if (properties.isEmpty()) "" else " $properties"
        Log.i(TAG, "$event$props")
    }
}

package com.fireball.nativeapp.player

/**
 * Engine events from [NativePlaybackService] / ExoPlayer that must sync UI state
 * (e.g. pause on headphone unplug / audio becoming noisy).
 */
object PlaybackEngineBridge {
    var onIsPlayingChanged: ((Boolean) -> Unit)? = null
}

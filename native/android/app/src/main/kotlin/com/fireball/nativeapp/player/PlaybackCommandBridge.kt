package com.fireball.nativeapp.player

/**
 * Routes notification / media-session skip actions to [com.fireball.nativeapp.ui.MainViewModel]
 * instead of ExoPlayer's built-in timeline navigation (which can diverge from the logical queue).
 */
object PlaybackCommandBridge {
    var onSkipToNext: (() -> Unit)? = null
    var onSkipToPrevious: (() -> Unit)? = null
}

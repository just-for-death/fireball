package com.fireball.nativeapp.ui.components

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput

/**
 * Tap opens the full player; long-press opens the track menu. Uses [detectTapGestures]
 * so a completed long-press does not also fire a tap (avoids combinedClick quirks).
 */
internal fun Modifier.miniPlayerMenuGestures(
    hostView: View,
    onTap: () -> Unit,
    onLongPressMenu: () -> Unit,
): Modifier = this.then(
    Modifier.pointerInput(hostView, onTap, onLongPressMenu) {
        val tap = onTap
        val longPress = onLongPressMenu
        detectTapGestures(
            onLongPress = {
                hostView.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                longPress()
            },
            onTap = { tap() },
        )
    },
)

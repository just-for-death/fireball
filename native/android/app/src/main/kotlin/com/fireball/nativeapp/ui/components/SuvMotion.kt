package com.fireball.nativeapp.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import com.fireball.nativeapp.ui.theme.MotionTokens

/**
 * Fade + slide entrance — port of Flutter [SuvFadeSlideIn].
 */
@Composable
fun SuvFadeSlideIn(
    modifier: Modifier = Modifier,
    delayMs: Int = 0,
    beginOffsetY: Float = 0.04f,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val reduceMotion = remember {
        runCatching {
            android.provider.Settings.Global.getFloat(
                context.contentResolver,
                android.provider.Settings.Global.TRANSITION_ANIMATION_SCALE,
                1f,
            ) == 0f
        }.getOrDefault(false)
    }
    if (reduceMotion) {
        Box(modifier) { content() }
        return
    }
    val progress = remember { Animatable(0f) }
    LaunchedEffect(delayMs) {
        progress.snapTo(0f)
        kotlinx.coroutines.delay(delayMs.toLong())
        progress.animateTo(
            targetValue = 1f,
            animationSpec = MotionTokens.tweenEmphasized(MotionTokens.DurationMedium2),
        )
    }
    val t = androidx.compose.animation.core.FastOutSlowInEasing.transform(progress.value)
    Box(
        modifier = modifier.graphicsLayer {
            alpha = t
            translationY = beginOffsetY * (1f - t) * 20f
        },
    ) {
        content()
    }
}

@Composable
fun SuvFadeSlideInStaggered(
    index: Int,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val delay = (index.coerceAtLeast(0) * 40).coerceAtMost(320)
    SuvFadeSlideIn(modifier = modifier, delayMs = delay, content = content)
}

/**
 * Press scale feedback — port of Flutter [SuvPressScale].
 */
@Composable
fun SuvPressScale(
    modifier: Modifier = Modifier,
    scaleDown: Float = 0.98f,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    var pressed by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (pressed) scaleDown else 1f,
        animationSpec = MotionTokens.springSnappy(),
        label = "suvPressScale",
    )
    Box(
        modifier = modifier
            .scale(scale)
            .then(
                if (onClick != null) {
                    Modifier.pointerInput(onClick) {
                        detectTapGestures(
                            onPress = {
                                pressed = true
                                try {
                                    awaitRelease()
                                } finally {
                                    pressed = false
                                }
                            },
                            onTap = { onClick() },
                        )
                    }
                } else {
                    Modifier
                },
            ),
    ) {
        content()
    }
}

/** Dark gradient shell — port of Flutter [PremiumBackground]. */
@Composable
fun PremiumBackground(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color(0xFF1A1A1A),
                        Color(0xFF121212),
                        Color(0xFF0A0A0A),
                    ),
                ),
            ),
    ) {
        content()
    }
}

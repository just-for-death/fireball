package com.fireball.nativeapp.ui.theme

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.graphics.get
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL

data class DominantColors(
    val primary: Color = Color(0xFF1A1A1A),
    val secondary: Color = Color(0xFF2A2A2A),
    val accent: Color = Color(0xFF888888),
    val onBackground: Color = Color.White,
)

internal fun defaultDominantColors(isDarkTheme: Boolean): DominantColors = if (isDarkTheme) {
    DominantColors(
        primary = Color(0xFF1A1A1A),
        secondary = Color(0xFF2A2A2A),
        accent = Color(0xFF888888),
        onBackground = Color.White,
    )
} else {
    DominantColors(
        primary = Color(0xFFF5F5F5),
        secondary = Color(0xFFE8E8E8),
        accent = Color(0xFF666666),
        onBackground = Color(0xFF1A1A1A),
    )
}

class DominantColorExtractor {
    suspend fun extract(imageUrl: String, isDarkTheme: Boolean): DominantColors? =
        withContext(Dispatchers.IO) {
            try {
                val connection = URL(imageUrl).openConnection()
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                val inputStream = connection.getInputStream()
                val bitmap = BitmapFactory.decodeStream(inputStream) ?: return@withContext null
                val (r, g, b) = sampleAverageRgb(bitmap)
                buildDominantColors(r, g, b, isDarkTheme)
            } catch (t: Throwable) {
                null
            }
        }

    private fun sampleAverageRgb(bitmap: Bitmap): Triple<Int, Int, Int> {
        val width = bitmap.width
        val height = bitmap.height
        val step = maxOf(1, minOf(width, height) / 10)
        var totalR = 0L
        var totalG = 0L
        var totalB = 0L
        var count = 0L
        for (x in 0 until width step step) {
            for (y in 0 until height step step) {
                val pixel = bitmap[x, y]
                totalR += android.graphics.Color.red(pixel)
                totalG += android.graphics.Color.green(pixel)
                totalB += android.graphics.Color.blue(pixel)
                count++
            }
        }
        if (count == 0L) return Triple(0, 0, 0)
        return Triple((totalR / count).toInt(), (totalG / count).toInt(), (totalB / count).toInt())
    }
}

@Composable
fun rememberDominantColors(
    imageUrl: String?,
    isDarkTheme: Boolean = true,
): DominantColors {
    val extractor = remember { DominantColorExtractor() }
    val themeAwareDefaults = remember(isDarkTheme) { defaultDominantColors(isDarkTheme) }
    var colors by remember(themeAwareDefaults) { mutableStateOf(themeAwareDefaults) }

    LaunchedEffect(imageUrl, isDarkTheme) {
        if (imageUrl == null) {
            colors = themeAwareDefaults
            return@LaunchedEffect
        }
        extractor.extract(imageUrl, isDarkTheme)?.let { colors = it }
    }

    return colors
}

internal fun buildDominantColors(
    avgR: Int,
    avgG: Int,
    avgB: Int,
    isDarkTheme: Boolean,
): DominantColors {
    val primary: Color
    val secondary: Color
    val onBackground: Color

    if (isDarkTheme) {
        primary = Color(
            red = (avgR * 0.3f / 255f).coerceIn(0f, 1f),
            green = (avgG * 0.3f / 255f).coerceIn(0f, 1f),
            blue = (avgB * 0.3f / 255f).coerceIn(0f, 1f),
        )
        secondary = Color(
            red = (avgR * 0.5f / 255f).coerceIn(0f, 1f),
            green = (avgG * 0.5f / 255f).coerceIn(0f, 1f),
            blue = (avgB * 0.5f / 255f).coerceIn(0f, 1f),
        )
        onBackground = Color.White
    } else {
        primary = Color(
            red = (avgR * 0.2f / 255f + 0.85f).coerceIn(0f, 1f),
            green = (avgG * 0.2f / 255f + 0.85f).coerceIn(0f, 1f),
            blue = (avgB * 0.2f / 255f + 0.85f).coerceIn(0f, 1f),
        )
        secondary = Color(
            red = (avgR * 0.3f / 255f + 0.75f).coerceIn(0f, 1f),
            green = (avgG * 0.3f / 255f + 0.75f).coerceIn(0f, 1f),
            blue = (avgB * 0.3f / 255f + 0.75f).coerceIn(0f, 1f),
        )
        onBackground = Color(0xFF1A1A1A)
    }

    val accent = saturatedAccent(avgR, avgG, avgB, isDarkTheme)
    return DominantColors(primary, secondary, accent, onBackground)
}

private fun saturatedAccent(r: Int, g: Int, b: Int, isDarkTheme: Boolean): Color {
    val (hue, sat, _) = rgbToHsl(r, g, b)
    val newSat = (sat * 1.2f).coerceIn(0f, 1f)
    val lightness = if (isDarkTheme) 0.6f else 0.5f
    val (rr, gg, bb) = hslToRgb(hue, newSat, lightness)
    return Color(red = rr / 255f, green = gg / 255f, blue = bb / 255f)
}

private fun rgbToHsl(r: Int, g: Int, b: Int): Triple<Float, Float, Float> {
    val rf = r / 255f
    val gf = g / 255f
    val bf = b / 255f
    val max = maxOf(rf, gf, bf)
    val min = minOf(rf, gf, bf)
    val l = (max + min) / 2f
    if (max == min) return Triple(0f, 0f, l)
    val d = max - min
    val s = if (l > 0.5f) d / (2f - max - min) else d / (max + min)
    val h = when (max) {
        rf -> ((gf - bf) / d + if (gf < bf) 6f else 0f)
        gf -> ((bf - rf) / d + 2f)
        else -> ((rf - gf) / d + 4f)
    } * 60f
    return Triple(h, s, l)
}

private fun hslToRgb(h: Float, s: Float, l: Float): Triple<Int, Int, Int> {
    if (s == 0f) {
        val gray = (l * 255f).toInt().coerceIn(0, 255)
        return Triple(gray, gray, gray)
    }
    val q = if (l < 0.5f) l * (1f + s) else l + s - l * s
    val p = 2f * l - q
    val hk = h / 360f
    val tr = hueToRgb(p, q, hk + 1f / 3f)
    val tg = hueToRgb(p, q, hk)
    val tb = hueToRgb(p, q, hk - 1f / 3f)
    return Triple(
        (tr * 255f).toInt().coerceIn(0, 255),
        (tg * 255f).toInt().coerceIn(0, 255),
        (tb * 255f).toInt().coerceIn(0, 255),
    )
}

private fun hueToRgb(p: Float, q: Float, tIn: Float): Float {
    var t = tIn
    if (t < 0f) t += 1f
    if (t > 1f) t -= 1f
    return when {
        t < 1f / 6f -> p + (q - p) * 6f * t
        t < 1f / 2f -> q
        t < 2f / 3f -> p + (q - p) * (2f / 3f - t) * 6f
        else -> p
    }
}

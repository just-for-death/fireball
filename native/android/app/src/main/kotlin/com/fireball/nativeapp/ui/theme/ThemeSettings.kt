package com.fireball.nativeapp.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable

/** Maps persisted [com.fireball.nativeapp.core.model.FireballSettings.themeMode]. */
fun themeModeToDark(themeMode: String, systemDark: Boolean): Boolean =
    when (themeMode.trim().lowercase()) {
        "light" -> false
        "dark" -> true
        else -> systemDark
    }

/** Best-effort map from Flutter [flexScheme] keys to native [AppTheme] palettes. */
fun flexSchemeToAppTheme(flexScheme: String): AppTheme {
    val k = flexScheme.trim().lowercase()
    return when {
        k.contains("ocean") || k.contains("blue") -> AppTheme.OCEAN
        k.contains("sunset") || k.contains("orange") || k.contains("amber") -> AppTheme.SUNSET
        k.contains("nature") || k.contains("green") || k.contains("forest") -> AppTheme.NATURE
        k.contains("love") || k.contains("pink") || k.contains("mandy") -> AppTheme.LOVE
        else -> AppTheme.DEFAULT
    }
}

@Composable
fun rememberAlbumArtColors(imageUrl: String?, isDarkTheme: Boolean): DominantColors? {
    if (imageUrl.isNullOrBlank()) return null
    return rememberDominantColors(imageUrl, isDarkTheme)
}

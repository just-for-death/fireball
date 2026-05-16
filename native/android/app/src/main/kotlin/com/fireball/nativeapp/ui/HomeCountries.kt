package com.fireball.nativeapp.ui

/** Chart region codes aligned with Flutter home defaults. */
object HomeCountries {
    val all: List<Pair<String, String>> = listOf(
        "US" to "United States",
        "GB" to "United Kingdom",
        "IN" to "India",
        "JP" to "Japan",
        "DE" to "Germany",
        "FR" to "France",
        "BR" to "Brazil",
        "CA" to "Canada",
        "AU" to "Australia",
        "KR" to "South Korea",
    )

    val defaultCodes: Set<String> = setOf("US", "GB", "IN", "JP", "DE")

    fun visibleCodes(saved: List<String>): List<String> =
        if (saved.isEmpty()) defaultCodes.toList() else saved
}

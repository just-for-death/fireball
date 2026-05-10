package com.fireball.nativeapp.navigation

import kotlinx.serialization.Serializable

@Serializable
sealed class Destination {
    @Serializable
    data object Home : Destination()

    @Serializable
    data object Search : Destination()

    @Serializable
    data object Library : Destination()

    @Serializable
    data object Settings : Destination()
}

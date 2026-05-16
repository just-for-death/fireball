package com.fireball.nativeapp.work

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

object ArtistReleaseScheduler {
    private const val UNIQUE = "fireball_followed_artist_releases"

    fun schedule(context: Context) {
        val req =
            PeriodicWorkRequestBuilder<ArtistReleaseWorker>(
                15,
                TimeUnit.HOURS,
            ).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
            UNIQUE,
            ExistingPeriodicWorkPolicy.UPDATE,
            req,
        )
    }
}

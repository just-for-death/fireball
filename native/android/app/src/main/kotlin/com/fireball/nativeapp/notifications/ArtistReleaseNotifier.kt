package com.fireball.nativeapp.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.fireball.nativeapp.MainActivity
import kotlin.random.Random

/**
 * Minimal local notifications when a followed artist publishes a new iTunes album row.
 */
object ArtistReleaseNotifier {
    const val CHANNEL_ID = "fireball_artist_releases"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Artist releases",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "New albums from artists you follow in Fireball"
            }
        mgr.createNotificationChannel(channel)
    }

    fun show(context: Context, title: String, message: String) {
        ensureChannel(context)
        val appContext = context.applicationContext
        val launch =
            PendingIntent.getActivity(
                appContext,
                0,
                Intent(appContext, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val nm = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val note =
            NotificationCompat.Builder(appContext, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setContentIntent(launch)
                .setAutoCancel(true)
                .build()
        nm.notify(Random.nextInt(60_000), note)
    }
}

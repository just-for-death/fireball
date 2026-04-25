// android/app/src/main/kotlin/com/fireball/fireball/MusicWidgetProvider.kt
package com.fireball.fireball

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.app.PendingIntent
import android.os.Build

class MusicWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            // Retrieve simple data from shared preferences (set by Flutter via MethodChannel)
            val prefs = context.getSharedPreferences("fireball_widget", Context.MODE_PRIVATE)
            val title = prefs.getString("track_title", "No track") ?: "No track"
            val artist = prefs.getString("track_artist", "") ?: ""

            // Construct the RemoteViews object
            val views = RemoteViews(context.packageName, R.layout.appwidget_music)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_artist, artist)

            // Click on the widget opens the app
            val intent = Intent(context, MainActivity::class.java)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            // Tell the AppWidgetManager to update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}

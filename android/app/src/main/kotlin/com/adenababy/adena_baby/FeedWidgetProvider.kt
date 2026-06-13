package com.adenababy.adena_baby

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Ana ekran widget'ı — "son beslenme". Veriyi Flutter (WidgetService) paylaşımlı
 * depoya yazar; burada okunup gösterilir. Dokununca uygulamayı açar.
 * Göreli zaman ("X önce") burada hesaplanır ki widget kendi yenileme periyodunda
 * da güncel kalsın.
 */
class FeedWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.feed_widget).apply {
                val babyName = widgetData.getString("baby_name", null) ?: "Bebek"
                val ms = widgetData.getString("last_feed_ms", null)?.toLongOrNull() ?: -1L
                setTextViewText(R.id.widget_baby, babyName)
                setTextViewText(R.id.widget_label, "Son beslenme")
                setTextViewText(R.id.widget_value, relativeText(ms))

                // Dokununca uygulamayı aç.
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun relativeText(ms: Long): String {
        if (ms <= 0L) return "Henüz kayıt yok"
        val diff = System.currentTimeMillis() - ms
        if (diff < 60_000L) return "az önce"
        val min = diff / 60_000L
        if (min < 60L) return "$min dk önce"
        val hours = min / 60L
        val mins = min % 60L
        if (hours < 24L) return if (mins > 0L) "$hours sa $mins dk önce" else "$hours sa önce"
        val days = hours / 24L
        return "$days gün önce"
    }
}

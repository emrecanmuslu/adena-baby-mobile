package com.adenababy.adena_baby

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Ana ekran widget'ı — "sonraki beslenme" geri sayımı. Veriyi Flutter
 * (WidgetService) paylaşımlı depoya yazar (tahmini sonraki beslenme zamanı);
 * burada "≈X kaldı" / "X gecikti" diye gösterilir. Dokununca uygulamayı açar.
 * Geri sayım burada hesaplanır ki widget kendi yenileme periyodunda da güncel
 * kalsın. Metin dili Flutter'ın yazdığı `locale` anahtarına göre (TR/EN).
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
                val en = widgetData.getString("locale", null) == "en"
                // Bu widget'a seçilmiş bebek (yapılandırma aktivitesi yazar); yoksa
                // aktif bebek fallback'i (baby_name/next_feed_ms).
                val selectedId = widgetData.getString("widget_baby_$widgetId", null)
                val babyName: String
                val ms: Long
                if (selectedId != null && widgetData.contains("name_$selectedId")) {
                    babyName = widgetData.getString("name_$selectedId", null)
                        ?: if (en) "Baby" else "Bebek"
                    ms = widgetData.getString("next_$selectedId", null)?.toLongOrNull() ?: -1L
                } else {
                    babyName = widgetData.getString("baby_name", null)
                        ?: if (en) "Baby" else "Bebek"
                    ms = widgetData.getString("next_feed_ms", null)?.toLongOrNull() ?: -1L
                }
                setTextViewText(R.id.widget_baby, babyName)
                setTextViewText(R.id.widget_label, if (en) "Next feed" else "Sonraki beslenme")
                setTextViewText(R.id.widget_value, countdownText(ms, en))

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

    /** Tahmini sonraki beslenmeye kalan/geçen süre. ms<=0 → kayıt yok. */
    private fun countdownText(ms: Long, en: Boolean): String {
        if (ms <= 0L) return if (en) "Awaiting feed" else "Beslenme bekleniyor"
        val diff = ms - System.currentTimeMillis()
        if (diff in 0L until 60_000L) return if (en) "now" else "şimdi"
        val late = diff < 0L
        val dur = durText(Math.abs(diff), en)
        return if (late) {
            if (en) "$dur overdue" else "$dur gecikti"
        } else {
            if (en) "in $dur" else "$dur kaldı"
        }
    }

    private fun durText(millis: Long, en: Boolean): String {
        val totalMin = millis / 60_000L
        val days = totalMin / 1440L
        val hours = (totalMin % 1440L) / 60L
        val mins = totalMin % 60L
        return when {
            days > 0L -> if (en) "${days}d ${hours}h" else "$days gün $hours sa"
            hours > 0L && mins > 0L -> if (en) "${hours}h ${mins}m" else "$hours sa $mins dk"
            hours > 0L -> if (en) "${hours}h" else "$hours sa"
            else -> if (en) "${mins}m" else "$mins dk"
        }
    }
}

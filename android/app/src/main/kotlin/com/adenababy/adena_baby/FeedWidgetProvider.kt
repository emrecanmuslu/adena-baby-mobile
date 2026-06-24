package com.adenababy.adena_baby

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.text.format.DateFormat
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Date

/**
 * Ana ekran widget'ı — "sonraki beslenme". Geri sayım DEĞİL, mutlak SAAT gösterir
 * (ör. "14:30"): değer sabit olduğu için widget'ın sürekli (dakikalık) güncellenmesi
 * gerekmez → iOS'taki donma / Android'deki pil derdi olmaz. Ayrıca "Son besleme HH:MM"
 * (gerçek bilgi) gösterilir. Veriyi Flutter (WidgetService) paylaşımlı depoya yazar.
 * Saat biçimi cihazın 12/24 saat ayarına saygılıdır. Dokununca uygulamayı açar.
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
                // aktif bebek fallback'i (baby_name/next_feed_ms/last_feed_ms).
                val selectedId = widgetData.getString("widget_baby_$widgetId", null)
                val babyName: String
                val nextMs: Long
                val lastMs: Long
                if (selectedId != null && widgetData.contains("name_$selectedId")) {
                    babyName = widgetData.getString("name_$selectedId", null)
                        ?: if (en) "Baby" else "Bebek"
                    nextMs = widgetData.getString("next_$selectedId", null)?.toLongOrNull() ?: -1L
                    lastMs = widgetData.getString("last_$selectedId", null)?.toLongOrNull() ?: -1L
                } else {
                    babyName = widgetData.getString("baby_name", null)
                        ?: if (en) "Baby" else "Bebek"
                    nextMs = widgetData.getString("next_feed_ms", null)?.toLongOrNull() ?: -1L
                    lastMs = widgetData.getString("last_feed_ms", null)?.toLongOrNull() ?: -1L
                }

                val due = nextMs in 1 until System.currentTimeMillis()
                setTextViewText(R.id.widget_baby, babyName)
                setTextViewText(
                    R.id.widget_label,
                    if (nextMs <= 0L) (if (en) "Next feed" else "Sonraki beslenme")
                    else if (due) (if (en) "Feed time" else "Beslenme zamanı")
                    else (if (en) "Next feed" else "Sonraki beslenme")
                )
                setTextViewText(
                    R.id.widget_value,
                    if (nextMs > 0L) timeStr(context, nextMs)
                    else if (en) "Awaiting feed" else "Beslenme bekleniyor"
                )
                setTextViewText(
                    R.id.widget_last,
                    if (lastMs > 0L) {
                        val t = timeStr(context, lastMs)
                        if (en) "Last $t" else "Son besleme $t"
                    } else ""
                )

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

    /** epoch ms → cihaz biçiminde saat (TR 24s "14:30", US 12s "2:30 PM"). */
    private fun timeStr(context: Context, ms: Long): String =
        DateFormat.getTimeFormat(context).format(Date(ms))
}

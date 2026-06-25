package com.adenababy.adena_baby

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.text.format.DateFormat
import android.util.TypedValue
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Date

/**
 * Ana ekran widget'ı — "Büyük Saat" tasarımı. Ortalanmış, dev SAAT gösterir
 * (ör. "14:30"): geri sayım DEĞİL, mutlak saat → değer sabit, sürekli güncelleme
 * gerekmez (iOS donma / Android pil derdi olmaz). Üst satır "Bebek · Sonraki
 * beslenme", alt satır "Son besleme HH:MM". İkon yok.
 *
 * RESPONSIVE: metin boyutları widget'ın O ANKİ boyutuna (getAppWidgetOptions) göre
 * hesaplanır → kare/yatay/dikey her ölçüde alanı doldurur. Yeniden boyutlandırmada
 * [onAppWidgetOptionsChanged] tekrar render eder. Saat biçimi cihazın 12/24 ayarına
 * saygılı. Dokununca uygulamayı açar.
 */
class FeedWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            render(context, appWidgetManager, widgetId, widgetData)
        }
    }

    /** Kullanıcı widget'ı yeniden boyutlandırınca → boyuta göre tekrar render. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        render(context, appWidgetManager, appWidgetId, data)
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.feed_widget)
        val en = widgetData.getString("locale", null) == "en"

        // Bu widget'a seçilmiş bebek (config aktivitesi yazar); yoksa aktif bebek fallback.
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
        val label = when {
            nextMs <= 0L -> if (en) "Next feed" else "Sonraki beslenme"
            due -> if (en) "Feed time" else "Beslenme zamanı"
            else -> if (en) "Next feed" else "Sonraki beslenme"
        }
        // Üst satır: "Defne · Sonraki beslenme"
        views.setTextViewText(R.id.widget_top, "$babyName · $label")
        views.setTextViewText(
            R.id.widget_value,
            if (nextMs > 0L) timeStr(context, nextMs)
            else if (en) "Awaiting feed" else "Beslenme bekleniyor"
        )
        views.setTextViewText(
            R.id.widget_last,
            if (lastMs > 0L) {
                val t = timeStr(context, lastMs)
                if (en) "Last $t" else "Son besleme $t"
            } else ""
        )

        // RESPONSIVE metin boyutları: widget'ın o anki min boyutundan (dp) hesapla.
        applyResponsiveSizes(appWidgetManager, widgetId, views)

        // Dokununca uygulamayı aç.
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        )
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    /** Saat metnini, widget'ın o anki boyutuna oranlayarak büyütür (alanı doldurur). */
    private fun applyResponsiveSizes(
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        views: RemoteViews
    ) {
        val opts = appWidgetManager.getAppWidgetOptions(widgetId)
        // Min boyutlar (dp) — en küçük yönelimi baz al → taşma/kırpılma olmaz.
        val w = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
            .let { if (it <= 0) 180 else it }
        val h = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 70)
            .let { if (it <= 0) 70 else it }
        // Saat: yükseklik ~%42'si; genişlikte "14:30" (~5 glif) sığsın diye w/4.6 ile sınırla.
        val byHeight = h * 0.42f
        val byWidth = w / 4.6f
        val timeSp = minOf(byHeight, byWidth).coerceIn(22f, 80f)
        val subSp = (timeSp * 0.30f).coerceIn(10.5f, 19f)
        views.setTextViewTextSize(R.id.widget_value, TypedValue.COMPLEX_UNIT_SP, timeSp)
        views.setTextViewTextSize(R.id.widget_top, TypedValue.COMPLEX_UNIT_SP, subSp)
        views.setTextViewTextSize(R.id.widget_last, TypedValue.COMPLEX_UNIT_SP, subSp)
    }

    /** epoch ms → cihaz biçiminde saat (TR 24s "14:30", US 12s "2:30 PM"). */
    private fun timeStr(context: Context, ms: Long): String =
        DateFormat.getTimeFormat(context).format(Date(ms))
}

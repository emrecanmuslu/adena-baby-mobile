package com.adenababy.adena_baby

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.os.Bundle
import android.text.format.DateFormat
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.core.content.edit
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Ana ekran widget'ı — "Büyük Saat" tasarımı. Ortalanmış, dev SAAT gösterir
 * (ör. "14:30"): geri sayım DEĞİL, mutlak saat → değer sabit, sürekli güncelleme
 * gerekmez (iOS donma / Android pil derdi olmaz). Üst satır "Bebek · Sonraki
 * beslenme", alt satır "Son besleme HH:MM". İkon yok.
 *
 * Hangi bebeğin gösterileceğini [WidgetLogic.resolve] çözer (bağlı / seçimsiz /
 * bebek bulunamadı / hiç bebek yok). Metinler CİHAZ dilinde değil, uygulamanın
 * yazdığı `locale`'de (res/values-xx) çözülür.
 *
 * RESPONSIVE: metin boyutları widget'ın O ANKİ boyutuna (getAppWidgetOptions) göre
 * hesaplanır → kare/yatay/dikey her ölçüde alanı doldurur. Yeniden boyutlandırmada
 * [onAppWidgetOptionsChanged] tekrar render eder. Saat biçimi cihazın 12/24 ayarına
 * saygılı. Dokununca uygulamayı açar; bebek bulunamadıysa o widget için bebek seçimi.
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

    /** Kaldırılan widget'ın bebek eşlemesi silinir (G10). */
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        applyEdits(context, WidgetLogic.deletedBindings(appWidgetIds))
    }

    /** Yedekten geri yükleme: eşlemeler launcher'ın verdiği yeni id'lere taşınır (M5). */
    override fun onRestored(context: Context, oldWidgetIds: IntArray, newWidgetIds: IntArray) {
        super.onRestored(context, oldWidgetIds, newWidgetIds)
        val prefs = HomeWidgetPlugin.getData(context)
        applyEdits(context, WidgetLogic.restoredBindings(oldWidgetIds, newWidgetIds) { prefs.getString(it, null) })
    }

    private fun applyEdits(context: Context, edits: Map<String, String?>) {
        if (edits.isEmpty()) return
        HomeWidgetPlugin.getData(context).edit {
            for ((k, v) in edits) if (v == null) remove(k) else putString(k, v)
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.feed_widget)
        val res = localized(context, widgetData.getString("locale", null))
        val get: (String) -> String? = { key ->
            try {
                widgetData.getString(key, null)
            } catch (_: ClassCastException) {
                null
            }
        }

        var reselect = false
        val value: String
        when (val v = WidgetLogic.resolve(widgetId, get)) {
            is WidgetView.Baby -> {
                val name = v.name ?: res.getString(R.string.widget_baby_default)
                val label = if (v.nextMs in 1 until System.currentTimeMillis()) {
                    res.getString(R.string.widget_feed_due)
                } else {
                    res.getString(R.string.widget_next_feed)
                }
                // Üst satır: "Defne · Sonraki beslenme"
                views.setTextViewText(R.id.widget_top, "$name · $label")
                val now = System.currentTimeMillis()
                value = if (v.nextMs > 0L) whenStr(res, v.nextMs, now)
                else res.getString(R.string.widget_awaiting)
                views.setTextViewText(
                    R.id.widget_last,
                    if (v.lastMs > 0L) {
                        res.getString(R.string.widget_last_feed, whenStr(res, v.lastMs, now))
                    } else ""
                )
            }
            // K4: eski bebeğin adı/saati ASLA gösterilmez; dokununca yeniden seçim.
            WidgetView.Missing -> {
                views.setTextViewText(R.id.widget_top, "")
                value = res.getString(R.string.widget_baby_missing)
                views.setTextViewText(R.id.widget_last, res.getString(R.string.widget_tap_reselect))
                reselect = true
            }
            WidgetView.NoBabies -> {
                views.setTextViewText(R.id.widget_top, "")
                value = res.getString(R.string.widget_no_babies)
                views.setTextViewText(R.id.widget_last, "")
            }
        }
        views.setTextViewText(R.id.widget_value, value)

        // RESPONSIVE metin boyutları: widget'ın o anki min boyutundan (dp) hesapla.
        applyResponsiveSizes(appWidgetManager, widgetId, views, value.length)

        views.setOnClickPendingIntent(
            R.id.widget_root,
            if (reselect) reselectIntent(context, widgetId)
            else HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        )
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    /** Bu widget için bebek seçim ekranı (yapılandırma aktivitesi, yeniden seçim kipi). */
    private fun reselectIntent(context: Context, widgetId: Int): PendingIntent {
        val intent = Intent(context, FeedWidgetConfigActivity::class.java).apply {
            action = FeedWidgetConfigActivity.ACTION_RESELECT
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(
            context, widgetId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * Ana metni widget'ın o anki boyutuna oranlayarak büyütür (alanı doldurur).
     * [glyphs] = ana metnin uzunluğu: saat (~5) dev, uzun durum metni sığacak kadar.
     */
    private fun applyResponsiveSizes(
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        views: RemoteViews,
        glyphs: Int
    ) {
        val opts = appWidgetManager.getAppWidgetOptions(widgetId)
        // Min boyutlar (dp) — en küçük yönelimi baz al → taşma/kırpılma olmaz.
        val w = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
            .let { if (it <= 0) 180 else it }
        val h = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 70)
            .let { if (it <= 0) 70 else it }
        // Saat: yükseklik ~%42'si; genişlikte metin sığsın diye glif başına ~0.58 em.
        val byHeight = h * 0.42f
        val byWidth = w / maxOf(4.6f, glyphs * 0.58f)
        val timeSp = minOf(byHeight, byWidth).coerceIn(14f, 80f)
        val subSp = (timeSp * 0.30f).coerceIn(10.5f, 19f)
        views.setTextViewTextSize(R.id.widget_value, TypedValue.COMPLEX_UNIT_SP, timeSp)
        views.setTextViewTextSize(R.id.widget_top, TypedValue.COMPLEX_UNIT_SP, subSp)
        views.setTextViewTextSize(R.id.widget_last, TypedValue.COMPLEX_UNIT_SP, subSp)
    }

    /**
     * Saat bugünse yalnız saat; değilse önünde tarih bağlamı (G7):
     * "Dün 23:10", "Yarın 02:00", "12 Ağu 15:13". Canlı sayaç yok.
     */
    private fun whenStr(res: Context, ms: Long, nowMs: Long): String {
        val time = timeStr(res, ms)
        return when (WidgetLogic.dayOffset(ms, nowMs, TimeZone.getDefault())) {
            0 -> time
            -1 -> "${res.getString(R.string.widget_yesterday)} $time"
            1 -> "${res.getString(R.string.widget_tomorrow)} $time"
            else -> {
                val locale = res.resources.configuration.locales[0]
                val pattern = DateFormat.getBestDateTimePattern(locale, "dMMM")
                "${SimpleDateFormat(pattern, locale).format(Date(ms))} $time"
            }
        }
    }

    /** epoch ms → cihaz biçiminde saat (TR 24s "14:30", US 12s "2:30 PM"). */
    private fun timeStr(context: Context, ms: Long): String =
        DateFormat.getTimeFormat(context).format(Date(ms))

    companion object {
        /** Uygulamanın dili (prefs `locale`) için kaynak bağlamı; yoksa cihaz dili. */
        fun localized(context: Context, lang: String?): Context {
            if (lang.isNullOrEmpty()) return context
            val config = Configuration(context.resources.configuration)
            config.setLocale(Locale.forLanguageTag(lang))
            return context.createConfigurationContext(config)
        }
    }
}

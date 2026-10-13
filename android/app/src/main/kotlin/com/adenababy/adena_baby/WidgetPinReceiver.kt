package com.adenababy.adena_baby

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * `requestPinAppWidget` başarı geri çağrısı: launcher widget'ı ana ekrana
 * yerleştirince sistem bu alıcıya `EXTRA_APPWIDGET_ID` ile yayın gönderir.
 *
 * Sabitlenen widget'ta yapılandırma aktivitesi ÇALIŞMAZ → onun tek-bebek yolunda
 * yaptığını burada yaparız: widget'ı aktif bebeğe bağla (`widget_baby_<id>`), yoksa
 * provider yalnız ön planda yazılan yedek anahtarları okur ve arka plan
 * güncellemelerini (FCM/WorkManager) alamaz. Sonra ilk çizimi tetikle ve uygulama
 * açıksa Dart'a "eklendi" bildir.
 */
class WidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        )
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

        val prefs = HomeWidgetPlugin.getData(context)
        val activeId = prefs.getString("active_id", null)
        if (!activeId.isNullOrEmpty()) {
            prefs.edit().putString("widget_baby_$widgetId", activeId).apply()
        }
        context.sendBroadcast(Intent(context, FeedWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
        })
        onPinned?.invoke(widgetId)
    }

    companion object {
        /** MainActivity açıkken Dart kanalına iletir; değilse null (yalnız sabitleme). */
        @Volatile
        var onPinned: ((Int) -> Unit)? = null
    }
}

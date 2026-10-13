package com.adenababy.adena_baby

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.edit
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * `requestPinAppWidget` başarı geri çağrısı: launcher widget'ı ana ekrana
 * yerleştirince sistem bu alıcıya `EXTRA_APPWIDGET_ID` ile yayın gönderir.
 *
 * Sabitlenen widget'ta yapılandırma aktivitesi ÇALIŞMAZ (launcher göstermez) →
 * bebek, istek anında kullanıcının seçtiği ([EXTRA_BABY_ID], K1) olarak buradan
 * bağlanır; ekstra yoksa (bebek yokken yapılan istek) aktif bebek. Bekleyen istek
 * kaydı düşülür, ilk çizim tetiklenir ve uygulama açıksa Dart'a "eklendi" bildirilir.
 * Geri çağrı hiç gelmezse eşlemeyi MainActivity açılışta yapar (K6).
 */
class WidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        )
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

        val prefs = HomeWidgetPlugin.getData(context)
        val babyId = intent.getStringExtra(EXTRA_BABY_ID)
            ?: prefs.getString("active_id", null)?.takeIf { it.isNotEmpty() }
        val seq = intent.getIntExtra(EXTRA_PIN_SEQ, -1)
        val pending = WidgetLogic.parsePending(prefs.getString(MainActivity.PENDING_PINS_KEY, null))
        prefs.edit {
            if (babyId != null) putString(WidgetLogic.bindingKey(widgetId), babyId)
            val rest = WidgetLogic.withoutPin(pending, seq)
            if (rest.isEmpty()) remove(MainActivity.PENDING_PINS_KEY)
            else putString(MainActivity.PENDING_PINS_KEY, WidgetLogic.pendingJson(rest))
        }
        context.sendBroadcast(Intent(context, FeedWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
        })
        onPinned?.invoke(widgetId)
    }

    companion object {
        const val EXTRA_BABY_ID = "com.adenababy.adena_baby.extra.BABY_ID"
        const val EXTRA_PIN_SEQ = "com.adenababy.adena_baby.extra.PIN_SEQ"

        /** MainActivity açıkken Dart kanalına iletir; değilse null (yalnız sabitleme). */
        @Volatile
        var onPinned: ((Int) -> Unit)? = null
    }
}

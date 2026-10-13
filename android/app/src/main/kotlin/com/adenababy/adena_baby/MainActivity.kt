package com.adenababy.adena_baby

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.edit
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val PENDING_PINS_KEY = "pending_pins"
        const val PIN_SEQ_KEY = "pin_seq"
    }

    /// Uygulamanın SİSTEM bildirim ayarları sayfasını açar.
    ///
    /// Gerekçe: Android 13+'ta kullanıcı bildirim iznini bir kez kalıcı olarak
    /// reddettiyse `requestNotificationsPermission()` artık diyalog GÖSTERMEZ —
    /// sessizce hiçbir şey olmaz. Android 12 ve altında ise çalışma-zamanı izni
    /// hiç yoktur; kullanıcı bildirimleri sistem ayarından kapatmışsa tek yol
    /// yine ayar sayfasıdır. Bu kanal o çıkmazı çözer.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "adena/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openNotificationSettings") {
                    result.success(openNotificationSettings())
                } else {
                    result.notImplemented()
                }
            }

        // Uygulama içinden ana ekrana widget ekleme. Bazı launcher'larda (Xiaomi)
        // widget seçicide bulunamıyor; requestPinAppWidget seçiciyi atlar.
        val widgetChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "adena/widget")
        widgetChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPinSupported" -> result.success(isPinSupported())
                "requestPin" -> result.success(requestPin(call.argument<String>("babyId")))
                else -> result.notImplemented()
            }
        }
        WidgetPinReceiver.onPinned = { id ->
            runOnUiThread { widgetChannel.invokeMethod("pinned", id) }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        WidgetPinReceiver.onPinned = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun isPinSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            AppWidgetManager.getInstance(this).isRequestPinAppWidgetSupported

    /**
     * Sistem onay penceresini açar; true = istek launcher'a iletildi (henüz eklenmedi).
     * [babyId] (K1: çoklu bebekte kullanıcının seçtiği, tekte o bebek) geri çağrı
     * intent'ine konur — belge önerisi: "configurations can be encapsulated in
     * successCallback". Geri çağrıya güvenilmez (K6): istekten ÖNCE bekleyen kayıt
     * yazılır, geri çağrı gelmezse açılışta [reconcilePendingPins] eşler.
     */
    private fun requestPin(babyId: String?): Boolean {
        // Sürüm kontrolü burada da açık olmalı: lint (NewApi) yardımcı fonksiyonu izlemez.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isPinSupported()) return false
        val mgr = AppWidgetManager.getInstance(this)
        val provider = ComponentName(this, FeedWidgetProvider::class.java)
        val prefs = HomeWidgetPlugin.getData(this)
        val now = System.currentTimeMillis()
        val seq = prefs.getInt(PIN_SEQ_KEY, 0) + 1
        val maxId = mgr.getAppWidgetIds(provider).maxOrNull() ?: 0
        val before = WidgetLogic.parsePending(prefs.getString(PENDING_PINS_KEY, null))
            .filter { now - it.atMs in 0..WidgetLogic.PENDING_TTL_MS }
        prefs.edit {
            putInt(PIN_SEQ_KEY, seq)
            putString(
                PENDING_PINS_KEY,
                WidgetLogic.pendingJson(before + PendingPin(seq, babyId, now, maxId))
            )
        }
        // Başarı geri çağrısı: sistem EXTRA_APPWIDGET_ID'yi ekler → S+'da MUTABLE şart
        // (intent açık bileşenli, yalnız bizim alıcımıza gider). requestCode = seq:
        // art arda iki istek birbirinin bebeğini EZMESİN (FLAG_UPDATE_CURRENT).
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        val callback = PendingIntent.getBroadcast(
            this, seq,
            Intent(this, WidgetPinReceiver::class.java)
                .putExtra(WidgetPinReceiver.EXTRA_PIN_SEQ, seq)
                .putExtra(WidgetPinReceiver.EXTRA_BABY_ID, babyId),
            flags
        )
        val ok = try {
            mgr.requestPinAppWidget(provider, null, callback)
        } catch (_: Exception) {
            false
        }
        if (!ok) {
            prefs.edit { putString(PENDING_PINS_KEY, WidgetLogic.pendingJson(before)) }
        }
        return ok
    }

    override fun onResume() {
        super.onResume()
        reconcilePendingPins()
    }

    /**
     * K6: launcher pin geri çağrısını göndermediyse, istekten sonra eklenmiş ve
     * bağlanmamış widget'ları bekleyen isteklerin bebeğine bağla (açılış / öne geliş).
     */
    private fun reconcilePendingPins() {
        try {
            val prefs = HomeWidgetPlugin.getData(this)
            val pending = WidgetLogic.parsePending(prefs.getString(PENDING_PINS_KEY, null))
            if (pending.isEmpty()) return
            val ids = AppWidgetManager.getInstance(this)
                .getAppWidgetIds(ComponentName(this, FeedWidgetProvider::class.java))
            val r = WidgetLogic.reconcilePins(
                ids, { prefs.contains(WidgetLogic.bindingKey(it)) },
                pending, System.currentTimeMillis()
            )
            prefs.edit {
                for ((id, baby) in r.bindings) putString(WidgetLogic.bindingKey(id), baby)
                if (r.remaining.isEmpty()) remove(PENDING_PINS_KEY)
                else putString(PENDING_PINS_KEY, WidgetLogic.pendingJson(r.remaining))
            }
            if (r.bindings.isNotEmpty()) {
                sendBroadcast(Intent(this, FeedWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, r.bindings.keys.toIntArray())
                })
            }
        } catch (_: Exception) {
            // Widget eşlemesi açılışı asla düşürmesin.
        }
    }

    private fun openNotificationSettings(): Boolean {
        // Önce doğrudan "uygulama bildirim ayarları" (API 26+). Bazı ROM'larda bu
        // ekran yoksa uygulama detay sayfasına düş — oradan da bildirimlere gidilir.
        val intents = listOf(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            ),
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Sonraki adaya geç.
            }
        }
        return false
    }
}

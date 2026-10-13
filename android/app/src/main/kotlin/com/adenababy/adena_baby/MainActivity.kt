package com.adenababy.adena_baby

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

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
                "requestPin" -> result.success(requestPin())
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

    /** Sistem onay penceresini açar; true = istek launcher'a iletildi (henüz eklenmedi). */
    private fun requestPin(): Boolean {
        // Sürüm kontrolü burada da açık olmalı: lint (NewApi) yardımcı fonksiyonu izlemez.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isPinSupported()) return false
        // Başarı geri çağrısı: sistem EXTRA_APPWIDGET_ID'yi ekler → S+'da MUTABLE şart
        // (intent açık bileşenli, yalnız bizim alıcımıza gider).
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        val callback = PendingIntent.getBroadcast(
            this, 0, Intent(this, WidgetPinReceiver::class.java), flags
        )
        return try {
            AppWidgetManager.getInstance(this).requestPinAppWidget(
                ComponentName(this, FeedWidgetProvider::class.java), null, callback
            )
        } catch (_: Exception) {
            false
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

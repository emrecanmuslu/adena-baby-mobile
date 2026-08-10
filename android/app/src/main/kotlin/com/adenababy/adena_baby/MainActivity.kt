package com.adenababy.adena_baby

import android.content.Intent
import android.net.Uri
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

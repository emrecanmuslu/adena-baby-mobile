package com.adenababy.adena_baby

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * "Sonraki beslenme" widget'ı yapılandırma ekranı — birden çok bebek varsa
 * hangi bebeğin gösterileceğini seçtirir. Seçim `widget_baby_<widgetId>` olarak
 * home_widget paylaşımlı deposuna yazılır; provider bunu okur. Tek bebek/veri
 * yoksa sormadan tamamlar (aktif bebek fallback'i devreye girer).
 */
class FeedWidgetConfigActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Vazgeçilirse (geri tuşu) widget eklenmesin.
        setResult(RESULT_CANCELED)

        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val prefs = HomeWidgetPlugin.getData(this)
        val res = FeedWidgetProvider.localized(this, prefs.getString("locale", null))
        val babies = WidgetLogic.parseBabies(prefs.getString("babies_json", null)).orEmpty()
        val ids = babies.map { it.id }
        val names = babies.map { it.name.ifEmpty { res.getString(R.string.widget_baby_default) } }

        // 0 veya 1 bebek → seçim sormaya gerek yok.
        if (ids.size <= 1) {
            applyAndFinish(ids.firstOrNull())
            return
        }

        val title = TextView(this).apply {
            text = res.getString(R.string.widget_choose_baby)
            textSize = 18f
            setPadding(48, 48, 48, 24)
        }
        val list = ListView(this).apply {
            adapter = ArrayAdapter(
                this@FeedWidgetConfigActivity,
                android.R.layout.simple_list_item_1,
                names
            )
            setOnItemClickListener { _, _, position, _ -> applyAndFinish(ids[position]) }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(title)
            addView(
                list,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
        })
    }

    companion object {
        /** "Bebek bulunamadı" widget'ına dokunma → o widget için yeniden seçim (K4). */
        const val ACTION_RESELECT = "com.adenababy.adena_baby.action.WIDGET_RESELECT"
    }

    private fun applyAndFinish(babyId: String?) {
        if (babyId != null) {
            HomeWidgetPlugin.getData(this).edit()
                .putString("widget_baby_$widgetId", babyId).apply()
        }
        // Widget'ı hemen çiz: provider'a güncelleme yayını gönder (onUpdate prefs'i okur).
        sendBroadcast(Intent(this, FeedWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
        })
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        )
        finish()
    }
}

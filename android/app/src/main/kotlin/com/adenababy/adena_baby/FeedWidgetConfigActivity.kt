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
import org.json.JSONArray

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
        val en = prefs.getString("locale", null) == "en"

        val ids = ArrayList<String>()
        val names = ArrayList<String>()
        prefs.getString("babies_json", null)?.let { json ->
            try {
                val arr = JSONArray(json)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    ids.add(o.getString("id"))
                    names.add(o.optString("name", if (en) "Baby" else "Bebek"))
                }
            } catch (_: Exception) {
            }
        }

        // 0 veya 1 bebek → seçim sormaya gerek yok.
        if (ids.size <= 1) {
            applyAndFinish(ids.firstOrNull())
            return
        }

        val title = TextView(this).apply {
            text = if (en) "Choose baby" else "Bebeği seç"
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

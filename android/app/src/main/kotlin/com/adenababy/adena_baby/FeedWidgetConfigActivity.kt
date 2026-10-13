package com.adenababy.adena_baby

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import androidx.core.content.edit
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * "Sonraki beslenme" widget'ı için bebek seçimi. Üç yoldan açılır:
 * - launcher widget'ı seçiciden eklerken (ilk yapılandırma),
 * - launcher "widget ayarları" ile yeniden yapılandırırken (`reconfigurable`, K2),
 * - "Bebek bulunamadı" widget'ına dokununca ([ACTION_RESELECT], K4).
 *
 * Seçim `widget_baby_<widgetId>` olarak home_widget paylaşımlı deposuna yazılır;
 * provider bunu okur. Tek bebekte sormadan bağlar; liste boşsa bilgi verir.
 * Yeniden seçimde mevcut bebek işaretli gelir.
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
        val babies = WidgetLogic.parseBabies(prefs.getString("babies_json", null))
        val current = prefs.getString(WidgetLogic.bindingKey(widgetId), null)

        when (val plan = WidgetLogic.configPlan(babies, current)) {
            is ConfigPlan.Auto -> applyAndFinish(plan.babyId)
            // G14: uygulama hiç açılmadan / bebek yokken eklenen widget sessizce
            // seçimsiz kalmasın — önce uygulamayı açıp bebek eklemesi söylenir.
            ConfigPlan.Empty -> showEmpty(
                res.getString(R.string.widget_no_babies),
                res.getString(R.string.widget_ok)
            )
            is ConfigPlan.Choose -> showList(
                res.getString(R.string.widget_choose_baby),
                babies.orEmpty(),
                res.getString(R.string.widget_baby_default),
                plan.checked
            )
        }
    }

    private fun showList(
        titleText: String,
        babies: List<WidgetBabyRef>,
        defaultName: String,
        checked: Int
    ) {
        val title = TextView(this).apply {
            text = titleText
            textSize = 18f
            setPadding(48, 48, 48, 24)
        }
        val list = ListView(this).apply {
            choiceMode = ListView.CHOICE_MODE_SINGLE
            adapter = ArrayAdapter(
                this@FeedWidgetConfigActivity,
                android.R.layout.simple_list_item_single_choice,
                babies.map { it.name.ifEmpty { defaultName } }
            )
            if (checked >= 0) setItemChecked(checked, true)
            setOnItemClickListener { _, _, position, _ -> applyAndFinish(babies[position].id) }
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

    private fun showEmpty(message: String, ok: String) {
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 48, 48, 24)
            addView(TextView(this@FeedWidgetConfigActivity).apply {
                text = message
                textSize = 16f
            })
            addView(Button(this@FeedWidgetConfigActivity).apply {
                text = ok
                // RESULT_CANCELED kalır: ilk eklemede widget eklenmez.
                setOnClickListener { finish() }
            })
        })
    }

    companion object {
        /** "Bebek bulunamadı" widget'ına dokunma → o widget için yeniden seçim (K4). */
        const val ACTION_RESELECT = "com.adenababy.adena_baby.action.WIDGET_RESELECT"
    }

    private fun applyAndFinish(babyId: String) {
        HomeWidgetPlugin.getData(this).edit {
            putString(WidgetLogic.bindingKey(widgetId), babyId)
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

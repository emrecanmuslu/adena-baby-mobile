package com.adenababy.adena_baby

import org.json.JSONArray

/** `babies_json`'daki bir bebek (yalnız doğmuş bebekler; Dart `publishAll` yazar). */
data class WidgetBabyRef(val id: String, val name: String)

/** Bir widget örneğinin çizeceği durum. */
sealed class WidgetView {
    /** [name] null → varsayılan "Bebek" metni. [bound] = widget bu bebeğe bağlı mı. */
    data class Baby(
        val babyId: String?,
        val name: String?,
        val nextMs: Long,
        val lastMs: Long,
        val bound: Boolean,
    ) : WidgetView()

    /** Bağlı bebek artık listede yok (silindi, aileden çıkarıldı, gebelik, hesap değişti). */
    object Missing : WidgetView()

    /** Hiç (doğmuş) bebek yok ya da oturum kapalı. */
    object NoBabies : WidgetView()
}

/** Yapılandırma ekranının ne yapacağı. */
sealed class ConfigPlan {
    /** Hiç bebek yok → "Önce uygulamayı açıp bebek ekleyin" bilgisi (G14). */
    object Empty : ConfigPlan()

    /** Tek bebek → sormadan ona bağla. */
    data class Auto(val babyId: String) : ConfigPlan()

    /** Liste göster; [checked] = mevcut seçimin sırası (yoksa -1). */
    data class Choose(val checked: Int) : ConfigPlan()
}

/**
 * Widget'ın hangi bebeği göstereceğini paylaşımlı depodan (home_widget prefs) çözer.
 * Android bağımlılığı yok → JVM birim testleriyle doğrulanır.
 *
 * Kurallar (WIDGET-COKLU-BEBEK K3/K4):
 * - Bağlı widget (`widget_baby_<id>`) yalnız kendi bebeğini gösterir; bebek
 *   `babies_json`'da yoksa [WidgetView.Missing] — eski ad/saat ASLA gösterilmez.
 * - Seçimsiz widget aktif bebeği izler ve onun BEBEK-BAŞI anahtarlarını okur;
 *   bu anahtarları arka plan yolları (FCM, WorkManager) da yazdığı için uygulama
 *   kapalıyken de güncellenir (G4). Yedek anahtarlar yalnız `babies_json` hiç
 *   yazılmamış eski kurulumlar içindir.
 */
object WidgetLogic {
    fun bindingKey(widgetId: Int) = "widget_baby_$widgetId"

    /** null = liste hiç yazılmamış ya da okunamadı. */
    fun parseBabies(json: String?): List<WidgetBabyRef>? {
        if (json == null) return null
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                WidgetBabyRef(o.getString("id"), o.optString("name", ""))
            }
        } catch (_: Exception) {
            null
        }
    }

    fun resolve(widgetId: Int, get: (String) -> String?): WidgetView {
        val babies = parseBabies(get("babies_json"))
        val bound = get(bindingKey(widgetId))?.takeIf { it.isNotEmpty() }

        if (bound != null) {
            if (babies != null) {
                val ref = babies.firstOrNull { it.id == bound } ?: return WidgetView.Missing
                return perBaby(bound, ref.name, get, bound = true)
            }
            // Eski kurulum: liste yok → yalnız bebek-başı anahtar varsa göster.
            if (get("name_$bound") == null) return WidgetView.Missing
            return perBaby(bound, null, get, bound = true)
        }

        if (babies != null) {
            if (babies.isEmpty()) return WidgetView.NoBabies
            val active = get("active_id")
            val ref = babies.firstOrNull { it.id == active } ?: babies.first()
            return perBaby(ref.id, ref.name, get, bound = false)
        }

        return WidgetView.Baby(
            babyId = null,
            name = get("baby_name"),
            nextMs = ms(get("next_feed_ms")),
            lastMs = ms(get("last_feed_ms")),
            bound = false,
        )
    }

    /** Yapılandırma / yeniden yapılandırma / yeniden seçim ekranının planı. */
    fun configPlan(babies: List<WidgetBabyRef>?, current: String?): ConfigPlan = when {
        babies.isNullOrEmpty() -> ConfigPlan.Empty
        babies.size == 1 -> ConfigPlan.Auto(babies.first().id)
        else -> ConfigPlan.Choose(babies.indexOfFirst { it.id == current })
    }

    /** Kaldırılan widget'ların eşlemeleri (anahtar → null = sil). G10. */
    fun deletedBindings(widgetIds: IntArray): Map<String, String?> =
        widgetIds.associate { bindingKey(it) to null }

    /**
     * Yedekten geri yükleme / telefon taşıma: launcher widget'lara YENİ id verir
     * (`onRestored(old, new)`, dizinler eşleşik). Eşlemeler yeni id'lere taşınır;
     * yeni kümede olmayan eski anahtarlar silinir (anahtar → null). M5.
     */
    fun restoredBindings(
        oldIds: IntArray,
        newIds: IntArray,
        get: (String) -> String?,
    ): Map<String, String?> {
        val edits = LinkedHashMap<String, String?>()
        val newSet = newIds.toSet()
        for (old in oldIds) if (old !in newSet) edits[bindingKey(old)] = null
        for (i in 0 until minOf(oldIds.size, newIds.size)) {
            val baby = get(bindingKey(oldIds[i])) ?: continue
            edits[bindingKey(newIds[i])] = baby
        }
        return edits
    }

    private fun perBaby(id: String, listName: String?, get: (String) -> String?, bound: Boolean) =
        WidgetView.Baby(
            babyId = id,
            name = listName?.takeIf { it.isNotEmpty() } ?: get("name_$id"),
            nextMs = ms(get("next_$id")),
            lastMs = ms(get("last_$id")),
            bound = bound,
        )

    private fun ms(s: String?): Long = s?.toLongOrNull() ?: -1L
}

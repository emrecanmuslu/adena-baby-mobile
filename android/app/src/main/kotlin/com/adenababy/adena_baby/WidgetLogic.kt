package com.adenababy.adena_baby

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

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

/**
 * Uygulama içinden yapılan, launcher'ın henüz geri çağırmadığı widget sabitleme
 * isteği. [maxId] = istek anındaki en büyük widget id'si (yalnız ondan büyük
 * yeni id'ler bu isteğe ait olabilir).
 */
data class PendingPin(val seq: Int, val babyId: String?, val atMs: Long, val maxId: Int)

data class PinReconcile(val bindings: Map<Int, String>, val remaining: List<PendingPin>)

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

    const val PENDING_TTL_MS = 24 * 3_600_000L

    fun parsePending(json: String?): List<PendingPin> {
        if (json == null) return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                PendingPin(
                    seq = o.getInt("seq"),
                    babyId = if (o.isNull("baby")) null else o.getString("baby"),
                    atMs = o.getLong("at"),
                    maxId = o.getInt("max"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun pendingJson(list: List<PendingPin>): String = JSONArray().apply {
        for (p in list) put(JSONObject().apply {
            put("seq", p.seq)
            put("baby", p.babyId ?: JSONObject.NULL)
            put("at", p.atMs)
            put("max", p.maxId)
        })
    }.toString()

    /** Geri çağrı geldi → o istek artık bekleyen değil. */
    fun withoutPin(pending: List<PendingPin>, seq: Int) = pending.filter { it.seq != seq }

    /**
     * Pin geri çağrısı GELMEMİŞ olabilir (bazı launcher'lar; K6). Açılışta/öne
     * gelişte: istek anından sonra eklenmiş (id > maxId) ve henüz bağlanmamış widget'lar
     * bekleyen isteklerle SIRAYLA eşlenir. Sayılar tutmazsa (iptal edilen istek, araya
     * seçiciden eklenen widget) yanlış bebeğe bağlamamak için eşleme yapılmaz — o
     * widget'lar seçimsiz kalır ve aktif bebeği izler (K3). 24 saatten eski istekler düşer.
     */
    fun reconcilePins(
        widgetIds: IntArray,
        isBound: (Int) -> Boolean,
        pending: List<PendingPin>,
        nowMs: Long,
        ttlMs: Long = PENDING_TTL_MS,
    ): PinReconcile {
        val fresh = pending.filter { nowMs - it.atMs in 0..ttlMs }.sortedBy { it.seq }
        if (fresh.isEmpty()) return PinReconcile(emptyMap(), emptyList())
        val floor = fresh.minOf { it.maxId }
        val candidates = widgetIds.filter { it > floor && !isBound(it) }.sorted()
        if (candidates.size != fresh.size) return PinReconcile(emptyMap(), fresh)
        val bindings = LinkedHashMap<Int, String>()
        for ((id, p) in candidates.zip(fresh)) {
            if (id <= p.maxId) return PinReconcile(emptyMap(), fresh)
            if (p.babyId != null) bindings[id] = p.babyId
        }
        return PinReconcile(bindings, emptyList())
    }

    /**
     * [ms] ile [nowMs] arasındaki TAKVİM günü farkı ([tz] saat diliminde):
     * 0 bugün, -1 dün, 1 yarın, -62 iki ay önce. Widget saati bugün değilse önüne
     * tarih bağlamı koyar (G7: dünkü saat bugünkü gibi görünmesin).
     */
    fun dayOffset(ms: Long, nowMs: Long, tz: TimeZone): Int {
        fun dayNumber(t: Long): Long {
            val c = Calendar.getInstance(tz).apply { timeInMillis = t }
            // Yerel tarihin epoch gün sayısı (yaz saati kaymalarından bağımsız).
            return Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear()
                set(c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis / 86_400_000L
        }
        return (dayNumber(ms) - dayNumber(nowMs)).toInt()
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

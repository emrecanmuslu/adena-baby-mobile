package com.adenababy.adena_baby

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Widget'ın hangi bebeği / hangi durumu çizeceği (WIDGET-COKLU-BEBEK A3, A4). */
class WidgetLogicTest {
    private val babies = """[{"id":"a","name":"Ada"},{"id":"b","name":"Bora"}]"""

    private fun prefs(vararg kv: Pair<String, String>): (String) -> String? {
        val m = mapOf(*kv)
        return { m[it] }
    }

    private val perBaby = arrayOf(
        "name_a" to "Ada", "next_a" to "1000", "last_a" to "900",
        "name_b" to "Bora", "next_b" to "2000", "last_b" to "1900",
        // Eski yedek anahtarlar BAYAT — seçimsiz widget artık bunları okumamalı (G4).
        "baby_name" to "Eski", "next_feed_ms" to "1", "last_feed_ms" to "1",
    )

    @Test
    fun `seçimsiz widget aktif bebeğin bebek-başı anahtarlarını okur`() {
        val v = WidgetLogic.resolve(7, prefs("babies_json" to babies, "active_id" to "b", *perBaby))
        assertEquals(WidgetView.Baby("b", "Bora", 2000L, 1900L, bound = false), v)
    }

    @Test
    fun `bağlı widget aktif bebekten bağımsız kendi bebeğini gösterir`() {
        val v = WidgetLogic.resolve(
            7, prefs("babies_json" to babies, "active_id" to "b", "widget_baby_7" to "a", *perBaby)
        )
        assertEquals(WidgetView.Baby("a", "Ada", 1000L, 900L, bound = true), v)
    }

    @Test
    fun `bağlı bebek listede yoksa Missing — eski ad ve saat gösterilmez`() {
        val v = WidgetLogic.resolve(
            7,
            prefs(
                "babies_json" to babies, "widget_baby_7" to "c",
                "name_c" to "Silinen", "next_c" to "5", "last_c" to "4", *perBaby
            )
        )
        assertEquals(WidgetView.Missing, v)
    }

    @Test
    fun `liste boşken bağlı widget Missing, seçimsiz widget NoBabies`() {
        val p = prefs("babies_json" to "[]", "widget_baby_7" to "a", *perBaby)
        assertEquals(WidgetView.Missing, WidgetLogic.resolve(7, p))
        assertEquals(WidgetView.NoBabies, WidgetLogic.resolve(8, p))
    }

    @Test
    fun `aktif bebek listede değilse seçimsiz widget ilk bebeğe düşer`() {
        val v = WidgetLogic.resolve(7, prefs("babies_json" to babies, "active_id" to "x", *perBaby))
        assertEquals(WidgetView.Baby("a", "Ada", 1000L, 900L, bound = false), v)
    }

    @Test
    fun `babies_json hiç yoksa (eski kurulum) yedek anahtarlar okunur`() {
        val v = WidgetLogic.resolve(7, prefs("baby_name" to "Eski", "next_feed_ms" to "3", "last_feed_ms" to "2"))
        assertEquals(WidgetView.Baby(null, "Eski", 3L, 2L, bound = false), v)
    }

    @Test
    fun `babies_json yokken bağlı widget bebek-başı anahtarı varsa onu gösterir`() {
        val v = WidgetLogic.resolve(7, prefs("widget_baby_7" to "a", "name_a" to "Ada", "next_a" to "10"))
        assertEquals(WidgetView.Baby("a", "Ada", 10L, -1L, bound = true), v)
    }

    @Test
    fun `bozuk babies_json yok sayılır`() {
        assertNull(WidgetLogic.parseBabies("{bozuk"))
        assertTrue(WidgetLogic.parseBabies("[]")!!.isEmpty())
        assertEquals(listOf(WidgetBabyRef("a", "Ada"), WidgetBabyRef("b", "Bora")), WidgetLogic.parseBabies(babies))
    }

    @Test
    fun `widget kaldırılınca eşlemesi silinir (G10)`() {
        val edits = WidgetLogic.deletedBindings(intArrayOf(3, 9))
        assertEquals(mapOf("widget_baby_3" to null, "widget_baby_9" to null), edits)
    }

    @Test
    fun `yedekten geri yüklemede eşlemeler yeni widget id'lerine taşınır (M5)`() {
        val edits = WidgetLogic.restoredBindings(
            intArrayOf(3, 4, 5), intArrayOf(7, 3, 8),
            prefs("widget_baby_3" to "a", "widget_baby_4" to "b")
        )
        // 3→7 (a), 4→3 (b; eski 3'ün üstüne yazılır, silinmez), 5 eşlemesizdi → 8'e bir şey yazılmaz.
        assertEquals(
            mapOf("widget_baby_4" to null, "widget_baby_5" to null, "widget_baby_7" to "a", "widget_baby_3" to "b"),
            edits
        )
    }

    @Test
    fun `yapılandırma planı - boş liste bilgi, tek bebek otomatik, çoklu bebekte mevcut seçim işaretli`() {
        assertEquals(ConfigPlan.Empty, WidgetLogic.configPlan(null, null))
        assertEquals(ConfigPlan.Empty, WidgetLogic.configPlan(emptyList(), "a"))
        val one = listOf(WidgetBabyRef("a", "Ada"))
        assertEquals(ConfigPlan.Auto("a"), WidgetLogic.configPlan(one, null))
        val two = WidgetLogic.parseBabies(babies)
        assertEquals(ConfigPlan.Choose(checked = 1), WidgetLogic.configPlan(two, "b"))
        assertEquals(ConfigPlan.Choose(checked = -1), WidgetLogic.configPlan(two, "silinen"))
        assertEquals(ConfigPlan.Choose(checked = -1), WidgetLogic.configPlan(two, null))
    }

    // ── A1 / K6: pin geri çağrısına güvenme — açılışta bekleyen pin eşlemesi ──
    private val hour = 3_600_000L
    private val now = 100 * hour

    @Test
    fun `geri çağrı gelmedi - açılışta yeni eşlenmemiş widget bekleyen pinin bebeğine bağlanır`() {
        val pending = listOf(PendingPin(seq = 1, babyId = "b", atMs = now - hour, maxId = 4))
        val r = WidgetLogic.reconcilePins(intArrayOf(2, 4, 5), { it == 2 }, pending, now)
        assertEquals(mapOf(5 to "b"), r.bindings)
        assertTrue(r.remaining.isEmpty())
    }

    @Test
    fun `iki ardışık pin geri çağrısız - sırayla eşlenir`() {
        val pending = listOf(
            PendingPin(seq = 2, babyId = "b", atMs = now - 10, maxId = 5),
            PendingPin(seq = 1, babyId = "a", atMs = now - 20, maxId = 5),
        )
        val r = WidgetLogic.reconcilePins(intArrayOf(5, 7, 6), { false }, pending, now)
        assertEquals(mapOf(6 to "a", 7 to "b"), r.bindings)
        assertTrue(r.remaining.isEmpty())
    }

    @Test
    fun `eski (istekten önceki) seçimsiz widget eşlenmez`() {
        val pending = listOf(PendingPin(seq = 1, babyId = "b", atMs = now - 10, maxId = 9))
        val r = WidgetLogic.reconcilePins(intArrayOf(3, 9), { false }, pending, now)
        assertTrue(r.bindings.isEmpty())
        assertEquals(pending, r.remaining) // launcher henüz eklemediyse sonraki açılışa kalır
    }

    @Test
    fun `belirsizlikte (bekleyen ile yeni widget sayısı farklı) eşleme yapılmaz`() {
        val pending = listOf(
            PendingPin(seq = 1, babyId = "a", atMs = now - 20, maxId = 5),
            PendingPin(seq = 2, babyId = "b", atMs = now - 10, maxId = 5),
        )
        val r = WidgetLogic.reconcilePins(intArrayOf(6), { false }, pending, now)
        assertTrue(r.bindings.isEmpty())
        assertEquals(2, r.remaining.size)
    }

    @Test
    fun `24 saati geçen bekleyen pin silinir`() {
        val pending = listOf(PendingPin(seq = 1, babyId = "a", atMs = now - 25 * hour, maxId = 1))
        val r = WidgetLogic.reconcilePins(intArrayOf(2), { false }, pending, now)
        assertTrue(r.bindings.isEmpty())
        assertTrue(r.remaining.isEmpty())
    }

    @Test
    fun `geri çağrı gelince bekleyen kayıt sırasıyla düşer ve json gidiş-dönüş`() {
        val pending = listOf(
            PendingPin(1, "a", 10L, 3),
            PendingPin(2, null, 20L, 3),
        )
        assertEquals(listOf(PendingPin(2, null, 20L, 3)), WidgetLogic.withoutPin(pending, 1))
        assertEquals(pending, WidgetLogic.parsePending(WidgetLogic.pendingJson(pending)))
        assertTrue(WidgetLogic.parsePending("bozuk").isEmpty())
        assertTrue(WidgetLogic.parsePending(null).isEmpty())
    }

    // ── A7 (G7): saat bugün değilse tarih bağlamı ──
    @Test
    fun `takvim günü farkı - bugün dün yarın ve günler önce`() {
        val tz = java.util.TimeZone.getTimeZone("Europe/Istanbul")
        fun at(y: Int, m: Int, d: Int, h: Int, min: Int): Long =
            java.util.Calendar.getInstance(tz).apply {
                clear(); set(y, m - 1, d, h, min)
            }.timeInMillis
        val now = at(2026, 10, 13, 0, 30)
        assertEquals(0, WidgetLogic.dayOffset(at(2026, 10, 13, 0, 5), now, tz))
        assertEquals(-1, WidgetLogic.dayOffset(at(2026, 10, 12, 23, 10), now, tz))
        assertEquals(1, WidgetLogic.dayOffset(at(2026, 10, 14, 2, 0), now, tz))
        assertEquals(-62, WidgetLogic.dayOffset(at(2026, 8, 12, 15, 13), now, tz))
        assertEquals(-1, WidgetLogic.dayOffset(at(2025, 12, 31, 22, 0), at(2026, 1, 1, 8, 0), tz))
    }
}

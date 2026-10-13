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
}

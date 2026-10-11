# KARAR-BEKLEYEN — fix/audit-bulgular

**Düzeltme turu 1 (2026-10-11) kararları:** KB-1, KB-2, KB-3, KB-6, KB-7 → KARARLAŞTI: varsayılan. KB-4 → UYGULANDI (`689c58d`). KB-5 → (b) sıfırla, UYGULANDI (`5245b65`). KB-8 → (a), UYGULANDI (`5d2c5a0`). KB-9 → (a), UYGULANDI (`cfd9daa`).

Ürün/UX kararı gerektiren ya da birden fazla makul çözümü olan maddeler. Güvenli varsayılan uygulandıysa belirtildi.

## KB-1 — "Geri al": sunucuda olmayan SAHİP bebek
- **KARARLAŞTI: varsayılan**
- **Soru:** Profil push'u kalıcı reddedilmiş ve sunucuda hiç olmayan (yerelde oluşturulmuş) sahip bebekte "değişikliği geri al" bebeği ve tüm çocuk verisini (kayıt/anı/anne/sağlık) yerelden silmeli mi?
- **Seçenekler:** (a) onay diyaloğuyla sil — kullanıcı kararının bedeli tüm bebek verisi, geri alınamaz; (b) silme; bayraklar temizlenir, bebek yalnız bu cihazda kalır (kullanıcı isterse bebeği normal yoldan siler); (c) "Düzenle" akışına yönlendir (ör. ad geçersiz → düzelt → yeniden gönder).
- **Uygulanan varsayılan:** (b) — `BabyRepository.keepLocalOnly`, sheet "Bu kayıt yalnız bu cihazda kalacak" der. Tombstone (bekleyen silme) + sunucuda yok → onayla yerel satır + çocuk verisi kaldırılır (zaten silinmek isteniyordu).
- **Etkilenen:** `lib/data/push_error_repository.dart`, `lib/features/settings/push_error_sheet.dart`, `lib/data/baby_repository.dart` — commit `3c7d94c`.

## KB-2 — "Geri al" uygulanamayan tablolar
- **KARARLAŞTI: varsayılan**
- **Soru:** Records (`POST /sync` batch) ve ilaç planları (yanıt otoriter) için kalem bazlı "geri al" gerekli mi?
- **Seçenekler:** (a) O9 batch sınırıyla birlikte records'a `pushError` eklemek (ayrı şema); (b) mevcut davranış (records çakışması sunucuda çözülür, ilaç planı yanıtı otoriter → kalıcı red kavramı yok).
- **Uygulanan varsayılan:** (b) — kapsam dışı, banner sayacına girmez.
- **Etkilenen:** TASARIM §6b.

## KB-3 — "Tümünü geri al" ve sunucuda olmayan satırlar
- **KARARLAŞTI: varsayılan**
- **Soru:** Toplu geri almada sunucuda olmayan satırlar sessizce silinmeli mi?
- **Uygulanan varsayılan:** Hayır — yalnız sunucuda olanlar uygulanır, kalanlar listede kalır ve tek tek onay ister.
- **Etkilenen:** `push_error_sheet.dart` `_all`.

## KB-4 — Kesin alarm (exact alarm) izni için UI girişi (O16)
- **KARARLAŞTI: UYGULANDI — diyalog (ilk ilaç planı / beslenme hatırlatıcısı ilk açılış) + Bildirimler satırı, yalnız Android (`689c58d`)**
- **Soru:** Android 14+'ta kesin alarm izni artık otomatik istenmiyor (izin yoksa ±dakika gecikmeli inexact). Kullanıcıya nerede/nasıl açıklanıp istenmeli?
- **Seçenekler:** (a) Bildirimler ayar ekranına "Tam dakikasında bildirim" satırı + açıklama → `NotificationService.requestExactAlarmPermission()`; (b) beslenme hatırlatıcısı ilk kez açılırken tek seferlik açıklama diyaloğu; (c) hiç istememek (inexact yeterli).
- **Uygulanan varsayılan:** otomatik istek kaldırıldı; `requestExactAlarmPermission()/canScheduleExact()` hazır, UI bağlanmadı (c gibi davranır).
- **Etkilenen:** `lib/core/notification_service.dart` — `82d3db2`.

## KB-5 — Gebelikten "Adet takibine dön"de çapa (O23)
- **KARARLAŞTI: (b) sıfırla — UYGULANDI (`5245b65`); K6 ile çelişmez (açık mod geçişi)**
- **Soru:** Bekleyen bebek kaldırılırken `first_period_date` (eski LMP çapası) korunmalı mı sıfırlanmalı mı?
- **Seçenekler:** (a) korumak — yanlış-alarm senaryosu: kullanıcı yeni adetini loglayınca çapa taşınır, ama o ana dek "N gün gecikti" görünür; (b) sıfırlamak — adet ekranı bekleme moduna döner, kullanıcı ilk adetini girer (kayıp akışıyla aynı).
- **Uygulanan varsayılan:** (a) korundu.
- **Etkilenen:** `lib/features/cycle/cycle_loss.dart` — `ce4e912`.

## KB-6 — DST gün aritmetiği kapsamı (O29)
- **KARARLAŞTI: varsayılan (b)**
- **Soru:** Adet motoru + LMP→TDT dışındaki ~20 nokta (akış "‹", 7-gün grafik anahtarı, dün özeti, düzeltilmiş yaş/atak/gebelik haftası, takvim adjust sheet, notification_sync) `cycleAddDays`/UTC-gün yardımcılarına taşınsın mı?
- **Seçenekler:** (a) toplu mekanik değişim (15 dosya; görsel/istatistik sonuçları değişebilir, DST ortamında doğrulanamıyor); (b) yalnız veri yazan noktalar (yapıldı: TDT) + görünür hesaplar kalsın (TR pazarı DST yok).
- **Uygulanan varsayılan:** (b).
- **Etkilenen:** `cycle_engine.dart`, `cycle_pregnancy_bridge.dart` — `1b2696d`.

## KB-7 — Aşı anahtarı dil bağımlılığı (O19)
- **KARARLAŞTI: varsayılan (a)**
- **Soru:** Backend #3 (dil-bağımsız `key`) gelene dek istemcide bir şey yapılmalı mı?
- **Seçenekler:** (a) beklemek (K4 yankı güvencesiyle tik kaybolmuyor, yalnız farklı dilde paylaşılmıyor); (b) 5 ek dilde kataloğu EN'e düşürmek (mevcut TR-adlı işaretler görünmez olur — veri kaybı görünümü).
- **Uygulanan varsayılan:** (a).
- **Etkilenen:** —

## KB-8 — Bakıcı (caregiver) ilaç planı ekleyebilmeli mi? (D30)
- **KARARLAŞTI: (a) — UYGULANDI (`5d2c5a0`)**
- **Soru:** UI bakıcıya plan ekletiyor ama senkron bakıcı değişikliğini göndermiyor (backend `can_full_write`) → cihazda hayalet plan.
- **Seçenekler:** (a) K-7 gibi repo `StateError` + UI kilidi (bakıcı yalnız doz işaretler); (b) backend'de bakıcıya plan yazma izni; (c) mevcut (yalnız bu cihazda kalan plan, not metni düzeltildi).
- **Uygulanan varsayılan:** (c) + not metni güncellendi (`fix(D30)`).
- **Etkilenen:** `lib/features/health/medications_screen.dart`, `health_repository.dart`.

## KB-9 — Hesap silme sonrası yerel veri ve fotoğraflar (D43)
- **KARARLAŞTI: (a) — UYGULANDI (`cfd9daa`)**
- **Soru:** Hesap silince drift'teki hesap verisi ve foto dosyaları cihazda kalıyor; metin "verileriniz silinecek" diyor. 30 gün geri alma için bilinçli mi?
- **Seçenekler:** (a) hesap silmede yerel kapsamı da sil (O33'teki wipe yolu ile); (b) korumak ve metni "sunucudaki verileriniz silinecek; cihazdakiler için Yerel verileri sil" diye düzeltmek; (c) 30 gün sonra otomatik temizlik.
- **Uygulanan varsayılan:** atlandı (kod değişmedi).
- **Etkilenen:** `auth_controller.deleteAccount`, `privacy_screen.dart`.

## KB-6 ek — DST'de gerçekten 1 gün kayabilecek görünür hesaplar (yayın sonrası iş, M6 tespiti)
Yalnız DST uygulayan bölgelerde (TR'de yok); yerel gece-yarısı + `Duration(days:)` ya da `.inDays` deseni. Hepsi `cycleAddDays`/UTC-gün yardımcısına taşınmalı:
- `lib/features/records/timeline_view.dart:43-46` — akışta "‹/›" gün geçişi (bir gün atlanabilir).
- `lib/features/charts/charts_view.dart:782-784, 816-820` — 7-gün grafik anahtarı (o günün kayıtları düşer).
- `lib/features/charts/growth_report.dart:132-142` — 7-gün trend.
- `lib/features/home/home_screen.dart:132-135, 1738-1741` ve `yesterday_recap_sheet.dart:44-46`, `lib/core/yesterday_recap.dart:255, 264` — dün özeti yanlış güne.
- `lib/features/records/record_ui.dart:106-115` — gün etiketi.
- `lib/core/leaps.dart:14, 17, 50` ve `lib/core/age.dart:32, 113, 132, 169, 188` — düzeltilmiş yaş / atak haftası / gebelik haftası 1 kayar.
- `lib/features/babies/notification_sync.dart:314, 360` — atak/büyüme hatırlatıcı tarihi.
- `lib/features/cycle/cycle_calendar_screen.dart:429, 436, 1062`, `cycle_period_adjust_sheet.dart:134-165` — takvim gün hücresi/`_marked.contains` eşleşmesi.
Düzeltilenler (`1b2696d`): `cycle_engine._diffDays`, `pregnancyFromLmp` (TDT — veri yazan tek nokta). Doğrulama ortamı: bu makinede (Windows) `TZ` ortam değişkeni Dart VM'de yok sayılıyor (sistem saat dilimi kullanılıyor) → CI/Linux/macOS'ta `TZ=Europe/Berlin flutter test test/engines test/journeys test/data/cycle_repository_k6_test.dart` ve `TZ=America/New_York …` koşulmalı.

## KB-10 — Bakıcı cihazındaki yerel-only ilaç planları (KB-8 öncesi oluşmuş)
- **Tanım:** bakıcı rolündeki bebekte `medication_plans.dirty = true` satırlar — bakıcıda push yok, pull sunucudakileri `dirty=false` yazar → dirty olan tek şey sunucuya hiç gitmemiş yerel plandır. Senkron bunları silmiyor (sunucuda olmayan dirty satıra dokunmuyor), hatırlatıcıları çalışıyor; KB-8 sonrası bakıcı silemiyordu.
- **Soru:** Silinsin mi, taşınsın mı (ebeveyn onaylasın), kalsın mı?
- **Seçenekler:** (a) sessiz silme — veri kaybı; (b) kalsın + "yalnız bu cihazda" notu + bakıcı silebilsin; (c) ebeveyne "bu planı paylaşıma al" akışı (backend yazma izni gerekir).
- **Uygulanan varsayılan:** (b) — `MedicationPlan.localOnly`, kart notu + Sil; düzenleme kapalı (`e77a23d`). KARARLAŞTI: varsayılan uygulandı.
- **Etkilenen:** `health_repository.dart` (`medicationPlans`, `deleteMedicationPlan`), `medications_screen.dart`, `models/medication_plan.dart`.

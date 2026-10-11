# KARAR-BEKLEYEN — fix/audit-bulgular

Ürün/UX kararı gerektiren ya da birden fazla makul çözümü olan maddeler. Güvenli varsayılan uygulandıysa belirtildi.

## KB-1 — "Geri al": sunucuda olmayan SAHİP bebek
- **Soru:** Profil push'u kalıcı reddedilmiş ve sunucuda hiç olmayan (yerelde oluşturulmuş) sahip bebekte "değişikliği geri al" bebeği ve tüm çocuk verisini (kayıt/anı/anne/sağlık) yerelden silmeli mi?
- **Seçenekler:** (a) onay diyaloğuyla sil — kullanıcı kararının bedeli tüm bebek verisi, geri alınamaz; (b) silme; bayraklar temizlenir, bebek yalnız bu cihazda kalır (kullanıcı isterse bebeği normal yoldan siler); (c) "Düzenle" akışına yönlendir (ör. ad geçersiz → düzelt → yeniden gönder).
- **Uygulanan varsayılan:** (b) — `BabyRepository.keepLocalOnly`, sheet "Bu kayıt yalnız bu cihazda kalacak" der. Tombstone (bekleyen silme) + sunucuda yok → onayla yerel satır + çocuk verisi kaldırılır (zaten silinmek isteniyordu).
- **Etkilenen:** `lib/data/push_error_repository.dart`, `lib/features/settings/push_error_sheet.dart`, `lib/data/baby_repository.dart` — commit `3c7d94c`.

## KB-2 — "Geri al" uygulanamayan tablolar
- **Soru:** Records (`POST /sync` batch) ve ilaç planları (yanıt otoriter) için kalem bazlı "geri al" gerekli mi?
- **Seçenekler:** (a) O9 batch sınırıyla birlikte records'a `pushError` eklemek (ayrı şema); (b) mevcut davranış (records çakışması sunucuda çözülür, ilaç planı yanıtı otoriter → kalıcı red kavramı yok).
- **Uygulanan varsayılan:** (b) — kapsam dışı, banner sayacına girmez.
- **Etkilenen:** TASARIM §6b.

## KB-3 — "Tümünü geri al" ve sunucuda olmayan satırlar
- **Soru:** Toplu geri almada sunucuda olmayan satırlar sessizce silinmeli mi?
- **Uygulanan varsayılan:** Hayır — yalnız sunucuda olanlar uygulanır, kalanlar listede kalır ve tek tek onay ister.
- **Etkilenen:** `push_error_sheet.dart` `_all`.

## KB-4 — Kesin alarm (exact alarm) izni için UI girişi (O16)
- **Soru:** Android 14+'ta kesin alarm izni artık otomatik istenmiyor (izin yoksa ±dakika gecikmeli inexact). Kullanıcıya nerede/nasıl açıklanıp istenmeli?
- **Seçenekler:** (a) Bildirimler ayar ekranına "Tam dakikasında bildirim" satırı + açıklama → `NotificationService.requestExactAlarmPermission()`; (b) beslenme hatırlatıcısı ilk kez açılırken tek seferlik açıklama diyaloğu; (c) hiç istememek (inexact yeterli).
- **Uygulanan varsayılan:** otomatik istek kaldırıldı; `requestExactAlarmPermission()/canScheduleExact()` hazır, UI bağlanmadı (c gibi davranır).
- **Etkilenen:** `lib/core/notification_service.dart` — `82d3db2`.

## KB-5 — Gebelikten "Adet takibine dön"de çapa (O23)
- **Soru:** Bekleyen bebek kaldırılırken `first_period_date` (eski LMP çapası) korunmalı mı sıfırlanmalı mı?
- **Seçenekler:** (a) korumak — yanlış-alarm senaryosu: kullanıcı yeni adetini loglayınca çapa taşınır, ama o ana dek "N gün gecikti" görünür; (b) sıfırlamak — adet ekranı bekleme moduna döner, kullanıcı ilk adetini girer (kayıp akışıyla aynı).
- **Uygulanan varsayılan:** (a) korundu.
- **Etkilenen:** `lib/features/cycle/cycle_loss.dart` — `ce4e912`.

## KB-6 — DST gün aritmetiği kapsamı (O29)
- **Soru:** Adet motoru + LMP→TDT dışındaki ~20 nokta (akış "‹", 7-gün grafik anahtarı, dün özeti, düzeltilmiş yaş/atak/gebelik haftası, takvim adjust sheet, notification_sync) `cycleAddDays`/UTC-gün yardımcılarına taşınsın mı?
- **Seçenekler:** (a) toplu mekanik değişim (15 dosya; görsel/istatistik sonuçları değişebilir, DST ortamında doğrulanamıyor); (b) yalnız veri yazan noktalar (yapıldı: TDT) + görünür hesaplar kalsın (TR pazarı DST yok).
- **Uygulanan varsayılan:** (b).
- **Etkilenen:** `cycle_engine.dart`, `cycle_pregnancy_bridge.dart` — `1b2696d`.

## KB-7 — Aşı anahtarı dil bağımlılığı (O19)
- **Soru:** Backend #3 (dil-bağımsız `key`) gelene dek istemcide bir şey yapılmalı mı?
- **Seçenekler:** (a) beklemek (K4 yankı güvencesiyle tik kaybolmuyor, yalnız farklı dilde paylaşılmıyor); (b) 5 ek dilde kataloğu EN'e düşürmek (mevcut TR-adlı işaretler görünmez olur — veri kaybı görünümü).
- **Uygulanan varsayılan:** (a).
- **Etkilenen:** —

## KB-8 — Bakıcı (caregiver) ilaç planı ekleyebilmeli mi? (D30)
- **Soru:** UI bakıcıya plan ekletiyor ama senkron bakıcı değişikliğini göndermiyor (backend `can_full_write`) → cihazda hayalet plan.
- **Seçenekler:** (a) K-7 gibi repo `StateError` + UI kilidi (bakıcı yalnız doz işaretler); (b) backend'de bakıcıya plan yazma izni; (c) mevcut (yalnız bu cihazda kalan plan, not metni düzeltildi).
- **Uygulanan varsayılan:** (c) + not metni güncellendi (`fix(D30)`).
- **Etkilenen:** `lib/features/health/medications_screen.dart`, `health_repository.dart`.

## KB-9 — Hesap silme sonrası yerel veri ve fotoğraflar (D43)
- **Soru:** Hesap silince drift'teki hesap verisi ve foto dosyaları cihazda kalıyor; metin "verileriniz silinecek" diyor. 30 gün geri alma için bilinçli mi?
- **Seçenekler:** (a) hesap silmede yerel kapsamı da sil (O33'teki wipe yolu ile); (b) korumak ve metni "sunucudaki verileriniz silinecek; cihazdakiler için Yerel verileri sil" diye düzeltmek; (c) 30 gün sonra otomatik temizlik.
- **Uygulanan varsayılan:** atlandı (kod değişmedi).
- **Etkilenen:** `auth_controller.deleteAccount`, `privacy_screen.dart`.

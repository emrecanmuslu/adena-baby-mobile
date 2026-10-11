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

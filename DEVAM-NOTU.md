# DEVAM NOTU — fix/adet-senkron

Güncelleme: 2026-10-11 (1.6.0 yayın hazırlığı) · Branch: `fix/adet-senkron` (main `80b1e74`'ten; main'e merge YOK, push YOK, `../api` commit YOK) · Son test: **1473 geçti, 0 başarısız**, `flutter analyze` temiz.

## DURUM: KOD TAMAM — 1.6.0 YAYIN HAZIRLIĞINDA (1.6.0+67)
Yayın hazırlığı commit'leri (kod davranışı değişmedi): sürüm `daadd31` (pubspec **1.6.0+67**; tag'ler `v1.6.0` / `ios-v1.6.0`; CI build = run_number+100 → Android ≥153, iOS ≥204), sürüm notları `dc9c21b` (`SURUM-NOTLARI-1.6.0.md`, 7 dil — kökteki `SURUM-NOTLARI.md` kullanıcı tarafından silinmiş/staged olduğu için ayrı dosya), runbook `26b80f4` (`YAYIN-1.6.0.md`: bekleyen 75+5 çeviri anahtarı, 12 cihaz adımı, telemetri okuma rehberi, yayın sırası + durdurma eşikleri). Şema değişikliği YOK (v15). **Sıradaki iş kullanıcıda, sırası `YAYIN-1.6.0.md` §4.**

- Bölüm 1 (iOS "Senkron sorunu"): telemetri `a8fb5aa`; kök neden düzeltmesi yok (Crashlytics `sync-alert` verisi bekleniyor).
- Bölüm 2 (adet modülü): `ADET-INCELEME.md` 24 bulgu → **23 DÜZELTİLDİ, B3 bilinçli tercih**; kararlar S1–S12 uygulandı. Tüm sağlık metinleri: `SAGLIK-METINLERI.md` (TR+EN, ekran + koşul + bulgu); Türkçe içerik için uzman onayı isteğe bağlı. Çeviriler doğrudan kullanılır (ana dil kontrolü adımı yok — kullanıcı kararı).
- Tur 2: N1 `4c3ef2a` (ilk 42 günde açık "Bu ilk adetim" + onay), N2 `efc2c49` ("Tipik döngü"), N3 `71a839d` (bayrak etiketleri sabit tr), docs.

## Düzeltme turu commit'leri (sırayla)
A1+C5 `8116ba6` · A2+A5+C8+D3 `9782d32` · A3+B5 `8d6dcb8` · A4+C6 `51c1ed3` · B1 `7a703b3` · B2 `998d35d` · B4 `0d0ae85` · B6 `29fcc79` · C1 `61231d6` · C2 `2d46cec` · C3 `8ee2dd9` · C4 `94fec3d` · C7 `9ab919f` · D1 `720c75f` · D2 testi `a63519c` · D4 `e2e6fe1` · D5 `69f9287` · S12 `bb58275` · senaryo testi `b86b503`.

Sözleşme fikstürü güncellenen mevcut testler (amaç korunarak): `cycle_repository_k6_test` (2), `cycle_anchor_test` (2), `cycle_lifecycle_journey_test` J1b (1) — doğum+32/44. gün "ilk adet" fikstürleri S1 kararıyla loşia penceresine düştüğü için 56 günün ötesine taşındı; `cycle_notif_sync_o25_test` — `activeAccountIdProvider` override eklendi (eşitleyici artık hesap kapsamlı "döngüm uzundu" cevaplarını okur).

## Sıradaki iş (kullanıcıda) — ayrıntı `YAYIN-1.6.0.md` §4
1. (İsteğe bağlı) `SAGLIK-METINLERI.md` Türkçe tıbbi eşik metinlerini bir uzmana okut; değişiklik gelirse metin + kod eşiği birlikte güncellenir.
2. `../api/apps/translations/data/*.json`: 75 yeni anahtar (6 dil; tur 1: 68, tur 2: 7) + 2 güncellenen ("Tahmini doğum", "Tahmini doğum: {d}" — D2) + birkaç mevcut anahtarın değer güncellemesi → api'de commit + `seed_translations`.
3. Cihazda doğrula: doğum+0..42. günde "Bu ilk adetim" → onay → takvim bu günden başlar; doğum+43..56. günde kanama kaydı → "loşia mı, ilk adet mi?" diyaloğu; unutulan ay soru kartı; TTC dışında takvimde olasılık satırı yok; kırmızı bayrak diyaloğunda 112/acil metni.
4. Bölüm 1: Crashlytics `sync-alert` non-fatal'larını izle.

## Bilinen sınırlar
- "Hayır, döngüm uzundu" cevabı yalnız cihazda saklanır (sunucu alanı yok); başka cihazda soru bir kez daha görünebilir.
- Uzun süre adet görmeme kartı: düzenli döngüde ≥90 gün, düzensiz döngüde ≥180 gün.

## Çalışma kuralları (devam ederken)
Her değişiklikte önce mevcut koda karşı düşen test → en küçük düzeltme → ilgili testler → ayrı commit; sonunda tam `flutter test` + `flutter analyze`. Yalnız ilgili koda dokun; yan sorunları raporla. Yeni UI metni → `../api/apps/translations/data/*.json`'a ekle, commit'leme.

## Çalışma ağacı notu
Oturum başında çalışma ağacında kullanıcının **commit'lenmemiş staged silmeleri** vardı (`claude-memory/`, BULGULAR/INCELEME/YAYIN-KONTROL/… belgeleri, eski DEVAM-NOTU.md) + `CLAUDE.md` ve `.github/workflows/test.yml` değişiklikleri. Bunlara DOKUNULMADI; commit'ler yalnız kendi dosyalarıyla (`git commit -- <paths>`) yapıldı. Bu DEVAM-NOTU.md yeniden oluşturuldu.

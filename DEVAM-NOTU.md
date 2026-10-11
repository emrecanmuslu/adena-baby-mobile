# DEVAM NOTU — fix/adet-senkron

Güncelleme: 2026-10-11 · Branch: `fix/adet-senkron` (main `80b1e74`'ten; main'e merge YOK, push YOK, `../api` commit YOK) · Son test: **1344 geçti, 0 başarısız**, `flutter analyze` temiz.

## DURUM: BÖLÜM 1 TELEMETRİ UYGULANDI, BÖLÜM 2 RAPOR YAZILDI — ONAY BEKLİYOR
- Bölüm 1 (iOS "Senkron sorunu"): analiz raporda (oturum özeti); telemetri `a8fb5aa` (`feat(sync-telemetry)`). **Kök neden düzeltmesi YAPILMADI** — hiçbir hipotez yeni sürümde kodla kesinleştirilemedi; telemetri alanları hangi hipotezi doğrular, raporda.
- Bölüm 2 (adet modülü): `ADET-INCELEME.md` — 24 bulgu (5 sağlık riski, 6 yanlış bilgi, 8 eksik uyarı, 5 UX/dil), senaryo tablosu, uzman soruları. **Kod değişikliği yok** (görev gereği).

## Yapılanlar
1. `a8fb5aa` feat(sync-telemetry): `lib/core/sync_alert_telemetry.dart` (+ `test/core/sync_alert_telemetry_test.dart`, 10 test); kancalar `SyncService.syncAll` (onTourStart / onSyncError / onTourFinished), `SyncStatusBanner` (`sync_alert_shown`, `sync_retry_tapped`), `_AdenaAppState` (onAppStart / onLifecycle); `ApiClient` refresh kilidi getter'ları; `DbWatchdog.lastBackgroundSyncSummary()`.
2. `ADET-INCELEME.md` (docs commit).

## Sıradaki iş (kullanıcı onayı sonrası)
- Bölüm 1: sürümü dağıtıp Crashlytics'te `sync-alert` non-fatal'larını izle; `sync_exc` = `SqliteException` → H5 (DB kilidi); `sync_err_type` = connectionError + `sync_launch` = warm + `sync_fg_ms` küçük → H2 (bayat bağlantı); `sync_refresh_inflight` = yes / `sync_stage` = refresh → H1; `sync_retry_result` = same_error ve `sync_online` = yes → yapışkan/kalıcı neden. Düzeltme kararı veriye göre.
- Bölüm 2: ADET-INCELEME §4'teki A1–A5 (sağlık riski) ve B1/B6 için uzman onayı + kod turu (ayrı branch önerilir).
- Çeviri: yeni UI metni eklenmedi (`../api/apps/translations/data/*.json` değişmedi).

## Çalışma kuralları (devam ederken)
Her değişiklikte önce mevcut koda karşı düşen test → en küçük düzeltme → ilgili testler → ayrı commit; sonunda tam `flutter test` + `flutter analyze`. Yalnız ilgili koda dokun; yan sorunları raporla. Yeni UI metni → `../api/apps/translations/data/*.json`'a ekle, commit'leme.

## Çalışma ağacı notu
Oturum başında çalışma ağacında kullanıcının **commit'lenmemiş staged silmeleri** vardı (`claude-memory/`, BULGULAR/INCELEME/YAYIN-KONTROL/… belgeleri, eski DEVAM-NOTU.md) + `CLAUDE.md` ve `.github/workflows/test.yml` değişiklikleri. Bunlara DOKUNULMADI; commit'ler yalnız kendi dosyalarıyla (`git commit -- <paths>`) yapıldı. Bu DEVAM-NOTU.md yeniden oluşturuldu.

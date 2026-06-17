---
name: statik-icerik-api-migrasyonu
description: "Uygulamaya gömülü statik bilgi içerikleri kademeli olarak API'ye taşınıyor; pilot=gebelik haftaları (tamamlandı), kalan adaylar belli"
metadata: 
  node_type: memory
  type: project
  originSessionId: 25600dfe-b590-4cea-aa23-44ac7147e1de
---

Karar (2026-06-15): Uygulamaya gömülü statik "bilgi/içerik" verileri, uygulama güncellemesi gerekmeden kürasyon + çoklu dil + genişletme için kademeli olarak **API'ye taşınıyor**. Desen: backend model + ListAPIView + admin + seed komutu; mobilde cache'li repository ki **gömülü tablo offline fallback** olarak kalır.

**Tamamlanan pilot — Gebelik haftaları:**
- Backend: `apps/content/models.py` `PregnancyWeek` (week unique, fruit, emoji, size, note, published) + serializer + `GET /content/pregnancy-weeks` + admin + `manage.py seed_pregnancy_weeks` (37 kayıt, 4–40).
- Mobil: `data/pregnancy_weeks.dart` içinde `PregnancyWeeksData` (embedded sabiti + `fromApi` + `stageFor`/`noteFor`); `data/pregnancy_repository.dart` (`pregnancyWeeksProvider` FutureProvider, API→cache dosyası→embedded); `expecting_home.dart` provider'ı izler, yoksa `PregnancyWeeksData.embedded`.

**Tamamlanan — WHO LMS (2026-06-15):**
- Backend: `WhoLmsSeries` (key unique=wt|len|hc_M|F, l/m/s JSONField) + serializer + `GET /content/who-lms` + admin + `seed_who_lms` (6 seri, `apps/content/data/who_lms.json`'dan; bu JSON mobil gömülü Dart'tan regex parse ile üretildi → birebir).
- Mobil: `data/who_lms.dart` artık `whoLms` MUTABLE global (`_whoLmsEmbedded` ile başlar) + `applyWhoLms()`; `data/who_lms_repository.dart` (`whoLmsProvider` FutureProvider<void>: API→cache→applyWhoLms; yoksa gömülü kalır); `charts_view.dart` build'de `ref.watch(whoLmsProvider)` ile hydrate+yeniden çizim. `who_growth.dart` değişmedi (global `whoLms` okur).

**Henüz taşınmayan gömülü statik içerik:**
- `models/symptom.dart` — `kSymptoms` + `trSymptomInfo()` → BİLEREK TAŞINMADI: metinler `tr()` ile i18n sistemine sarılı (TR+EN); içerik endpoint'ine almak makaleler gibi TR-only yapardı (EN gerilemesi) + timeline'da senkron `trSymptom()` çağrıları var. i18n'de bırakmak daha sağlıklı. Kullanıcı isterse TR-only kabulüyle taşınabilir.
- `core/who_growth.dart` `zForPct`/`pcts` → matematiksel sabit, TAŞINMAZ.
- Zaten API'de: milestone/vaccine/tooth/makaleler (fromJson).

**Bekleyen (prod deploy):** Yeni endpoint'ler (`/content/pregnancy-weeks`, `/content/who-lms`) git pull ile gider ama Hetzner'da migration + seed elle çalıştırılmalı: `migrate` + `seed_pregnancy_weeks` + `seed_who_lms`. Ayrıca fetus görselleri `media/fetus/` sunucuya ayrı yüklenmeli (bkz [[fetus-gorseli-bekleme-ekrani]]). Local'de hepsi yapıldı + emulator-5554'e kurulu.

**Bekleyen (karar):** symptom taşınsın mı (TR-only kabulüyle) yoksa i18n'de mi kalsın — kullanıcı kararı bekliyor.

İlgili: [[gebelik-haftasi-veri-dogrulama]], [[fetus-gorseli-bekleme-ekrani]]

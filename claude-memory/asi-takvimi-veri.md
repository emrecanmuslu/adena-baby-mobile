---
name: asi-takvimi-veri
description: "Aşı takvimi verisi — TR (Sağlık Bakanlığı 2025) + US (CDC/ACIP), bölgeye göre seçim, ücretli aşı etiketi; doğrulanmış kaynaklar"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a1e29b85-42d7-4934-9164-40dbcd01684b
---

`api/apps/health/vaccine_schedule.py` — iki şema + locale seçimi. `schedule_for(locale)`: 'en'→US (CDC), aksi→TR. `build_schedule(birth, locale)` / `regenerate_for_baby(baby, locale)`; çağrı yerlerinde `resolve_locale(request)` (baby create yok ama doğum-tarihi-değişimi @ babies/views + lazy-gen @ health/views). Doz adları VaccineSchedule.vaccine_name'e o dilde yazılır (data, tr() değil).

**TR (Sağlık Bakanlığı 2025, 14 Nisan 2025 güncellemesi — asi.saglik.gov.tr):** ÖNEMLİ değişiklik = **altılı karma DaBT-İPA-Hib-HepB** (2-4-6. ay), **1. ay ayrı HepB dozu KALDIRILDI** (HepB doğum + karma içinde). BCG 2.ay. KKK/Suçiçeği 12+48. HepA 18+24. OPA 6+18. Td 13 yaş. (Eski şema beşli karma + 1.ay HepB idi → DÜZELTİLDİ.)

**TR ücretli/isteğe bağlı (ulusal takvimde YOK, adında "(ücretli)"):** Rotavirüs (2-3 doz, markaya göre), Meningokok B, Meningokok ACWY. Kullanıcı isteği: ücretli aşılar "(ücretli)" etiketiyle gösterilsin.

**US (CDC/ACIP birth–6 yıl, 2025 — cdc.gov/vaccines/imz-schedules/child-easyread.html, 2 Tem 2025):** HepB 0/1/6 · DTaP 2/4/6/15/48 (5) · Hib 2/4/6/12 (4, markaya göre) · IPV 2/4/6/48 (4) · PCV 2/4/6/12 (4) · RV 2/4/6 (3, RotaTeq) · MMR 12/48 · Varicella 12/48 · HepA 12/18 · Influenza 6 aydan yıllık. (İlk taslakta IPV 3.doz eksikti → düzeltildi.)

**Dava riski denetimi (2026-06-16):** Aşı takvimleri tek ciddi yanlış-veri riskiydi; ikisi de otoriter kaynakla doğrulandı. Uygulamada **ilaç dozu/mg iddiası YOK** (en yüksek risk — yok). Semptom rehberi ([[oturum-durumu-fiziksel-test]] models/symptom.dart) genel tavsiye + AdMedicalNote feragati. WHO büyüme + gebelik haftası verisi kaynak-doğrulanmış ([[who-lms-veri-kaynagi]], [[gebelik-haftasi-veri-dogrulama]]).

**Mevcut bebekler:** eski şema DB'de kalır; doğum tarihi değişince/lazy-gen'de yeni şemaya geçer (done işaretleri korunur değil — yeniden üretilir). Toplu regen komutu YOK (done-mark sıfırlardı).

---
name: api-degisiklik-izni
description: Gerektiğinde ve standartlara uygunsa backend (../api Django) değişikliği yapmaktan çekinme
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 51705ee7-5832-41ca-b19e-8c7ff489b39a
---

Bir özellik için gerekiyorsa ve "doğru/standart" çözüm backend değişikliği gerektiriyorsa, **çekinmeden backend'i (`../api`, Django+DRF) değiştir** — modele alan ekle, serializer/migration yap, endpoint güncelle.

**Why:** Kullanıcı temiz/standart şemayı, mevcut alanı amacı dışında zorlamaya (workaround) tercih ediyor. Örn. beslenme hatırlatıcı config'i `reminder_schedule`'a sıkıştırmak yerine FamilySettings'e ayrı `feed_reminder` JSONField eklemek daha doğru.

**How to apply:** Backend değişikliğinde `apps/<app>/models.py` + `serializers.py` güncelle, `./.venv/Scripts/python.exe manage.py makemigrations && migrate` çalıştır, gerekiyorsa `../API_SOZLESME.md`'yi de güncelle (sözleşme = kaynak gerçek). Yine de gereksiz/riskli şema değişikliğinden kaçın; mümkünse additive (default'lu) tut. İlgili: [[beslenme-hatirlatici]] [[manuel-test-tercihi]]

**Django runserver autoreload (kullanıcı teyidi 2026-06-13):** Kullanıcının `runserver`'ı dosya değişikliğini otomatik reload eder → **saf Python kod değişikliği (view/url/serializer/model metodu) için manuel restart GEREKMEZ, "restart bekliyor" deme.** Manuel müdahale yalnız: (1) **migration** varsa kullanıcı `migrate` çalıştırmalı (autoreload migration uygulamaz), (2) **yeni paket** (pip install) kurulduysa restart gerekir (autoreload paketi almaz). Bu ikisi dışında ek operasyonel iş yok.

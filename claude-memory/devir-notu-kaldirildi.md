---
name: devir-notu-kaldirildi
description: Devir notu (HandoffNote) özelliği kaldırıldı; ekip bakımında yalnız Canlı aktivite kaldı
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

**Devir notu (HandoffNote) tamamen kaldırıldı** (kullanıcı 2026-06-11'de "gerek yok" dedi). Ekip/paylaşım ("Bakıcı akışı" ekranı) artık **yalnız Canlı aktivite akışını** (ActivityEvent — "X kayıt girdi", otomatik) gösteriyor.

**ÖNEMLİ:** `FAZ_1_KAPSAM.md` devir notunu "ana farklılaşma / ekip bakımına çıkarır" diye anıyor — bu artık geçerli değil, **geri ekleme**. Farklılaşma canlı aktivite ile sağlanıyor.

Kaldırılan yerler:
- Frontend: `models/handoff_note.dart` (silindi); `sharing_repository.dart` handoffs/createHandoff/handoffsProvider; `caregiver_screen.dart` "Devir notu" bölümü + _HandoffCard/_HandoffComposer/_stampLabel (Canlı aktivite kısmı duruyor); `members_screen.dart` menü "Bakıcı akışı" (eski "& devir notu" çıktı).
- Backend: `apps/sharing` HandoffNote model/serializer/view/url/admin; migration `0002_delete_handoffnote` uygulandı (tablo düştü). Migration sonrası **Django restart** gerekir.
- Docs: API_SOZLESME §8 ve sync kapsamı, api/CLAUDE.md güncellendi.

Korunan: `ActivityEvent` (otomatik aktivite, records/views.py `log_activity`), `/babies/{id}/activity` ucu, roller (owner/parent/caregiver), davet akışı.

---
name: kayit-silme-sheet
description: "Kayıt silme onay sheet'i (design ScrEditModal, yalnız silme) — timeline swipe artık anında silmez, sheet açar"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

Kayıt silerken tasarımdaki **ScrEditModal** ("Kayıt düzenle / sil") gösteriliyor ama **yalnız silme** için (kullanıcı 2026-06-11): kategori çipi + tür özeti (RecordUi.summary) + zaman + **"&lt;isim&gt; · &lt;saat&gt;'te ekledi"** (createdBy→isim) + kırmızı **Sil** + Vazgeç. Kaydet YOK.

- `features/records/delete_record_sheet.dart` → `showDeleteRecordSheet(context, ref, record)`. Sil → `recordActionsProvider.delete(id)` (soft-delete) + undo'lu toast.
- **Timeline davranışı değişti** (`timeline_view.dart`): swipe artık `onDismissed` ile ANINDA silmiyor; `confirmDismiss` ile bu sheet'i açıp `return false` döner (silme sheet'te; provider tazelenince satır gider). Tap hâlâ düzenleme formunu açar.
- "Kim ekledi": `record.createdBy` (id) → members/auth ile isme çözülür ("Sen" kendi kaydı). "Ne zaman": `record.ts` (tasarımdaki gibi). Model değişikliği gerekmedi (created_at/updated_by Flutter modelinde yok; ts kullanıldı).

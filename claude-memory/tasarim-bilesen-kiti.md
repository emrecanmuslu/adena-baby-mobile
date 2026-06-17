---
name: tasarim-bilesen-kiti
description: "Tüm ekranlar core/ad_widgets.dart tasarım bileşenlerini kullanmalı, düz Material değil"
metadata: 
  node_type: memory
  type: project
  originSessionId: 417fe98a-ecac-4700-a8b9-2eb3ecca65ae
---

Adena Baby mobil'de tasarım sistemi bileşenleri **`mobile-app/lib/core/ad_widgets.dart`**'ta (design adena.css `.ad-*` sınıfları): `AdField`, `AdInput`, `AdStepper`, `AdTabs`, `AdChoice`, `AdSides`, `AdTimeChip`, `AdSaveButton`, `AdIconChip`, `AdMenuItem`, `adSec`, `fieldBg`, **`showAdToast`** (SnackBar yerine — koyu .ad-toast + "Geri al" undo + timerline), **`adGrabHandle`** + **`adSheetShape`** (bottom sheet'ler: showDragHandle:false + bunları kullan).

**Why:** İlk ekranlar düz Material (AppBar+ListTile+TextFormField+ElevatedButton+ChoiceChip) ile yapılmıştı ve sonradan gelen detaylı design'a (`design/AdenaBaby` JSX+CSS) uymuyordu; hepsi bu kitle yeniden hizalandı.

**How to apply:** Yeni/değişen ekranda Material varsayılanı kullanma — `ad_widgets.dart`'tan ilgili bileşeni al. Form alanı=AdField+AdInput, sayısal=AdStepper, segment=AdTabs, ikili/üçlü seçim=AdSides, ikon seçim=AdChoice, birincil buton=AdSaveButton (kategori-renkli; ghost=ikincil), menü satırı=AdMenuItem, bölüm başlığı=adSec, zaman=AdTimeChip. `features/records/entry_widgets.dart` buraya re-export eder. İlgili: [[tasarim-kaynagi]], [[skeleton-ve-performans]].

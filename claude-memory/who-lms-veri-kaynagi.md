---
name: who-lms-veri-kaynagi
description: Charts persentil eğrisi için WHO LMS verisinin kaynağı ve yeniden üretimi
metadata: 
  node_type: memory
  type: reference
  originSessionId: 417fe98a-ecac-4700-a8b9-2eb3ecca65ae
---

Charts ekranının WHO persentil eğrileri `mobile-app/lib/data/who_lms.dart` (LMS tabloları) + `lib/core/who_growth.dart` (LMS yöntemi hesap motoru) ile çalışır.

**KAPSAM 0–60 ay (2026-06-14 genişletildi; eski hâli 0–24).** `who_growth.dart` `maxMonth=60`. Charts `axisMax`'ı dinamik üretip uyarlanır (x etiketleri `axisMax/6`); backend `report.py` saf renderer, `axis_max`'ı client'tan alır → ekstra backend değişikliği YOK.

**Veri kaynağı (güncel, 0–60):** pygrowup reposu (WHO ile aynı kaynak; mevcut 0–24 değerlerle birebir uyuştu) — `https://raw.githubusercontent.com/ewheeler/pygrowup/master/pygrowup/tables/{wfa,lhfa,hcfa}_{boys,girls}_0_5_zscores.json`. Her JSON 61 satır (Month 0–60) + L,M,S. **lhfa 62 satır:** 24. ayda çift kayıt (uzunluk→boy geçişi); İLK kayıt (uzunluk=87.8161) tutulur → mevcut 0–24 veriyle süreklilik, 25–60 boy (ayakta). Sadece L,M,S saklanır (kilo L değişken, boy/baş L=1).

**Yeniden üretmek için:** 6 JSON'u indir, ay başına ilk kaydı al (dedup), `repr(float)` ile Dart double literal'e çevir, `whoLms['<wt|len|hc>_<M|F>']` yaz. Kanonik birimler: kilo kg, boy/baş cm (record.data: weight/height/head_circ). `BabyGender` unknown → persentil yok. (Eski 0–24 kaynağı: CDC/NCHS ftp aynası — yalnız 0–24 olduğu için 24–60'a yetmiyordu.)

İlgili: [[tasarim-kaynagi]], [[skeleton-ve-performans]].

---
name: platform-paritesi
description: iOS ve Android ikisi de eşit öncelikli; her özellik/düzeltmede çapraz platform paritesi/uyumluluğu şart
metadata: 
  node_type: memory
  type: project
  originSessionId: 937eea7a-7db9-4463-ab41-f23ce7fd0c5c
---

iOS ve Android ikisi de bizim için eşit öncelikli platform (2026-06-11 kullanıcı belirtti). Biri diğerinden üstün değil — **çapraz platform uyumluluğu/paritesi** asıl hedef.

**Why:** Geliştirme geçmişte pratikte Android odaklı ilerledi ve bazı özellikler iOS'ta eksik paritede kaldı (örn. uyku/emzirme canlı bildirimi + Dynamic Island yok, statik banner). Kullanıcı artık iki platformun da eşit ele alınmasını istiyor.

**How to apply:** Yeni özellik/düzeltme yaparken her iki platformda da çalışacak şekilde tasarla ve ikisini de açıkça doğrula — birinde çalıştı diye bitti sayma. Platform farkı kaçınılmazsa kullanıcıya bildir. Özellikle iOS'ta gözden kaçan konular: ongoing/canlı bildirim ve Live Activities (native iş), `static final`/top-level final tema/dil donma tuzağı, sunucu hatalarının dili, connectivity_plus pinleri. iOS test akışı (GitHub Actions imzasız .ipa + Sideloadly) bkz [[oturum-durumu-fiziksel-test]].

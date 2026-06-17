---
name: hafiza-repoda-senkron
description: Kalıcı hafıza artık mobile-app reposunda claude-memory/ altında; Windows+Mac git ile senkron
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e51c6cff-6270-4246-90b0-fd1273406874
---

Kullanıcı isteğiyle (2026-06-17) kalıcı hafıza **mobile-app reposuna `claude-memory/` klasörüne** kopyalandı ve git ile versiyonlanıyor. Amaç: Windows host + macOS VM iki makinede de her zaman güncel hafızayla çalışmak.

**Protokol (repo `CLAUDE.md`'de de yazılı):**
- Oturum başında `git pull` → `claude-memory/MEMORY.md` oku.
- Hafıza değişince hem yerel `.claude/.../memory` hem repo `claude-memory/` güncellenir, sonra **commit + push** (diğer makine pull'la alsın).
- Repo **private**; hafızada hassas veri var (sunucu IP, kişisel/legal veri, strateji) → public yapma/yetkisiz erişim verme.

**Bilinen sınır:** Claude Code'un otomatik MEMORY.md enjeksiyonu hâlâ makineye-özgü yerel yoldan okur; repo `claude-memory/` ile yerel kopya elle (commit'lerle) eşit tutulur. İstenirse Windows'ta junction / Mac'te symlink ile yerel yol repo klasörüne bağlanıp tam otomatikleştirilebilir (şimdilik yapılmadı).

İlgili: [[adim-adim-tek-tek]], [[iletisim-dili-turkce]]

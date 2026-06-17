---
name: oturum-durumu-fiziksel-test
description: "Kaldığımız nokta — proje genel durumu, bekleyen operasyonel iş, bilinen sorunlar, test/deploy kurulumu"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

## EN SON OTURUM (2026-06-16, yayın kod işleri turu) — KALDIĞIMIZ NOKTA
Önceki turun bekleyen işleri + kalan YAYIN kod kalemleri tamamlandı (analyze + 29 api testi temiz). Kapanan YAYIN_EKSIKLERI: **#10, #14, #15, #16, #17** → kalan açık maddeler artık yalnız mağaza/Mac/token (bkz YAYIN_EKSIKLERI.md).
- **Bekleyenler kapandı:** mobile-app 3 commit **push edildi** (GitHub güncel); cloud-bağlı güncel APK derlenip `Desktop/AdenaBaby-cloud.apk`'ya kondu (rıza UI'lı, api.adenababy.com).
- **#10 media koruması:** bebek/anı foto'ları **imzalı HMAC URL** (`apps/common/media.py`, `/api/v1/files/<path>?e=&s=`); serializer'lar imzalı URL üretir, içerik/fetüs public kalır. Mobil değişiklik YOK. **DEPLOY nginx kuralı zorunlu:** `location ~ ^/media/(babies|memories)/ { deny all; return 404; }` (opsiyonel `MEDIA_X_ACCEL=True`). 8 test.
- **#15 hesap silme grace:** anlık hard-delete kaldırıldı → yumuşak silme (`deletion_requested_at`+is_active=False, JWT anında reddedilir), `GRACE_DAYS=30`, 30 gün içinde tekrar giriş **otomatik geri yükler** (`account_restored`); `purge_deleted_accounts` cron komutu (`apps/accounts/deletion.py`, migration **0008**). Mobil silme onayı dürüst metin+EN. 7 test. **DEPLOY:** migrate + cron `0 3 * * * purge_deleted_accounts`.
- **#14 export tam kopya:** `GET /auth/me/export` (`apps/accounts/export.py`) hesap+ayar+rıza+abonelik+tüm bebekler(foto imzalı+kayıt+anı+mom+hatırlatıcı/aşı/gelişim/diş)+topluluk Q&A; mobil `data_export.dart` sunucu-öncelikli, offline'da yerele düşer. 2 test.
- **#16 EN tamlık:** 919 tr/trp anahtarının tümü en.json'da (eksik **0**, Dart concat hesaba katıldı).
- **#17 erişilebilirlik:** `AdenaIcon.semanticLabel` (etiketsiz=dekoratif) + nav/header `Semantics(button)` + tüm ikon-only IconButton `tooltip`. en.json **1041** giriş (+9 EN bu turda).
- **TÜM DEPLOY EDİLDİ + DOĞRULANDI (2026-06-16):** api `4ef89f8` canlı (migration 0008, EN seed v4118), media koruması nginx deny kuralı (her iki config), purge cron (03:00), web SS revizyonu (adenababy.com). Doğrulama: api 200, /media/memories→404, /files kötü-imza→403, web 200. Detay [[cloud-deploy-hetzner]].
- **İkinci batch (kod-dışı senin yapamayacakların hariç hepsi):** #20 US/CDC aşı takvimi (bkz [[asi-takvimi-veri]]) · #19 iOS InfoPlist.strings EN/TR hazır (Xcode kaydı Mac'te kalan) · #11 uygulama-içi gizlilik metni canlı politikayla hizalandı (yanıltıcı "reklam yok" kaldırıldı) · #12 manifest SCHEDULE_EXACT_ALARM doğrulandı.
- **VERİ DOĞRULAMA (dava riski):** aşı takvimleri tek riskti, düzeltildi+doğrulandı ([[asi-takvimi-veri]]). İlaç dozu/mg iddiası YOK; semptom rehberi genel+feragatli; WHO/gebelik kaynak-doğrulanmış.
- **SUNUCU SERTLEŞTİRİLDİ (2026-06-16):** ufw aktif (22/80/443), SSH parola auth kapalı (yalnız key — başka makineden Hetzner console fallback), fail2ban aktif (brute-force banlıyor), nginx server_tokens off, sslip.io devre dışı. Detay [[cloud-deploy-hetzner]].
- **NOT — masaüstü cloud APK biraz eski:** oturum BAŞINDA derlendi (consent UI var) ama #14 export/#17 a11y/#11 metin/aşı sonradan eklendi → tam güncel cloud APK için yeniden derle (mobil GitHub güncel).
- **KALAN (yalnız senin yapacakların):** release keystore (#1), prod API URL build (#4), iOS entitlements/Firebase Mac (#5), mağaza varlıkları (#6), Play Data Safety + App Store Privacy formları (#11), exact-alarm Play formu (#12), iOS .strings Xcode kaydı (#19), RevenueCat token (#18).
- API_SOZLESME.md güncellendi (me/export, grace delete, korumalı media).

## EN SON OTURUM (2026-06-15/16, yasal + güvenlik + rıza turu)
Bu turda kapanan YAYIN_EKSIKLERI maddeleri: **#2, #7, #8, #9, #13**. Detaylar: [[legal-pricing-uygulama-durumu]] + [[acik-riza-yas-kapisi]].
- **Yasal belgeler** (4 belge TR+EN) API+site CANLI + uygulama-içi linkler (url_launcher, ayarlar+kayıt). pricing API-fetch. CORS sertleştirme.
- **KVKK açık rıza + yaş kapısı**: kayıt tek kutu (18+ ve Gizlilik/Şartlar) + sosyal giriş ConsentGateScreen + denetlenebilir Consent modeli. CANLI deploy edildi.
- **Prod güvenlik sertleştirme** (#9): DEBUG=False hard-fail (SECRET_KEY/ALLOWED_HOSTS) + HSTS/secure cookies/X-Frame/nosniff/CSRF_TRUSTED_ORIGINS. CANLI (HSTS header doğrulandı).
- **Tıbbi feragat** (#13): paylaşımlı AdMedicalNote → charts/gebelik/semptom ekranlarında kalıcı.
- **api repo: tamamen push'lu + deploy edildi** (api.adenababy.com, commit 263f88f). Migration accounts 0007 + 7 EN seed canlı.

**⚠️ BEKLEYEN İŞLER (yeni oturum):**
1. **mobile-app'te 3 commit PUSH EDİLMEMİŞ** (40caf80 feragat, 13fb953 consent/yaş, 01a732a yasal-link). Emülatörde kurulu ama GitHub'da yok → iOS build/uzak yedek için `git push` gerek (repo emrecanmuslu/adena-baby-mobile).
2. **Cloud-bağlı güncel APK yeniden derlenmedi** (kullanıcıya önerildi): masaüstü eski AdenaBaby.apk consent UI'sız → register 400 alır. Güncel kodla `--dart-define=API_BASE_URL=https://api.adenababy.com/api/v1` ile derleyip masaüstüne koymak fiziksel rıza testi için kaldı.
3. **Kalan YAYIN kod işleri**: #10 (foto media erişim koruması), #14 (export tam kopya), #15 (hesap silme grace), #16 (EN çeviri tamlık raporu), #17 (erişilebilirlik Semantics — saf mobil).
4. Backend register artık accepted_legal+age_confirmed zorunlu → eski cloud APK'lar kayıtta kırılır (login etkilenmez); demo/eski hesaplar ilk girişte rıza kapısı görür (beklenen).

## EN SON OTURUM (2026-06-15, çeviri açıkları + dil-restart turu)
analyze temiz, APK emulator-5554'e kuruldu, seed_translations dev'de çalıştı (katalog 2918).
1. **Dil değişince app restart** ([[dil-degisince-app-restart]]): `core/restart_widget.dart` + `data/locale_cache.dart`; main.dart RestartWidget ile sarıldı; appearance dil seçince setLocale→restart. Sebep: AnimatedBuilder rebuild'i const/önceden-build ekranlara ulaşmıyordu.
2. **Çeviri açıkları kapatıldı** ([[ceviri-en-karsiligi-zorunlu]]): `tr()` ile sarılı ama en.json'da EN'i olmayan 117 + 6 metin eklendi; ayrıca sarılmamış string'ler sarıldı — social_auth hata mesajları, api_error alan etiketleri (tr(label)), membership rolleri, quiet_hours 'Kapalı', register 'Ayşe', ve interpolasyonlu/ASCII-only kaçaklar (expecting_home 'Tahmini:'/'~{w} hafta', health 'Gecikti·/Planlanan·', home '{w}. hf', baby_switcher '{name} eklendi', settings '{theme}·birimler', baby_setup 'Merhaba{name}'). en.json ~1014 giriş.
3. **YENİ KURAL** ([[ceviri-en-karsiligi-zorunlu]]): bundan sonra her yeni/düzeltilen tr()/trp() için en.json'a EN ekle/güncelle + seed et.
**BEKLEYEN OPERASYONEL İŞ (deploy):** en.json'a yeni girişler eklendi → Hetzner sunucuda git pull sonrası `seed_translations --locale en` çalıştırılmalı (önceki turun bekleyen migration+seed listesine eklenir, aşağı bak). Kod değişiklikleri saf Dart (mobil) + en.json → backend migration YOK; yalnız seed.

## EN SON OTURUM (2026-06-15, İngilizce + bölgeselleştirme turu)
TR+US lansmanı için tam İngilizce + cihaz-bölgesine bağlı davranış yapıldı — analyze + Django check temiz, APK emulator-5554'e kuruldu. Tam detay: [[ingilizce-ve-bolgesellestirme]]. Özet: 891 UI metni EN seed; içerik modelleri locale'li + EN içerik (29 makale/37 hafta/58 milestone); cihaz dili/birimi/tarihi locale-duyarlı; DB-yönetilebilir fiyat+indirim (`PricingPlan`); sunucu-yönetimli `Language`+`Country` (61 ülke) → yeni dil eklenince app'te otomatik; KURAL: Türkiye dışı her zaman EN (dil+içerik `content_locale`); locales/countries/pricing diske cache'li (`core/json_cache.dart`).
**BEKLEYEN OPERASYONEL İŞ (deploy):** Bu turda MIGRATION VAR (content 0005, accounts 0005+0006, translations 0003) + yeni SEED'ler. Sunucuda (Hetzner [[cloud-deploy-hetzner]]) `migrate` + `seed_translations --locale en` + `seed_content_en` + `seed_pregnancy_weeks_en` + `seed_pricing` + `seed_locales` çalıştırılmalı; gunicorn restart. Dev'de hepsi çalıştırıldı (sqlite). İngilizce çeviriler admin'den de düzenlenebilir.

## EN SON OTURUM (2026-06-13, entegrasyon/login turu)
Sosyal giriş hatası teşhis edildi: kod tam ama provision eksikti. Google **web client ID** `mobile-app/dart_defines.json`'a + `scripts/run.sh` (= `--dart-define-from-file`) eklendi, backend `.env` ile eşleşti. 4 entegrasyon (Google iOS login, Apple login, reklam, ödeme) **test aşamasında bilinçle bekletildi** → tam durum/eksikler: [[entegrasyon-bekleyen-tokenlar]]. Özet: login+ödeme kod TAM (token kaldı), **reklam SDK'sı henüz entegre değil** (google_mobile_ads yok, placeholder). Android Google için debug SHA-1 Cloud'a eklenecek (nottadır). Kod değişikliği yok → migration/restart gerekmez.

## ÖNCEKİ OTURUM (2026-06-13, paylaşım/bildirim turu)
Bu turda eklenenler — detay [[bakici-bildirim-paylasim-2026-06-13]] (analyze+check temiz, APK build geçti):
bakıcı=sınırlı yazma, anne takibi bakıcıdan gizli, aile etkinlik bildirimi (opt-in polling), çok-bebek bildirim id slot + tüm bebekler + başlıkta bebek adı, çıkarılan üye temizliği, rol-değiştirme kaldırıldı, Son Aktivite göreli zaman+akıllı tarih. Çok bebek FREE kalır.
**Bekleyen FİZİKSEL test** (kod tamam, davranış denenmeli): (1) iki bebekte eş-zamanlı uyku/emzirme sayacı çakışmıyor + bebek adı; (2) bakıcı hesabıyla sağlık/anı/anne takibi salt-okunur+gizli; (3) üye çıkarılınca diğer cihaz öne gelince bebek düşer + "erişim kaldırıldı". Migration yok → restart gerekmez.
Ayrıca bu oturumda: hedef kitle/konumlandırma kararı ([[hedef-kitle-konumlandirma]]) + 2-5 yaş zenginleştirme backlog'u ([[yas-genisletme-backlog]]).

## GÜNCEL DURUM (2026-06-13)

Uygulama özellik olarak **büyük ölçüde tamam**: FAZ 1 (çekirdek takip, sağlık hub + TR aşı takvimi, WHO grafik, rol-bazlı paylaşım, offline sync + dakikalık polling, i18n, hatırlatıcılar, iki mod, Google girişi) + FAZ 2 (anılar/foto günlüğü, milestone) + FAZ 3 (semptom, diş/ağız haritası, uzman içeriği, topluluk) + **monetizasyon** ([[para-kazanma-modeli]]) hepsi yapıldı. Navigasyon = Keşfet hub'ı ([[navigasyon-kesfet-hub]]), home özelleştirme ([[home-ozellestirme-ve-senin-icin]]).

**Bu oturumda (2026-06-13) yapılanlar** — analyze + Django check temiz, APK emulator-5554'e kuruldu:
1. **Tema cache** (`data/theme_cache.dart` + `cachedThemeProvider`): splash artık seçili temada açılır (sistem koyu olsa bile Açık seçiliyse açık).
2. **Sonraki beslenme kartı** (home `_PredictSection`): "120 dk sonra" → insan-dostu "2 saat / 1 saat 50 dakika sonra"; alt satır "Son 09:10 (anne sütü) · 1 sa 10 dk önce"; son 30 dk amber, vakti geçince kırmızı + nabız animasyonu.
3. **Home pull-to-refresh** → syncAll.
4. **Beslenme son-değer cache** (`data/feed_input_cache.dart`): Mama/Sağılmış/Katı son girilen miktar ön-doldurulur; **anne sütü hariç**.
5. **Bildirim textleri** gözden geçirildi (3 eski ifade düzeltildi).
6. **Topluluk tamamlandı**: kendi soru/cevabını düzenle+sil (backend PATCH/DELETE sahip-only + OwnerMenu + edit sheet'leri), sonsuz kaydırma (feed paginated, repo offset/limit), arama (backend `search` + arama çubuğu), kullanıcı profili (`/community/users/<id>` + `author_id` + tıklanabilir AuthorRow + `community_profile_screen`), feed/detay retry + pull-to-refresh.

## BEKLEYEN OPERASYONEL İŞ
**Yok.** Bu oturumda community değişiklikleri saf Python kodu (view/url/serializer) → kullanıcının `runserver` autoreload'u otomatik aldı, migration ve yeni paket yok. Manuel restart GEREKMEZ ([[api-degisiklik-izni]] — autoreload notu). Manuel müdahale yalnız migration (`migrate`) veya yeni paket (pip install) olduğunda gerekir.

## Sıradaki olası işler (kullanıcıya sor)
- "Cevabın geldi" gerçek-zamanlı bildirim → push gerektirir, lansman sonrası hedefli (şu an push bilinçli yok, polling yeterli).
- Token entegrasyonu: RevenueCat/AdMob/IAP anahtarları gelince gerçek akışlar otomatik aktif olur ([[para-kazanma-modeli]]).

## KALICI KARARLAR / İPTALLER (geri açma)
- **iOS Live Activities** canlı kronometre iptal — iOS'ta statik banner kalır (native iş, yapılmayacak).
- **Gerçek push (FCM/APNs)** eklenmeyecek — yerel bildirim + polling yeterli.
- **Düzeltilmiş yaş / doğum haftası** tamamen kaldırıldı (backend dahil) ([[faz1-kararlari-2026-06-11]]).
- **Tip jar** ayrı bağış iptal → premium destek notuna dönüştü ([[para-kazanma-modeli]]).

## BİLİNEN SORUNLAR
1. **iOS kronometre (uyku/emzirme):** iOS'ta ongoing/canlı bildirim ve Dynamic Island yok (flutter_local_notifications desteklemez); statik banner.
2. **`static final` tuzağı:** `tr()` ya da tema-duyarlı `AppColors` getter'ı yakalayan `static final`/top-level `final` ilk açılışta DONAR (dil/tema değişince güncellenmez). ÇÖZÜM = getter kullan. (NotificationService kanal adları bilinçle static — Android kanalı OS'a bir kez yazılır.)

## TEST / DEPLOY KURULUMU
- **Cihaz:** emulator-5554 (AVD) aktif; local geliştirme local Django'ya bağlanır (config default `10.0.2.2:8000/api/v1`, dart-define verme) ([[local-dev-local-api]]). MuMu kullanılırsa LAN IP gerekir (bkz mobile-app/CLAUDE.md).
- **Manuel test:** analyze temizse otomatik APK build + adb install; UI testini kullanıcı yapar ([[manuel-test-tercihi]]).
- **Backend kullanıcının kendi terminalinde** ayakta (0.0.0.0:8000) — ben başlatmıyorum. Claude sandbox bash'i loopback/dış ağa çıkamaz → `curl localhost:8000` 000 döner, YANILTICI (gerçekte ayakta).
- **Fiziksel cihaz (gerektiğinde):** cloudflared tüneli (`C:\Users\Dev\cloudflared.exe tunnel --url http://localhost:8000`, URL ephemeral — değişince APK yeniden derle dart-define ile). Cloud test API'si de var ([[cloud-deploy-hetzner]]).
- **iOS:** GitHub repo `emrecanmuslu/adena-baby-mobile`, `.github/workflows/ios.yml` (workflow_dispatch, imzasız .ipa) → Sideloadly + ücretsiz Apple ID. `connectivity_plus` 6.1.5'e pinli (7.x Xcode 26 derleme hatası). Yeni fix'ler için kullanıcı `git push` + Actions çalıştırmalı.

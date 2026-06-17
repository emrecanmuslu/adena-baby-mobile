---
name: para-kazanma-modeli
description: Freemium + yumuşak reklam + premium (abonelik & lifetime); free/premium sınır çizgisi. Tip jar/ayrı bağış İPTAL.
metadata: 
  node_type: memory
  type: project
  originSessionId: 5a1718dd-f88e-4571-a2cc-054b7a6cea75
---

2026-06-12'de kilitlenen para kazanma modeli. Önceki "her şey free" kararı ([[faz1-kararlari-2026-06-11]]) güncellendi: premium artık aktif.

**Premium** = abonelik (aylık + yıllık) + tek-seferlik **Lifetime** seçeneği. Kapsam:
- Reklamsız
- Aile/ekip paylaşımı + Canlı aktivite ekip görünümü ([[devir-notu-kaldirildi]])
- Bulut yedek + sınırsız foto günlüğü
- PDF / gelişmiş grafik export (doktor raporu — bu AI export değil, faz1'de kaldırılan AI export'tan farklı)
- Sınırsız özel hatırlatıcı ([[hatirlatici-sistemi]])

**Free** = tüm çekirdek izleme + temel grafikler + uzman içeriği her zaman ücretsiz. Yumuşak limitler:
- Foto günlüğü: son 30 gün / yerel (bulut yedek yok)
- Aktif hatırlatıcı: 2 adet
- Export yok, aile paylaşımı yok

**Reklam (yumuşak doz):** kaydı BLOKLAMADAN, kayıt sonrası timeline'a dönüşte interstitial; frekans limiti en fazla 2-3 dk'da bir + en az 3-5 kayıtta bir (peş peşe girişte çıkmaz); ilk gün/onboarding reklamsız; sessiz saat ([[sessiz-saat]]) ve süren sayaç ([[suren-sayac-bildirimi]]) sırasında yok. AdMob iki platform; AB için UMP onay ekranı; Google Families/aile-güvenli kategori.

**Bağış ("Geliştiriciye destek ol"):** ❌ İPTAL (2026-06-12 kullanıcı düzeltmesi) — ayrı tip jar yok. Yerine premium ekranında destek notu kartı (premium'a teşvik). Aşağıdaki "Adım 4" notuna bak.

**Why:** Kullanıcının kendi mantığı: ilk indiren free+reklam kullanır; aile paylaşımı/gelişmiş özellik isteyen premium alır (reklam da kalkar). Çekirdek izleme duvarsız kalmalı yoksa acemi ebeveyn siler.
**How to apply:** Yeni ekran/özellik eklerken free/premium sınırını ve reklam tetikleme noktasını bu çizgiye göre belirle; iki platformda da ([[platform-paritesi]]) doğrula.

## Uygulama planı + ilerleme (RevenueCat seçildi)
Sıra: 1 entitlement altyapısı → 2 paywall+gating → 3 reklam → 4 (tip jar İPTAL → yerine destek notu + ince ayarlar).

**Adım 1 BİTTİ (2026-06-12, analyze temiz + migration + APK kuruldu):** Kaynak gerçek = backend; RC satın almayı sürer, entitlement'ı backend RC webhook + `/me/subscription/refresh` ile doğrular; UI gating `isPremiumProvider` (= `subscription.is_premium`).
- Backend: `Subscription` modeli RC alanlarıyla genişledi + `is_active` property; `User.is_premium`; `apps/accounts/revenuecat.py` (REST fetch + apply_subscriber/apply_event/find_user); `RevenueCatWebhookView` → `/api/v1/webhooks/revenuecat`; `SubscriptionView.post` artık `/me/subscription/refresh` (RC senkron); `SubscriptionSerializer`; `apps/accounts/permissions.py` `IsPremium` (henüz uca uygulanmadı=Adım2); settings `REVENUECAT_SECRET_KEY`+`REVENUECAT_WEBHOOK_AUTH`. migration accounts 0003.
- Mobile: `purchases_flutter ^10.2.3`; `core/revenuecat_service.dart` (configure/identify/logout/offering/purchase(PurchaseParams.package)/restore, anahtar boşsa no-op); `config.dart` REVENUECAT_ANDROID/IOS_KEY dart-define; `subscription.dart`+repo `refresh()`/`isPremiumProvider`/`premiumSyncProvider`; main.dart configure + premiumSync watch; auth_controller identify/logout.

**Kullanıcıdan gereken (Adım 2 öncesi):** RevenueCat hesabı + Play/App Store ürünleri (aylık+yıllık abonelik + Lifetime non-renewing), entitlement id="premium", offering paketleri; anahtarlar dart-define ile (REVENUECAT_ANDROID_KEY goog_…, REVENUECAT_IOS_KEY appl_…), backend .env REVENUECAT_SECRET_KEY+WEBHOOK_AUTH, RC dashboard webhook URL+Authorization.

**Adım 2+3 BİTTİ (2026-06-12, analyze temiz + migration 0004 + APK kuruldu) — GELİŞTİRME MODU:** token'lar gelene kadar premium "sahte satın alma" ile, reklam "placeholder" ile çalışır.
- Geliştirme modu kararı (kullanıcı): RC anahtarı yokken "Premium ol" → backend `/me/subscription/dev-activate` (yalnız DEBUG) ile sahte premium; AdMob anahtarı yokken gerçek reklam yerine placeholder dialog. RC/AdMob anahtarı set edilince otomatik gerçek akışa geçer (kod hazır).
- TEK-KULLANIMLIK KOD sistemi (kullanıcı isteği): `RedemptionCode` modeli (plan=monthly|yearly|lifetime, used_by tek-sefer); `apps/accounts/premium.py` grant_premium/revoke_premium (plan→süre: 30/365/None); `RedeemCodeView` `/me/subscription/redeem`; admin kaydı + `python manage.py gen_premium_codes --plan lifetime --count N --note ...`. Paywall'da "Kodum var" sheet.
- Backend: `DevActivateView` `/me/subscription/dev-activate` (DEBUG); aile daveti `InvitationCreateView` artık `IsPremium` duvarlı (owner premium değilse 403).
- Mobile: `core/premium_gate.dart` `requirePremium()`/`showPremiumUpsell()` (premium değilse upsell sheet→/premium); members_screen davet butonu bununla sarıldı. premium_screen yeniden yazıldı: 3 plan (aylık/yıllık/**lifetime** kartı) + RC offerings fiyatı veya placeholder fiyat + dev sahte satın alma + restore (RC) + Kodum var. `core/ad_service.dart` (rootNavigatorKey; frekans limiti ≥3 kayıt + ≥3dk, premium muaf; placeholder dialog) → record_controller `_saveAndSync(r, ad:true)` yalnız tamamlanmış kayıtlarda (upsert/addDiaper/addFeed/stopSleep/stopBreast); config.dart ADMOB_*_INTERSTITIAL_ID.

**Premium rozeti (tasarım 23·Menü / 25·AI export):** `AdProBadge` (ad_widgets, altın .ad-pill.prem) eklendi; settings AI export + members "Bakıcı akışı" satırlarında `trailing: AdProBadge(withChevron:true)` (premium değilse). Bakıcı akışı artık `requirePremium` ile gated (önceki açık kapatıldı).

**İKİ KÖK HATA DÜZELTİLDİ (kullanıcı reprodüksiyonu):** (1) dev-activate 404 → abonelik uçları `auth/` include altında ama subscription_repository öneksiz `/me/subscription` çağırıyordu; hepsi `/auth/me/subscription...` yapıldı (auth_repository zaten `/auth/me` kullanıyor — konvansiyon). (2) Reklam 3. kayıtta sheet kapanmıyor/reklam yok → yarış: ad dialog açılıyor, hemen ardından kayıt sheet'inin Navigator.pop'u (ikisi de kök navigator) ad dialog'unu kapatıyordu. Fix: AdService._present başına 500ms gecikme (sheet kapanış animasyonu bitsin). Premium rozeti artık Aile/Paylaşım satırına da eklendi. Reklam tasarım gereği seyrek: 3. tamamlanmış kayıtta + 3dk cooldown.

**Adım 4 + ek gating + reklam ince ayarı BİTTİ (2026-06-12, analyze temiz + APK):**
- Hatırlatıcı limiti: free en fazla 2 'custom' hatırlatıcı; reminders_screen "Hatırlatıcı ekle" free+≥2'de showPremiumUpsell→/premium. (aşı/dürtükleme sistem; beslenme/sessiz saat ayrı kartlar sayılmaz)
- Reklam ince ayarı: AdService.init() ile ilk 24 saat reklamsız (secure storage `ad_first_launch` kalıcı); `onRecordSaved(suppress:)` → record_controller `_suppressAd(r)`: süren uyku/emzirme sayacı (az önce durdurulan aynı-id hariç) VEYA sessiz saat penceresinde reklam susturulur (quietHoursProvider + _inQuietHours gece-yarısı sarması).
- Tip jar İPTAL (kullanıcı düzeltmesi): ayrı bağış istenmiyordu → tip_jar.dart silindi, settings girişi kaldırıldı. Yerine premium_screen'e destek notu kartı eklendi (peach, heart): "Premium'a geçerek küçük ekibimizin Adena Baby'yi geliştirmeye devam etmesine de destek olursun 💛" — premium'a teşvik.
- Tek-seferlik hatırlatıcı temizliği (kullanıcı isteği): reminders_screen `_pruneExpiredOnce` — 'once' + at<now custom hatırlatıcıları otomatik sil (deleteReminder + cancelReminder); liste yüklenince/değişince çalışır.

**Rozet flaşı + iptal notu + foto duvarı BİTTİ (2026-06-12, analyze temiz + APK):**
- Rozet flaşı fix (kullanıcı bug'ı: profile açınca premium rozetleri gelip kayboluyordu): `isDefinitelyFreeProvider` (subscription_repository) = subscription yüklendi VE free. Rozet GÖSTERİMİ artık bununla (settings Aile/Paylaşım + AI export, members Bakıcı akışı, memories kilit). Gating hâlâ isPremiumProvider.
- Premium iptal notu (kullanıcı isteği): premium_screen aktif bloğunda plan/kaynak satırı (_planLabel: lifetime/kod/dev/yenileme tarihi) + iptal bilgi kartı (_InfoCard: abonelik mağazadan iptal, dönem sonuna kadar açık / lifetime yenileme yok / kod-deneme bilgisi). Ayrıca DEV: RC yokken "Premium'u kapat (geliştirme)" → devActivate(active:false) (test için premium'u geri alma).
- Foto günlüğü duvarı: KALDIRILDI (kullanıcı düzeltmesi 2026-06-12: "her zaman buluta kaydedilsin"). 30 gün kilidi + premium/free bulut ayrımı silindi; fotoğraflar HERKESE her zaman buluta yedeklenir. memories_screen yeniden tasarlandı (scrapbook akışı: büyük foto kartları + ay ayraçları + "ilk" rozetleri + üstte tek "☁️ buluta yedekleniyor" çipi). premium_screen özellik listesinden "Bulut yedek + sınırsız foto" satırı çıkarıldı (artık 4 özellik: reklamsız/aile/gelişmiş grafik+PDF/sınırsız hatırlatıcı). Foto artık premium özelliği DEĞİL.
- Export kararı: AI export zaten premium-gated (_Upsell). Data export (JSON) GDPR "verini indir" hakkı → FREE kalır (gating yok). PDF/gelişmiş grafik export henüz BİR ÖZELLİK olarak yok (pdf üretimi yazılmadı) → ileride premium özellik.

**Premium cache + foto bulut ibaresi BİTTİ (2026-06-12, analyze temiz + APK):**
- Premium durumu kalıcı cache (kullanıcı isteği — flaş'ı tamamen bitir): `data/subscription_cache.dart` (secure storage `sub_is_premium`); repo get/refresh/redeem/devActivate her başarılı yanıtta `_store`→cache yazar; `cachedPremiumProvider` main()'de overrideWithValue ile açılışta okunan değere set; `isPremiumProvider` canlı yoksa cache'e düşer; `isDefinitelyFreeProvider`=!isPremium (artık cache sayesinde açılıştan doğru). logout'ta SubscriptionCache().clear() (kullanıcı sızması yok).
- Foto bulut ibaresi (kullanıcı isteği): memories_screen `_CloudBanner` — premium "Anıların buluta yedekleniyor", free "Premium ile kalıcı bulut yedeği + tüm geçmişe eriş" (→/premium). ☁️ emoji (cloud ikonu yok).
- Foto upload DOĞRULANDI: backend memories ImageField upload_to=memories/, DRF mutlak URL döner, DEBUG media serve; DB'de kayıt + media/memories/ dosyası mevcut → gerçekten buluta kaydediliyor. (Not: free fotolar da sunucuya yüklenir; premium farkı = kalıcı arşiv + 30g üstü erişim.)

**PDF sağlık raporu BİTTİ (2026-06-12, analyze temiz + APK + render doğrulandı):** "Gelişmiş grafik + PDF" premium özelliği gerçek yapıldı.
- Mimari kararı (kullanıcı önerisi — Flutter PDF yerine): backend render daha stabil + WHO motoru tek yerde. İstemci grafik için zaten hesapladığı veriyi (persentil + WHO eğrileri + 7-gün trend, tercih birimine çevrili) JSON POST eder; Django ReportLab ile deterministik PDF render edip indirtir.
- Backend: `apps/babies/report.py` `render_growth_report(payload)` (ReportLab: başlık + büyüme özet tablosu + ölçüm başına WHO LinePlot eğrisi + ölçüm geçmişi + 7-gün beslenme/uyku tablosu); `GrowthReportView` POST `/babies/<uuid>/report` (IsAuthenticated+IsBabyMember+**IsPremium**); requirements'a `reportlab` (4.5.1 kuruldu).
- Mobile: `features/charts/growth_report.dart` — `buildGrowthReportPayload(baby,records,units)` (charts_view ile aynı hesap; kanonik→tercih birimi) + `shareGrowthReport` (dio bytes → temp dosya → SharePlus). charts_view sonuna premium-gated `_ReportButton` ("📄 PDF sağlık raporu", free'de AdProBadge + requirePremium upsell).
- Render smoke testi geçti (3958 byte geçerli %PDF). Veri yoksa ilgili bölüm atlanır.
- ⚠️ Django sunucusu RESTART (yeni reportlab bağımlılığı + yeni view/url) — runserver autoreload kodu alır ama yeni paket için restart güvenli.

**HENÜZ YAPILMADI:** google_mobile_ads SDK + AndroidManifest app id eklenmedi (placeholder modunda). Tek-seferlik prune yalnız reminders ekranı açılınca/refetch'te (lazy). Token'lar (RC/AdMob/IAP) gelince gerçek akışlar otomatik aktif.

**Token bekleyen eksikler (kullanıcı verecek):** RevenueCat (REVENUECAT_ANDROID/IOS_KEY dart-define + backend .env SECRET_KEY/WEBHOOK_AUTH + dashboard ürün/offering/webhook); AdMob (ADMOB_ANDROID/IOS_INTERSTITIAL_ID dart-define + manifest app id + google_mobile_ads paketi). Hepsi config'te placeholder; set edilince çalışır.

⚠️ Migration 0003+0004 uygulandı → çalışan Django sunucusu **restart** edilmeli ([[api-degisiklik-izni]]).

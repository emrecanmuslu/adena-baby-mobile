# BULGULAR — Adena Baby Flutter mobil uygulaması kod denetimi

Tarih: 2026-10-11 · Sürüm: v1.4.26+65 (commit c8cebf5) · Kapsam: `lib/` altındaki 196 Dart dosyası (~52K satır), Android manifest/Gradle, iOS Info.plist/NSE/Widget (Swift), ilgili testler ve `../API_SOZLESME.md`. Hiçbir dosya değiştirilmedi.

Yöntem: çekirdek katman (açılış, auth, router, API istemcisi, senkron, drift, repository'ler, arka plan isolate, abonelik) satır satır elle okundu; özellik modülleri dört paralel okuma turunda tarandı ve her bulgu ilgili satırlar yeniden okunarak doğrulandı. Satır numaraları bu commit'e aittir. "Şüpheli: evet" olan maddeler ya bir uç zamanlamaya ya da bu depoda görülemeyen backend/platform davranışına dayanır; bunlar sonda ayrıca listelenmiştir.

Odak alanları: yarış durumları/asenkron, state tutarsızlıkları, yakalanmayan hatalar, ağ kesintisi/zaman aşımı/token süresi, arka plan→ön plan geçişleri, null/boş veri, iş mantığı.

---

## 1. Mimari ve ana akışlar

### 1.1 Katmanlar
- **Giriş (`main.dart`)**: `_step()` ile her açılış adımı zaman aşımlı (intl, Firebase 5 sn, LocalSession+SlotRegistry 5 sn, dil bundle'ı 2 sn, premium/tema/ana sayfa yerleşim cache'leri). Firebase başarısızsa arka planda 3 deneme. `runApp(RestartWidget(ProviderScope(AdenaApp)))` — `RestartWidget` dil/tema/wipe/ortam değişiminde yalnız widget ağacını (ProviderScope dahil) yeniden kurar, süreç ve `static` alanlar yaşamaya devam eder.
- **State**: flutter_riverpod 3.2 (`AsyncNotifier`/`Notifier`/`StreamProvider`). Önemli semantik: `ref.invalidate` sonrası state `AsyncData(eski, isLoading:true)` olur → `asData?.value` ESKİ veriyi döndürür; bağımlılık değişimiyle rebuild'de ise `AsyncLoading` olur → `asData` null döner. Kodda 119 yerde `.asData?.value` var; iki davranış farkı birkaç bulgunun kaynağı (K5, O3, D-tema).
- **Yönlendirme (`router.dart`)**: tek `redirect`; auth yüklenirken `/` (splash) → kullanıcı yoksa misafir dalı (yerel rıza → bebek → `/home`; bebeksiz `cycleFirst` dalı `/cycle`) ya da `/login`; kullanıcı varsa sunucu rızası → bebek → `/home`. `_RouterRefresh` auth/baby/guest/consent/cycleFirst/I18n/LocalSession.loadedTick değişimlerinde redirect'i yeniden koşturur.
- **HTTP (`core/api_client.dart`)**: Dio, 15 sn connect / 20 sn receive, `Accept-Language`, Bearer; 401'de tek-uçuş (single-flight) refresh, refresh 401/400'de token silme, geçici hatada koruma. Refresh için ayrı, zaman aşımsız Dio.
- **Kimlik (`features/auth/auth_controller.dart`, `data/local_session.dart`)**: `AuthController.build` token varsa önbellekteki kullanıcıyla anında döner, `/auth/me`'yi arka planda doğrular. `LocalSession` (SharedPreferences) misafir UUID'si, rıza, `activeAccountId` (yerel veri kapsamı), import/premiumSynced bayrakları. Misafir→hesap geçişinde `GuestMigration` `babies/cycle_entries.account_id`'yi rebind eder.
- **Yerel DB (`data/local/app_database.dart`)**: drift v14; tablolar Records, Babies, Memories, MomEntries, CycleSettings, CycleEntries, SyncCursors, HealthStatuses, LocalReminders, MedicationPlans. WAL + busy_timeout 8 sn, `shareAcrossIsolates` kapalı (her isolate kendi bağlantısı) → `refreshSyncedStreams()` öne gelişte/sync sonrası stream'leri zorla yeniler.
- **Repository'ler (`data/*_repository.dart`)**: local-first; yazım drift'e `dirty=true`, bulut uygunsa (`sync_gate.dart`: oturum ∧ kendi premium'um, paylaşılan bebekte sahibin premium'u) push. Records: delta `/sync` (cursor + LWW, uçuşta düzenleme koruması). Babies: `POST/PATCH /babies` + `GET /babies` reconcile (paylaşılan bebek listeden düşünce yerelden purge). Memories/Mom/Cycle: push dirty (bulk) + `GET` pull (yalnız upsert). Health: `/health/sync` tam-küme push; ilaç planları `/medication-plans/sync` (LWW, uuid, tombstone).
- **Senkron (`features/records/record_controller.dart` → `SyncService`)**: tetikler = bağlantı değişimi, öne geliş, bebek id-kümesi değişimi, kayıt yazımı, push `requestSyncSoon` (1.2 sn debounce), 1 dk polling (yalnız paylaşımlı bebek). `_running/_pending` ile çakışma önleme; 403 → bebek oturum-içi salt-okunur; durum `syncStatusProvider` → "Senkron sorunu" rozeti. `static wiping` bayrağı yerel silme sırasında turu durdurur.
- **Arka plan (`core/background_sync.dart`)**: workmanager 30 dk (Android), BGTask (iOS): ayrı isolate + ayrı `ProviderContainer`; yalnız paylaşımlı bebekler `repo.sync`, ardından widget + beslenme hatırlatıcısı `FeedReminderCache` snapshot'ından yeniden kurulur. FCM arka plan işleyicisi (`core/push_service.dart`) `sync_nudge`'da tek bebeği senkronlar.
- **Push/bildirim**: FCM yalnız aile etkinliği + topluluk; zaman-bazlı hatırlatıcılar yerel (`core/notification_service.dart`, id aralıkları: <600000 özel hatırlatıcı (drift localId), 600000 adet, 610000-670000 sağlık (slot/plan), 700000 aile, 800000/810000/820000 beslenme, 900000/910000 sayaç). `features/babies/notification_sync.dart` (`FamilyNotificationSync`, MaterialApp.builder'da her zaman ağaçta) provider'ları izleyip her bebek için bildirimleri her rebuild'de iptal edip yeniden kurar. Slot = `SlotRegistry` (prefs). "Sonraki beslenme" tek kaynağı `family_settings.dart`'taki `lastFeedRecord/nextFeedEstimate`; altı yazıcı (ana sayfa, `_WidgetSync`, `_BabyNotifSync`, bg sync, push handler, iOS NSE) App Group/prefs anahtarlarıyla (epoch ms) uyumlu doğrulandı.
- **Premium**: RevenueCat satın alma → backend `/subscription/refresh` → `subscriptionProvider`; gating `isPremiumProvider` (auth yüklenirken ve veri yokken açılışta okunan `cachedPremiumProvider` sabitine düşer). free→premium geçişinde `MigrationController` big-bang yükleme (markAllDirty + overlay); premium bitişinde "indir ve sil" (purge).
- **Adet modülü (`features/cycle/*`, `data/cycle_repository.dart`)**: hesap kapsamlı tekil ayar satırı + gün-başına kayıt; `computeStatus` saf motor (çapa = `firstPeriodDate`, akıllı tahmin = son N döngü ortalaması, DST-güvenli `cycleAddDays`); yaşam döngüsü tracking/ttc/pregnant/postpartum/loss; gebelik köprüsü gerçek `Baby(expecting)` üretir.
- **Sağlık (`data/health_repository.dart`)**: katalog (API → disk cache → gömülü asset tr/en) × bebek durumu (drift). Aşı anahtarı = yerelleştirilmiş ad.

### 1.2 Kritik akışlar (özet)
1. **Soğuk açılış**: main `_step`'ler → `AuthController.build` (önbellek) → router `/` → `BabyController.build` (drift stream + oturum varsa `_pull`) → `/home`; `_onForeground` ilk frame sonrası: `refreshSyncedStreams`, `babyController.refresh`, `repostActiveTimers`, FCM token kaydı, app-open reklam.
2. **Kayıt ekleme**: form → `RecordActions.upsert` → `upsertLocal` → `syncAll` (tamamlanmış beslenmede ≤10 sn beklenir) → post-frame reklam/puanlama → drift stream UI'ı günceller → `_BabyNotifSync` beslenme hatırlatıcısını/widget'ı yeniden kurar.
3. **Aile paylaşımı**: üye `repo.sync` ile LWW delta; push `family_activity` → ön planda `requestSyncSoon`, arka planda widget/hatırlatıcı + `refreshBabyFeedStateFromPush`.
4. **Misafir → hesap**: login → `_postLogin` (exitGuest, setActiveAccount, cacheAuthUser, `initialImport.runIfNeeded`) → AdenaApp dinleyicisi 1.2 sn sonra "aktaralım mı?" → `GuestMigration.migrate/discard`.
5. **Dil/tema/wipe**: ayar yazılır → `RestartWidget.restartApp` → tüm ağaç + ProviderScope yeniden; `static`'ler ve `main()` yan etkileri (dinleyiciler, Timer'lar) korunur.

---

## 2. Bulgu özeti

| Önem | Adet | Şüpheli işaretli |
|---|---|---|
| Kritik | 9 | 1 (K9 kısmen) |
| Orta | 37 | 5 |
| Düşük | 45 | 15 |

Önce bakılması önerilen sıra: K1, K3, K5 (bildirim/senkron sessiz arızaları, tek satırlık düzeltmeler) → K2, K4, O4-O7 (pull'un dirty'yi ezmesi ailesi; ortak çözüm "push başarısızsa satırı pull'da koru + tombstone") → K6-K8 (adet/misafir göçü) → K9/O35/O36 (bg isolate'te `LocalSession.ensureLoaded` + dispose sırası) → O1/O2 (auth zombi + refresh timeout).

---

## 3. KRİTİK bulgular

### K1. Çok-bebekte özel/randevu hatırlatıcıları birbirini iptal ediyor
- **Dosya:** `lib/core/notification_service.dart:470-477` (`_syncNow`), tetik `lib/features/babies/notification_sync.dart:371-386` (`_ReminderSync`), `lib/data/health_repository.dart:182-187`
- **Sorun:** `NotificationService.sync(list)` TEK bebeğin hatırlatıcı listesini alıyor (`reminders(babyId)` bebek filtreli) ama mutabakat adımı `_cycleBase`(600000) altındaki TÜM bekleyen bildirimleri bu listeye göre iptal ediyor: `if (p.id < _cycleBase && !activeIds.contains(p.id)) cancel`. `_ReminderSync` her bebek için ayrı çağrıldığından A bebeğinin sync'i B'nin randevu/özel hatırlatıcılarını, B'ninki A'nınkileri siler; `_syncChain` serileştirdiği için yalnız son çağrılan bebeğinkiler kalır. Her `FamilyNotificationSync` rebuild'inde (bebek listesi emit'i, öne geliş) tekrarlanır.
- **Koşul:** 2+ bebek ve en az birinde özel/randevu hatırlatıcısı.
- **Etki:** Bir bebeğin hatırlatıcıları hiç çalmaz; Hatırlatıcılar ekranında "açık" görünür.
- **Şüpheli:** hayır

### K2. `pullFromServer` yerel dirty bebek düzenlemesini ve yüklenmemiş fotoğrafı sessizce eziyor
- **Dosya:** `lib/data/baby_repository.dart:235-256` (`insertOnConflictUpdate … photo: Value(b.photo), dirty: const Value(false)`); çağıran `lib/features/babies/baby_controller.dart:120-122` (`pushDirty` → `pullFromServer`)
- **Sorun:** `pushDirty` satır başına her hatayı yutar (`baby_repository.dart:350-352`). Push 4xx alırsa (doğrulama hatası, 413 foto, bakıcı rolü filtresi — bkz. O20) ya da `MultipartFile.fromFile` dosya bulunamadığı için fırlatırsa satır dirty kalır; hemen ardından gelen `pullFromServer` sunucu kopyasını `dirty:false` ve sunucu `photo` değeriyle üstüne yazar → yerel ad/tarih/durum değişikliği ve seçilen yerel foto yolu kalıcı kaybolur, yeniden deneme de olmaz.
- **Koşul:** Push kısmen başarısızken pull'un başarılı olması (deterministik: her 4xx; ağ hatasında da push düşüp pull geçebilir).
- **Etki:** "Kaydedildi" denen bebek düzenlemesi bir sonraki öne gelişte geri alınır; foto kaybolur.
- **Şüpheli:** hayır

### K3. `SyncService.wiping` hiçbir yerde `false`'a dönmüyor → yerel silme sonrası senkron süreç ömrü boyunca kapalı
- **Dosya:** `lib/features/records/record_controller.dart:185` (tanım), `:231` (`if (wiping) return;`); set eden `lib/features/settings/privacy_screen.dart:248`, `lib/features/settings/dev_settings_screen.dart:165`
- **Sorun:** Bayrak `static`; `RestartWidget` yalnız widget ağacını yeniler, süreç ve static alan kalır. Bayrağı sıfırlayan tek satır yok (grep ile doğrulandı). `wipeAllData` fırlatırsa da `true` kalır.
- **Koşul:** "Yerel verileri sil" (ya da debug ortam değişimi) → aynı süreçte hesaba giriş / paylaşımlı bebek.
- **Etki:** `syncAll` her çağrıda `syncStatusProvider`'a dokunmadan erken döner: kayıt push/pull'u ve paylaşılan bebek senkronu uygulama öldürülüp açılana kadar çalışmaz; "Senkron sorunu" rozeti de çıkmaz (sessiz).
- **Şüpheli:** hayır

### K4. Aile paylaşımında sağlık durumu (aşı/gelişim/diş) hiç çekilmiyor; her push tam küme olduğundan diğer cihazın işaretlerini sunucuda siliyor
- **Dosya:** `lib/data/health_repository.dart:451-469` (`pushAll`), `:473-505` (`importFromCloud`), `:68-76` (`_setStatus`); çekme yalnız `lib/data/initial_import.dart:53-55` ve `lib/data/migration_service.dart:242-248`; `lib/features/records/record_controller.dart:260-261` (syncAll sağlık çekmez)
- **Sorun:** `vaccines()/milestones()/teeth()` kataloğun tamamını `done: s?.done ?? false` ile döndürür; `pushAll` bunların hepsini gönderir (fiilen replace-set). Sağlık durumunun tek çekme yolu hesabın ilk girişi ve free→premium göçü. İki cihaz sırayla işaretlerse sonuncunun bayat kümesi sunucuyu ezer; ilk cihaz bunu hiç öğrenmez, yeni cihaz/yeniden kurulum eksik veri indirir.
- **Koşul:** Premium/paylaşımlı bebekte birden fazla cihazın işaretleme yapması.
- **Etki:** Aşı/gelişim/diş işaretleri cihazlar arasında yakınsamıyor, sunucuda kaybolabiliyor; UI "ailen görür" vaadiyle çelişiyor.
- **Şüpheli:** hayır

### K5. Silinen/duraklatılan ilaç planının bildirimleri bayat provider listesinden yeniden kuruluyor
- **Dosya:** `lib/features/babies/notification_sync.dart:252-263` (`medPlans = ref.watch(medicationPlansProvider(baby.id)).asData?.value` → `syncMedicationPlan(enabled: … p.active …)`); `lib/features/health/medication_plan_sheet.dart:320-325` (`_togglePause`), `:327-336` (`_delete`)
- **Sorun:** `ref.invalidate(medicationPlansProvider)` sonrası yenileme sırasında `asData` ESKİ listeyi taşır (Riverpod 3 `copyWithPrevious(isRefresh:true)` → `AsyncData(…, isLoading:true)`; projenin kendi notu `notification_sync.dart:380-383`'te `_ReminderSync` için bunu `isLoading ? null` ile koruyor, `_HealthNotifSync`'te koruma yok). `_delete`: önce `cancelMedicationPlan`, sonra invalidate → `_HealthNotifSync` eski listeyle (plan aktif) rebuild olup günlük bildirimleri YENİDEN kurar; yeni liste gelince plan listede olmadığından kimse iptal etmez. Duraklatmada eski (aktif) ve yeni (pasif) çağrıların `await` zincirleri iç içe geçer.
- **Koşul:** Plan silme (yerel-only bebekte kalıcı; bulutlu bebekte sunucu `removed` dönene dek), plan duraklatma, başka cihazın duraklattığı planın senkronla gelmesi.
- **Etki:** Silinen plan için her gün "İlaç zamanı: X" bildirimi gelmeye devam eder.
- **Şüpheli:** hayır

### K6. Adet düzenleme takvimi çapayı "en eski işaretli gün"e çekip doğum/kayıp sıfırlamasını geri alıyor
- **Dosya:** `lib/features/cycle/cycle_period_adjust_sheet.dart:213-223` (`newAnchor = (_marked.toList()..sort()).first` → `patchSettings({'first_period_date': …})`)
- **Sorun:** `_marked` TÜM adet kayıtlarından kurulur; kaydette çapa sıfırlama olayına (doğum/kayıp, `cycle_repository.dart:360-368 _afterLatestReset`) bakılmadan en eski adet gününe eşitlenir. `saveEntry`'deki backfill koruması bypass edilir; patch'te `lifecycle_mode` olmadığından postpartum/loss'ta `patchSettings` (`cycle_repository.dart:84-96`) otomatik `tracking`'e de geçirir.
- **Koşul:** Doğum/kayıp öncesi adet geçmişi olan kullanıcı bu sheet'ten herhangi bir değişiklik kaydeder.
- **Etki:** Çapa doğum öncesine kurulur → "Döngü 7 · 190. gün / 150 gün gecikti" gibi çöp tahmin; lohusa kullanıcı istemeden aktif takibe geçer.
- **Şüpheli:** hayır

### K7. Bebeksiz (cycle-first) misafir hesap açınca adet verisi sessizce yetim kalıyor
- **Dosya:** `lib/data/guest_migration.dart:27-39` (`hasData`: yalnız `babies` sayılır)
- **Sorun:** "Aktaralım mı?" teklifi yalnız misafir kapsamında bebek varsa tetiklenir; `cycle_entries`/`cycle_settings_table` kontrol edilmez. Giriş sonrası `activeAccountId` değişir, adet verisi guest id altında görünmez olur.
- **Koşul:** "Bebeğim yok, adet takibi" dalında kayıt tutmuş misafirin kayıt olması.
- **Etki:** Aylarca tutulan adet kayıtları ve kurulum kaybolmuş görünür (sihirbaz baştan açılır), kullanıcıya hiç sorulmaz.
- **Şüpheli:** hayır

### K8. Misafir göçünde adet ayarı atılıyor: ilk import, sunucu varsayılanını önce yazmış oluyor
- **Dosya:** `lib/data/guest_migration.dart:70-97` (`if (newS == null) {…taşı…}` sonra misafir satırı `delete`); `lib/data/initial_import.dart:57-59` → `lib/data/cycle_repository.dart:251-257` (`importFromCloud` `_writeSettings(…, dirty:false)`)
- **Sorun:** `AuthController._postLogin` → `initialImport.runIfNeeded` (premium'dan bağımsız) → `GET /cycle/settings` sunucunun otomatik oluşturduğu boş varsayılan satırı yeni hesap id'siyle yerele yazar. Göç diyaloğu 1.2 sn sonra gelir; `newS != null` olduğundan misafir ayarı taşınmaz ve silinir. Ayrıca kopyalanan alan listesi `lifecycleMode/ttcStartedAt/predictionsHidden/lastLossDate/learningWindow`'u içermiyor (`:75-93`) ve `migrate()` cycle provider'larını invalidate etmiyor (yalnız `babyControllerProvider`).
- **Koşul:** Bebekli misafir adet kurulumunu tamamlamış (emzirme, çapa, mod) ve "Aktar" demiş.
- **Etki:** Kayıtlar taşınır ama çapa/mod/kurulum kaybolur; loss/postpartum kullanıcı `tracking + predictions_hidden=false`'a düşer, `lastLossDate` gidince backfill koruması da gider.
- **Şüpheli:** hayır

### K9. Arka plan isolate'inde `LocalSession.ensureLoaded()` çağrılmıyor → her 30 dk turunda tam cloud import başlıyor, bayrak prefs'leri eziliyor
- **Dosya:** `lib/core/background_sync.dart:52-57, 76-78` ve `:141-146`; `lib/features/auth/auth_controller.dart:32-38, 65-76` (`_refreshInBackground` → `runIfNeeded`); `lib/data/initial_import.dart:20-24`; `lib/data/local_session.dart:40-42, 259-274`
- **Sorun:** Bg isolate'te `container.read(authControllerProvider.future)` önbellekli kullanıcıyla anında döner ve `_refreshInBackground` unawaited sürer: `/auth/me` → `initialImport.runIfNeeded` → `_importedAccounts` bu isolate'te boş (`ensureLoaded` hiç çalışmadı) → `_import(acct)`: `pullFromServer` + tüm bebeklerin records/memories/mom/health sayfalı GET'leri + cycle. Tur sonunda `container.dispose()` DB'yi kapatır; import ya yarım kalır (hatalar yutulur) ya da tamamlanıp `markImportedForAccount`/`markPremiumSyncedForAccount` prefs'i yalnız `{acct}` ile yazar → ön planın çoklu-hesap bayrakları silinir. `refreshBabyFeedStateFromPush` aynı deseni taşır.
- **Koşul:** Oturum açık + paylaşımlı bebek (periyodik tur) ya da sync_nudge push'u.
- **Etki:** Her arka plan turunda gereksiz tam import trafiği (pil/veri), kapalı DB'ye yazım hataları, çoklu hesapta import bayraklarının bozulması (bir sonraki girişte yeniden tam import).
- **Şüpheli:** kısmen — mekanizma kesin; import'un dispose'dan önce ne kadar ilerlediği zamanlamaya bağlı.

---

## 4. ORTA bulgular

### Çekirdek / kimlik / API

#### O1. Refresh token reddedilince token siliniyor ama oturum durumu düşmüyor (zombi oturum)
- **Dosya:** `lib/core/api_client.dart:91-94`; `lib/features/auth/auth_controller.dart` (hiçbir dinleyici yok)
- **Sorun:** 401/400'de `_tokens.clear()` çağrılır, fakat `AuthController` state'i User olarak kalır; `loggedInProvider` true, `activeAccountId` dolu. Sonraki tüm istekler 401 alır, sync "Senkron sorunu" gösterir, kullanıcı giriş ekranına yönlendirilmez; ancak uygulama öldürülüp açılınca `hasSession=false` ile login görülür.
- **Koşul:** Refresh token'ın süresi dolması / sunucunun oturumu düşürmesi (tek-cihaz-oturum özelliği: başka cihazdan giriş!).
- **Etki:** Başka cihazdan giriş yapılan ilk cihazda saatlerce "senkron sorunu", bulut verisi gelmez; neden görünmez.
- **Şüpheli:** hayır

#### O2. Refresh isteği için zaman aşımı yok; tek-uçuş kilidi nedeniyle tüm 401'ler askıda kalır
- **Dosya:** `lib/core/api_client.dart:24-25` (`Dio(BaseOptions(baseUrl: …))` — connect/receiveTimeout yok), `:61-73`
- **Sorun:** Ölü/yalancı ağda `/auth/refresh` TCP düşene kadar (dakikalar) askıda kalır; o sırada 401 alan her istek `_refreshing` future'ını bekler. Ana Dio'nun 15/20 sn sınırı burada geçerli değil.
- **Koşul:** Token süresi dolmuşken bağlı-ama-internetsiz ağ.
- **Etki:** Açılış turu (babies/sync/me) ve "Kaydet" bekleyişi dakikalarca takılabilir.
- **Şüpheli:** hayır

#### O3. `isPremiumProvider` hata durumunda açılışta okunan SABİT cache'e düşüyor; satın alma sonrası çevrimdışı kalan kullanıcı free görünür
- **Dosya:** `lib/data/subscription_repository.dart:111, 135-139`; `lib/main.dart:224` (`cachedPremiumProvider.overrideWithValue(cachedPremium)` — bir kez)
- **Sorun:** `subscriptionProvider` `AsyncError`'a düşünce (invalidate sonrası GET hatası) ya da bağımlılık rebuild'inde (`authControllerProvider` emit'i → `AsyncLoading`) `asData` null → `cachedPremiumProvider`, yani açılıştaki değer. `SubscriptionCache` diske `'1'` yazılmış olsa bile runtime'da okunmaz. Not: `ref.invalidate` sırasında eski değer korunur (Riverpod 3 refresh semantiği), bu yüzden sorun yalnız hata/bağımlılık rebuild'inde.
- **Koşul:** Satın alma/kod kullanma sonrası `GET /auth/me/subscription` başarısız (çevrimdışı) ya da `_refreshInBackground`'un auth emit'i sırasında.
- **Etki:** Para ödemiş kullanıcıya kilit/reklam; uygulama yeniden açılınca düzelir.
- **Şüpheli:** hayır

#### O4. Aile ayarları (birim/sessiz saat/enabled_types) sunucudan hiç çekilmiyor; her üyenin push'u sunucuyu eziyor
- **Dosya:** `lib/data/baby_repository.dart:186-208` (`familySettings` yalnız yerel JSON), `:335-338` (`PATCH /babies/{id}/settings` yerel sözlükle), `lib/features/babies/family_settings.dart:34-37`; sözleşme `API_SOZLESME.md:189` GET/PATCH
- **Sorun:** `pullFromServer` `settings`'i almaz; `GET /babies/{id}/settings` kodda yok. Yeni cihaz/aile üyesi sahibin ayarlarını görmez; `updateFamilySettings` yerel sözlüğü `dirty` yapar, `pushDirty` tüm sözlüğü PATCH'ler → son yazan kazanır, yakınsama yok.
- **Koşul:** Paylaşımlı bebek / yeniden kurulum / ikinci cihaz.
- **Etki:** Birim (ml/oz) ve sessiz saat cihazlar arasında tutarsız; sahibin ayarı üyenin varsayılanıyla ezilebilir.
- **Şüpheli:** hayır

#### O5. Anı ve anne-takibi pull'u sunucudaki silmeleri yansıtmıyor; başarısız push'tan sonra dirty satırları eziyor
- **Dosya:** `lib/data/memory_repository.dart:36-48, 108-129, 148-182`; `lib/data/mom_repository.dart:26-38, 96-119`
- **Sorun:** (a) `_pull` yalnız upsert; sunucuda olmayan yerel `dirty=false` satırlar kaldırılmaz, tombstone okunmaz → A üyesinin sildiği anı B'de sonsuza dek kalır; B silmeye kalkarsa DELETE 404 yutulur, satır `dirty+isDeleted` olarak her listede yeniden denenir. (b) `list()` push→pull sırasında DELETE 5xx/timeout alıp GET geçerse `insertOnConflictUpdate(dirty:false)` (companion'da `isDeleted` yok) → `isDeleted=true, dirty=false`: bir daha push edilmez, kullanıcı da göremez.
- **Koşul:** Paylaşımlı bebekte silme; kısmi ağ hatası.
- **Etki:** Cihazlar arası hayalet anı/anne kaydı; sunucuda kalan "silinmiş" kayıt.
- **Şüpheli:** hayır

#### O6. Adet ayarında "sunucu kazanır": gönderilememiş yerel değişiklik ilk GET'te kalıcı kaybolur
- **Dosya:** `lib/data/cycle_repository.dart:32-47` (`getSettings` GET → `_writeSettings(dirty:false)`), `:78-107` (`patchSettings` önce `getSettings` çağırır), `:100-105` (PATCH hatası yutulur)
- **Sorun:** Dirty ayar satırını push etmeden sunucu kopyası üstüne yazılır; dirty ayarı yeniden deneyen tek yol `migrateToCloud` (yalnız göçte). `toPatchJson` `baby`'yi yalnız doluyken gönderdiğinden sunucuda `baby` hiç null'lanamaz.
- **Koşul:** Premium kullanıcı çevrimdışı mod/çapa/hatırlatıcı değiştirir, sonra herhangi bir ekran yenilemesi.
- **Etki:** Kayıp/doğum geçişi, çapa, hatırlatıcı ayarı sessizce eski hâline döner.
- **Şüpheli:** hayır

#### O7. Adet kayıtları pull'u kısmen başarısız push'ları ve silme tombstone'larını `dirty=false` yapıyor; sunucu silmeleri yayılmıyor
- **Dosya:** `lib/data/cycle_repository.dart:289-311` (`_pullEntries` upsert, `isDeleted` companion'da yok), `:325-330`
- **Sorun:** O5 ile aynı desen: bulk `failed` kalan ya da DELETE'i hata alan satır hemen ardından sunucu kopyasıyla ezilip dirty temizlenir; `GET /cycle/entries` tombstone döndürmediğinden A cihazında silinen gün B'de kalır.
- **Koşul:** Premium çok cihaz / geçici ağ hatası.
- **Etki:** Hayalet adet günü → döngü başlangıcı/ortalama yanlış; cihazlar farklı tahmin gösterir.
- **Şüpheli:** hayır

#### O8. Aynı güne çift adet kaydı: çift dokunma yarışı + sunucu gün-upsert'inin id değiştirmesi
- **Dosya:** `lib/features/cycle/cycle_today_screen.dart:97-117` (`_quickStartPeriod`, `_saving` yok), `lib/features/cycle/cycle_calendar_screen.dart:862-878, 914-921`; `lib/data/cycle_repository.dart:173-181` (existing arama), `:343-353` (`saved` id eşleme)
- **Sorun:** Hızlı çift dokunuşta iki `saveEntry` aynı anda `existing == null` görüp iki UUID üretir. Backend aynı gün varsa mevcut satırı güncelleyip kendi pk'sini `saved`'e koyar → yerel id eşleşmez, satır her `listEntries`'de yeniden push edilir; pull sunucu id'li ikinci satırı indirir.
- **Koşul:** Çift dokunma; iki kaynak aynı güne farklı id ile yazmış (iki cihaz, misafir göçü + bulut).
- **Etki:** Listede aynı gün iki satır, her ekran yüklemesinde gereksiz bulk POST, dirty asla temizlenmez.
- **Şüpheli:** hayır

#### O9. Kayıt senkronu tüm dirty satırları tek, sınırsız POST'ta gönderiyor
- **Dosya:** `lib/data/record_repository.dart:210-238`; göç `lib/data/migration_service.dart:101-106, 151-155` (`markAllDirty` → `sync`)
- **Sorun:** Binlerce kayıt tek gövde; receiveTimeout 20 sn. Zayıf ağda timeout → `applied` gelmez → her turda aynı dev istek tekrarlanır (sonsuz başarısız tur, "Senkron sorunu" kalıcı). Mom/cycle bulk'ta 1000 sınırı var, records'ta yok.
- **Koşul:** Uzun geçmişi olan kullanıcının free→premium geçişi ya da purge sonrası tam yeniden yükleme, zayıf ağ.
- **Etki:** Göç hiç tamamlanamaz; overlay "bitti" der ama veri buluta çıkmaz.
- **Şüpheli:** hayır

#### O10. Hesap silme: geri alınamayan yerel yan etkiler, ağ isteğinden ÖNCE çalışıyor
- **Dosya:** `lib/features/auth/auth_controller.dart:170-182`
- **Sorun:** `PushService.unregister`, `NotificationService.cancelAll`, `SlotRegistry.clear` → sonra `_repo.deleteAccount()` (ağ). İstek başarısız olursa hesap durur, kullanıcı oturumda kalır ama tüm yerel bildirimler iptal, slot haritası sıfırlanmış (sonraki `slotFor` farklı slot verir, eski zamanlanmış id'ler artık eşleşmez).
- **Koşul:** Hesap silme sırasında ağ/sunucu hatası.
- **Etki:** Hatırlatıcılar sessizce gider; kullanıcı neden görmez.
- **Şüpheli:** hayır

#### O11. "Kaydet → sunucu onayını bekle" sözü, bir tur zaten sürüyorsa tutulmuyor
- **Dosya:** `lib/features/records/record_controller.dart:234-237, 362-377`
- **Sorun:** `syncAll` `_running` ise `_pending=true` deyip hemen döner → `_saveAndSync` beklemeden geçer; kayıt bir sonraki turda gider. Ayrıca `onlineProvider.asData` henüz yokken `?? true` → çevrimdışı olsa da 10 sn beklenir.
- **Koşul:** Push/polling turu sürerken tamamlanmış beslenme kaydı.
- **Etki:** Kullanıcı kaydeder kaydetmez uygulamayı kapatırsa kayıt eşe geç ulaşır (tasarımın önlemeye çalıştığı durum).
- **Şüpheli:** hayır

#### O12. Satın alma başarılı ama backend refresh hatası → kullanıcıya "hata" gösterilip premium açılmıyor
- **Dosya:** `lib/features/settings/premium_screen.dart:473-500`; aynı kalıp `lib/features/onboarding/premium_welcome_screen.dart:141-165`
- **Sorun:** `RevenueCatService.purchase` başarılıyken `refresh()` (POST /subscription/refresh) fırlatırsa genel `catch`'e düşer: `subscriptionProvider` invalidate edilmez, "Premium etkinleştirildi" yerine "Sunucuya ulaşılamadı…" gösterilir, ekran kapanmaz.
- **Koşul:** Ödeme bitince bağlantı kopması / backend geçici hata.
- **Etki:** Para ödenmiş anda hata mesajı; RC dinleyicisi ya da yeniden açılış düzeltir (D22 ile birlikte düzelmeyebilir).
- **Şüpheli:** hayır

### Senkron / arka plan / bildirim

#### O13. "Bugün" özeti gece yarısından sonra bir önceki günü de sayıyor
- **Dosya:** `lib/features/records/record_controller.dart:127-134` (`todayRecordsProvider`: `DateTime.now()` kuruluşta bir kez, autoDispose değil, invalidate eden yok); tüketici `lib/features/home/home_screen.dart:1627`
- **Koşul:** Uygulama öldürülmeden gece yarısını geçmek (arka planda bekleyip sabah açmak).
- **Etki:** Ana sayfa "Bugün" kartı dünkü kayıtları da toplar; yalnız tam kapat-aç düzeltir.
- **Şüpheli:** hayır

#### O14. Periyodik bildirimler her rebuild'de sıfırlanıyor → 14 günlük gelişim/diş dürtmesi ve "her X dk" hatırlatıcılar fiilen hiç çalmıyor
- **Dosya:** `lib/features/babies/notification_sync.dart:329-352` (`_HealthNotifSync`), `:371-386` (`_ReminderSync`); `lib/core/notification_service.dart:650-668, 513-523` (`cancel` + `periodicallyShowWithDuration`)
- **Sorun:** Build içi yan etki; üst `FamilyNotificationSync` `babyControllerProvider` her emit ettiğinde (öne geliş `refresh()`, her sync turu, herhangi bir provider değişimi) iptal + yeniden kurulum → ilk tetik "şimdi + aralık"a kayar.
- **Koşul:** Uygulamayı 14 günde bir kez bile açan herkes.
- **Etki:** Gelişim/diş kontrol bildirimleri ölü; "her 15 dk ateş takibi" her öne gelişte yeniden başlar.
- **Şüpheli:** hayır

#### O15. Bebek silinince / erişim kalkınca sağlık ve ilaç bildirimleri yetim kalıyor
- **Dosya:** `lib/features/babies/baby_controller.dart:90-93` (`deleteBaby` hiç iptal etmez), `:126-147` (erişim kaldırma yalnız feed+uyku+emzirme iptal eder)
- **Sorun:** Aşı (610000+slot), atak, büyüme, gelişim/diş (periyodik!), ilaç (670000+) bildirimleri cihazda kalır; o bebeğin `_HealthNotifSync`'i ağaçtan düştüğü için bir daha temizlenmez; slot haritadan silinmez.
- **Koşul:** Bebek silme ya da paylaşımdan çıkarılma.
- **Etki:** Olmayan bebek için "Aşı zamanı", "İlaç zamanı", 14 günde bir gelişim dürtmesi; çıkışa (cancelAll) kadar.
- **Şüpheli:** hayır

#### O16. Android 14+: açılışta izin açıklaması olmadan sistem "Alarmlar ve hatırlatıcılar" sayfasına atılma
- **Dosya:** `lib/core/notification_service.dart:113-119` (`_ensureExactAlarm` → `requestExactAlarmsPermission`), çağrılar `:338, 514, 542`; `android/app/src/main/AndroidManifest.xml:6` (`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` değil)
- **Sorun:** Android 14+'ta bu izin yeni kurulumda varsayılan RET; plugin izin yoksa sistem ayar Activity'sini açar. `syncVaccineReminder → _scheduleOnce` açılışta `FamilyNotificationSync` build'inde koşuyor; süreç başına bir kez ama her soğuk açılışta.
- **Koşul:** Android 14+, doğmuş bebek ya da beslenme hatırlatıcısı açık, izin verilmemiş.
- **Etki:** Her açılışta açıklamasız Ayarlar'a zıplama → "bozuk" algısı.
- **Şüpheli:** evet — Android 14 varsayılan-ret davranışı dokümante, cihazda doğrulanmadı.

#### O17. Push/NSE yolu çapa için "gelecek tarih eşiği" ve "en yeni kayıt" kuralını uygulamıyor
- **Dosya:** `lib/core/push_service.dart:83, 166, 213`; `ios/NotificationService/NotificationService.swift:68-83, 113-116`
- **Sorun:** Ön plan/bg sync `lastFeedRecord` (son 15 içinde en yeni, `now+1sa` üstü hariç, süren emzirme hariç) kullanırken push ve NSE push'taki `last_feed_ts`'i doğrudan çapa yapar: eşin ileri tarihli girdiği kayıt widget'ı/hatırlatıcıyı günler sonrasına kurar; geriye tarihli ek kayıt mevcut daha yeni çapayı geri çeker. Bg turu/öne geliş düzeltir → widget ileri-geri oynar. (Aralık/baz türü kuralı altı yazıcıda aynı — doğrulandı.)
- **Koşul:** Başka üyenin ileri/geri tarihli beslenme girmesi, bu cihazın arka planda olması.
- **Etki:** Geçici yanlış "sonraki beslenme" + yanlış zamana hatırlatıcı (≤30 dk; iOS force-quit'te açılışa kadar).
- **Şüpheli:** evet — backend `last_feed_ts`'in "eklenen" mi "en yeni" kayıt mı olduğu bu depoda görülemiyor.

#### O18. `FirebaseMessaging.onMessage` dinleyicisi dispose'da iptal edilmiyor → RestartWidget sonrası eski dinleyici yaşıyor
- **Dosya:** `lib/main.dart:310-321` (initState), `:328-332` (dispose yalnız observer kaldırır)
- **Sorun:** Dil/tema/wipe/ortam değişimi `_AdenaAppState`'i yeniden kurar; eski `dispatch` closure'ı disposed `WidgetRef` ile `ref.read` yapar (flutter_riverpod 3.x'te `StateError`), her push çift sevk edilir (`requestSyncSoon` debounce ve banner event_id dedup'ı zararı azaltır).
- **Koşul:** Oturumda en az bir kez dil/tema değişimi + sonrasında push.
- **Etki:** Yakalanmayan async hata → `platformDispatcher.onError` bunu Crashlytics'e `fatal:true` olarak raporlar (sahte çökme kaydı); işlevsel etki düşük.
- **Şüpheli:** evet — release'te disposed ref davranışı doğrulanmadı.

### Sağlık / ilaç / gelişim

#### O19. Aşı durum anahtarı = yerelleştirilmiş aşı adı; dil değişince ve farklı dildeki aile üyeleri arasında eşleşmiyor
- **Dosya:** `lib/data/health_catalog.dart:24` (`j['key'] ?? j['name']` — asset'te key == name), `:100` (`_locale` yalnız en/tr); `lib/data/health_repository.dart:458, 480`
- **Sorun:** TR katalogda key "Hepatit B (1. doz)", EN'de "Hepatitis B (1st dose)" (listeler de farklı uzunlukta). Dil değişince aşılar "yapılmadı" görünür; push EN adlarla gider, sunucu satırları ilk istek diline göre üretildiğinden eşleşmez (sessiz no-op); `importFromCloud` sunucu dilindeki adı yazar. zh/hi/es/fr/ar için çevrimdışı katalog TR'dir.
- **Koşul:** Dil değişimi; farklı dilde iki aile üyesi; 5 ek dil kullanıcısının çevrimdışı ilk açılışı.
- **Etki:** Aşı işaretleri kaybolmuş gibi görünür / aileye yansımaz.
- **Şüpheli:** hayır

#### O20. Bakıcı (caregiver) bebek bilgilerini düzenleyip "Kaydedildi" görüyor; değişiklik sessizce geri alınıyor
- **Dosya:** `lib/features/babies/baby_edit_screen.dart:147-178` (`_save`), `:393-401` ("Bebeğim doğdu"); `lib/data/baby_repository.dart:301-306` (rol filtresi caregiver'ı göndermez)
- **Sorun:** `_pickPhoto` `canFullWrite` ile korunmuş ama `_save` ve born-flow korunmamış. Caregiver satırı `pushDirty`'de filtrelenir, `pullFromServer` `dirty:false` ile sunucu değerini üstüne yazar (K2 mekanizması).
- **Koşul:** Rolü caregiver olan üye ad/tarih/durum değiştirir.
- **Etki:** Toast "Kaydedildi", bir sonraki pull'da geri döner; "doğdu" geçişi bekleme moduna düşer.
- **Şüpheli:** hayır

#### O21. Aşı/gelişim/diş işaretleme bulut açıkken `pushAll` ağ isteğini bekliyor; hata yutuluyor, yeniden deneme yok
- **Dosya:** `lib/data/health_repository.dart:68-76`; `lib/features/health/vaccines_screen.dart:338-345` (meşgul durumu yok); `lib/features/development/teeth_screen.dart:589-592`; `milestones_screen.dart:138-142, 482-488`
- **Sorun:** Yerel yazım anında biter ama çağıran `await pushAll` ile 15-35 sn ağı bekler, `invalidate` ondan sonra; kullanıcı tepki alamayınca tekrar dokunur. Sağlık durumunda `dirty` bayrağı yok → çevrimdışı işaret ancak bir sonraki çevrimiçi işaretle gider, kullanıcı öğrenmez.
- **Koşul:** Bağlı-ama-internetsiz ağ; premium/paylaşımlı bebek.
- **Etki:** Satır 15-35 sn tepkisiz; sunucuya gitmeyen işaret.
- **Şüpheli:** hayır

#### O22. Doz "verildi" düğmesinde çift-dokunma/uçuş koruması yok → aynı doz için iki kayıt
- **Dosya:** `lib/features/health/medication_widgets.dart:111-116, 165-191`
- **Sorun:** Rol kontrolü build anındaki `dose` nesnesine göre; drift stream yeni kaydı yayınlayana kadar ikinci dokunuş da `next` görür. 2 dozlu planda ikinci doz da "verildi" olur; tek dozlu planda akışta hayalet ilaç kaydı (aile de görür).
- **Koşul:** Hızlı çift dokunuş.
- **Etki:** Yanlış "verildi" özeti; çift doz riski.
- **Şüpheli:** hayır

### Adet modülü

#### O23. Gebelikten "Adet takibine dön": bekleyen bebek yetim kalıyor, eski LMP çapasıyla "N gün gecikti"
- **Dosya:** `lib/features/cycle/cycle_loss.dart:99-102` (`choice == 'tracking'`), `:44-50`
- **Sorun:** `CycleModeSwitcher._select` pregnant→tracking'i bu kapıya yönlendirir, ama seçenek `Baby(status=expecting)`'e ve `baby` bağına dokunmaz; çapa (LMP) kalır. Matrisin "yetim expecting bebek kalmasın" değişmezi ihlal.
- **Koşul:** Gebelik modunda "Durumu güncelle → Adet takibine dön".
- **Etki:** Ana sayfa gebelik göstermeye devam eder; adet ekranı "95 gün gecikti" der.
- **Şüpheli:** evet (çapa kısmı "yanlış alarm" senaryosunda kasıtlı olabilir; yetim bebek kısmı değil)

#### O24. Bekleme modundaki bebeksiz kullanıcı loşia rengi girebiliyor → motor kalıcı "lohusalık" moduna kilitleniyor
- **Dosya:** `lib/features/cycle/cycle_engine.dart:146-148` (`hasLochia && (sinceBirth == null || …)`); `cycle_today_screen.dart:77-81`; `cycle_calendar_screen.dart:285-288, 658-661`; `cycle_entry_sheet.dart:257-268`
- **Sorun:** Kayıt sheet'i `active` dışındaki her modda loşia satırını gösterir; `birthDate == null` ise tek loşia kaydı motoru süresiz `lochia`'ya alır; loşialı kayıt `isPeriod=false` olduğundan çapa da kurulamaz.
- **Koşul:** Doğum/LMP girilmemiş kullanıcı "Kayıt ekle"de renk seçer.
- **Etki:** "Doğum +0 gün · Lohusalık", takvimde adet düzenleme gizlenir; çıkış için kaydı silmek gerekir.
- **Şüpheli:** hayır

#### O25. Adet hatırlatıcıları yalnız Ayarlar ekranında yeniden planlanıyor
- **Dosya:** `lib/features/cycle/cycle_settings_screen.dart:111-137` (tek `syncCycle` çağrısı)
- **Sorun:** `saveEntry`/adjust sheet/ilk adet/kayıp/doğum geçişleri `syncCycle` çağırmaz; `nextPeriod` kayınca bildirim eski tarihte kalır; kayıp/postpartum'a geçince doğurganlık bildirimi iptal edilmez.
- **Koşul:** Hatırlatıcı açık, sonra yeni adet loglanır veya mod değişir.
- **Etki:** "Adetin yaklaşıyor" yanlış günde; iyileşme modundaki kullanıcıya "Doğurganlık pencereniz başlıyor".
- **Şüpheli:** hayır

#### O26. Premium'da her adet ekranı yüklemesi ağı bekliyor (local-first değil)
- **Dosya:** `lib/data/cycle_repository.dart:35-42, 150-155`; `lib/core/api_client.dart:21-22`
- **Sorun:** `cycleSettingsProvider`/`cycleEntriesProvider` her invalidate'te önce GET/POST'u bekler; `cloudSyncEnabledProvider` çevrimiçi durumunu hesaba katmaz.
- **Koşul:** Premium + bağlı-ama-erişimsiz ağ.
- **Etki:** Her kayıttan sonra 15-35 sn spinner; kullanıcı tekrar basar (O8'i tetikler).
- **Şüpheli:** hayır

### Ana sayfa / kayıt

#### O27. Uyku elle girişinde bitiş < başlangıç doğrulanmıyor → negatif süre kaydediliyor
- **Dosya:** `lib/features/records/record_form.dart:316-322, 1218-1222`; `lib/features/records/record_controller.dart:464-476` (`stopSleep` de clamp'lemez)
- **Koşul:** Saat seçicide bitiş başlangıçtan önce; ya da başka cihazın saat sapması.
- **Etki:** "Uyku · -1 sa -5 dk", günlük toplam azalır, grafik çubuğu negatif; recap `d > 0` ile atar, diğer yerler atmaz.
- **Şüpheli:** hayır

#### O28. Emzirme: duraklatmışken meme değiştirip kaydedince hayalet dakika ekleniyor
- **Dosya:** `lib/features/records/record_controller.dart:494-507` (`_accrueBreast` sonda `seg_start_ts = now`, `paused` korunur), `:531-537` (`switchBreastSide`), `:558-566` (`stopBreast` `paused`'a bakmaz); UI `record_form.dart:795`
- **Koşul:** Durdur → Sol/Sağ geçişi → Kaydet (Devam et'e basmadan).
- **Etki:** Kaydedilen dakika, ekranda gösterilenden duraklama süresi kadar fazla.
- **Şüpheli:** hayır

#### O29. DST uygulayan bölgelerde gün aritmetiği `Duration(days:)` / `.inDays` ile yapılıyor → 1 gün kayma (modüller arası)
- **Dosya:** `lib/features/records/timeline_view.dart:43-46`; `lib/features/charts/charts_view.dart:782-784, 816-820`; `growth_report.dart:132-142`; `lib/features/home/home_screen.dart:132-135, 1738-1741`; `yesterday_recap_sheet.dart:44-46`; `lib/core/yesterday_recap.dart:255, 264`; `record_ui.dart:106-115`; `lib/core/leaps.dart:14, 17, 50`; `lib/core/age.dart:32, 113, 132, 169, 188`; `notification_sync.dart:314, 360`; `lib/features/cycle/cycle_engine.dart:82` (`_diffDays`), `cycle_calendar_screen.dart:429, 436, 1062`, `cycle_period_adjust_sheet.dart:134-165`, `cycle_pregnancy_bridge.dart:37-40` (`l.add(Duration(days:280))`)
- **Sorun:** Yerel gece-yarısı `DateTime` + 24n saat, DST geçişini aşınca 23:00/01:00 üretir; `.inDays` 23 saati 0 sayar. Etkiler: akışta "‹" ile bir gün atlanır, 7-gün grafik anahtarı eşleşmez (o günün kayıtları düşer), dün özeti yanlış güne kurulur, düzeltilmiş yaş/atak haftası/gebelik haftası 1 kayar, adet "gün N"/geri sayım 1 eksik, adjust sheet'te 01:00'lik gün `_marked.contains` eşleşmesini bozar, `pregnancyFromLmp` TDT'yi 1 gün erken üretir (`Baby.dueDate`).
- **Koşul:** DST uygulayan ülke (EU/US; TR değil) — yılda 2 geçiş, haftalarca etkili olanlar var.
- **Etki:** Görünür tutarsızlıklar; veri kaybı yok. `cycleAddDays` DST-güvenli ama yaygın kullanılmamış.
- **Şüpheli:** hayır (mekanizma kesin; pazar TR ağırlıklı)

### Ayarlar / gizlilik / içerik

#### O30. Anılar ekranı free/misafir kullanıcıya koşulsuz "Anıların buluta yedekleniyor" rozeti gösteriyor
- **Dosya:** `lib/features/memories/memories_screen.dart:103-106` (koşulsuz), `:245-270`
- **Sorun:** `MemoryRepository` yalnız bulut-uygun bebekte push eder; Veri & Gizlilik ekranı aynı kullanıcıya "verin yalnız bu cihazda" der.
- **Etki:** Kullanıcı fotoğraflarının yedeklendiğini sanır; telefon kaybında veri kaybı; mağaza/KVKK açısından yanıltıcı beyan.
- **Şüpheli:** hayır

#### O31. Yasal belgeler yalnız tr/en: 5 ek dil kullanıcısına Türkçe gizlilik/şartlar açılıyor
- **Dosya:** `lib/core/legal_links.dart:24` (`locale == 'en' ? 'en' : 'tr'`)
- **Koşul:** Uygulama dili zh/hi/es/fr/ar.
- **Etki:** Rıza alınan metni kullanıcı okuyamaz (bilgilendirilmiş rıza ve Apple 3.1.2(c) açısından zayıf); İngilizce'ye düşmeliydi.
- **Şüpheli:** hayır

#### O32. "Verilerimi indir" yerel export'u eksik: sağlık durumu, hatırlatıcı, ilaç planı, bebek foto/prematüre alanları yok
- **Dosya:** `lib/features/settings/data_export.dart:75-141`
- **Koşul:** Free/misafir kullanıcı — ekran metni "önce yedek al" diye buna yönlendiriyor.
- **Etki:** Yedek sanıp "Yerel verileri sil" yapan kullanıcı aşı/gelişim/diş işaretlerini, ilaç planlarını ve bebek fotoğrafını kaybeder.
- **Şüpheli:** hayır

#### O33. "Yerel verileri sil" anı fotoğraflarını diskte bırakıyor, zamanlanmış bildirimleri ve prefs store'larını temizlemiyor
- **Dosya:** `lib/features/settings/privacy_screen.dart:247-251`; `lib/data/local/app_database.dart:379-385`
- **Sorun:** Wipe yalnız tabloları siler; `ApplicationSupport/memories/*` ve `babies/*` dosyaları, `NotificationService.cancelAll`, feed-reminder/notif-pref/SlotRegistry prefs'leri dokunulmaz.
- **Ek (2026-10-11, commit 4 sonrası):** Aynı aile: anı pull'unda R4 ile silinen (başka üyenin sildiği) anının yerel fotoğraf dosyası (`memories/<id>.<ext>`) da diskte kalıyor; `_pull` yalnız satırı siler. Düzeltme yapılmadı, bu maddeyle birlikte ele alınmalı.
- **Etki:** "Kalıcı silinecek" denen fotoğraflar kalır; silinmiş bebeğin hatırlatıcıları çalmaya devam edebilir.
- **Şüpheli:** hayır (bildirim kısmı cihaz durumuna bağlı)

### Diğer çekirdek

#### O34. `_refreshInBackground` ile `logout()` yarışı: çıkış sonrası eski `/auth/me` yanıtı oturumu geri getiriyor
- **Dosya:** `lib/features/auth/auth_controller.dart:65-76, 184-197`
- **Sorun:** `ref.mounted` notifier dispose'unu kapsar, logout'u kapsamaz; `me()` logout'tan sonra dönerse `state = AsyncData(user)` + `cacheAuthUser` yeniden yazılır.
- **Koşul:** Açılıştan hemen sonra çıkış, yavaş `/auth/me`.
- **Etki:** Çıkış yapılmış kullanıcı oturumda görünür (token yok → 401'ler, O1 ile birleşir).
- **Şüpheli:** evet (pencere dar)

#### O35. `LocalSession` bayrak setleri bellek-içi; arka plan isolate ve zaman aşımı sonrası yazımlar prefs'i eziyor
- **Dosya:** `lib/data/local_session.dart:40-42, 259-284`
- **Sorun:** `markImportedForAccount` vb. `Set.join(',')` ile tüm listeyi yazar; bg isolate (K9) ya da `ensureLoaded` tamamlanmadan (`main.dart:189-191` 8 sn güvenlik ağı) yapılan yazım diğer hesapların bayraklarını siler.
- **Etki:** Çoklu hesapta yeniden tam import / yeniden "buluta yükleniyor" overlay'i.
- **Şüpheli:** hayır

#### O36. Arka plan turu `container.dispose()` ile süren işin altından DB'yi çekiyor
- **Dosya:** `lib/core/background_sync.dart:52-57, 76-78, 141-168`
- **Sorun:** `authControllerProvider.future` önbellekle anında döner; `_refreshInBackground` (K9) ve `BabyController._pull` unawaited sürerken `finally` DB'yi kapatır → kapalı DB'ye yazım hataları (yutulur), `DbWatchdog.markBackgroundSync('bitti')` yanlış damga.
- **Etki:** Yarım kalan import/pull, teşhis telemetrisinde yanıltıcı "bitti".
- **Şüpheli:** hayır

#### O37. Kayıt düzenleme formu `createdBy`'ı düşürüyor
- **Dosya:** `lib/features/records/record_form.dart:359-365` (`Record(…)` yeni nesne, `copyWith` değil)
- **Etki:** Sunucu echo'su gelene kadar akışta "X ekledi" kaybolur; bakıcı rolünde `canDelete` (`createdBy == me.id`) kendi kaydı için false'a düşebilir.
- **Şüpheli:** hayır

---

## 5. DÜŞÜK bulgular

### Çekirdek / API
- **D1.** `lib/core/api_client.dart:46-48` — retry `dio.fetch` DioException ile düşerse yutulup orijinal 401 `handler.next` ile geçer; çağıran gerçek hatayı (500/timeout) değil 401'i görür, `apiErrorText` "tekrar giriş yap" der. Şüpheli: hayır.
- **D2.** `lib/core/token_storage.dart:24-33` — `saveTokens` delete→write atomik değil; arada okuyan istek Authorization'sız gider → 401 → retry (kendini onarır); arada crash oturum kaybı. Şüpheli: hayır.
- **D3.** `lib/data/record_repository.dart:230-256` — `sentStamp` eşitliği drift'in saniye hassasiyetinde; uçuş sırasında AYNI saniyede yeniden düzenlenen kayıt "applied" sayılıp `dirty=false` olur, ikinci düzenleme gönderilmez (`health_repository._planStamp` bunu planlar için çözmüş, records için yok). Şüpheli: hayır (nadir).
- **D4.** `lib/main.dart:335-347, 353-379` — `appInForeground` yalnız `resumed`'da true; `inactive` (bildirim paneli, iOS app switcher) → false → push gelirse `handlePushMessage` OS bildirimi basar VE main `dispatch` in-app banner da gösterir → çift. Şüpheli: hayır.
- **D5.** `lib/core/push_service.dart:251-306` — `registerToken` her resume + auth listener'da; iOS'ta 15 sn APNs polling; eşzamanlı çağrı guard'ı yok → paralel polling/çift POST (idempotent). Şüpheli: hayır.
- **D6.** `lib/data/subscription_repository.dart:149-160`; `lib/core/revenuecat_service.dart:64-67` — `premiumSyncProvider` `addUpdateListener` RC `_configured` değilse no-op; `configure()` main'de unawaited → ilk `AdenaApp.build` çoğunlukla sonra ama garanti değil → RC dinleyicisi hiç kurulmayabilir (webhook + manuel refresh telafi eder). Şüpheli: evet.
- **D7.** `lib/data/baby_repository.dart:376-385` — `acceptInvitation` → `create(baby)` `myRole ?? 'owner'`; `/invitations/accept` yanıtındaki `baby` `my_role` taşımıyorsa üye bebeği 'owner' olur → `pushDirty` POST /babies 403 (yutulur), pull düzeltene kadar. Şüpheli: evet (sözleşmede alan listesi yok).
- **D8.** `lib/main.dart:189-191` — 8 sn güvenlik ağı `markLoaded` sonrası `ensureLoaded` geç biterse router önce varsayılanlarla `/login`'e, sonra `/home`'a sıçrar (flaş). Tasarım gereği degrade. Şüpheli: hayır.
- **D9.** `lib/data/local_session.dart:162-169` — `enterGuest` userId üretimi prefs yazımı başarısızsa `_activeAccountId` set edilmez → misafir bebek `account_id=null` → görünmez, onboarding döngüsü. Şüpheli: hayır (prefs hatası nadir).
- **D10.** `lib/data/migration_service.dart:73-84, 138` — `run()` guard'ı ile `state=running` arasında await'ler var; `GuestMigration.migrate` (`guest_migration.dart:111`) ile `localToCloudMigrationProvider` (`:286-293`) aynı anda tetiklenirse iki paralel tam yükleme (idempotent, overlay flicker). Şüpheli: hayır.
- **D11.** `lib/data/memory_repository.dart:166-167, 184-197`; `lib/data/baby_repository.dart:152-172` — `_persistPhoto` kopyalama hatasında image_picker GEÇİCİ yolunu döndürür; OS temizleyince foto kaybolur; `MultipartFile.fromFile` fırlatır → satır sonsuza dek dirty, sessiz (bebekte K2 fotoyu sunucu değeriyle ezer). Şüpheli: hayır.
- **D12.** `lib/features/babies/baby_controller.dart:138-146` — erişim kaldırmada `cancelTimer`/`scheduleFeedReminder(enabled:false)` unawaited; `showActivity` sıra garantisi yok (zararsız). Şüpheli: hayır.
- **D13.** `lib/features/settings/theme_controller.dart:20-33` — misafirde `build()` `cachedThemeProvider` sabitine döner; `setMode` sonrası auth state her değişince (yanlış şifre → AsyncError, sosyal iptal) tema açılış değerine geri döner; restart'ta düzelir. Şüpheli: hayır.
- **D14.** `lib/features/settings/locale_controller.dart:15-50, 62` — `build()` `authControllerProvider`'ı watch eder → her auth emit'inde `_activate` → `repo.sync(locale)` ağ isteği + `updateSettings`; `setLocale` → `_activate` ağ senkronunu (15 sn) bekler, UI'da spinner yok, `language_quick_pick.dart:52-55` tekrar basılabilir. Şüpheli: hayır.
- **D15.** `lib/data/local/app_database.dart:363-375` — `refreshSyncedStreams` her resume + her sync turunda 9 tablonun tüm stream'lerini yeniden okutur; paylaşımlı bebekte dakikada bir tüm Home sorguları (pil/CPU). Performans. Şüpheli: hayır.

### Bildirim / widget / arka plan
- **D16.** `lib/core/notification_service.dart:85-91, 526-529` — tz alınamazsa `tz.local` UTC kalır; günlük ilaç/özel hatırlatıcı 09:00 → TR'de 12:00 çalar (tek seferlikler `TZDateTime.from` ile güvenli). Şüpheli: evet (nadir).
- **D17.** `lib/core/notification_service.dart:792, 805-806` — arka plan "Ertele 10 dk" metni her dilde Türkçe (`I18n` bg isolate'te yüklü değil); ayrıca yalnız ana uyarı ertelenir, "Kaydı unuttun mu?" (820000+slot) eski saatinde çalar. Şüpheli: hayır.
- **D18.** `lib/core/notification_service.dart:64, 284-287` — aile etkinlik bildirim id'si `_activitySeq` bellek-içi; FCM bg isolate her kurulduğunda 0'dan başlar → ardışık bildirimler üst üste yazılır. Şüpheli: evet (isolate ömrü platforma bağlı).
- **D19.** `lib/core/notification_service.dart:43-54, 560-569, 682-702` — iOS 64 bekleyen bildirim sınırı kontrol edilmiyor (çok bebek × plan × doz + randevular). Şüpheli: evet (tipik kullanımda 15-25).
- **D20.** `lib/data/record_repository.dart:30` + `family_settings.dart:204` + `notification_sync.dart:446-497` + `background_sync.dart:90,105` — çapa son 15 kayıt (tür bağımsız) içinde aranıyor; son beslenmeden sonra 15+ başka kayıt (bez/doz/ateş) girilince çapa pencereden düşer → kart kaybolur, widget "Beslenme bekleniyor", `scheduleFeedReminder(nextTime:null)` 3 id'yi iptal eder, uyarı yok. Şüpheli: evet (eşik tasarım kararı).
- **D21.** `lib/features/home/home_layout.dart:70-100` — `build()` async sürerken `setQuick` yapılırsa eski `settings()` yanıtı state+cache'i eski listeyle ezer. Şüpheli: evet (dar pencere).
- **D22.** `lib/features/settings/premium_screen.dart:101-102`; `settings_screen.dart:27-28` — `isPremiumProvider` yerine ham `subscriptionProvider.asData` → çevrimdışı premium kullanıcıya "Premium ol" + plan kartları. Şüpheli: hayır.

### Kayıt / ana sayfa / grafik
- **D23.** `lib/features/home/home_screen.dart:685-691`; `record_form.dart:770-774, 1128-1132` — "Uykuyu/Emzirmeyi başlat" çift dokunuşta iki süren kayıt; `watchOngoingSleep` yalnız en sonu gösterir, diğeri akışta sonsuza dek "Uyuyor…" (silmekten başka çıkış yok). Şüpheli: evet (~100 ms).
- **D24.** `lib/features/home/home_screen.dart:753-756`; `record_form.dart:1350-1361`; `yesterday_recap_sheet.dart:220-242` — `await` sonrası `mounted` kontrolsüz `ref` kullanımı (flutter_riverpod 3.x release'te `StateError`): pull-to-refresh sırasında sekme değiştirme, "Uyandı" diyaloğu açıkken uykunun başka cihazdan bitirilmesi, "Verdiysen ekle" sürerken sheet kapatma → yakalanmayan async hata, işlem yarım (`_addMissing`'de kayıt yazılır, sync tetiklenmez). Şüpheli: evet (uç zamanlama).
- **D25.** `lib/features/records/record_controller.dart:464-476` — `stopSleep` `now - start` clamp'siz (`_accrueBreast` clamp'li); başka cihazın saat sapmasıyla negatif dakika (O27'nin sayaç yolu). Şüpheli: hayır.

### Sağlık / gelişim
- **D26.** `lib/data/health_catalog.dart:136-148` — bozuk API yanıtı önce cache'e yazılıp sonra parse ediliyor; cache dalındaki `fromJson` try dışında → `healthCatalogProvider` kalıcı hata, gömülü asset'e düşülmez. Şüpheli: evet (sunucu hatası gerekir).
- **D27.** `lib/data/health_catalog.dart:134-146`; `health_repository.dart:99, 121, 146` — katalog network-first; "bağlı ama internetsiz"de aşı/gelişim/diş ekranı 15 sn spinner, `_HealthNotifSync` bildirimleri de gecikir. Şüpheli: hayır.
- **D28.** `lib/features/health/medication_plan_sheet.dart:315-317, 320-336` — plan kaydetme hatası sessiz (`_saving=false`, mesaj yok); `_togglePause/_delete` try/catch'siz → drift hatasında sayfa açık kalır, bildirim/invalidate atlanır. Şüpheli: evet (nadir).
- **D29.** `lib/data/who_lms.dart:21-34`; `lib/core/who_growth.dart:49-57, 90-93` — WHO LMS serisi uzunluğu doğrulanmıyor; 61'den kısa sunucu verisi `RangeError` → büyüme grafiği çöker, cache'lendiği için çevrimdışı da sürer. Şüpheli: evet.
- **D30.** `lib/features/health/medications_screen.dart:62-63, 89-90, 175-178`; `health_repository.dart:325, 339-341` — bakıcı plan ekleyebiliyor ama senkron bakıcı değişikliğini hiç göndermiyor → cihazda hayalet plan; ekran notu hâlâ "yalnızca bu telefonda saklanır" (v1.4.26'dan beri paylaşımlı). Şüpheli: hayır.
- **D31.** `lib/features/babies/premature_section.dart:65, 93-100`; `lib/core/age.dart:95`; `born_flow_screen.dart:36-55` — `gestationalAgeFromDue` 22'nin altında hafta üretebilir; `didUpdateWidget` içindeki controller ataması listener'ı tetikleyip parent `setState`'i build fazında çağırır (debug kırmızı ekran; release muhtemelen toparlar). Şüpheli: evet.

### Adet
- **D32.** `lib/features/cycle/cycle_setup_screen.dart:78-84` — doğum sonrası sihirbaz `postpartum` modunu/`predictions_hidden`ı yazmıyor; "Hedefim" TTC'yi seçilebilir sunar, `patchSettings` otomatik geçiş kancası devreye girmez (matris P4'ten sapma). Şüpheli: hayır.
- **D33.** `lib/features/cycle/cycle_calendar_screen.dart:937-960`; `cycle_entry_sheet.dart:94-106` — çapa gününün adet işareti kaldırılınca `firstPeriodDate` kalır; motor çapayı `starts`'a her zaman ekler (`cycle_engine.dart:163-165`) → hayalet döngü başlangıcı. Şüpheli: hayır.
  - **Ek (2026-10-11, commit 5):** Aynı sapma senkronla da tetikleniyor: başka cihazda silinen çapa-günü kaydı R4 ile yerelden kalkınca (çapa settings'te kalır) ertesi adet günü `periodStarts`'ta yeni başlangıç sayılıyor → `dayInCycle` 1 gün kayıyor (testle kanıtlandı: `cycle_repository_o7_test.dart` "motor çapadan sürer"). K6 aşamasında çapa/kayıt tutarlılığıyla birlikte ele alınmalı.
- **D34.** `lib/features/cycle/cycle_today_screen.dart:100-113` — "İlk adetimi kaydet" günün loşia rengini koruyor → `isPeriod=false`, çapa kurulmaz ama başarı toast'ı gelir. Şüpheli: hayır.
- **D35.** `lib/features/cycle/cycle_lifecycle.dart:65-84` — ttc→tracking'de `ttcStartedAt` temizlenmiyor; sihirbaz yeniden koşunca eski damga korunur. Şüpheli: hayır.

### Topluluk / içerik / ayarlar / anı
- **D36.** `lib/features/community/community_feed_screen.dart:62-102` — reset fetch süren loadMore'u beklemiyor/iptal etmiyor; eski sorgunun sayfası yeni listeye eklenir (yanlış kategori/arama sonuçları, tekrarlar). Şüpheli: hayır.
- **D37.** `lib/features/community/question_detail_screen.dart:60, 70, 86` — `await` sonrası `mounted` kontrolsüz `setState` (yutulur); oy butonunda çift dokunma koruması yok → son yanıt eskisi olabilir. Şüpheli: hayır.
- **D38.** `lib/features/community/blocked_users_screen.dart:95-96, 103` — `u['name'] as String` zorunlu cast; backend `null` döndürürse liste build'i TypeError. Şüpheli: evet.
- **D39.** `lib/features/community/ask_question_sheet.dart:94` — sheet ebeveyn ekranının `WidgetRef`'iyle `watch` yapıyor; kategoriler sonradan yüklenince sheet rebuild olmaz. Şüpheli: hayır.
- **D40.** `lib/features/content/article_detail_screen.dart:27-28` — `content_opened` analitiği build içinde; her rebuild'de tekrar loglanır. Şüpheli: hayır.
- **D41.** `lib/features/babies/members_screen.dart:219-229` — davet "Oluştur" çift dokunuşta iki davet; ikincisi `dialogCtx.mounted` false ile kaybolur. Şüpheli: hayır.
- **D42.** `lib/features/memories/memories_screen.dart:536-544, 652` — `Image.file` errorBuilder'sız; picker sonrası `mounted` yok; Android `retrieveLostData()` hiç çağrılmıyor (baby_edit dahil). Şüpheli: hayır.
- **D43.** `lib/features/auth/auth_controller.dart:170-182`; `privacy_screen.dart:193-221` — hesap silme sonrası drift'teki hesap verisi ve foto dosyaları cihazda kalıyor (metin "verileriniz silinecek" diyor). Şüpheli: evet (30 gün geri alma için bilinçli olabilir).
- **D44.** `lib/features/settings/data_export.dart:44, 66` — export geçici dizine yazılıyor; paylaşım 60 sn'de dönmezse "dosya cihaza kaydedildi" denir ama temp dizini kullanıcıya erişilemez/OS silebilir. Şüpheli: hayır.
- **D45.** `lib/features/settings/premium_screen.dart:473-500` ile birlikte `lib/features/onboarding/premium_welcome_screen.dart:141-165` — O12 ile aynı; ayrıca "Satın alma doğrulanamadı" dalı `restore` önermiyor. Şüpheli: hayır.

---

## 6. "Şüpheli" olarak işaretlenen maddeler (ayrı liste)

Mekanizması kodda görünen ama ya uç zamanlamaya ya da bu depoda görülemeyen backend/platform davranışına bağlı olanlar; kesinleştirmek için cihaz/backend testi gerekir:

- K9 (kısmen): bg import'un dispose'dan önce ne kadar ilerlediği.
- O16: Android 14+ exact-alarm varsayılan-ret → ayar sayfasına atma.
- O17: backend `last_feed_ts`'in anlamı (eklenen vs en yeni kayıt).
- O18: release'te disposed `WidgetRef.read` davranışı; çift dispatch kesin.
- O23: pregnant→tracking'de çapanın korunması kasıtlı olabilir (yetim bebek kısmı kesin).
- O34: logout ile `_refreshInBackground` yarışı (dar pencere).
- D6: RevenueCat dinleyicisinin kurulamama olasılığı (zamanlama).
- D7: `/invitations/accept` yanıtında `my_role` olup olmadığı.
- D16, D18, D19: tz fallback, bg isolate ömrü, iOS 64 sınırı (uç durumlar).
- D20: 15 kayıt penceresi (tasarım eşiği).
- D21, D23, D24: dar yarış pencereleri.
- D26, D29, D38: bozuk/eksik sunucu verisi gerektirir.
- D28: drift yazım hatası gerektirir.
- D31: release'te build-fazı setState davranışı.
- D43: bilinçli tasarım kararı olabilir.

---

## 7. Kontrol edilip SORUN BULUNMAYAN noktalar

- `ApiClient` tek-uçuş refresh kilidi ve retried/noAuth döngü koruması (testlerle uyumlu); refresh'in geçici hatada token koruması.
- `AuthController.build` önbellek-öncelikli açılış; `LocalSession.ensureLoaded` paralel okuma + yetim-id koruması; router'ın `LocalSession.loaded` beklemesi.
- `RecordRepository.sync` uçuş-içi düzenleme koruması (`sentStamp`), çakışmada sunucu otoriterliği, cursor'ın ISO string saklanması (sonsuz döngü fix'i).
- `SyncService` `_running/_pending` ve bebek id-kümesi karşılaştırması (geri besleme döngüsü yok); 403 → salt-okunur + self-heal.
- `AppDatabase` PRAGMA sırası (busy_timeout → WAL) ve `shareAcrossIsolates` kapalı kararı; `DbWatchdog` probe > busy_timeout.
- `SlotRegistry` benzersiz slot; bildirim id aralıkları (600000 adet, 61–67xxxx sağlık, 700000 aile, 8xxxxx feed, 9xxxxx sayaç) çakışmıyor (slot < 10000, plan localId < 1000 varsayımıyla).
- Widget anahtarları ve birimleri Dart↔Kotlin↔Swift birebir uyumlu (`babies_json`, `next_/last_<id>`, `active_id`, `next_feed_ms`, `fr_*`, `feed_interval_<id>`; epoch ms); NSE/Dart feed id formülleri aynı; `effectiveForEstimate/matchesBase` kuralı beş yazıcıda aynı.
- `_feedSyncAwaitTimeout`: kayıt yerele yazılmış, 10 sn sonra spinner biter, `SyncStatusBanner` "senkron sorunu" gösterir.
- Reklam: çevrimdışı yüklenemezse sessiz atlanır, premium muaf, günlük tavan/aralık/ilk-gün penceresi kalıcı.
- Sessiz saat gece-yarısı geçişi (`covers`), TR virgül ondalık (`_num`), `record.data` okumalarının `is num`/`as String?` korumaları, grafiklerde sıfıra bölme korumaları.
- Adet: JSON cast'leri try/catch'li, `fromString`'ler `orElse`'li, boş liste `reduce` korumaları, ay/artık yıl gezintisi, hafta başı hesabı, `cycle_shell` resume'da gün değişimi, entry/adjust sheet'lerde `_saving` çift gönderim koruması, `saveEntry` backfill koruması (testlerle uyumlu).
- `ModalGate` paywall↔tur önceliği; `OnboardingPaywall` tek-kez; ConsentGate POST başarısızsa kapıda kalma.
- Güvenlik notu: Android debug manifest'te cleartext yalnız debug; release'te https. Token yalnız Keychain/Keystore; prefs'te gizli veri yok.

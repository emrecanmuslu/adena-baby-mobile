import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:firebase_messaging/firebase_messaging.dart';

import '../data/activity_notif_cache.dart';
import '../data/feed_reminder_cache.dart';
import '../data/notification_prefs.dart';
import '../data/slot_registry.dart';
import 'api_client.dart';
import 'i18n_warm.dart';
import 'background_sync.dart';
import 'medication/med_scheduler.dart';
import 'notification_service.dart';
import 'widget_service.dart';

/// FCM push — yalnız 'cihazın kendi bilemeyeceği' olaylar: aile etkinliği
/// (başka üye kayıt ekledi) + topluluk (cevap/işaret). Zaman-bazlı hatırlatıcılar
/// YEREL kalır (bkz. bildirim mimarisi).
///
/// Mesajlar sunucudan DATA-ağırlıklı gelir; istemci hem yerel bildirimi gösterir
/// hem de "son beslenme" ana ekran widget'ını günceller — uygulama kapalıyken bile.
///
/// Bildirim tek kaynak = PUSH. Uygulama ön plandayken OS bildirimi basılmaz;
/// bunun yerine main.dart in-app üst banner gösterir (bkz. showInAppNotification).
/// [appInForeground] bu ayrımı sağlar: ön planda `onMessage` ANA isolate'te çalışır
/// (bayrak true → OS bildirimi atla), arka planda `onBackgroundMessage` AYRI
/// isolate'te çalışır (bayrak varsayılan false → OS bildirimi göster).
bool appInForeground = false;

/// D4: `inactive` (bildirim paneli, iOS app switcher) de ön plandır — aksi hâlde
/// push hem OS bildirimi hem in-app banner olarak çift görünür. Saf, testli.
bool isForegroundLifecycle(AppLifecycleState state) =>
    state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

/// O17: push çapası makul mü — ön plan `lastFeedAt` kuralıyla aynı eşik
/// (şimdi + 1 saatten ileri kayıt çapa OLMAZ). "En yeni kayıt" kuralı backend
/// tarafında (BACKEND-TALEPLERI #10); bg turu / öne geliş yine düzeltir.
bool feedAnchorPlausible(DateTime lastFeed, {DateTime? now}) =>
    !lastFeed.isAfter((now ?? DateTime.now()).add(const Duration(hours: 1)));

/// İlaç v2 (A5): `med_dose` push'unda iptal edilecek doz — yalnız "verildi" /
/// "atlandı" olayında ve kimlik (plan + gün + saat) varsa. "Geri alındı"da
/// hatırlatma geri gelmeli → senkron + yeniden kurma yapar (iptal değil).
/// V7: "geri alındı" ama doz başkasınca HÂLÂ verilmiş (`still_given=1`) → iptal
/// (geri ekleme yok).
({String plan, String date, String time})? medDoseCancelTarget(Map<String, dynamic> data) {
  if (data['type'] != 'med_dose') return null;
  final ev = data['event'];
  final stillGiven = ev == 'undone' && data['still_given'] == '1';
  if (ev != 'given' && ev != 'skipped' && !stillGiven) return null;
  final plan = data['plan_uuid'], date = data['dose_date'], time = data['dose_time'];
  if (plan is! String || date is! String || time is! String) return null;
  if (plan.isEmpty || date.isEmpty || time.isEmpty) return null;
  // V16: defter anahtarı kanonik (küçük harf) plan uuid'siyle kurulur.
  return (plan: plan.toLowerCase(), date: date, time: time);
}

/// İlaç v2 (M10): üyelikten çıkarılma push'u — bu bebeğin zamanlanmış tüm
/// bildirimleri uygulama açılmadan iptal edilir.
String? accessRemovedBabyId(Map<String, dynamic> data) {
  if (data['type'] != 'access_removed') return null;
  final id = data['baby_id'];
  return id is String && id.isNotEmpty ? id : null;
}

/// Arka plan (uygulama kapalı/arka planda) mesaj işleyici — TOP-LEVEL olmalı.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await warmI18nFromCache(); // M7: bildirim metinleri kullanıcının dilinde
  await handlePushMessage(message);
}

/// Hem ön plan hem arka plan için ortak işleyici (Riverpod gerektirmez).
Future<void> handlePushMessage(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] ?? '';
  final title = data['title'] ?? message.notification?.title ?? 'Adena Baby';
  final body = data['body'] ?? message.notification?.body ?? '';

  // sync_nudge = başka üye bir kaydı GÜNCELLEDİ ya da SİLDİ (bkz. push_sync_nudge
  // backend'te). family_activity'nin (EKLEME) tersine hangi kayıt değiştiğini
  // TEK başına bilmeyiz — kendi widget/hatırlatıcı mantığı _handleSyncNudge'de.
  if (type == 'med_dose') {
    // İlaç v2: önce ağsız iptal (doz verildi/atlandı → o dozun "İlaç zamanı" ve
    // +30 dk hatırlatması), sonra (arka plandaysak) tam senkron + yeniden kurma.
    final t = medDoseCancelTarget(data);
    if (t != null) {
      try {
        await MedicationScheduler.instance.cancelDose(t.plan, t.date, t.time);
      } catch (_) {}
    }
    final babyId = (data['baby_id'] as String?) ?? '';
    if (!appInForeground && babyId.isNotEmpty) {
      await refreshBabyFeedStateFromPush(babyId);
    }
    // Bildirim gösterme adımına DÜŞER (görünür gövde → aile bildirimi).
  } else if (type == 'access_removed') {
    final babyId = accessRemovedBabyId(data);
    if (babyId != null) {
      try {
        // V5: revoke → yerel veri ön planda temizlenene dek sonraki yeniden
        // kurmalar (bg turu) bu bebeği geri KURMAZ.
        await MedicationScheduler.instance.cancelBaby(babyId, revoke: true);
        final slot = await SlotRegistry.instance.slotForStored(babyId);
        if (slot != null) {
          await NotificationService.instance.cancelBabyScheduled(slot: slot);
        }
      } catch (_) {}
      // V5: bu isolate'in defteri bayat olabilir → kalanları yetim temizliği alsın.
      // V24: bg'de özel/randevu hatırlatıcıları da (yerel id'ler) iptal edilir.
      if (!appInForeground) await rebuildMedicationFromPush(revokedBabyId: babyId);
    }
    // Bildirim gösterme adımına DÜŞER ("bu bebeğe erişimin kaldırıldı").
  } else if (type == 'sync_nudge') {
    await _handleSyncNudge(data, title);
    // Bildirim gösterme adımına (aşağı) DÜŞER — family_activity ile aynı yoldan.
  } else if (type == 'baby_update') {
    // baby_update = sahip bebek profilini değiştirdi (gebelik→doğdu vb). Sessiz;
    // ön plan/öne geliş bebek listesini tazeler (main.dart).
    return;
  } else {
    // 1) Beslenme EKLEME olayı: widget + yerel hatırlatıcı güncellemesi. last_feed_ts
    //    süren emzirme dahil her beslenmede gelir; widget_update yalnız TAMAMLANMIŞ
    //    beslenmede (widget süren emzirmeyi "son beslenme" saymaz).
    // O17: ileri tarihli (yanlış girilmiş) çapa widget'ı/hatırlatıcıyı günler
    // sonrasına kurmasın — ön plan/bg sync'teki "gelecek tarih eşiği" ile aynı.
    final rawLast = DateTime.tryParse(data['last_feed_ts'] ?? '')?.toLocal();
    final lastFeed = rawLast != null && feedAnchorPlausible(rawLast) ? rawLast : null;
    if (data['widget_update'] == 'feed') {
      // Widget artık SONRAKİ beslenmeyi gösterir → son beslenme + aralıktan hesapla.
      // Çok-bebek: bu bebeğin verisini per-baby anahtarına yaz (o bebeği seçen widget tazelenir).
      final babyId = data['baby_id'];
      if (babyId is String && babyId.isNotEmpty) {
        final snap = await FeedReminderCache().read(babyId);
        // Snapshot YOKSA aralığı da baz türünü de BİLMİYORUZ. Eskiden burada
        // varsayılan 120 dk'ya düşülüyordu; kullanıcının aralığı 3 saat olsa bile
        // widget "son beslenme + 2 saat" yazıyordu (ve publishOne bunu App Group'a
        // `feed_interval_default` olarak kalıcılaştırıp iOS NSE'yi de zehirliyordu).
        // Bayat ama DOĞRU veri, taze ama yanlış veriden iyidir → hiç dokunma.
        // (Snapshot'ı ön plandaki _syncFeed her oturumda yazar; doğmuş bebeği olan
        // bir kullanıcıda pratikte hep vardır.)
        if (snap != null) {
          // Ön planla (_WidgetSync / ana sayfa kartı) BİREBİR aynı kural: hatırlatıcı
          // kapalıysa tahmin varsayılana düşer.
          final cfg = snap.toConfig().effectiveForEstimate;
          // KRİTİK: baz türü filtresi. Hatırlatıcı "son MAMA sonrası" ise eşin
          // eklediği ANNE SÜTÜ kaydı çapayı oynatmamalı — ön plan/bg sync zaten
          // filtreliyordu, yalnız bu dal filtrelemiyordu. Sonuç: push widget'a
          // "anne sütü + 3 sa" yazıyor, 30 dk sonraki bg sync "son mama + 3 sa"ya
          // geri çekiyor, widget ileri-geri zıplıyordu.
          final subSeen = data['feed_sub'] as String?;
          final matches = cfg.matchesBase(subSeen);
          if (matches) {
            final next = lastFeed?.add(Duration(minutes: cfg.intervalMin));
            // Bebek adı backend data'sında 'baby_name' ile gelir (sessiz iOS push'unda
            // notification/title yok → title 'Adena Baby'ye düşerdi). title yedek.
            final babyName = (data['baby_name'] as String?) ?? title;
            await WidgetService.publishOne(
                babyId: babyId,
                babyName: babyName,
                nextFeed: next,
                lastFeed: lastFeed,
                intervalMin: cfg.intervalMin);
          }
        }
      }
    }
    // Hatırlatıcı yeniden planlaması aile-etkinlik bildirimi tercihinden BAĞIMSIZ:
    // beslenme hatırlatıcısı ayrı bir özelliktir, kullanıcı aktivite bildirimini
    // kapatmış olsa bile çalışmalı (widget güncellemesi gibi koşulsuz).
    if (lastFeed != null) {
      await _rescheduleFeedReminder(data, lastFeed, title);
    }
  }

  // 2) Bildirimi göster — YALNIZ uygulama ön planda DEĞİLKEN (arka plan/kapalı).
  // Ön planda OS bildirimi basılmaz; main.dart in-app üst banner gösterir (iOS'ta
  // OS ön plan sunumu da kapalı → çift olmaz). Bu dal foreground onMessage'dan da
  // çağrılır (push_service dinleyicisi) → bayrakla erken dön.
  if (appInForeground) return;

  // iOS'ta görünür 'notification' payload'ı APNs tarafından zaten gösterilir →
  // tekrar yerel bildirim basma (çift olmasın). Android data-only geldiği için
  // her zaman yerel basılır.
  if (Platform.isIOS && message.notification != null) return;

  if (type == 'family_activity' || type == 'sync_nudge') {
    // Kullanıcı tercihi (varsayılan açık) bunu da yönetir. Sessiz push'larda
    // (aile etkinliği tercihi kapalı üye) body zaten boştur → gösterilecek bir
    // şey olmaz, showActivity çağrısı görünürde bir etki yapmaz.
    if (body.isNotEmpty && await ActivityNotifCache().enabled()) {
      await NotificationService.instance.showActivity(title: title, body: body);
    }
  } else if (type == 'med_dose' || type == 'access_removed') {
    // İlaç v2 (K2): "Ayşe · D vitamini verildi · 08:00". Sunucu "Ailenin ilaç
    // işaretleri" kapalı üyeye gövdesiz (sessiz) gönderir → gösterilecek şey yok.
    // access_removed: Android data-only olduğundan yerelde basılmalı (M10).
    if (body.isNotEmpty) {
      await NotificationService.instance.showActivity(title: title, body: body);
    }
  } else if (type.startsWith('community')) {
    // Topluluk bildirimleri (cevap geldi / cevabın en iyi seçildi) — kullanıcı
    // tercihi (varsayılan açık, cihaz-yerel) yönetir.
    if (await NotificationPrefs.instance.enabled(NotificationPrefs.community)) {
      await NotificationService.instance.showActivity(title: title, body: body);
    }
  }
}

/// sync_nudge (başka üye bir kaydı GÜNCELLEDİ/SİLDİ) → timer iptali + (arka
/// plandaysak) tam senkron + widget/hatırlatıcı güncellemesi.
///
/// family_activity'nin (EKLEME) last_feed_ts + feed_sub ikilisinden FARKLI: orada
/// "hangi kayıt eklendi" bellidir, burada değil — sunucu bu yüzden ÜÇ baz-türü
/// karşılığını gönderir (last_feed_all/breast/formula, bkz. _feed_anchors
/// backend'te); cihaz KENDİ baz-türü ayarına uyanı doğrudan seçer.
Future<void> _handleSyncNudge(Map<String, dynamic> data, String babyNameFallback) async {
  final cancel = (data['cancel'] as String?) ?? '';
  final babyId = (data['baby_id'] as String?) ?? '';
  if (cancel.isNotEmpty && babyId.isNotEmpty) {
    // Slot = SlotRegistry (Baby.notifSlot ile AYNI kaynak). Arka plan isolate →
    // depodan oku; yoksa bu bebeğe dair zamanlanmış sayaç bildirimi de yok.
    final slot = await SlotRegistry.instance.slotForStored(babyId);
    if (slot != null) {
      if (cancel.contains('sleep')) {
        await NotificationService.instance
            .cancelTimer(NotificationService.sleepIdFor(slot));
      }
      if (cancel.contains('breast')) {
        await NotificationService.instance
            .cancelTimer(NotificationService.breastIdFor(slot));
      }
    }
  }
  if (data['widget_update'] == 'feed' && babyId.isNotEmpty) {
    final snap = await FeedReminderCache().read(babyId);
    // Snapshot yoksa (bkz. family_activity dalındaki AYNI gerekçe) bayat ama
    // DOĞRU veride kal — dokunma.
    if (snap != null) {
      final cfg = snap.toConfig().effectiveForEstimate;
      final tsStr = data['last_feed_${cfg.baseType}'] as String?;
      final rawLast = tsStr != null ? DateTime.tryParse(tsStr)?.toLocal() : null;
      final lastFeed =
          rawLast != null && feedAnchorPlausible(rawLast) ? rawLast : null; // O17
      if (lastFeed != null) {
        final next = lastFeed.add(Duration(minutes: cfg.intervalMin));
        final babyName = (data['baby_name'] as String?) ?? babyNameFallback;
        await WidgetService.publishOne(
            babyId: babyId,
            babyName: babyName,
            nextFeed: next,
            lastFeed: lastFeed,
            intervalMin: cfg.intervalMin);
        if (snap.enabled) {
          await NotificationService.instance.scheduleFeedReminder(
            enabled: true,
            nextTime: next,
            preMin: snap.preMin,
            slot: snap.slot,
            babyName: babyName,
            sound: snap.sound,
            quiet: snap.quiet,
            forgot: snap.forgot,
          );
        }
      }
    }
  }
  // Ön plandaysak dokunma: main.dart'taki canlı Riverpod ağacı bu push'u AYRICA
  // görüp requestSyncSoon() ile aynı işi yapıyor — burada da senkronlarsak aynı
  // bebeğe iki eşzamanlı bağlantı (bu isolate + canlı uygulama) açılırdı. Widget'ı
  // YUKARIDA zaten (network'süz, anında) tazeledik; bu TAM senkron yerel drift
  // DB'yi (kayıt listesi, ana sayfa kartı) doğru veriyle hizalar.
  if (!appInForeground && babyId.isNotEmpty) {
    await refreshBabyFeedStateFromPush(babyId);
  }
}

/// family_activity feed push'undan yerel beslenme hatırlatıcısını yeniden kurar.
/// Drift'e DOKUNMAZ: parametreler ön planda FeedReminderCache'e yazılmıştır;
/// burada yalnız "son beslenme + aralık"tan sonraki vakti hesaplayıp planlarız.
/// Arka plan isolate'ında da güvenle çalışır (NotificationService init kendini
/// kurar, tz dahil). baseType filtresi nextFeedEstimate ile birebir aynıdır.
Future<void> _rescheduleFeedReminder(
    Map<String, dynamic> data, DateTime lastFeed, String babyName) async {
  final babyId = data['baby_id'];
  if (babyId is! String || babyId.isEmpty) return;
  final snap = await FeedReminderCache().read(babyId);
  if (snap == null || !snap.enabled) return;
  // Eklenen beslenmenin türü hatırlatıcının baz türüyle uyuşmuyorsa (ör. baz=anne
  // sütü, eklenen=mama) hatırlatıcıyı sıfırlama — mevcut plan korunur.
  if (!snap.matchesBase(data['feed_sub'] as String?)) return;
  final next = lastFeed.add(Duration(minutes: snap.intervalMin));
  await NotificationService.instance.scheduleFeedReminder(
    enabled: true,
    nextTime: next,
    preMin: snap.preMin,
    slot: snap.slot,
    babyName: babyName,
    sound: snap.sound,
    quiet: snap.quiet,
    forgot: snap.forgot,
  );
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _foregroundReady = false;
  String? _lastRegistered;
  bool _refreshSubscribed = false;
  bool _prefSynced = false;

  /// Ön plan mesaj dinleyicisini kur (oturum gerektirmez). main() içinde bir kez.
  void startForeground() {
    if (_foregroundReady) return;
    _foregroundReady = true;
    // iOS: uygulama ön plandayken OS banner'ı GÖSTERME (alert:false) → onMessage
    // yine ateşlenir ve main.dart in-app üst banner gösterir (tek, tutarlı UX).
    // Rozet güncellensin diye badge açık. Android'de etkisi yok (data-only gelir).
    FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
    FirebaseMessaging.onMessage.listen(handlePushMessage);
  }

  /// FCM token'ını al ve sunucuya kaydet (oturum açıkken çağır). İzin de ister.
  /// D5: eşzamanlı çağrılar (resume + auth listener) tek uçuşta birleşir —
  /// iOS'ta 15 sn APNs yoklaması paralel koşmasın, çift POST atılmasın.
  Future<void>? _registering;

  Future<void> registerToken(ApiClient api) {
    final inflight = _registering;
    if (inflight != null) return inflight;
    final run = _registerTokenNow(api).whenComplete(() => _registering = null);
    _registering = run;
    return run;
  }

  Future<void> _registerTokenNow(ApiClient api) async {
    // Açılışta Firebase.initializeApp() timeout'a ya da bir eklenti (Crashlytics)
    // component hatasına takılıp başarısız olmuş olabilir → FirebaseMessaging.instance
    // [core/no-app] fırlatır ve token kaydı sessizce düşerdi. FCM'e dokunmadan önce
    // Firebase'in hazır olduğundan emin ol (asıl kalıcı çözüm release R8 keep kuralları;
    // bu ek güvence).
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } catch (_) {}
    // KRİTİK: onTokenRefresh'i KOŞULSUZ + EN BAŞTA kur. iOS'ta ilk anda
    // getToken() null dönebilir/atabilir (APNs token henüz gelmemiş); token
    // saniyeler sonra hazır olunca BU dinleyici yakalar ve kaydeder. Önceden
    // dinleyici yalnız getToken başarısından SONRA kuruluyordu → null olunca
    // hiç kurulmuyor, sonradan gelen token kaçıyordu (iOS cihaz kaydolmuyordu).
    if (!_refreshSubscribed) {
      _refreshSubscribed = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        if (t == _lastRegistered) return;
        postToken(api, t);
      });
    }
    try {
      await FirebaseMessaging.instance.requestPermission();
      // iOS: FCM token ancak APNs token hazır olunca gelir; biraz bekle.
      // (APNs token AppDelegate'te elle Messaging'e iletiliyor — UIScene fix.)
      // Gelmezse de yukarıdaki onTokenRefresh sonradan yakalar.
      if (Platform.isIOS) {
        var apns = await FirebaseMessaging.instance.getAPNSToken();
        for (var i = 0; i < 15 && apns == null; i++) {
          await Future.delayed(const Duration(seconds: 1));
          apns = await FirebaseMessaging.instance.getAPNSToken();
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token != _lastRegistered) {
        await postToken(api, token);
      }
    } catch (_) {
      // İzin reddi / ağ / APNs hatası → sessiz; onTokenRefresh backstop kalır.
    }
    // Aile etkinlik bildirim tercihini (cihaz-yerel) sunucuya bir kez yansıt →
    // backend opt-out üyelere SESSİZ, opt-in'lere GÖRÜNÜR push seçer. Yalnız
    // tercih değiştiğinde (notifier) + oturum başına bir kez (burada) gönderilir.
    if (!_prefSynced) {
      _prefSynced = true;
      try {
        final on = await ActivityNotifCache().enabled();
        final med = await NotificationPrefs.instance
            .enabled(NotificationPrefs.medicationActivity);
        await api.dio.patch('/auth/me/settings', data: {
          'notification_prefs': {'family_activity': on, 'medication_activity': med}
        });
      } catch (_) {
        _prefSynced = false; // başarısızsa bir sonraki çağrıda tekrar dene
      }
    }
  }

  /// Token'ı sunucuya kaydeder; `_lastRegistered` YALNIZ başarılı POST'ta
  /// işaretlenir (O1 artığı): zorunlu çıkış → `deleteToken` → FCM yeni token
  /// üretir → `onTokenRefresh` oturum yokken gelir. Eskiden token önce
  /// işaretlenip POST 401 ile düşüyordu; yeniden girişte `registerToken` aynı
  /// token'ı "zaten kayıtlı" sanıp hiç göndermiyordu → aile push'u ölü kalırdı.
  /// Oturum yoksa istek hiç atılmaz (yetkisiz 401 → refresh yolu tetiklenmesin).
  @visibleForTesting
  Future<bool> postToken(ApiClient api, String token) async {
    try {
      if (!await api.hasSession) return false;
      await api.dio.post('/me/devices', data: {
        'push_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      _lastRegistered = token;
      return true;
    } catch (_) {
      return false; // ağ/401 → giriş sonrası / sonraki öne gelişte tekrar denenir
    }
  }

  @visibleForTesting
  String? get lastRegistered => _lastRegistered;

  @visibleForTesting
  void resetForTests() => _lastRegistered = null;

  /// Çıkışta çağrılır: bu cihazın FCM token'ını sunucudan siler (token HÂLÂ
  /// geçerliyken, yani _repo.logout()'tan ÖNCE çağır). Böylece çıkılan hesaba bu
  /// cihaza push gelmez ve aynı cihaza giren başka kullanıcıya bildirim sızmaz.
  Future<void> unregister(ApiClient api) async {
    try {
      final token = _lastRegistered ?? await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await api.dio.delete('/me/devices', data: {'push_token': token});
      }
    } catch (_) {
      // Ağ/oturum hatası → sessiz; token sunucuda kalsa bile kritik değil.
    }
    _lastRegistered = null;
  }
}

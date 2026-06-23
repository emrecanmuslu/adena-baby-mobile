import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../data/activity_notif_cache.dart';
import '../data/feed_reminder_cache.dart';
import '../models/feed_reminder.dart';
import 'api_client.dart';
import 'notification_service.dart';
import 'widget_service.dart';

/// FCM push — yalnız 'cihazın kendi bilemeyeceği' olaylar: aile etkinliği
/// (başka üye kayıt ekledi) + topluluk (cevap/işaret). Zaman-bazlı hatırlatıcılar
/// YEREL kalır (bkz. bildirim mimarisi).
///
/// Mesajlar sunucudan DATA-ağırlıklı gelir; istemci hem yerel bildirimi gösterir
/// hem de "son beslenme" ana ekran widget'ını günceller — uygulama kapalıyken bile.
///
/// Çift bildirim önleme: push gösterince aile-etkinliği cursor'unu (ActivityNotifCache)
/// ilerletir; böylece öne gelince çalışan polling watcher aynı olayı tekrar
/// göstermez. Push düşmezse polling yedek olarak yakalar.

/// Arka plan (uygulama kapalı/arka planda) mesaj işleyici — TOP-LEVEL olmalı.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await handlePushMessage(message);
}

/// Hem ön plan hem arka plan için ortak işleyici (Riverpod gerektirmez).
Future<void> handlePushMessage(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] ?? '';
  final title = data['title'] ?? message.notification?.title ?? 'Adena Baby';
  final body = data['body'] ?? message.notification?.body ?? '';

  // 1) Beslenme olayı: widget + yerel hatırlatıcı güncellemesi. last_feed_ts
  //    süren emzirme dahil her beslenmede gelir; widget_update yalnız TAMAMLANMIŞ
  //    beslenmede (widget süren emzirmeyi "son beslenme" saymaz).
  final lastFeed = DateTime.tryParse(data['last_feed_ts'] ?? '')?.toLocal();
  if (data['widget_update'] == 'feed') {
    // Widget artık SONRAKİ beslenmeyi gösterir → son beslenme + aralıktan hesapla.
    // Aralık: bebeğin hatırlatıcı snapshot'ı (FeedReminderCache), yoksa varsayılan 120 dk.
    // Çok-bebek: bu bebeğin verisini per-baby anahtarına yaz (o bebeği seçen widget tazelenir).
    final babyId = data['baby_id'];
    if (babyId is String && babyId.isNotEmpty) {
      // Aralığı lastFeed'den bağımsız hesapla → kapalıyken çalışacak iOS NSE için
      // App Group'a da yazılsın (publishOne intervalMin'i önbelleğe alır).
      var interval = const FeedReminderConfig().intervalMin; // 120
      final snap = await FeedReminderCache().read(babyId);
      if (snap != null) interval = snap.intervalMin;
      final next = lastFeed?.add(Duration(minutes: interval));
      // Bebek adı backend data'sında 'baby_name' ile gelir (sessiz iOS push'unda
      // notification/title yok → title 'Adena Baby'ye düşerdi). title yedek.
      final babyName = (data['baby_name'] as String?) ?? title;
      await WidgetService.publishOne(
          babyId: babyId, babyName: babyName, nextFeed: next, intervalMin: interval);
    }
  }
  // Hatırlatıcı yeniden planlaması aile-etkinlik bildirimi tercihinden BAĞIMSIZ:
  // beslenme hatırlatıcısı ayrı bir özelliktir, kullanıcı aktivite bildirimini
  // kapatmış olsa bile çalışmalı (widget güncellemesi gibi koşulsuz).
  if (lastFeed != null) {
    await _rescheduleFeedReminder(data, lastFeed, title);
  }

  // sync_nudge = sessiz (güncelleme/silme). Bildirim yok; ön planda sync'i main.dart
  // tetikler. Burada yalnız biten süren-sayaç bildirimini iptal ederiz — alıcı ARKA
  // PLANDA olsa bile (drift'e yazamasa da) cihazdaki "uyku/emzirme sürüyor"
  // bildirimi düşsün. Slot = baby_id'den, Baby.notifSlot ile AYNI formül.
  if (type == 'sync_nudge') {
    final cancel = (data['cancel'] as String?) ?? '';
    final babyId = (data['baby_id'] as String?) ?? '';
    if (cancel.isNotEmpty && babyId.isNotEmpty) {
      final slot = babyId.hashCode.abs() % 1000;
      if (cancel.contains('sleep')) {
        await NotificationService.instance.cancelTimer(NotificationService.sleepIdFor(slot));
      }
      if (cancel.contains('breast')) {
        await NotificationService.instance.cancelTimer(NotificationService.breastIdFor(slot));
      }
    }
    return;
  }

  // baby_update = sahip bebek profilini değiştirdi (gebelik→doğdu vb). Sessiz: görünür
  // bildirim yok. Ön planda main.dart bebek listesini tazeler; arka planda ise bir
  // sonraki öne gelişte (_onForeground → babyController.refresh) status güncellenir.
  if (type == 'baby_update') {
    return;
  }

  // 2) Bildirimi göster.
  // iOS'ta görünür 'notification' payload'ı APNs tarafından zaten gösterilir →
  // tekrar yerel bildirim basma (çift olmasın). Android data-only geldiği için
  // her zaman yerel basılır.
  final alreadyShownByOs = Platform.isIOS && message.notification != null;
  if (alreadyShownByOs) {
    // OS bildirimi gösterdi → polling'in aynı olayı tekrar göstermemesi için
    // olay-id'yi işaretle, sonra cursor'u ilerlet.
    final eventId = (data['event_id'] as String?) ?? '';
    if (type == 'family_activity') await ActivityNotifCache().markNotifiedIfNew(eventId);
    _advanceCursorIfFamily(type, data);
    return;
  }

  if (type == 'family_activity') {
    // Kullanıcı tercihi (opt-in, varsayılan kapalı) bunu da yönetir.
    if (await ActivityNotifCache().enabled()) {
      // Olay-id dedup: polling aynı olayı önce işlediyse tekrar gösterme.
      final eventId = (data['event_id'] as String?) ?? '';
      if (await ActivityNotifCache().markNotifiedIfNew(eventId)) {
        await NotificationService.instance.showActivity(title: title, body: body);
      }
      await _advanceCursorIfFamily(type, data);
    }
  } else if (type.startsWith('community')) {
    await NotificationService.instance.showActivity(title: title, body: body);
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
  );
}

/// Aile etkinliği gösterildiyse polling cursor'unu ilerlet (çift bildirim önleme).
Future<void> _advanceCursorIfFamily(String type, Map<String, dynamic> data) async {
  if (type != 'family_activity') return;
  final babyId = data['baby_id'];
  if (babyId is String && babyId.isNotEmpty) {
    await ActivityNotifCache().setLastSeen(babyId, DateTime.now());
  }
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
    // iOS: uygulama ön plandayken de bildirim banner/ses/rozet göster (varsayılan
    // gizler). onMessage zaten ateşlenir; bu yalnız görünür sunumu açar. Android'de
    // etkisi yok (orada data-only gelir, yerel bildirimi istemci basar).
    FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    FirebaseMessaging.onMessage.listen(handlePushMessage);
  }

  /// FCM token'ını al ve sunucuya kaydet (oturum açıkken çağır). İzin de ister.
  Future<void> registerToken(ApiClient api) async {
    // KRİTİK: onTokenRefresh'i KOŞULSUZ + EN BAŞTA kur. iOS'ta ilk anda
    // getToken() null dönebilir/atabilir (APNs token henüz gelmemiş); token
    // saniyeler sonra hazır olunca BU dinleyici yakalar ve kaydeder. Önceden
    // dinleyici yalnız getToken başarısından SONRA kuruluyordu → null olunca
    // hiç kurulmuyor, sonradan gelen token kaçıyordu (iOS cihaz kaydolmuyordu).
    if (!_refreshSubscribed) {
      _refreshSubscribed = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        if (t == _lastRegistered) return;
        _lastRegistered = t;
        _post(api, t);
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
        _lastRegistered = token;
        await _post(api, token);
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
        await api.dio.patch('/auth/me/settings',
            data: {'notification_prefs': {'family_activity': on}});
      } catch (_) {
        _prefSynced = false; // başarısızsa bir sonraki çağrıda tekrar dene
      }
    }
  }

  Future<void> _post(ApiClient api, String token) async {
    try {
      await api.dio.post('/me/devices', data: {
        'push_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (_) {
      // Oturum yoksa 401 → giriş sonrası tekrar denenir.
    }
  }

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

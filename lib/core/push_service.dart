import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../data/activity_notif_cache.dart';
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

  // 1) Son beslenme widget'ını güncelle (beslenme olayıysa).
  if (data['widget_update'] == 'feed') {
    final lastFeed = DateTime.tryParse(data['last_feed_ts'] ?? '')?.toLocal();
    await WidgetService.updateLastFeed(babyName: title, lastFeed: lastFeed);
  }

  // 2) Bildirimi göster.
  // iOS'ta görünür 'notification' payload'ı APNs tarafından zaten gösterilir →
  // tekrar yerel bildirim basma (çift olmasın). Android data-only geldiği için
  // her zaman yerel basılır.
  final alreadyShownByOs = Platform.isIOS && message.notification != null;
  if (alreadyShownByOs) {
    _advanceCursorIfFamily(type, data);
    return;
  }

  if (type == 'family_activity') {
    // Kullanıcı tercihi (opt-in, varsayılan kapalı) bunu da yönetir.
    if (await ActivityNotifCache().enabled()) {
      await NotificationService.instance.showActivity(title: title, body: body);
      await _advanceCursorIfFamily(type, data);
    }
  } else if (type.startsWith('community')) {
    await NotificationService.instance.showActivity(title: title, body: body);
  }
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

  /// Ön plan mesaj dinleyicisini kur (oturum gerektirmez). main() içinde bir kez.
  void startForeground() {
    if (_foregroundReady) return;
    _foregroundReady = true;
    FirebaseMessaging.onMessage.listen(handlePushMessage);
  }

  /// FCM token'ını al ve sunucuya kaydet (oturum açıkken çağır). İzin de ister.
  Future<void> registerToken(ApiClient api) async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token == _lastRegistered) return;
      await _post(api, token);
      _lastRegistered = token;
      // Token yenilenince tekrar kaydet.
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _lastRegistered = t;
        _post(api, t);
      });
    } catch (_) {
      // İzin reddi / ağ hatası → sessiz; push olmadan uygulama çalışır.
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
}

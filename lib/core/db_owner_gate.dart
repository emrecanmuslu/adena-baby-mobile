import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

/// **Tek yazar (single-writer) kapısı** — yerel SQLite dosyasına aynı süreçte
/// İKİ bağlantının yazmasını önler.
///
/// Neden: iOS'ta BGTask / FCM arka plan işleyicisi, uygulama arka planda canlıyken
/// AYNI süreçte ayrı bir Flutter motoru (isolate) başlatıp kendi drift
/// bağlantısını açıyordu. İki bağlantı WAL'da aynı anda yazınca ön plan
/// `SqliteException(517) SQLITE_BUSY_SNAPSHOT` / `(261)` alıyor ve "Senkron
/// sorunu" şeridi yalnız kapat-aç ile kalkıyordu (2026-10-15 Crashlytics:
/// `INSERT INTO sync_cursors` 517, `sync_last_bg=başladı 0dk önce`). SQLite
/// belgesine göre 517'yi busy_timeout çözmez; drift yazarının önerisi "yazma
/// yetkili TEK bağlantı".
///
/// Çözüm: ön plan isolate'i süreç-genel bir port kaydeder. Arka plan girişleri
/// DB'ye dokunmadan önce bu portu arar; ön plan canlıysa (ping yanıtı gelirse)
/// işi ONA devreder ve kendi bağlantısını hiç açmaz. Ön plan yoksa (Android'de
/// uygulama kapalı, iOS'ta sahne kurulmadan arka plan açılışı) eski yol sürer.
class DbOwnerGate {
  DbOwnerGate._();

  static const portName = 'adena_db_owner';

  /// Canlılık yoklaması — ön plan isolate'i askıdaysa/ölüyse bu kadar beklenir.
  static const pingTimeout = Duration(seconds: 2);

  static ReceivePort? _port;
  static StreamSubscription? _sub;

  /// Ön plan: devredilen işi çalıştıran işleyiciyi kaydeder (idempotent;
  /// RestartWidget sonrası yeni işleyici eskisinin yerine geçer). Döner:
  /// [unregisterForeground]'a verilecek tutamaç — RestartWidget'ta yeni State
  /// eskisinin dispose'undan ÖNCE kaydolur; eski dispose yeni kaydı silmesin.
  static Object registerForeground(
      Future<void> Function(String op, String? babyId) handler) {
    unregisterForeground();
    final port = ReceivePort('adena-db-owner');
    _port = port;
    _sub = port.listen((msg) async {
      if (msg is! List || msg.isEmpty) return;
      final kind = msg[0];
      if (kind == 'ping' && msg.length == 2 && msg[1] is SendPort) {
        (msg[1] as SendPort).send('pong');
        return;
      }
      if (kind == 'run' && msg.length == 4 && msg[3] is SendPort) {
        final reply = msg[3] as SendPort;
        try {
          await handler(msg[1] as String, msg[2] as String?);
          reply.send('ok');
        } catch (e) {
          debugPrint('[db-owner] devredilen iş hata verdi: $e');
          reply.send('error');
        }
      }
    });
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    return port;
  }

  /// [handle] verilirse yalnız o kayıt hâlâ güncelse kaldırılır.
  static void unregisterForeground([Object? handle]) {
    final port = _port;
    if (port == null) return;
    if (handle != null && !identical(handle, port)) return;
    if (IsolateNameServer.lookupPortByName(portName) == port.sendPort) {
      IsolateNameServer.removePortNameMapping(portName);
    }
    _sub?.cancel();
    port.close();
    _port = null;
    _sub = null;
  }

  /// Arka plan: işi canlı ön plana devretmeyi dener.
  ///
  /// Döner:
  /// - [DelegateResult.noOwner] → ön plan yok/yanıtsız; çağıran KENDİSİ yapar.
  /// - [DelegateResult.done] / [DelegateResult.failed] / [DelegateResult.timedOut]
  ///   → ön plan canlı ve işi üstlendi; çağıran DB'ye DOKUNMAMALI (iş ön planda
  ///   sürüyor olabilir — paralel ikinci yazar açmak tam da önlenen durum).
  static Future<DelegateResult> delegate(String op,
      {String? babyId, required Duration timeout}) async {
    final owner = IsolateNameServer.lookupPortByName(portName);
    if (owner == null) return DelegateResult.noOwner;
    if (!await _ping(owner)) {
      // Bayat kayıt (motor yıkılmış, port kapanmış) → temizle, kendin yap.
      if (IsolateNameServer.lookupPortByName(portName) == owner) {
        IsolateNameServer.removePortNameMapping(portName);
      }
      return DelegateResult.noOwner;
    }
    final reply = ReceivePort();
    try {
      owner.send(['run', op, babyId, reply.sendPort]);
      final r = await reply.first.timeout(timeout);
      return r == 'ok' ? DelegateResult.done : DelegateResult.failed;
    } on TimeoutException {
      return DelegateResult.timedOut;
    } finally {
      reply.close();
    }
  }

  static Future<bool> _ping(SendPort owner) async {
    final reply = ReceivePort();
    try {
      owner.send(['ping', reply.sendPort]);
      final r = await reply.first.timeout(pingTimeout);
      return r == 'pong';
    } catch (_) {
      return false;
    } finally {
      reply.close();
    }
  }

  @visibleForTesting
  static bool get debugRegistered => _port != null;
}

enum DelegateResult {
  /// Canlı ön plan yok → çağıran işi kendisi yapar.
  noOwner,

  /// Ön plan işi bitirdi.
  done,

  /// Ön plan işi üstlendi ama hata aldı (ön plan kendi sonraki turunda dener).
  failed,

  /// Ön plan işi üstlendi, bütçe içinde bitmedi (ön planda sürüyor).
  timedOut,
}

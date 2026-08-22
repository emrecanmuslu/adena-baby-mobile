import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/app_database.dart';

/// Yerel drift veritabanının YANIT VERDİĞİNİ doğrulayan nöbetçi.
///
/// Neden var: 2026-07/08'de `shareAcrossIsolates: true` yüzünden drift bağlantısı
/// sessizce ölebiliyordu — hiçbir hata fırlatmadan tüm `watch()` stream'leri
/// sonsuza kadar "loading"de kalıyor, uygulama açılıyor ama Son Aktivite / Bugün /
/// Günlük Akış hep skeleton görünüyor, sync şeridi hiç kapanmıyordu. Çökme
/// olmadığı için Crashlytics'e HİÇBİR ŞEY düşmüyordu (`main.dart` watchdog'u
/// yalnız ilk frame gelmezse tetikleniyor; burada UI geliyor, sadece boş).
///
/// Kök neden [AppDatabase] içinde giderildi (bkz. `AppDatabase._open`). Bu sınıf
/// nüksetme ihtimaline karşı KANIT üretir: açılışta / öne gelişte / periyodik
/// olarak DB'ye ucuz bir `SELECT 1` atar; süre aşılırsa Crashlytics'e non-fatal
/// olarak düşer — üstelik son arka plan sync turunun zamanı/sonucu da custom key
/// olarak eklenir, böylece "hangi BGTask turundan sonra bozuldu" görünür.
class DbWatchdog {
  DbWatchdog._();
  static final DbWatchdog instance = DbWatchdog._();

  /// Sağlıklı DB'de `SELECT 1` milisaniyeler sürer. Bu süre aşılırsa bağlantı
  /// ölmüş/askıda demektir (bug hâlinde sorgu ASLA dönmüyordu).
  static const _probeTimeout = Duration(seconds: 6);

  /// Bu süreden yavaş ama başarılı probe → erken uyarı olarak loglanır.
  static const _slowProbe = Duration(seconds: 2);

  /// Aynı arızayı saniyede defalarca raporlamayalım (kota + gürültü).
  static const _reportCooldown = Duration(minutes: 5);

  /// Ön planda periyodik nabız — arıza uygulama açıkken başlarsa da yakalansın.
  static const _pulseInterval = Duration(minutes: 2);

  static const _kBgSyncMs = 'db_last_bg_sync_ms';
  static const _kBgSyncOutcome = 'db_last_bg_sync_outcome';

  DateTime? _lastReport;
  bool _probing = false;
  Timer? _pulse;

  /// Arka plan (workmanager) isolate'i her turda çağırır: turun bitiş zamanı +
  /// sonucu kalıcı yazılır. Ön plandaki rapora custom key olarak eklenir —
  /// arıza ile BGTask turu arasındaki bağı kanıtlamanın tek yolu (ayrı isolate,
  /// belleği paylaşmıyor).
  static Future<void> markBackgroundSync(String outcome) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBgSyncMs, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_kBgSyncOutcome, outcome);
    } catch (_) {
      // Prefs yazılamazsa telemetri eksilir; arka plan turu etkilenmemeli.
    }
  }

  /// Ön planda periyodik nabzı başlatır (idempotent).
  void startPulse(AppDatabase db) {
    _pulse?.cancel();
    _pulse = Timer.periodic(_pulseInterval, (_) => unawaited(check(db, 'pulse')));
  }

  void stopPulse() {
    _pulse?.cancel();
    _pulse = null;
  }

  /// DB'ye ucuz bir sorgu atar. Yanıt verirse `true`.
  ///
  /// [reason] rapora yazılır: 'startup' | 'resume' | 'pulse' | ...
  Future<bool> check(AppDatabase db, String reason) async {
    if (_probing) return true; // önceki probe hâlâ askıda → onun raporu yeter
    _probing = true;
    final sw = Stopwatch()..start();
    try {
      await db.customSelect('SELECT 1').get().timeout(_probeTimeout);
      sw.stop();
      if (sw.elapsed > _slowProbe) {
        _report('db_slow', reason, sw.elapsedMilliseconds, null);
      }
      return true;
    } catch (e) {
      sw.stop();
      _report('db_unresponsive', reason, sw.elapsedMilliseconds, e);
      return false;
    } finally {
      _probing = false;
    }
  }

  void _report(String kind, String reason, int ms, Object? error) {
    debugPrint('[db-watchdog] $kind — $reason (${ms}ms) ${error ?? ''}');
    final now = DateTime.now();
    final last = _lastReport;
    if (last != null && now.difference(last) < _reportCooldown) return;
    _lastReport = now;
    // Prefs okuması async → raporu bekletmeden, ek bilgiyle birlikte gönder.
    unawaited(_send(kind, reason, ms, error));
  }

  Future<void> _send(String kind, String reason, int ms, Object? error) async {
    var bgInfo = 'unknown';
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_kBgSyncMs);
      final outcome = prefs.getString(_kBgSyncOutcome) ?? '?';
      if (at != null) {
        final ago = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(at))
            .inMinutes;
        bgInfo = '$outcome, ${ago}dk önce';
      } else {
        bgInfo = 'hiç çalışmadı';
      }
    } catch (_) {}
    try {
      final c = FirebaseCrashlytics.instance;
      c.setCustomKey('db_probe_reason', reason);
      c.setCustomKey('db_probe_ms', ms);
      c.setCustomKey('db_last_bg_sync', bgInfo);
      c.log('[db-watchdog] $kind reason=$reason ms=$ms bgSync=$bgInfo');
      await c.recordError(
        '$kind: reason=$reason ms=$ms bgSync=($bgInfo) err=${error ?? '-'}',
        null,
        reason: 'db-watchdog',
        fatal: false,
      );
    } catch (_) {
      // Firebase hazır değil (çok erken çağrı) → sessiz; konsola zaten basıldı.
    }
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'db_watchdog.dart';

/// "Senkron sorunu" uyarısının saha teşhisi — Crashlytics **non-fatal** +
/// breadcrumb + custom key. Davranışı DEĞİŞTİRMEZ.
///
/// Neden var: iOS'ta uzun arka plan sonrası ilk açılışta uyarı çıkıyor,
/// "Tekrarla" düzeltmiyor, kapat-aç düzeltiyordu; ama uyarıyı tetikleyen
/// hata (`SyncService.syncAll` catch'leri) hiçbir yere yazılmıyordu. Bu sınıf
/// hangi aşamada, hangi uç noktada, hangi hata türüyle (Dio tipi / HTTP kodu /
/// alttaki istisna) düşüldüğünü; açılışın soğuk/sıcak olduğunu, arka planda
/// kalınan süreyi, bağlantı durumunu, refresh kilidinin durumunu, deneme
/// sayısını ve "Tekrarla" sonucunu kaydeder → hipotezler (bayat bağlantı,
/// refresh kilidi, DB kilidi, yapışkan durum) sahada ayrışır.
///
/// Kurallar: KİŞİSEL VERİ YOK (id'ler maskelenir, token/e-posta temizlenir,
/// kayıt içeriği hiç yazılmaz); aynı (aşama + hata türü) oturumda BİR kez
/// non-fatal, tekrarlar sayaç. Crashlytics bu uygulamada rızaya bağlı DEĞİL
/// (yalnız Analytics rızalı; bkz. `AnalyticsService`) — mevcut DbWatchdog /
/// SyncTelemetry ile aynı yüzey kullanılır.
abstract class CrashSink {
  void log(String message);
  void setCustomKey(String key, Object value);
  Future<void> recordError(Object error, StackTrace? stack, {String? reason});
}

/// Üretim: FirebaseCrashlytics. Firebase hazır değilse (çok erken çağrı /
/// test) her çağrı sessizce yutulur.
class FirebaseCrashSink implements CrashSink {
  const FirebaseCrashSink();
  @override
  void log(String message) {
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (_) {}
  }

  @override
  void setCustomKey(String key, Object value) {
    try {
      FirebaseCrashlytics.instance.setCustomKey(key, value);
    } catch (_) {}
  }

  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {String? reason}) async {
    try {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, reason: reason, fatal: false);
    } catch (_) {}
  }
}

/// Senkron aşamaları (custom key `sync_stage`).
class SyncStage {
  SyncStage._();
  static const sync = 'sync'; // POST /sync (kayıt push + pull)
  static const medication = 'medication'; // ilaç planı senkronu (sessiz)
  static const healthPush = 'health_push';
  static const healthPull = 'health_pull';
  static const cycle = 'cycle'; // adet senkronu (sessiz)
  static const refresh = 'refresh'; // /auth/refresh geçici hatası
  static const babies = 'babies';
  static const authMe = 'auth_me';
  static const settings = 'settings';
}

final _uuidRe = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
final _numSegRe = RegExp(r'/\d+(?=/|$)');
final _bearerRe = RegExp(r'Bearer\s+\S+');
final _jwtRe = RegExp(r'[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}');
final _emailRe = RegExp(r'[\w.+\-]+@[\w\-]+\.[\w.\-]+');
final _wsRe = RegExp(r'\s+');

/// Yol şablonu: UUID ve tamamen sayısal segmentler `{id}`; sorgu dizesi ve
/// host atılır. `/babies/3f2a…/sync?x=1` → `/babies/{id}/sync`.
String maskPath(String path) {
  var p = path;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) p = uri.path;
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  p = p.replaceAll(_uuidRe, '{id}');
  p = p.replaceAll(_numSegRe, '/{id}');
  return p.isEmpty ? '-' : p;
}

/// Hata mesajı temizliği: Bearer/JWT → `{token}`, e-posta → `{email}`,
/// UUID → `{id}`, boşluklar sıkıştırılır, en çok [max] karakter.
String sanitizeMessage(String s, {int max = 200}) {
  var out = s.replaceAll(_bearerRe, 'Bearer {token}');
  out = out.replaceAll(_jwtRe, '{token}');
  out = out.replaceAll(_emailRe, '{email}');
  out = out.replaceAll(_uuidRe, '{id}');
  out = out.replaceAll(_wsRe, ' ').trim();
  return out.length > max ? out.substring(0, max) : out;
}

/// Sınıflandırılmış senkron hatası (saf, test edilebilir).
class SyncErrorInfo {
  final String stage;
  final String endpoint; // maskeli yol şablonu; Dio dışı → '-'
  final String errorType; // DioExceptionType.name ya da 'exception'
  final int? httpStatus;
  final String exception; // alttaki istisna sınıfı
  final String message; // temizlenmiş, ≤200
  const SyncErrorInfo({
    required this.stage,
    required this.endpoint,
    required this.errorType,
    required this.httpStatus,
    required this.exception,
    required this.message,
  });

  /// Gürültü sınırı anahtarı: aşama + hata türü (+ HTTP kodu + istisna sınıfı).
  String get signature => '$stage|$errorType|${httpStatus ?? '-'}|$exception';
}

SyncErrorInfo classifySyncError(String stage, Object error, {String? endpoint}) {
  if (error is DioException) {
    final inner = error.error;
    final isRefresh = inner == 'refresh_transient';
    final innerName = inner == null
        ? '-'
        : (inner is String ? inner : inner.runtimeType.toString());
    final rawMsg = [
      if (error.message != null) error.message!,
      if (inner != null && inner is! String) inner.toString(),
    ].join(' | ');
    return SyncErrorInfo(
      stage: isRefresh ? SyncStage.refresh : stage,
      endpoint: maskPath(endpoint ?? error.requestOptions.path),
      errorType: error.type.name,
      httpStatus: error.response?.statusCode,
      exception: isRefresh ? 'refresh_transient' : innerName,
      message: sanitizeMessage(rawMsg),
    );
  }
  return SyncErrorInfo(
    stage: stage,
    endpoint: endpoint == null ? '-' : maskPath(endpoint),
    errorType: 'exception',
    httpStatus: null,
    exception: error.runtimeType.toString(),
    message: sanitizeMessage(error.toString()),
  );
}

/// Crashlytics'e düşen sentetik hata nesnesi (başlık = alanlar).
class SyncAlertError implements Exception {
  final SyncErrorInfo info;
  const SyncAlertError(this.info);
  @override
  String toString() => 'SyncAlertError: stage=${info.stage} '
      'type=${info.errorType} http=${info.httpStatus ?? '-'} '
      'exc=${info.exception} endpoint=${info.endpoint} msg=${info.message}';
}

/// Refresh kilidinin anlık görünümü (ApiClient'tan okunur; test doğrudan verir).
class RefreshLockSnapshot {
  final DateTime? inFlightSince;
  final RefreshResult? lastResult;
  final DateTime? lastFinishedAt;
  const RefreshLockSnapshot(
      {this.inFlightSince, this.lastResult, this.lastFinishedAt});

  factory RefreshLockSnapshot.of(ApiClient api) => RefreshLockSnapshot(
        inFlightSince: api.refreshInFlightSince,
        lastResult: api.lastRefreshResult,
        lastFinishedAt: api.lastRefreshFinishedAt,
      );
}

class SyncAlertTelemetry {
  SyncAlertTelemetry._(this._sink, this._now) : _processStart = _now();

  static SyncAlertTelemetry instance =
      SyncAlertTelemetry._(const FirebaseCrashSink(), DateTime.now);

  @visibleForTesting
  static SyncAlertTelemetry forTest(
          {required CrashSink sink, DateTime Function()? now}) =>
      SyncAlertTelemetry._(sink, now ?? DateTime.now);

  /// Son ön plan damgası (prefs) — soğuk açılışta "arka planda ne kadar
  /// kaldı"yı önceki süreçten taşır.
  static const lastForegroundKey = 'sync_tel_last_fg_ms';

  final CrashSink _sink;
  final DateTime Function() _now;
  final DateTime _processStart;

  // Yaşam döngüsü
  bool _sawPause = false;
  DateTime? _lastResumedAt;
  int? _lastBackgroundMinutes;

  // Oturum sayaçları
  final _seen = <String>{};
  int _repeats = 0;
  int _failedTours = 0;
  int _retryTaps = 0;
  bool _retryPending = false;
  String? _retrySig; // Tekrarla anındaki uyarı imzası
  String? _lastAlertSig; // uyarıyı tetikleyen son hata imzası
  String? _tourLastSig; // süren turun son hata imzası

  String? _versionCache;

  String get launchType => _sawPause ? 'warm' : 'cold';

  /// Uygulama ön plana ilk kez kuruldu (AdenaApp.initState). Soğuk açılış.
  void onAppStart() {
    unawaited(_noteForeground());
  }

  /// WidgetsBindingObserver.didChangeAppLifecycleState'ten.
  Future<void> onLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _noteForeground();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _sawPause = true;
      await _stampForeground();
    }
  }

  Future<void> _noteForeground() async {
    final now = _now();
    _lastResumedAt = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(lastForegroundKey);
      if (last != null) {
        _lastBackgroundMinutes =
            now.difference(DateTime.fromMillisecondsSinceEpoch(last)).inMinutes;
      }
    } catch (_) {}
    await _stampForeground();
  }

  Future<void> _stampForeground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(lastForegroundKey, _now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Senkron turu başladı (SyncService.syncAll).
  void onTourStart() {
    _tourLastSig = null;
  }

  /// Uyarıyı tetikleyen bir hata yakalandı. Oturumda ilk görülen imza →
  /// non-fatal; tekrarlar yalnız breadcrumb + `sync_err_repeats`.
  Future<void> onSyncError({
    required String stage,
    required Object error,
    StackTrace? stack,
    bool? online,
    ApiClient? api,
    RefreshLockSnapshot? refresh,
    String? endpoint,
  }) async {
    final info = classifySyncError(stage, error, endpoint: endpoint);
    _tourLastSig = info.signature;
    _lastAlertSig = info.signature;
    final isNew = _seen.add(info.signature);
    if (!isNew) _repeats++;
    // Bağlam — hepsi hatasız, kısa zaman aşımlı.
    final now = _now();
    final conn = await _connectivity();
    final bg = await DbWatchdog.lastBackgroundSyncSummary();
    final ver = await _version();
    final lock = refresh ?? (api == null ? null : RefreshLockSnapshot.of(api));
    final inflightAge = lock?.inFlightSince == null
        ? null
        : now.difference(lock!.inFlightSince!).inMilliseconds;
    final sinceFg = now.difference(_lastResumedAt ?? _processStart).inMilliseconds;
    final keys = <String, Object>{
      'sync_stage': info.stage,
      'sync_endpoint': info.endpoint,
      'sync_err_type': info.errorType,
      'sync_http': info.httpStatus ?? '-',
      'sync_exc': info.exception,
      'sync_launch': launchType,
      'sync_bg_min': _lastBackgroundMinutes ?? -1,
      'sync_fg_ms': sinceFg,
      'sync_online': online == null ? 'unknown' : (online ? 'yes' : 'no'),
      'sync_conn': conn,
      'sync_refresh_inflight': lock?.inFlightSince == null ? 'no' : 'yes',
      'sync_refresh_age_ms': inflightAge ?? -1,
      'sync_refresh_last': lock == null
          ? '-'
          : '${lock.lastResult?.name ?? '-'}'
              '${lock.lastFinishedAt == null ? '' : ' ${now.difference(lock.lastFinishedAt!).inSeconds}s önce'}',
      'sync_attempts': _failedTours + 1, // bu tur dahil
      'sync_retry_tapped': _retryTaps,
      'sync_last_bg': bg,
      'sync_err_repeats': _repeats,
      'app_version': ver,
      'platform': _platform(),
    };
    keys.forEach(_sink.setCustomKey);
    final line = '[sync] sync_error ${keys.entries.map((e) => '${e.key}=${e.value}').join(' ')} '
        'msg=${info.message}';
    debugPrint(line);
    _sink.log(line);
    if (isNew) {
      await _sink.recordError(SyncAlertError(info), stack, reason: 'sync-alert');
    }
  }

  /// Tur bitti. [failed] = uyarıyı tetikleyen en az bir hata oldu.
  void onTourFinished({required bool failed}) {
    if (failed) {
      _failedTours++;
    } else {
      _failedTours = 0;
    }
    _sink.setCustomKey('sync_attempts', _failedTours);
    if (_retryPending) {
      _retryPending = false;
      final result = !failed
          ? 'success'
          : (_tourLastSig == _retrySig ? 'same_error' : 'different_error');
      _sink.setCustomKey('sync_retry_result', result);
      _sink.log('[sync] sync_retry_result result=$result '
          'sig=${_tourLastSig ?? '-'} attempts=$_failedTours');
    }
  }

  /// Uyarı şeridi görünür oldu (gizliden görünüre geçiş).
  void markAlertShown() {
    _sink.log('[sync] sync_alert_shown sig=${_lastAlertSig ?? '-'} '
        'attempts=$_failedTours launch=$launchType');
  }

  /// Kullanıcı "Şimdi yeniden dene"ye bastı; sonucu takip turu yazar.
  void markRetryTapped() {
    _retryTaps++;
    _retryPending = true;
    _retrySig = _lastAlertSig;
    _sink.setCustomKey('sync_retry_tapped', _retryTaps);
    _sink.log('[sync] sync_retry_tapped n=$_retryTaps sig=${_retrySig ?? '-'}');
  }

  Future<String> _connectivity() async {
    try {
      final r = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      if (r.isEmpty) return 'none';
      return r.map((e) => e.name).join('+');
    } catch (_) {
      return 'unknown';
    }
  }

  Future<String> _version() async {
    if (_versionCache != null) return _versionCache!;
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 2));
      _versionCache = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _versionCache = '?';
    }
    return _versionCache!;
  }

  String _platform() {
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
      return Platform.operatingSystem;
    } catch (_) {
      return '?';
    }
  }
}

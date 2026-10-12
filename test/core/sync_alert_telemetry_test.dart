import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/sync_alert_telemetry.dart';
import 'package:adena_baby/core/token_storage.dart';

/// Sahte Crashlytics yüzeyi — çağrıları toplar.
class _FakeSink implements CrashSink {
  final logs = <String>[];
  final keys = <String, Object>{};
  final errors = <(Object, String?)>[];
  @override
  void log(String message) => logs.add(message);
  @override
  void setCustomKey(String key, Object value) => keys[key] = value;
  @override
  Future<void> recordError(Object error, StackTrace? stack,
          {String? reason}) async =>
      errors.add((error, reason));
}

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'a';
  @override
  Future<String?> get refreshToken async => 'r';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

DioException _dio(String path,
        {DioExceptionType type = DioExceptionType.connectionError,
        int? status,
        Object? error,
        String? message}) =>
    DioException(
      requestOptions: RequestOptions(path: path),
      type: type,
      response: status == null
          ? null
          : Response(requestOptions: RequestOptions(path: path), statusCode: status),
      error: error,
      message: message,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSink sink;
  late SyncAlertTelemetry tel;
  var now = DateTime(2026, 10, 11, 9, 0);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Adena', packageName: 'x', version: '1.5.0',
        buildNumber: '66', buildSignature: '');
    sink = _FakeSink();
    now = DateTime(2026, 10, 11, 9, 0);
    tel = SyncAlertTelemetry.forTest(sink: sink, now: () => now);
  });

  group('maskPath', () {
    test('UUID ve sayısal id segmentleri maskelenir, sorgu atılır', () {
      expect(
          maskPath('/babies/3f2a9c1e-1b2c-4d5e-8f90-abcdef123456/sync?x=1'),
          '/babies/{id}/sync');
      expect(maskPath('/cycle/entries/42'), '/cycle/entries/{id}');
      expect(maskPath('https://api.adenababy.com/api/v1/babies/7/health/sync'),
          '/api/v1/babies/{id}/health/sync');
      expect(maskPath('/sync'), '/sync');
    });
  });

  group('sanitizeMessage', () {
    test('token / e-posta / uuid temizlenir, 200 karaktere kesilir', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      final s = sanitizeMessage(
          'Authorization: Bearer $jwt user ayse@example.com '
          'id 3f2a9c1e-1b2c-4d5e-8f90-abcdef123456 token=$jwt');
      expect(s, isNot(contains('eyJ')));
      expect(s, isNot(contains('@example.com')));
      expect(s, isNot(contains('3f2a9c1e')));
      expect(s, contains('{token}'));
      expect(s, contains('{email}'));
      expect(s, contains('{id}'));
      final long = sanitizeMessage('x' * 500);
      expect(long.length, 200);
    });
  });

  group('classifySyncError', () {
    test('Dio hatası: tip, HTTP kodu, alt istisna sınıfı, uç nokta', () {
      final info = classifySyncError(
        SyncStage.sync,
        _dio('/babies/3f2a9c1e-1b2c-4d5e-8f90-abcdef123456/health/sync',
            type: DioExceptionType.badResponse,
            status: 502,
            error: const SocketException('reset'),
            message: 'Bad response'),
      );
      expect(info.stage, SyncStage.sync);
      expect(info.endpoint, '/babies/{id}/health/sync');
      expect(info.errorType, 'badResponse');
      expect(info.httpStatus, 502);
      expect(info.exception, 'SocketException');
      expect(info.signature, 'sync|badResponse|502|SocketException');
    });

    test('refresh_transient → aşama refresh', () {
      final info = classifySyncError(
          SyncStage.sync,
          _dio('/sync',
              type: DioExceptionType.connectionTimeout,
              error: 'refresh_transient'));
      expect(info.stage, SyncStage.refresh);
      expect(info.endpoint, '/sync');
      expect(info.errorType, 'connectionTimeout');
    });

    test('Dio dışı istisna (ör. DB kilidi) sınıf adıyla kaydedilir', () {
      final info = classifySyncError(
          SyncStage.healthPull, StateError('database is locked'));
      expect(info.stage, SyncStage.healthPull);
      expect(info.endpoint, '-');
      expect(info.errorType, 'exception');
      expect(info.httpStatus, isNull);
      expect(info.exception, 'StateError');
      expect(info.message, contains('database is locked'));
    });
  });

  group('kayıt', () {
    test('alanlar custom key + breadcrumb + non-fatal olarak düşer', () async {
      final api = ApiClient(_FakeTokens());
      tel.onAppStart();
      tel.onTourStart();
      await tel.onSyncError(
        stage: SyncStage.sync,
        error: _dio('/sync', error: const SocketException('abort')),
        stack: StackTrace.current,
        online: true,
        api: api,
      );
      expect(sink.errors, hasLength(1));
      expect(sink.errors.single.$2, 'sync-alert');
      expect(sink.errors.single.$1.toString(), contains('stage=sync'));
      expect(sink.keys['sync_stage'], 'sync');
      expect(sink.keys['sync_endpoint'], '/sync');
      expect(sink.keys['sync_err_type'], 'connectionError');
      expect(sink.keys['sync_http'], '-');
      expect(sink.keys['sync_exc'], 'SocketException');
      expect(sink.keys['sync_launch'], 'cold');
      expect(sink.keys['sync_online'], 'yes');
      expect(sink.keys['sync_refresh_inflight'], 'no');
      expect(sink.keys['sync_attempts'], 1);
      expect(sink.keys['sync_retry_tapped'], 0);
      expect(sink.keys['sync_last_bg'], 'hiç çalışmadı');
      expect(sink.keys['app_version'], '1.5.0+66');
      expect(sink.keys.containsKey('platform'), isTrue);
      expect(sink.keys.containsKey('sync_conn'), isTrue);
      expect(sink.keys.containsKey('sync_fg_ms'), isTrue);
      expect(sink.logs.any((l) => l.contains('sync_error')), isTrue);
    });

    test('aynı aşama+hata türü oturumda bir kez non-fatal; tekrar sayaç',
        () async {
      tel.onAppStart();
      final e = _dio('/sync', type: DioExceptionType.receiveTimeout);
      tel.onTourStart();
      await tel.onSyncError(stage: SyncStage.sync, error: e, online: true);
      tel.onTourStart();
      await tel.onSyncError(stage: SyncStage.sync, error: e, online: true);
      tel.onTourStart();
      await tel.onSyncError(stage: SyncStage.sync, error: e, online: true);
      expect(sink.errors, hasLength(1));
      expect(sink.keys['sync_err_repeats'], 2);
      // Farklı tür → yeni non-fatal.
      await tel.onSyncError(
          stage: SyncStage.sync,
          error: _dio('/sync', type: DioExceptionType.badResponse, status: 500),
          online: true);
      expect(sink.errors, hasLength(2));
    });

    test('uyarı gösterildi + Tekrarla + sonuç breadcrumb\'ları', () async {
      tel.onAppStart();
      final e = _dio('/sync', type: DioExceptionType.connectionError);
      tel.onTourStart();
      await tel.onSyncError(stage: SyncStage.sync, error: e, online: true);
      tel.onTourFinished(failed: true);
      tel.markAlertShown();
      expect(sink.logs.any((l) => l.contains('sync_alert_shown')), isTrue);

      // Tekrarla → aynı hata.
      tel.markRetryTapped();
      expect(sink.keys['sync_retry_tapped'], 1);
      tel.onTourStart();
      await tel.onSyncError(stage: SyncStage.sync, error: e, online: true);
      tel.onTourFinished(failed: true);
      expect(sink.keys['sync_retry_result'], 'same_error');
      expect(sink.keys['sync_attempts'], 2);

      // Tekrarla → farklı hata.
      tel.markRetryTapped();
      tel.onTourStart();
      await tel.onSyncError(
          stage: SyncStage.healthPush,
          error: _dio('/babies/1/health/sync',
              type: DioExceptionType.badResponse, status: 503),
          online: true);
      tel.onTourFinished(failed: true);
      expect(sink.keys['sync_retry_result'], 'different_error');

      // Tekrarla → başarılı; sayaç sıfırlanır.
      tel.markRetryTapped();
      tel.onTourStart();
      tel.onTourFinished(failed: false);
      expect(sink.keys['sync_retry_result'], 'success');
      expect(sink.keys['sync_attempts'], 0);
      expect(
          sink.logs.where((l) => l.startsWith('[sync] sync_retry_tapped')).length,
          3);
    });

    test('soğuk/sıcak açılış ve arka plan süresi', () async {
      // Önceki süreçten kalan "son ön plan" damgası: 90 dk önce.
      SharedPreferences.setMockInitialValues({
        SyncAlertTelemetry.lastForegroundKey:
            now.subtract(const Duration(minutes: 90)).millisecondsSinceEpoch,
      });
      tel.onAppStart();
      await tel.onLifecycle(AppLifecycleState.resumed); // iOS açılışta da yollar
      await tel.onSyncError(
          stage: SyncStage.sync, error: _dio('/sync'), online: true);
      expect(sink.keys['sync_launch'], 'cold');
      expect(sink.keys['sync_bg_min'], 90);

      // Arka plana in, 30 dk sonra dön → sıcak.
      await tel.onLifecycle(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 30));
      await tel.onLifecycle(AppLifecycleState.resumed);
      now = now.add(const Duration(milliseconds: 1500));
      await tel.onSyncError(
          stage: SyncStage.sync,
          error: _dio('/sync', type: DioExceptionType.receiveTimeout),
          online: false);
      expect(sink.keys['sync_launch'], 'warm');
      expect(sink.keys['sync_bg_min'], 30);
      expect(sink.keys['sync_fg_ms'], 1500);
      expect(sink.keys['sync_online'], 'no');
    });

    test('refresh kilidi uçuştaysa yaşı yazılır', () async {
      final api = ApiClient(_FakeTokens());
      tel.onAppStart();
      await tel.onSyncError(
          stage: SyncStage.sync,
          error: _dio('/sync'),
          online: true,
          refresh: RefreshLockSnapshot(
              inFlightSince: now.subtract(const Duration(seconds: 7)),
              lastResult: RefreshResult.transient,
              lastFinishedAt: now.subtract(const Duration(minutes: 2))));
      expect(sink.keys['sync_refresh_inflight'], 'yes');
      expect(sink.keys['sync_refresh_age_ms'], 7000);
      expect(sink.keys['sync_refresh_last'], contains('transient'));
      expect(api.refreshInFlightSince, isNull);
    });
  });

  group('onSilentStageError (Adım 0: ilaç planı senkronu sessiz hatası)', () {
    DioException err403() {
      final ro = RequestOptions(path: '/babies/3f2a9c1e-1b2c-4d5e-8f90-abcdef123456/medication-plans/sync');
      return DioException(
          requestOptions: ro,
          response: Response(requestOptions: ro, statusCode: 403),
          type: DioExceptionType.badResponse);
    }

    test('aynı (aşama+hata) oturumda bir kez non-fatal; uyarı imzalarına dokunmaz', () async {
      await tel.onSilentStageError(stage: SyncStage.medication, error: err403());
      await tel.onSilentStageError(stage: SyncStage.medication, error: err403());
      expect(sink.errors, hasLength(1));
      expect(sink.errors.single.$2, 'sync-silent');
      expect(sink.keys['sync_silent_stage'], 'medication');
      expect(sink.logs.single, contains('medication'));
      expect(sink.logs.single, isNot(contains('3f2a9c1e')));
      // Uyarı bağlamı (Tekrarla sonucu vb.) etkilenmez.
      tel.onTourFinished(failed: false);
      expect(sink.keys['sync_attempts'], 0);
    });
  });
}

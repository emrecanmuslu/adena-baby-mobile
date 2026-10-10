import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/models/cycle.dart';

/// O6 (BULGULAR.md / TASARIM-SENKRON.md R1, R8, K-8): adet ayarında "sunucu
/// kazanır"dı — gönderilememiş yerel ayar ilk GET'te eziliyordu; patchSettings
/// önce GET yapıyordu; dirty ayar yalnız göçte yeniden deneniyordu; `baby=null`
/// hiç gönderilmiyordu; ekranlar ağı bekliyordu (O26).
class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'fake-access';
  @override
  Future<String?> get refreshToken async => 'fake-refresh';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

class _Rec extends Interceptor {
  final List<({String method, String path, Object? data})> calls = [];
  bool sent(String m, String p) => calls.any((c) => c.method == m && c.path == p);
  Map<String, dynamic>? body(String m, String p) {
    for (final c in calls) {
      if (c.method == m && c.path == p && c.data is Map) {
        return Map<String, dynamic>.from(c.data as Map);
      }
    }
    return null;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls.add((method: options.method, path: options.path, data: options.data));
    handler.next(options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const acct = 'acct-o6';
  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late _Rec rec;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    rec = _Rec();
    api.dio.interceptors.add(rec);
    db = AppDatabase(NativeDatabase.memory());
    LocalSession.setActiveAccount(acct);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  CycleRepository localRepo() => CycleRepository(db, api, () => false);
  CycleRepository cloudRepo() => CycleRepository(db, api, () => true);

  Future<CycleSettingsRow?> row() =>
      (db.select(db.cycleSettingsTable)..where((r) => r.id.equals(acct)))
          .getSingleOrNull();

  Map<String, dynamic> serverJson({String? firstPeriod = '2026-03-01', int? cycleLen}) => {
        'baby': null,
        'breastfeeding': 'mixed',
        'first_period_date': firstPeriod,
        'reminders': {},
        'show_fertility_warning': true,
        'enabled': true,
        'expected_cycle_length': cycleLen,
        'lifecycle_mode': 'tracking',
      };

  // ───────── MEVCUT API ─────────
  group('O6 — çevrimdışı patch, online GET ezmez', () {
    test('PATCH 503 → dirty; sonra getSettings GET sonucunu dirty satıra uygulamaz',
        () async {
      adapter.onPatch('/cycle/settings', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      await cloudRepo().patchSettings({'expected_cycle_length': 31});
      expect((await row())!.dirty, isTrue);

      // Ağ geldi ama sunucu eski değeri döndürüyor (bizim PATCH hiç gitmedi).
      adapter.onGet('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 28)));
      final s = await cloudRepo().getSettings();

      expect(s.expectedCycleLength, 31, reason: 'yerel dirty değer korunmalı');
      expect((await row())!.dirty, isTrue);
    });

    test('patchSettings yerel dirty değişikliği GET ile ezmeden üstüne yazar',
        () async {
      adapter.onPatch('/cycle/settings', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      await cloudRepo().patchSettings({'expected_cycle_length': 31}); // dirty kaldı
      adapter.onGet('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 28)));

      // İkinci patch (başka alan) — ilk değişiklik ezilmemeli.
      final next = await cloudRepo().patchSettings({'period_length': 6});
      expect(next.expectedCycleLength, 31);
      expect(next.periodLength, 6);
    });
  });

  group('O6 — baby alanı (K-8)', () {
    test('baby açıkça null\'lanınca PATCH gövdesinde "baby": null gider', () async {
      await localRepo().patchSettings({'baby': 'baby-1'});
      adapter.onPatch('/cycle/settings', (s) => s.reply(200, serverJson()),
          data: Matchers.any);

      await cloudRepo().patchSettings({'baby': null});

      final body = rec.body('PATCH', '/cycle/settings');
      expect(body, isNotNull);
      expect(body!.containsKey('baby'), isTrue);
      expect(body['baby'], isNull);
    });

    test('baby zaten null ve değişmediyse PATCH gövdesinde alan gitmez', () async {
      adapter.onPatch('/cycle/settings', (s) => s.reply(200, serverJson()),
          data: Matchers.any);
      await cloudRepo().patchSettings({'enabled': false});
      final body = rec.body('PATCH', '/cycle/settings');
      expect(body, isNotNull);
      expect(body!.containsKey('baby'), isFalse);
    });
  });

  // ───────── YENİ API ─────────
  group('O6 — syncIfCloud: dirty ayar yeniden denenir; R8', () {
    test('dirty ayar syncIfCloud\'da PATCH edilir, temizlenir; GET sonrası uygulanmaz',
        () async {
      adapter.onPatch('/cycle/settings', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      await cloudRepo().patchSettings({'expected_cycle_length': 31});
      expect((await row())!.dirty, isTrue);

      // Ağ geldi: PATCH başarılı (sunucu güncel hâli döner); GET eski değeri
      // döndürse bile uygulanmamalı (PATCH yanıtı otoriter).
      adapter
        ..onPatch('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 31)),
            data: Matchers.any)
        ..onGet('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 28)));

      await cloudRepo().syncIfCloud();

      final r = await row();
      expect(r!.dirty, isFalse);
      expect(r.expectedCycleLength, 31);
    });

    test('temiz ayar: syncIfCloud GET sonucunu uygular', () async {
      adapter.onGet('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 29)));
      await cloudRepo().syncIfCloud();
      expect((await row())!.expectedCycleLength, 29);
      expect(rec.sent('PATCH', '/cycle/settings'), isFalse);
    });

    test('dirty ayar + PATCH yine 503 → GET uygulanmaz, dirty kalır', () async {
      adapter.onPatch('/cycle/settings', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      await cloudRepo().patchSettings({'expected_cycle_length': 31});
      adapter.onGet('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 28)));

      await cloudRepo().syncIfCloud();

      final r = await row();
      expect(r!.dirty, isTrue);
      expect(r.expectedCycleLength, 31);
    });

    test('dirty satırın yeniden denenen PATCH gövdesi yerel gerçeği (baby null dahil) taşır',
        () async {
      await localRepo().patchSettings({'baby': 'baby-1'});
      adapter.onPatch('/cycle/settings', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      await cloudRepo().patchSettings({'baby': null}); // gönderilemedi, dirty
      rec.calls.clear();
      adapter
        ..onPatch('/cycle/settings', (s) => s.reply(200, serverJson()),
            data: Matchers.any)
        ..onGet('/cycle/settings', (s) => s.reply(200, serverJson()));

      await cloudRepo().syncIfCloud();

      final body = rec.body('PATCH', '/cycle/settings');
      expect(body!.containsKey('baby'), isTrue);
      expect(body['baby'], isNull);
    });

    test('watchSettings / watchEntries: ağ olmadan yerelden akar (cloud açık, stub yok)',
        () async {
      final repo = cloudRepo();
      await localRepo().patchSettings({'expected_cycle_length': 30});
      await localRepo().saveEntry(
          CycleEntry(id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.medium));

      final s = await repo.watchSettings().first;
      expect(s.expectedCycleLength, 30);
      final e = await repo.watchEntries().first;
      expect(e, hasLength(1));
      expect(rec.calls, isEmpty, reason: 'okuma ağa çıkmamalı');
    });

    test('syncIfCloud cloud kapalıyken ağa hiç çıkmaz', () async {
      await localRepo().syncIfCloud();
      expect(rec.calls, isEmpty);
    });
  });

  // ───────── K8 (3. madde): importFromCloud dirty ayarı ezmez ─────────
  group('K8 — importFromCloud dirty ayar satırını ezmez', () {
    test('yerel dirty ayar (göçten) + sunucu varsayılanı → yerel korunur', () async {
      await localRepo().patchSettings({
        'breastfeeding': 'mixed',
        'lifecycle_mode': 'loss',
        'last_loss_date': '2026-04-01',
      }); // dirty (cloud kapalı)
      adapter
        ..onGet('/cycle/settings', (s) => s.reply(200, {'breastfeeding': ''}))
        ..onGet('/cycle/entries', (s) => s.reply(200, []));

      await cloudRepo().importFromCloud();

      final r = await row();
      expect(r!.dirty, isTrue);
      expect(r.lifecycleMode, 'loss');
      expect(r.breastfeeding, 'mixed');
    });

    test('temiz yerel ayar → sunucu uygulanır (import davranışı korunur)', () async {
      adapter
        ..onGet('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 29)))
        ..onGet('/cycle/entries', (s) => s.reply(200, []));
      await cloudRepo().importFromCloud();
      expect((await row())!.expectedCycleLength, 29);
    });
  });
}

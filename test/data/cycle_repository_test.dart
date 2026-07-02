import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/models/cycle.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const acct = 'acct-1';

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    LocalSession.setActiveAccount(acct); // adet modülü hesaba kapsamlı
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  CycleRepository localRepo() => CycleRepository(db, api, () => false);
  CycleRepository cloudRepo() => CycleRepository(db, api, () => true);

  group('getSettings — aktif hesaba kapsamlı', () {
    test('hesap yoksa boş varsayılan döner (ağ yok)', () async {
      LocalSession.setActiveAccount(null);
      final s = await localRepo().getSettings();
      expect(s.enabled, isTrue);
      expect(s.firstPeriodDate, isNull);
      expect(s.babyId, isNull);
    });

    test('yerel satır yoksa varsayılan; settings id = hesap id', () async {
      final s = await localRepo().getSettings();
      expect(s.showFertilityWarning, isTrue);
      // patch sonrası tekil satır hesap id'siyle yazılmalı
      await localRepo().patchSettings({'enabled': false});
      final row = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(acct)))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.id, acct);
      expect(row.enabled, isFalse);
    });
  });

  group('patchSettings — merge + dirty + cloud patch', () {
    test('cloud kapalı: yerel merge, dirty=true', () async {
      await localRepo().patchSettings({
        'breastfeeding': 'exclusive',
        'first_period_date': '2026-03-01',
        'show_fertility_warning': false,
      });
      final next = await localRepo().patchSettings({'enabled': false});

      // önceki alanlar korunur (merge), yeni alan uygulanır
      expect(next.breastfeeding, Breastfeeding.exclusive);
      expect(next.firstPeriodDate, DateTime(2026, 3, 1));
      expect(next.showFertilityWarning, isFalse);
      expect(next.enabled, isFalse);

      final row = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(acct)))
          .getSingle();
      expect(row.dirty, isTrue);
      expect(row.breastfeeding, 'exclusive');
    });

    test('tahmin ayarları (döngü/adet/luteal) yerelde KALICI olur (regresyon)',
        () async {
      // Daha önce DB kolonu yoktu → değer yazılıp okunduğunda kayboluyordu (28'e
      // dönüyordu). Artık tur-gidiş-dönüş korunmalı.
      await localRepo().patchSettings({
        'expected_cycle_length': 30,
        'period_length': 6,
        'luteal_phase_length': 12,
      });
      final reread = await localRepo().getSettings();
      expect(reread.expectedCycleLength, 30);
      expect(reread.periodLength, 6);
      expect(reread.lutealPhaseLength, 12);

      // Satır da doğru kolonlara yazılmış olmalı.
      final row = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(acct)))
          .getSingle();
      expect(row.expectedCycleLength, 30);
      expect(row.periodLength, 6);
      expect(row.lutealPhaseLength, 12);
    });

    test('cloud açık: PATCH /cycle/settings gönderir, dirty temizlenir',
        () async {
      // getSettings cloud açıkken /cycle/settings GET de yapar → stub'la
      adapter
        ..onGet('/cycle/settings', (s) => s.reply(200, _settingsJson()))
        ..onPatch('/cycle/settings', (s) => s.reply(200, _settingsJson()),
            data: Matchers.any);

      await cloudRepo().patchSettings({'enabled': true});
      final row = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(acct)))
          .getSingle();
      expect(row.dirty, isFalse); // _markSettingsClean
    });
  });

  group('saveEntry — gün-tekli kayıt + faz/akış bütünlüğü', () {
    test('flow/lochia/symptoms/mood yerelde, dirty=true, gün-only tarih',
        () async {
      final e = CycleEntry(
        id: '',
        date: DateTime(2026, 6, 1, 14, 30), // saat atılmalı
        flow: FlowLevel.heavy,
        lochiaColor: LochiaColor.yellowWhite,
        symptoms: const ['cramp', 'headache'],
        mood: 3,
        note: 'yorgun',
      );
      final saved = await localRepo().saveEntry(e);

      expect(saved.id, isNotEmpty);
      expect(saved.date, DateTime(2026, 6, 1)); // gün-only
      expect(saved.flow, FlowLevel.heavy);
      expect(saved.lochiaColor, LochiaColor.yellowWhite);
      expect(saved.symptoms, ['cramp', 'headache']);
      expect(saved.mood, 3);
      // Loşia rengi set olduğunda gün ADET sayılmaz (yeni kural): doğum sonrası
      // loşia günü yanlışlıkla döngü başlatmasın. Adet günü loşia rengi taşımaz.
      expect(saved.isPeriod, isFalse);

      final row = await (db.select(db.cycleEntries)
            ..where((r) => r.id.equals(saved.id)))
          .getSingle();
      expect(row.dirty, isTrue);
      expect(row.accountId, acct);
      expect(row.flow, 'heavy');
      expect(row.lochiaColor, 'yellow_white'); // apiValue saklanır
      expect(jsonDecode(row.symptoms), ['cramp', 'headache']);
      expect(row.clientUpdatedAt, isNotNull);
    });

    test('aynı güne yeni kayıt mevcut kaydı (id) günceller', () async {
      final first = await localRepo().saveEntry(CycleEntry(
          id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.light));
      final second = await localRepo().saveEntry(CycleEntry(
          id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.heavy));

      expect(second.id, first.id); // aynı gün → aynı id
      final list = await localRepo().listEntries();
      expect(list.length, 1);
      expect(list.single.flow, FlowLevel.heavy);
    });

    test('spotting period sayılmaz', () async {
      final s = await localRepo().saveEntry(
          CycleEntry(id: '', date: DateTime(2026, 6, 2), flow: FlowLevel.spotting));
      expect(s.isPeriod, isFalse);
    });
  });

  group('listEntries — filtre + sıralama + hesap izolasyonu', () {
    test('from/to aralığı, yeni→eski sıralı', () async {
      final repo = localRepo();
      await repo
          .saveEntry(CycleEntry(id: '', date: DateTime(2026, 1, 1)));
      await repo
          .saveEntry(CycleEntry(id: '', date: DateTime(2026, 6, 1)));
      await repo
          .saveEntry(CycleEntry(id: '', date: DateTime(2026, 3, 1)));

      final all = await repo.listEntries();
      expect(all.map((e) => e.date).toList(),
          [DateTime(2026, 6, 1), DateTime(2026, 3, 1), DateTime(2026, 1, 1)]);

      final ranged = await repo.listEntries(
          from: DateTime(2026, 2, 1), to: DateTime(2026, 5, 1));
      expect(ranged.map((e) => e.date).toList(), [DateTime(2026, 3, 1)]);
    });

    test('başka hesabın kayıtları sızmaz', () async {
      await localRepo().saveEntry(CycleEntry(id: '', date: DateTime(2026, 1, 1)));
      LocalSession.setActiveAccount('other-acct');
      final list = await localRepo().listEntries();
      expect(list, isEmpty);
    });
  });

  group('deleteEntry — soft-delete tombstone', () {
    test('isDeleted+dirty, listeden gizli', () async {
      final e = await localRepo()
          .saveEntry(CycleEntry(id: '', date: DateTime(2026, 1, 1)));
      await localRepo().deleteEntry(e.id);

      final row = await (db.select(db.cycleEntries)
            ..where((r) => r.id.equals(e.id)))
          .getSingle();
      expect(row.isDeleted, isTrue);
      expect(row.dirty, isTrue);
      expect(await localRepo().listEntries(), isEmpty);
    });
  });

  group('_pullEntries — JSON → satır eşleme (importFromCloud)', () {
    test('sunucu girdilerini dirty=false yerele indirir', () async {
      adapter
        ..onGet('/cycle/settings', (s) => s.reply(200, _settingsJson()))
        ..onGet('/cycle/entries', (s) {
          s.reply(200, [
            {
              'id': 'e-1',
              'date': '2026-05-10',
              'flow': 'medium',
              'lochia_color': 'yellow_white',
              'symptoms': ['cramp'],
              'mood': 4,
              'note': 'ok',
            }
          ]);
        });

      await cloudRepo().importFromCloud();

      final row = await (db.select(db.cycleEntries)
            ..where((r) => r.id.equals('e-1')))
          .getSingle();
      expect(row.dirty, isFalse);
      expect(row.flow, 'medium');
      expect(row.lochiaColor, 'yellow_white');
      expect(row.mood, 4);
      expect(row.accountId, acct);
      // ayar da indirilmiş
      final s = await localRepo().getSettings();
      expect(s.firstPeriodDate, DateTime(2026, 3, 1));
    });
  });

  group('migrateToCloud — endpoint + payload doğrulama', () {
    test('dirty ayar PATCH + dirty girdi POST eder', () async {
      // dirty ayar + dirty girdi üret (cloud kapalı)
      await localRepo().patchSettings({
        'first_period_date': '2026-03-01',
        'breastfeeding': 'mixed',
      });
      final entry = await localRepo().saveEntry(CycleEntry(
          id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.medium));

      final rec = RequestRecorder();
      api.dio.interceptors.add(rec);
      adapter
        ..onPatch('/cycle/settings', (s) => s.reply(200, _settingsJson()),
            data: Matchers.any)
        ..onPost('/cycle/entries/bulk', (s) => s.reply(200, {'saved': [entry.id]}),
            data: Matchers.any);

      await cloudRepo().migrateToCloud();

      final patchBody = rec.body('PATCH', '/cycle/settings');
      expect(patchBody, isNotNull, reason: 'PATCH /cycle/settings çağrılmalı');
      expect(patchBody!['first_period_date'], '2026-03-01');
      expect(patchBody['breastfeeding'], 'mixed');

      // Girdiler tek toplu istekle (/cycle/entries/bulk) array olarak gönderilir.
      final postList = rec.listBody('POST', '/cycle/entries/bulk');
      expect(postList, isNotNull, reason: 'POST /cycle/entries/bulk çağrılmalı');
      final postBody = Map<String, dynamic>.from(postList!.first as Map);
      expect(postBody['id'], entry.id);
      expect(postBody['flow'], 'medium');
      expect(postBody['date'], '2026-06-01');

      // başarı sonrası temizlenmiş
      final settingsRow = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(acct)))
          .getSingle();
      expect(settingsRow.dirty, isFalse);
      final entryRow = await (db.select(db.cycleEntries)
            ..where((r) => r.id.equals(entry.id)))
          .getSingle();
      expect(entryRow.dirty, isFalse);
    });

    test('temiz ayar varsa PATCH atlanır, sadece girdi push edilir', () async {
      // ayar yok (varsayılan, satır yok → dirty değil); sadece girdi
      final entry = await localRepo()
          .saveEntry(CycleEntry(id: '', date: DateTime(2026, 6, 1)));

      final rec = RequestRecorder();
      api.dio.interceptors.add(rec);
      adapter
        ..onPatch('/cycle/settings', (s) => s.reply(200, _settingsJson()),
            data: Matchers.any)
        ..onPost('/cycle/entries/bulk', (s) => s.reply(200, {'saved': [entry.id]}),
            data: Matchers.any);

      await cloudRepo().migrateToCloud();
      // ayar satırı yok → PATCH gönderilmez; yalnız girdi push edilir
      expect(rec.sent('PATCH', '/cycle/settings'), isFalse);
      expect(rec.sent('POST', '/cycle/entries/bulk'), isTrue);
    });
  });

  group('markAllDirty — migrasyon işaretleme', () {
    test('aktif hesabın girdi + ayarını dirty yapar', () async {
      final e = await localRepo()
          .saveEntry(CycleEntry(id: '', date: DateTime(2026, 1, 1)));
      await localRepo().patchSettings({'enabled': true});
      // temizle
      await (db.update(db.cycleEntries)..where((r) => r.id.equals(e.id)))
          .write(const CycleEntriesCompanion(dirty: Value(false)));
      await (db.update(db.cycleSettingsTable)..where((r) => r.id.equals(acct)))
          .write(const CycleSettingsTableCompanion(dirty: Value(false)));

      await localRepo().markAllDirty();

      final entryRow = await (db.select(db.cycleEntries)
            ..where((r) => r.id.equals(e.id)))
          .getSingle();
      final setRow = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(acct)))
          .getSingle();
      expect(entryRow.dirty, isTrue);
      expect(setRow.dirty, isTrue);
    });
  });

  group('_pushDirtyEntries — tombstone DELETE', () {
    test('silinmiş dirty girdi DELETE + kalıcı silme', () async {
      final e = await localRepo()
          .saveEntry(CycleEntry(id: '', date: DateTime(2026, 1, 1)));
      await localRepo().deleteEntry(e.id);

      var deleted = false;
      adapter
        ..onGet('/cycle/settings', (s) => s.reply(200, _settingsJson()))
        ..onGet('/cycle/entries', (s) => s.reply(200, []))
        ..onDelete('/cycle/entries/${e.id}', (s) {
          deleted = true;
          s.reply(204, null);
        });

      await cloudRepo().listEntries(); // push+pull tetikler
      expect(deleted, isTrue);
      final row = await (db.select(db.cycleEntries)
            ..where((r) => r.id.equals(e.id)))
          .getSingleOrNull();
      expect(row, isNull);
    });
  });
}

Map<String, dynamic> _settingsJson() => {
      'baby': null,
      'birth_date': null,
      'breastfeeding': 'mixed',
      'first_period_date': '2026-03-01',
      'reminders': {},
      'show_fertility_warning': true,
      'enabled': true,
    };

/// GERÇEKTEN gönderilen istekleri (method+path+gövde) kaydeder. Stub callback'in
/// side-effect bayrağına güvenmek yerine (http_mock_adapter onPatch callback'i
/// istek gönderilmese de eşleşme sırasında çalışabiliyor) ağ katmanını gözler.
class RequestRecorder extends Interceptor {
  final List<({String method, String path, Object? data})> calls = [];

  bool sent(String method, String path) =>
      calls.any((c) => c.method == method && c.path == path);

  Map<String, dynamic>? body(String method, String path) {
    for (final c in calls) {
      if (c.method == method && c.path == path && c.data is Map) {
        return Map<String, dynamic>.from(c.data as Map);
      }
    }
    return null;
  }

  /// Array gövdeli istekler (toplu /bulk uçları) için ham liste gövdesi.
  List? listBody(String method, String path) {
    for (final c in calls) {
      if (c.method == method && c.path == path && c.data is List) {
        return c.data as List;
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

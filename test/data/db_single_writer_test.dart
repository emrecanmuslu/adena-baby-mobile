import 'dart:io';
import 'dart:ui' show IsolateNameServer;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/db_owner_gate.dart';
import 'package:adena_baby/data/local/app_database.dart';

/// 2026-10-15 iOS olayı: arka plan BGTask'ı aynı süreçte ikinci bir sqlite
/// bağlantısıyla yazarken ön planın `_applySyncResponse` transaction'ı
/// `SqliteException(517) SQLITE_BUSY_SNAPSHOT` ile düşüyor, "Senkron sorunu"
/// şeridi kalkmıyordu. İki savunma burada kilitlenir:
///  1. DbOwnerGate — ön plan canlıyken arka plan işi devreder (ikinci yazar yok).
///  2. AppDatabase.transaction — kilit hatasında transaction baştan denenir.
void main() {
  group('AppDatabase.transaction kilit yeniden denemesi', () {
    late Directory dir;
    late AppDatabase a;
    late AppDatabase b;

    // Üretimle aynı: AppDatabase._open önbelleği KAPALI açar.
    AppDatabase open(File f, {bool cache = false}) => AppDatabase(NativeDatabase(
        f,
        cachePreparedStatements: cache,
        setup: (db) => AppDatabase.applyPragmas(db.execute)));

    Future<void> openBoth({bool cache = false}) async {
      final f = File('${dir.path}/adena.sqlite');
      a = open(f, cache: cache);
      await a.customSelect('SELECT 1').get(); // şemayı kur
      b = open(f);
      await b.customSelect('SELECT 1').get();
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('adena_db_');
    });

    tearDown(() async {
      await a.close();
      await b.close();
      await dir.delete(recursive: true);
    });

    test('başka bağlantı araya yazınca (517) transaction baştan denenip başarır',
        () async {
      await openBoth();
      var attempts = 0;
      Object? firstError;
      await a.transaction(() async {
        attempts++;
        // Okuma → bu bağlantının WAL görüntüsü sabitlenir.
        await a.select(a.syncCursors).get();
        if (attempts == 1) {
          // İkinci yazar (bg isolate'i taklidi) araya girip commit eder.
          await b.into(b.syncCursors).insertOnConflictUpdate(
              const SyncCursorsCompanion(baby: Value('x'), cursor: Value('bg')));
        }
        try {
          await a.into(a.syncCursors).insertOnConflictUpdate(
              const SyncCursorsCompanion(baby: Value('x'), cursor: Value('fg')));
        } catch (e) {
          firstError ??= e;
          rethrow;
        }
      });
      // Gerçek SQLite davranışı: ilk deneme 517 ile düşer (busy_timeout bunu
      // beklemez) — testin taklidi gerçekten olayı üretiyor mu?
      expect(firstError, isNotNull);
      expect(AppDatabase.isSqliteLockError(firstError!), isTrue,
          reason: 'beklenen BUSY_SNAPSHOT, gelen: $firstError');
      expect(attempts, 2);
      final row = await a.select(a.syncCursors).getSingle();
      expect(row.cursor, 'fg');
    });

    test('kilit DIŞI hata yeniden denenmez', () async {
      await openBoth();
      var attempts = 0;
      await expectLater(
        a.transaction(() async {
          attempts++;
          throw StateError('başka hata');
        }),
        throwsStateError,
      );
      expect(attempts, 1);
    });

    test('iç içe transaction yalnız dıştan denenir', () async {
      await openBoth();
      var outer = 0;
      var inner = 0;
      await a.transaction(() async {
        outer++;
        await a.transaction(() async {
          inner++;
          if (outer == 1) {
            throw Exception('SqliteException(517): database is locked');
          }
        });
      });
      expect(outer, 2);
      expect(inner, 2);
    });

    // Belgeleme: neden önbellek KAPALI. drift varsayılanında (önbellek açık)
    // 517 ile düşen ifade bağlantıyı eski görüntüde tutar → araya giren yazar
    // gittikten sonra bile her yeniden deneme düşer (sahadaki "yeniden dene işe
    // yaramıyor, kapat-aç düzeltiyor"). drift bunu düzeltirse bu test kırılır —
    // o zaman önbellek yeniden açılmayı düşünebilir.
    test('önbellek AÇIKKEN 517 yapışkan kalır (kök neden belgesi)', () async {
      await openBoth(cache: true);
      var attempts = 0;
      await expectLater(
        a.transaction(() async {
          attempts++;
          await a.select(a.syncCursors).get();
          if (attempts == 1) {
            await b.into(b.syncCursors).insertOnConflictUpdate(
                const SyncCursorsCompanion(baby: Value('x'), cursor: Value('bg')));
          }
          await a.into(a.syncCursors).insertOnConflictUpdate(
              const SyncCursorsCompanion(baby: Value('x'), cursor: Value('fg')));
        }),
        throwsA(predicate(AppDatabase.isSqliteLockError)),
      );
      expect(attempts, AppDatabase.lockRetryDelays.length + 1);
    });
  });

  test('isSqliteLockError: kilit kodları ve DriftRemoteException metni', () {
    expect(AppDatabase.isSqliteLockError(Exception(
            'DriftRemoteException: SqliteException(517): while executing statement, '
            'database is locked, database is locked (code 517)')),
        isTrue);
    expect(AppDatabase.isSqliteLockError(Exception('SqliteException(261): x')),
        isTrue);
    expect(AppDatabase.isSqliteLockError(Exception('SqliteException(19): UNIQUE')),
        isFalse);
  });

  group('DbOwnerGate', () {
    tearDown(() {
      DbOwnerGate.unregisterForeground();
      IsolateNameServer.removePortNameMapping(DbOwnerGate.portName);
    });

    test('ön plan yoksa noOwner → çağıran kendisi yapar', () async {
      final r = await DbOwnerGate.delegate('periodic',
          timeout: const Duration(seconds: 1));
      expect(r, DelegateResult.noOwner);
    });

    test('ön plan canlıysa iş ona devredilir', () async {
      final calls = <(String, String?)>[];
      DbOwnerGate.registerForeground((op, babyId) async {
        calls.add((op, babyId));
      });
      final r = await DbOwnerGate.delegate('push',
          babyId: 'b1', timeout: const Duration(seconds: 2));
      expect(r, DelegateResult.done);
      expect(calls, [('push', 'b1')]);
    });

    test('ön plan işleyicisi hata verirse failed (çağıran DB açmaz)', () async {
      DbOwnerGate.registerForeground((_, _) async => throw StateError('x'));
      final r = await DbOwnerGate.delegate('periodic',
          timeout: const Duration(seconds: 2));
      expect(r, DelegateResult.failed);
    });

    test('iş bütçeyi aşarsa timedOut (ön planda sürüyor, ikinci yazar yok)',
        () async {
      DbOwnerGate.registerForeground(
          (_, _) => Future.delayed(const Duration(milliseconds: 500)));
      final r = await DbOwnerGate.delegate('periodic',
          timeout: const Duration(milliseconds: 50));
      expect(r, DelegateResult.timedOut);
    });

    test('eski State dispose\'u yeni kaydı silmez (RestartWidget)', () async {
      final old = DbOwnerGate.registerForeground((_, _) async {});
      DbOwnerGate.registerForeground((_, _) async {});
      DbOwnerGate.unregisterForeground(old);
      expect(IsolateNameServer.lookupPortByName(DbOwnerGate.portName), isNotNull);
      final r = await DbOwnerGate.delegate('periodic',
          timeout: const Duration(seconds: 2));
      expect(r, DelegateResult.done);
    });
  });
}

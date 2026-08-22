import 'dart:async';

import 'package:adena_baby/core/db_watchdog.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sorguları SONSUZA KADAR askıda bırakan executor — `shareAcrossIsolates`
/// bug'ındaki "hata yok, yanıt da yok" hâlini birebir taklit eder.
class _HangingExecutor extends QueryExecutor {
  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      Completer<void>().future;

  @override
  Future<List<Map<String, Object?>>> runSelect(
          String statement, List<Object?> args) =>
      Completer<List<Map<String, Object?>>>().future;

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      Completer<int>().future;

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      Completer<int>().future;

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      Completer<int>().future;

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      Completer<void>().future;

  @override
  TransactionExecutor beginTransaction() => throw UnimplementedError();

  @override
  QueryExecutor beginExclusive() => throw UnimplementedError();

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<void> close() async {}

  @override
  SqlDialect get dialect => SqlDialect.sqlite;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sağlıklı DB → check true döner', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await DbWatchdog.instance.check(db, 'test-healthy'), isTrue);
  });

  test('askıda kalan DB → check timeout ile false döner (sonsuza kadar beklemez)',
      () async {
    final db = AppDatabase(_HangingExecutor());
    final sw = Stopwatch()..start();
    final ok = await DbWatchdog.instance.check(db, 'test-hanging');
    sw.stop();
    expect(ok, isFalse);
    // Probe timeout'u 6 sn; sonsuz beklemediğini kanıtlar.
    expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('markBackgroundSync tur sonucunu kalıcı yazar', () async {
    await DbWatchdog.markBackgroundSync('bitti');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('db_last_bg_sync_outcome'), 'bitti');
    expect(prefs.getInt('db_last_bg_sync_ms'), isNotNull);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/data/local/app_database.dart';

/// Açılış PRAGMA'ları — iOS 1.4.17'de 30 fatal olaya yol açan regresyonun bekçisi:
/// `SqliteException(261): database is locked ... PRAGMA journal_mode = WAL`.
///
/// Kök neden `busy_timeout`un WAL'dan SONRA ayarlanmasıydı (o an yürürlükteki
/// tolerans 0 → çakışmada anında düşüş) ve istisnanın `setup`tan kaçıp DB
/// açılışını komple düşürmesiydi. İkisi de burada kilitleniyor.
void main() {
  test('busy_timeout WAL pragmasından ÖNCE uygulanır', () {
    final executed = <String>[];
    AppDatabase.applyPragmas(executed.add);

    final busy = executed.indexWhere((s) => s.contains('busy_timeout'));
    final wal = executed.indexWhere((s) => s.contains('journal_mode'));
    expect(busy, isNonNegative, reason: 'busy_timeout hiç uygulanmamış');
    expect(wal, isNonNegative, reason: 'WAL hiç uygulanmamış');
    // Sıra bozulursa WAL'a geçiş toleranssız kalır → "database is locked" geri gelir.
    expect(busy, lessThan(wal));
  });

  test('WAL kilit yüzünden başarısız olursa açılış DÜŞMEZ', () {
    final executed = <String>[];
    void exec(String sql) {
      executed.add(sql);
      if (sql.contains('journal_mode')) {
        // Gerçek hatanın taklidi: SqliteException(261) — başka bir bağlantı
        // (bg sync isolate'i) dosyayı tutuyor.
        throw StateError('SqliteException(261): database is locked');
      }
    }

    // Fırlatırsa DB hiç açılmaz ve fatal FlutterError'a döner (yaşanan bug).
    expect(() => AppDatabase.applyPragmas(exec), returnsNormally);
    // Tolerans yine de kurulmuş olmalı — DB mevcut journal modunda çalışmaya devam eder.
    expect(executed.first, contains('busy_timeout'));
  });
}

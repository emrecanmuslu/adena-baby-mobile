import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/features/cycle/cycle_anchor.dart';
import 'package:adena_baby/models/cycle.dart';

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

/// ADET-INCELEME A3 (karar S1): doğumdan sonraki ilk 42 gün içindeki kanama
/// kaydı OTOMATİK ilk-adet çapası kurmaz; 43–56. gün arasında kullanıcıya
/// sorulur (onay = `confirmedFirstPeriod`). 56. günden sonra eski davranış.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final birth = DateTime(2026, 2, 1);
  DateTime pp(int d) => DateTime(2026, 2, 1 + d);

  group('saf pencere kuralları', () {
    final s = CycleSettings(birthDate: birth);
    test('loşia penceresi: doğum+0..42 (dahil)', () {
      expect(inPostpartumLochiaWindow(pp(0), s), isTrue);
      expect(inPostpartumLochiaWindow(pp(42), s), isTrue);
      expect(inPostpartumLochiaWindow(pp(43), s), isFalse);
      expect(inPostpartumLochiaWindow(pp(10), const CycleSettings()), isFalse);
    });
    test('sorulacak pencere: doğum+43..56', () {
      expect(postpartumAskFirstPeriod(pp(42), s), isFalse);
      expect(postpartumAskFirstPeriod(pp(43), s), isTrue);
      expect(postpartumAskFirstPeriod(pp(56), s), isTrue);
      expect(postpartumAskFirstPeriod(pp(57), s), isFalse);
    });
    test('anchorCandidate ilk 42 günü çapa yapmaz', () {
      expect(anchorCandidate([pp(20), pp(21), pp(45)], s), pp(45));
      expect(anchorCandidate([pp(20)], s), isNull);
    });
  });

  group('repository', () {
    const acct = 'acct-a3';
    late ApiClient api;
    late AppDatabase db;
    setUp(() {
      api = ApiClient(_FakeTokens());
      DioAdapter(dio: api.dio);
      db = AppDatabase(NativeDatabase.memory());
      LocalSession.setActiveAccount(acct);
    });
    tearDown(() async {
      LocalSession.setActiveAccount(null);
      await db.close();
    });
    CycleRepository repo() => CycleRepository(db, api, () => false);

    Future<CycleSettings> postpartum() => repo().patchSettings({
          'birth_date': '2026-02-01',
          'lifecycle_mode': 'postpartum',
          'predictions_hidden': true,
        });
    Future<void> flow(DateTime d, {bool confirmed = false}) => repo().saveEntry(
        CycleEntry(id: '', date: d, flow: FlowLevel.medium),
        confirmedFirstPeriod: confirmed);

    test('doğum+25 akış kaydı çapa KURMAZ, mod postpartum kalır', () async {
      await postpartum();
      await flow(pp(25));
      final s = await repo().getSettings();
      expect(s.firstPeriodDate, isNull);
      expect(s.lifecycleMode, CycleLifecycleMode.postpartum);
      expect(s.predictionsHidden, isTrue);
    });

    test('doğum+50 onaysız → çapa yok; "ilk adetim" onayıyla → çapa + takip', () async {
      await postpartum();
      await flow(pp(50));
      expect((await repo().getSettings()).firstPeriodDate, isNull);
      await flow(pp(51), confirmed: true);
      final s = await repo().getSettings();
      expect(s.firstPeriodDate, pp(51));
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
    });

    test('doğum+60 → eski davranış: otomatik çapa', () async {
      await postpartum();
      await flow(pp(60));
      expect((await repo().getSettings()).firstPeriodDate, pp(60));
    });
  });
}

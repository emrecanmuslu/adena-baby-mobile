import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/models/cycle.dart';

/// K6 + D33 (BULGULAR.md): çapa/kayıt tutarlılığı.
/// Politika: `settings.firstPeriodDate` esas çapadır (kurulumda kayıt olmadan da
/// verilebilir, motor değişmez). Kayıtlar çapayı yalnız ÇAPA GÜNÜNÜN ADET
/// İŞARETİ KALKTIĞINDA (silme / akış kaldırma / senkronla silinme) oynatır:
/// çapa, sıfırlama sonrası kalan en eski adet gününe taşınır; kalan yoksa korunur.
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

  const acct = 'acct-k6';
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

  Future<CycleEntry> period(int month, int day) => repo().saveEntry(
      CycleEntry(id: '', date: DateTime(2026, month, day), flow: FlowLevel.medium));

  group('K6 — düzenleme takvimi yaması patchSettings üzerinden', () {
    test('postpartum: sheet yaması (mode açık) modu DEĞİŞTİRMEZ, çapayı kurar', () async {
      await repo().patchSettings({
        'birth_date': '2026-02-01',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
      });
      // Sheet'in ürettiği yama şekli: first_period_date + mevcut mod.
      final s = await repo().patchSettings({
        'first_period_date': '2026-03-05',
        'lifecycle_mode': 'postpartum',
      });
      expect(s.firstPeriodDate, DateTime(2026, 3, 5));
      expect(s.lifecycleMode, CycleLifecycleMode.postpartum);
      expect(s.predictionsHidden, isTrue);
    });

    test('karşılaştırma: saveEntry yolu (mode yok) meşru otomatik geçişi KORUR', () async {
      await repo().patchSettings({
        'birth_date': '2026-02-01',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
      });
      // A3 (S1): doğumdan sonraki ilk 56 gün loşia/onay penceresi → fikstür 63. güne taşındı.
      await period(4, 5); // doğum sonrası ilk gerçek adet → tracking
      final s = await repo().getSettings();
      expect(s.firstPeriodDate, DateTime(2026, 4, 5));
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
      expect(s.predictionsHidden, isFalse);
    });
  });

  group('D33 — çapa gününün işareti kalkınca çapa taşınır', () {
    test('deleteEntry(çapa günü) → çapa kalan en eski adet gününe; hayalet başlangıç yok',
        () async {
      await repo().patchSettings({'first_period_date': '2026-05-01'});
      final a = await period(5, 1);
      await period(5, 2);
      await period(5, 3);
      final today = DateTime(2026, 5, 10);
      final before =
          computeStatus(await repo().getSettings(), await repo().listEntries(), today: today);

      await repo().deleteEntry(a.id);

      final s = await repo().getSettings();
      expect(s.firstPeriodDate, DateTime(2026, 5, 2));
      final after = computeStatus(s, await repo().listEntries(), today: today);
      expect(after.mode, CycleMode.active);
      // Döngü artık 2 Mayıs'ta başlıyor: gün sayısı tam 1 azalır (ek bir
      // "başlangıç" sayılmaz; eskiden çapa 1 Mayıs'ta kalıp 2 Mayıs ikinci
      // başlangıç oluyordu → aynı sonuç ama hayalet döngüyle).
      expect(after.dayInCycle, before.dayInCycle - 1);
      expect(after.cycleNumber, before.cycleNumber,
          reason: 'hayalet ikinci döngü sayılmamalı');
    });

    test('saveEntry ile akış kaldırılınca (diğer veri korunur) çapa taşınır', () async {
      await repo().patchSettings({'first_period_date': '2026-05-01'});
      final a = await period(5, 1);
      await period(5, 2);
      await repo().saveEntry(CycleEntry(
          id: a.id, date: DateTime(2026, 5, 1), flow: null, note: 'kramp'));
      expect((await repo().getSettings()).firstPeriodDate, DateTime(2026, 5, 2));
    });

    test('kalan adet günü yoksa çapa KORUNUR', () async {
      await repo().patchSettings({'first_period_date': '2026-05-01'});
      final a = await period(5, 1);
      await repo().deleteEntry(a.id);
      expect((await repo().getSettings()).firstPeriodDate, DateTime(2026, 5, 1));
    });

    test('çapa dışı bir günün silinmesi çapaya dokunmaz', () async {
      await repo().patchSettings({'first_period_date': '2026-05-01'});
      await period(5, 1);
      final b = await period(5, 2);
      await repo().deleteEntry(b.id);
      expect((await repo().getSettings()).firstPeriodDate, DateTime(2026, 5, 1));
    });

    test('kurulum çapası (kayıtsız) sonraki ilk adet kaydıyla OYNAMAZ', () async {
      // Sihirbaz "son adet 1 Mayıs" dedi, kayıt yok; 29 Mayıs adet loglandı.
      await repo().patchSettings({'first_period_date': '2026-05-01'});
      await period(5, 29);
      expect((await repo().getSettings()).firstPeriodDate, DateTime(2026, 5, 1));
    });

    test('sıfırlama (doğum) öncesi günler çapa adayı olamaz', () async {
      await repo().patchSettings({
        'birth_date': '2026-02-01',
        'lifecycle_mode': 'postpartum',
      });
      await period(1, 10); // doğum öncesi (backfill)
      final s1 = await repo().getSettings();
      expect(s1.firstPeriodDate, isNull, reason: 'backfill çapa kurmaz');
      // A3 (S1): doğumdan sonraki ilk 56 gün loşia/onay penceresi → fikstür 63. güne taşındı.
      final a = await period(4, 5); // ilk gerçek adet → çapa
      await period(4, 6);
      await repo().deleteEntry(a.id);
      final s2 = await repo().getSettings();
      expect(s2.firstPeriodDate, DateTime(2026, 4, 6),
          reason: '10 Ocak değil, sıfırlama sonrası kalan en eski gün');
    });
  });
}

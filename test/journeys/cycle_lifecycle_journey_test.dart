import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/features/cycle/cycle_lifecycle.dart';
import 'package:adena_baby/features/cycle/cycle_loss.dart';
import 'package:adena_baby/models/cycle.dart';

/// Yaşam-döngüsü YOLCULUK testleri — `ADET_DAVRANIS_MATRISI.md` sözleşmesinin
/// uçtan uca doğrulaması. Motor birim testlerinden (cycle_engine_test) farkı:
/// geçiş akışlarının repository'ye YAZDIĞI alanlar + kalıcılık + motorun bu
/// gerçek durumdan türettiği mod birlikte, zaman içinde ilerleyen senaryolarla
/// test edilir. Ekran akışlarının patch payload'ları (born-flow, gebelik
/// köprüsü) ekran koduyla birebir aynı alanlarla uygulanır.
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

  const acct = 'acct-journey';

  late ApiClient api;
  late AppDatabase db;
  late CycleRepository repo;

  setUp(() {
    api = ApiClient(_FakeTokens());
    db = AppDatabase(NativeDatabase.memory());
    repo = CycleRepository(db, api, () => false); // cloud kapalı — yerel yolculuk
    LocalSession.setActiveAccount(acct);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Future<CycleStatus> statusAt(DateTime today) async =>
      computeStatus(await repo.getSettings(), await repo.listEntries(),
          today: today);

  Future<CycleEntry> logFlow(DateTime d,
          {FlowLevel? flow, LochiaColor? lochia}) =>
      repo.saveEntry(
          CycleEntry(id: '', date: d, flow: flow, lochiaColor: lochia));

  /// Gerçek akış fonksiyonları (recordCycleLoss vb.) WidgetRef ister (Riverpod 3
  /// sealed → fake'lenemez) → gerçek bir Consumer'dan yakalanır; gövde runAsync
  /// içinde koşar (drift gerçek async I/O yapar).
  Future<void> withRef(
      WidgetTester tester, Future<void> Function(WidgetRef ref) body) async {
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
        cloudSyncEnabledProvider.overrideWithValue(false),
      ],
      child: Consumer(builder: (_, ref, child) {
        captured = ref;
        return const SizedBox.shrink();
      }),
    ));
    await tester.runAsync(() => body(captured));
  }

  group('J1 — doğum sonrası tam yolculuk (P4)', () {
    test('doğum → loşia → bekleme → ilk adet → otomatik aktif takip', () async {
      // born_flow_screen.dart'ın doğumda yazdığı alanlar (T5 ters senkron).
      await repo.patchSettings({
        'breastfeeding': 'exclusive',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
        'birth_date': '2026-05-01',
        'first_period_date': null,
      });

      // Gün 10: loşia penceresi (0–42) — sayaç var, tahmin yok.
      var st = await statusAt(DateTime(2026, 5, 11));
      expect(st.mode, CycleMode.lochia);
      expect(st.lochiaDay, 10);
      expect(st.nextPeriod, isNull);

      // Gün 50, loşia kaydı yok: pencere kapandı → bekleme.
      st = await statusAt(DateTime(2026, 6, 20));
      expect(st.mode, CycleMode.waiting);

      // Loşia kaydı girilir (akış girilmiş olsa bile adet DEĞİL).
      await logFlow(DateTime(2026, 5, 21),
          flow: FlowLevel.heavy, lochia: LochiaColor.red);
      var s = await repo.getSettings();
      expect(s.firstPeriodDate, isNull,
          reason: 'loşia günü çapayı otomatik SET ETMEMELİ');
      expect(s.lifecycleMode, CycleLifecycleMode.postpartum);

      // Gün 50 + loşia kaydı: pencere 60 güne uzar → hâlâ loşia.
      st = await statusAt(DateTime(2026, 6, 20));
      expect(st.mode, CycleMode.lochia);
      // Gün 75: uzatma da bitti → bekleme.
      st = await statusAt(DateTime(2026, 7, 15));
      expect(st.mode, CycleMode.waiting);
      expect(st.nextPeriod, isNull);

      // Gün 70'te İLK ADET (3 gün) → çapa + otomatik postpartum→tracking geçişi.
      await logFlow(DateTime(2026, 7, 10), flow: FlowLevel.medium);
      await logFlow(DateTime(2026, 7, 11), flow: FlowLevel.medium);
      await logFlow(DateTime(2026, 7, 12), flow: FlowLevel.light);
      s = await repo.getSettings();
      expect(s.firstPeriodDate, DateTime(2026, 7, 10));
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
      expect(s.predictionsHidden, isFalse);

      st = await statusAt(DateTime(2026, 7, 12));
      expect(st.mode, CycleMode.active);
      expect(st.cycleNumber, 1);
      expect(st.dayInCycle, 3);
      expect(st.phase, CyclePhase.menstrual);
      expect(st.nextPeriod, DateTime(2026, 8, 7)); // varsayılan 28 gün
      expect(st.lowConfidence, isTrue);
    });

    test('çapadan önceki (doğum öncesi) kayıtlar yeni dönemi kirletmez',
        () async {
      await repo.patchSettings({
        'breastfeeding': 'exclusive',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
        'birth_date': '2026-05-01',
        'first_period_date': null,
      });
      // İlk adet → yeni Gün 1.
      await logFlow(DateTime(2026, 7, 10), flow: FlowLevel.medium);
      // SONRADAN gebelik öncesi eski bir adet geri-girilir (backfill).
      await logFlow(DateTime(2026, 1, 10), flow: FlowLevel.heavy);

      final s = await repo.getSettings();
      expect(s.firstPeriodDate, DateTime(2026, 7, 10),
          reason: 'çapa doluyken backfill çapayı değiştirmemeli');
      final st = await statusAt(DateTime(2026, 7, 12));
      expect(st.cycleNumber, 1, reason: 'çapa öncesi kayıt sayılmamalı');
      expect(st.spans.first.start, DateTime(2026, 7, 10));
    });
  });

  group('J1b — backfill koruması (çapa boşken geçmiş kayıt)', () {
    test('doğum ÖNCESİ/GÜNÜ tarihli adet logu çapayı kurmaz, postpartum bozulmaz',
        () async {
      await repo.patchSettings({
        'breastfeeding': 'exclusive',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
        'birth_date': '2026-05-01',
        'first_period_date': null,
      });
      // Lohusa kullanıcı gebelik öncesi bir adetini hatırlayıp işler (backfill)
      // + doğum günü tarihli düz akış logu (aslında loşia) girer.
      await logFlow(DateTime(2026, 1, 10), flow: FlowLevel.heavy);
      await logFlow(DateTime(2026, 5, 1), flow: FlowLevel.medium);

      final s = await repo.getSettings();
      expect(s.firstPeriodDate, isNull,
          reason: 'doğumdan önceki/doğum günü kayıt "ilk adet döndü" değildir');
      expect(s.lifecycleMode, CycleLifecycleMode.postpartum);
      expect(s.predictionsHidden, isTrue);
      final st = await statusAt(DateTime(2026, 5, 11));
      expect(st.mode, CycleMode.lochia, reason: 'loşia deneyimi sürmeli');

      // Doğumdan SONRAKİ gerçek ilk adet ise çapayı kurar.
      await logFlow(DateTime(2026, 7, 10), flow: FlowLevel.medium);
      final s2 = await repo.getSettings();
      expect(s2.firstPeriodDate, DateTime(2026, 7, 10));
      expect(s2.lifecycleMode, CycleLifecycleMode.tracking);
    });

    test('kayıp GÜNÜ/öncesi tarihli adet logu çapayı kurmaz (kayıp kanaması ≠ adet)',
        () async {
      await repo.patchSettings({
        'breastfeeding': 'none',
        'lifecycle_mode': 'loss',
        'predictions_hidden': true,
        'last_loss_date': '2026-06-10',
        'first_period_date': null,
      });
      await logFlow(DateTime(2026, 6, 10), flow: FlowLevel.heavy); // kayıp günü
      await logFlow(DateTime(2026, 5, 20), flow: FlowLevel.medium); // öncesi

      final s = await repo.getSettings();
      expect(s.firstPeriodDate, isNull);
      expect(s.lifecycleMode, CycleLifecycleMode.loss);
      expect(s.predictionsHidden, isTrue);

      // Kayıptan sonraki gerçek ilk adet → yeni Gün 1 + otomatik dönüş.
      await logFlow(DateTime(2026, 7, 20), flow: FlowLevel.medium);
      final s2 = await repo.getSettings();
      expect(s2.firstPeriodDate, DateTime(2026, 7, 20));
      expect(s2.lifecycleMode, CycleLifecycleMode.tracking);
      expect(s2.predictionsHidden, isFalse);
    });

    test('onarım kancası da backfill ile tetiklenmez, sonrası kayıtla tetiklenir',
        () async {
      // Tutarsız miras durum: çapa dolu + gizli takılı + doğum var.
      await repo.patchSettings({
        'breastfeeding': 'exclusive',
        'first_period_date': '2026-03-01',
        'birth_date': '2026-06-01',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
      });
      // Doğum öncesi backfill → onarım TETİKLENMEMELİ (dönüş sinyali değil).
      await logFlow(DateTime(2026, 2, 15), flow: FlowLevel.medium);
      var s = await repo.getSettings();
      expect(s.predictionsHidden, isTrue);
      expect(s.lifecycleMode, CycleLifecycleMode.postpartum);

      // Doğum sonrası gerçek adet → onarım çalışır.
      await logFlow(DateTime(2026, 7, 15), flow: FlowLevel.medium);
      s = await repo.getSettings();
      expect(s.predictionsHidden, isFalse);
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
    });
  });

  group('J2 — kayıp yolculuğu (P3→P5→P1)', () {
    testWidgets(
        'aktif takip → gebelik → kayıp → iyileşme → dönüş → ilk adet = yeni Gün 1',
        (tester) async {
      await withRef(tester, (ref) async {
        // Aktif takip: çapa + 2 döngü gerçek kayıt.
        await repo.patchSettings(
            {'breastfeeding': 'none', 'first_period_date': '2026-01-05'});
        for (var d = 5; d <= 9; d++) {
          await logFlow(DateTime(2026, 1, d), flow: FlowLevel.medium);
        }
        for (var d = 2; d <= 6; d++) {
          await logFlow(DateTime(2026, 2, d), flow: FlowLevel.medium);
        }
        // Gebelik köprüsü yansıması (cycle_pregnancy_bridge ile aynı alanlar).
        await repo.patchSettings({
          'lifecycle_mode': 'pregnant',
          'predictions_hidden': false,
          'baby': 'baby-1',
        });

        // KAYIP — gerçek akış fonksiyonu.
        await recordCycleLoss(ref, date: DateTime(2026, 6, 10));
        var s = await repo.getSettings();
        expect(s.lifecycleMode, CycleLifecycleMode.loss);
        expect(s.predictionsHidden, isTrue);
        expect(s.lastLossDate, DateTime(2026, 6, 10));
        expect(s.firstPeriodDate, isNull,
            reason: 'gebelik LMP\'si kayıptan sonra geçersiz — sıfırlanmalı');
        expect(s.babyId, isNull, reason: 'silinen bebeğe bayat bağ kalmamalı');

        // Şefkatli mod: doğum yok → bekleme (loşia değil), tahmin yok.
        var st = await statusAt(DateTime(2026, 6, 15));
        expect(st.mode, CycleMode.waiting);
        expect(st.nextPeriod, isNull);

        // "Takibe hazırım" — çapa hâlâ boş, tahmin başlamaz.
        await returnToTrackingFromLoss(ref);
        s = await repo.getSettings();
        expect(s.lifecycleMode, CycleLifecycleMode.tracking);
        expect(s.predictionsHidden, isFalse);
        st = await statusAt(DateTime(2026, 6, 20));
        expect(st.mode, CycleMode.waiting);

        // İlk adet → yeni Gün 1; kayıp öncesi Ocak/Şubat döngüleri sayılmaz.
        await logFlow(DateTime(2026, 7, 20), flow: FlowLevel.medium);
        s = await repo.getSettings();
        expect(s.firstPeriodDate, DateTime(2026, 7, 20));
        st = await statusAt(DateTime(2026, 7, 21));
        expect(st.mode, CycleMode.active);
        expect(st.cycleNumber, 1);
        expect(st.spans.first.start, DateTime(2026, 7, 20));
      });
    });

    test('loss modundayken doğrudan adet logu da otomatik takibe döndürür',
        () async {
      await repo.patchSettings({
        'breastfeeding': 'none',
        'lifecycle_mode': 'loss',
        'predictions_hidden': true,
        'first_period_date': null,
      });
      await logFlow(DateTime(2026, 8, 1), flow: FlowLevel.heavy);
      final s = await repo.getSettings();
      expect(s.firstPeriodDate, DateTime(2026, 8, 1));
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
      expect(s.predictionsHidden, isFalse);
      final st = await statusAt(DateTime(2026, 8, 1));
      expect(st.mode, CycleMode.active);
      expect(st.dayInCycle, 1);
    });
  });

  group('J3 — patchSettings durum makinesi kenarları', () {
    test('onarım kancası: çapa dolu + gizli takılı kalmış → adet logu düzeltir',
        () async {
      // Tutarsız miras durum: çapa dolu ama tahminler gizli, mod postpartum.
      await repo.patchSettings({
        'breastfeeding': 'exclusive',
        'first_period_date': '2026-03-01',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
      });
      await logFlow(DateTime(2026, 3, 29), flow: FlowLevel.medium);
      final s = await repo.getSettings();
      expect(s.predictionsHidden, isFalse);
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
      expect(s.firstPeriodDate, DateTime(2026, 3, 1),
          reason: 'onarım çapaya dokunmamalı');
      final st = await statusAt(DateTime(2026, 3, 29));
      expect(st.mode, CycleMode.active);
      expect(st.cycleNumber, 2); // 1 Mart çapası + 29 Mart yeni başlangıç
      expect(st.dayInCycle, 1);
    });

    test('patch açıkça lifecycle_mode içeriyorsa otomatik geçiş çalışmaz',
        () async {
      await repo.patchSettings({
        'breastfeeding': 'exclusive',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
      });
      // Çağıran modu bilinçli sabitliyor → durum makinesi ezmemeli.
      await repo.patchSettings({
        'first_period_date': '2026-09-01',
        'lifecycle_mode': 'postpartum',
      });
      final s = await repo.getSettings();
      expect(s.lifecycleMode, CycleLifecycleMode.postpartum);
      expect(s.predictionsHidden, isTrue);
      // Gizlilik sürdüğü için çapa dolu olsa da tahmin üretilmez.
      final st = await statusAt(DateTime(2026, 9, 2));
      expect(st.mode, isNot(CycleMode.active));
      expect(st.nextPeriod, isNull);
    });

    test('çapa zaten doluyken yeni adet logu çapayı/modu değiştirmez',
        () async {
      await repo.patchSettings(
          {'breastfeeding': 'none', 'first_period_date': '2026-01-05'});
      await logFlow(DateTime(2026, 2, 2), flow: FlowLevel.medium);
      final s = await repo.getSettings();
      expect(s.firstPeriodDate, DateTime(2026, 1, 5));
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
      final st = await statusAt(DateTime(2026, 2, 3));
      expect(st.cycleNumber, 2);
      expect(st.avgCycleLength, 28); // Oca 5 → Şub 2 = tam 28 gün ölçüldü
    });
  });

  group('J4 — bebeksiz dal + hedef geçişleri (P1/P2)', () {
    testWidgets('kurulum → bekleme → ttc → tracking → LMP → aktif',
        (tester) async {
      await withRef(tester, (ref) async {
        // cycle-first kurulum: doğum yok, LMP yok.
        await repo.patchSettings({'breastfeeding': 'none'});
        var st = await statusAt(DateTime(2026, 7, 1));
        expect(st.mode, CycleMode.waiting,
            reason: 'doğum yok → asla loşia gösterilmemeli');

        // Hedef: TTC — gerçek akış fonksiyonu; damga yazılır.
        await setCycleLifecycleMode(ref, CycleLifecycleMode.ttc,
            ttcStartedAt: DateTime(2026, 7, 1));
        var s = await repo.getSettings();
        expect(s.lifecycleMode, CycleLifecycleMode.ttc);
        expect(s.ttcStartedAt, DateTime(2026, 7, 1));
        expect(s.predictionsHidden, isFalse);

        // Geri tracking'e — damga tarihçe olarak korunur.
        await setCycleLifecycleMode(ref, CycleLifecycleMode.tracking);
        s = await repo.getSettings();
        expect(s.lifecycleMode, CycleLifecycleMode.tracking);
        expect(s.ttcStartedAt, DateTime(2026, 7, 1));

        // LMP girilir → aktif + doğurgan pencere üretimi.
        await repo.patchSettings({'first_period_date': '2026-07-05'});
        st = await statusAt(DateTime(2026, 7, 10));
        expect(st.mode, CycleMode.active);
        expect(st.ovulationDay, DateTime(2026, 7, 19)); // 5 Tem + 28 − 14
        expect(st.fertileStart, DateTime(2026, 7, 14));
        expect(st.fertileEnd, DateTime(2026, 7, 20));
        expect(st.phase, CyclePhase.follicular);
      });
    });
  });
}

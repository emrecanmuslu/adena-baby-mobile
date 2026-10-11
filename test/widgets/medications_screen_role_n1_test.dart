import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/features/health/medication_widgets.dart';
import 'package:adena_baby/features/health/medications_screen.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/medication_plan.dart';

class _TwoBabies extends BabyController {
  @override
  Future<List<Baby>> build() async => const [
        Baby(id: 'cg', name: 'Bakılan', status: BabyStatus.born, myRole: 'caregiver'),
        Baby(id: 'own', name: 'Benim', status: BabyStatus.born, myRole: 'owner'),
      ];
}

class _ActiveId extends ActiveBabyIdNotifier {
  final String? id;
  _ActiveId(this.id);
  @override
  String? build() => id;
}

/// N1 — plan kartı kilidi kartın KENDİ bebeğinin rolüne göre: iki bebek; bakıcı
/// olunan bebekte "Düzenle" yok, sahip olunan bebekte var. `canFullWriteProvider`
/// aktif bebeğe değil id'ye bakar.
Finder _sem(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final plan = MedicationPlan(
      id: 1, name: 'D vitamini', dose: '1 damla', times: const ['09:00'],
      active: true, createdAt: DateTime(2026));

  Future<void> pump(WidgetTester tester, String activeId) async {
    // Overrides çalışma zamanında değişemez → her pump taze ProviderScope.
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        babyControllerProvider.overrideWith(_TwoBabies.new),
        activeBabyIdProvider.overrideWith(() => _ActiveId(activeId)),
        medicationPlansProvider.overrideWith((ref, id) async => [plan]),
        medicationDayProvider.overrideWith((ref, id) => null),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const MedicationsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  test('canFullWriteProvider: aktif bebek bakıcı iken diğer (sahip) bebek yazılabilir', () async {
    final c = ProviderContainer(overrides: [
      babyControllerProvider.overrideWith(_TwoBabies.new),
      activeBabyIdProvider.overrideWith(() => _ActiveId('cg')),
    ]);
    addTearDown(c.dispose);
    await c.read(babyControllerProvider.future);
    expect(c.read(activeBabyProvider)?.id, 'cg');
    expect(c.read(canFullWriteProvider('own')), isTrue);
    expect(c.read(canFullWriteProvider('cg')), isFalse);
    expect(c.read(canFullWriteProvider('yok')), isTrue, reason: 'bilinmeyen → eski varsayım');
  });

  testWidgets('sahip olunan bebek: Düzenle var; bakıcı olunan bebek: Düzenle yok, ekle yok',
      (tester) async {
    await pump(tester, 'own');
    expect(find.text('D vitamini'), findsOneWidget, reason: 'plan kartı çizildi');
    expect(_sem('Düzenle'), findsOneWidget);
    expect(_sem('İlaç / vitamin ekle'), findsOneWidget);

    await pump(tester, 'cg');
    expect(_sem('Düzenle'), findsNothing);
    expect(_sem('İlaç / vitamin ekle'), findsNothing);
    expect(find.textContaining('Bakıcı rolünde'), findsOneWidget);
  });

  testWidgets('N2: yerel-only plan → not + Sil düğmesi (bakıcı)', (tester) async {
    final local = MedicationPlan(
        id: 2, name: 'Eski plan', dose: '', times: const ['09:00'],
        active: true, createdAt: DateTime(2026), localOnly: true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        babyControllerProvider.overrideWith(_TwoBabies.new),
        activeBabyIdProvider.overrideWith(() => _ActiveId('cg')),
        medicationPlansProvider.overrideWith((ref, id) async => [local]),
        medicationDayProvider.overrideWith((ref, id) => null),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const MedicationsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('yalnız bu cihazda'), findsOneWidget);
    expect(_sem('Sil'), findsOneWidget);
    expect(_sem('Düzenle'), findsNothing);
  });
}

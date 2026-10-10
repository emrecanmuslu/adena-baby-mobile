import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/features/babies/baby_edit_screen.dart';
import 'package:adena_baby/models/baby.dart';

/// O20 (BULGULAR.md): bakıcı (caregiver) bebek bilgilerini düzenleyip
/// "Kaydedildi" görüyordu; push rol filtresine takılıp değişiklik sessizce geri
/// alınıyordu. Ekran bakıcıda salt-okunur olmalı: Kaydet ve "Bebeğim doğdu"
/// yok, kısa açıklama var. Ebeveyn/sahip için her şey aynen.
void main() {
  setUpAll(() => initializeDateFormatting()); // fmtDayMonthYear (intl)
  setUp(() => I18n.instance.apply('tr', const {}));

  Baby baby(String role, {BabyStatus status = BabyStatus.born}) => Baby(
        id: '11111111-1111-1111-1111-111111111111',
        name: 'Defne',
        status: status,
        birthDate: status == BabyStatus.born ? DateTime(2026, 4, 2) : null,
        dueDate: status == BabyStatus.expecting ? DateTime(2026, 12, 1) : null,
        myRole: role,
      );

  Future<void> pump(WidgetTester tester, Baby b) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeBabyProvider.overrideWithValue(b)],
        child: MaterialApp(theme: AppTheme.light, home: const BabyEditScreen()),
      ),
    );
    await tester.pump();
  }

  const readOnlyNote =
      'Bakıcı rolünde bebek bilgileri salt-okunurdur; düzenlemeyi ebeveyn/sahip yapabilir.';

  testWidgets('caregiver (doğmuş): Kaydet yok, salt-okunur açıklaması var',
      (tester) async {
    await pump(tester, baby('caregiver'));
    expect(find.text('Kaydet'), findsNothing);
    expect(find.text(readOnlyNote), findsOneWidget);
    expect(find.text('Bebeği sil'), findsNothing);
  });

  testWidgets('caregiver (bekleme): "Bebeğim doğdu" akışı da yok',
      (tester) async {
    await pump(tester, baby('caregiver', status: BabyStatus.expecting));
    expect(find.text('Kaydet'), findsNothing);
    expect(find.textContaining('Bebeğim doğdu'), findsNothing);
    expect(find.text(readOnlyNote), findsOneWidget);
  });

  testWidgets('parent (bekleme): Kaydet ve "Bebeğim doğdu" görünür, açıklama yok',
      (tester) async {
    await pump(tester, baby('parent', status: BabyStatus.expecting));
    expect(find.text('Kaydet'), findsOneWidget);
    expect(find.textContaining('Bebeğim doğdu'), findsOneWidget);
    expect(find.text(readOnlyNote), findsNothing);
    expect(find.text('Bebeği sil'), findsNothing); // yalnız sahip
  });

  testWidgets('owner: Kaydet + Bebeği sil görünür', (tester) async {
    await pump(tester, baby('owner'));
    expect(find.text('Kaydet'), findsOneWidget);
    expect(find.text('Bebeği sil'), findsOneWidget);
    expect(find.text(readOnlyNote), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/exact_alarm_prompt.dart';
import 'package:adena_baby/core/i18n.dart';

/// M4 / KB-4 — kesin alarm izni diyaloğu: yalnız Android + izin yokken, tek
/// sefer; izin varken ve iOS'ta hiç görünmez; ayar satırı iOS'ta boş.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.instance.apply('tr', const {});
  });

  Future<ExactAlarmPrompt> prompt({bool can = false, bool android = true,
      List<int>? requests}) async =>
      ExactAlarmPrompt(
        canSchedule: () async => can,
        request: () async {
          requests?.add(1);
          return true;
        },
        isAndroid: android,
      );

  test('shouldShow: Android + izin yok + ilk kez → true; sonra false', () async {
    final p = await prompt();
    expect(await p.shouldShow(), isTrue);
    expect(await p.shouldShow(), isTrue, reason: 'gösterilmeden bayrak yazılmaz');
  });

  test('izin varken hiç görünmez; iOS\'ta hiç görünmez', () async {
    expect(await (await prompt(can: true)).shouldShow(), isFalse);
    expect(await (await prompt(android: false)).shouldShow(), isFalse);
  });

  testWidgets('diyalog bir kez; "İzin ver" sistem isteğini çağırır; ikinci çağrıda görünmez',
      (tester) async {
    final requests = <int>[];
    final p = await prompt(requests: requests);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.shrink();
    })));

    final shown = p.maybeShow(ctx);
    await tester.pump();
    expect(find.text('Tam zamanında bildirim'), findsOneWidget);
    await tester.tap(find.text('İzin ver'));
    await tester.pump();
    expect(await shown, isTrue);
    expect(requests, hasLength(1));

    expect(await p.maybeShow(ctx), isFalse, reason: 'bir daha sorulmaz');
    await tester.pump();
    expect(find.text('Tam zamanında bildirim'), findsNothing);
  });

  testWidgets('"Daha sonra" → istek yok, yine de bir daha sorulmaz', (tester) async {
    final requests = <int>[];
    final p = await prompt(requests: requests);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.shrink();
    })));
    final shown = p.maybeShow(ctx);
    await tester.pump();
    await tester.tap(find.text('Daha sonra'));
    await tester.pump();
    await shown;
    expect(requests, isEmpty);
    expect(await p.shouldShow(), isFalse);
  });

  testWidgets('ExactAlarmTile: iOS\'ta boş; Android izin yokken "İzin ver" düğmesi',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExactAlarmTile(key: const ValueKey('ios'), prompt: await prompt(android: false)))));
    await tester.pump();
    expect(find.text('Tam zamanında bildirim'), findsNothing);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExactAlarmTile(key: const ValueKey('android'), prompt: await prompt(can: false)))));
    await tester.pump();
    await tester.pump();
    expect(find.text('Tam zamanında bildirim'), findsOneWidget);
    expect(find.text('İzin ver'), findsOneWidget);
  });
}

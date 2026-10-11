import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/cycle.dart';

/// Adet ekranları için ortak widget-test düzeneği (ADET-INCELEME düzeltme turu).
/// Ayar/kayıt akışları sabit değerle override edilir; bebek listesi isteğe bağlı.
class FakeBabies extends BabyController {
  final List<Baby> babies;
  FakeBabies(this.babies);
  @override
  Future<List<Baby>> build() async => babies;
}

/// Bugünün gece-yarısı + [days] gün (negatif = geçmiş).
DateTime dayOffset(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + days);
}

/// [starts] gün ofsetlerinden başlayan, her biri [len] gün süren adet kayıtları.
List<CycleEntry> periodEntries(List<int> starts,
    {int len = 5, FlowLevel flow = FlowLevel.medium, Map<int, int>? lenFor}) {
  final out = <CycleEntry>[];
  var i = 0;
  for (final s in starts) {
    final n = lenFor?[s] ?? len;
    for (var k = 0; k < n; k++) {
      out.add(CycleEntry(id: 'h${i++}', date: dayOffset(s + k), flow: flow));
    }
  }
  return out;
}

Future<void> pumpCycleScreen(
  WidgetTester tester,
  Widget screen, {
  required CycleSettings settings,
  List<CycleEntry> entries = const [],
  List<Baby> babies = const [],
  List overrides = const [],
  Map<String, Object> prefs = const {},
}) async {
  I18n.instance.apply('tr', const {});
  SharedPreferences.setMockInitialValues(prefs);
  await initializeDateFormatting();
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cycleSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      cycleEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      babyControllerProvider.overrideWith(() => FakeBabies(babies)),
      activeAccountIdProvider.overrideWithValue('acct-test'),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: screen)),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Ekranda (kaydırmalı listede de) metin içeren bir widget var mı.
Finder textHas(String s) => find.textContaining(s, findRichText: true);

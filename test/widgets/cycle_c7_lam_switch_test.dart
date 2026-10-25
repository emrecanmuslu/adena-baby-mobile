import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_settings_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME C7: "LAM / doğurganlık uyarıları" anahtarı hiçbir uyarıyı
/// kapatmıyordu (değer okunmuyordu) — sağlık uyarıları kapatılamaz; kaldırıldı.
void main() {
  testWidgets('âdet ayarlarında LAM uyarı anahtarı yok', (t) async {
    await pumpCycleScreen(t, const CycleSettingsScreen(),
        settings: const CycleSettings(breastfeeding: Breastfeeding.exclusive));
    expect(textHas('LAM / doğurganlık uyarıları'), findsNothing);
    expect(textHas('Emziren anneler için hatırlatmalar'), findsNothing);
    // Kalan anahtarlar: 4 hatırlatıcı + hafta başlangıcı + akıllı tahmin.
    expect(find.byType(Switch), findsNWidgets(6));
  });
}

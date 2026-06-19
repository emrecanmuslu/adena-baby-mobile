import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:adena_baby/core/ad_widgets.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/features/babies/premature_section.dart';

/// Prematüre veri girişi (PrematureSection) widget testleri. i18n varsayılan
/// locale 'tr' → tr('...') kaynak Türkçe metni döner; doğrulamalar Türkçe.
///
/// Kapsam: bölüm doğmuş bebekte görünür / bekleme modunda gizli (ekranın
/// `if (isBorn)` koşulunu taklit eden host), ve "Evet" toggle'ı gebelik
/// haftası alanını açar (onChanged ön-doldurma değeriyle tetiklenir).

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr'), Locale('en')],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Ekran davranışını taklit eden minimal host: born ise PrematureSection'ı
/// gösterir, expecting ise göstermez — durumu kendi içinde tutar.
class _Host extends StatefulWidget {
  final bool born;
  const _Host({required this.born});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int? _weeks;
  int _days = 0;
  @override
  Widget build(BuildContext context) {
    if (!widget.born) return const SizedBox();
    return PrematureSection(
      weeks: _weeks,
      days: _days,
      onChanged: (w, d) => setState(() {
        _weeks = w;
        _days = d;
      }),
    );
  }
}

void main() {
  group('PrematureSection', () {
    testWidgets('doğmuş bebekte görünür (başlık + Evet/Hayır)',
        (tester) async {
      await tester.pumpWidget(_wrap(const _Host(born: true)));
      expect(find.byType(PrematureSection), findsOneWidget);
      expect(find.text('PREMATÜRE DOĞDU MU?'), findsOneWidget); // AdField label
      expect(find.text('Hayır'), findsOneWidget);
      expect(find.text('Evet'), findsOneWidget);
    });

    testWidgets('bekleme (expecting) modunda gizli', (tester) async {
      await tester.pumpWidget(_wrap(const _Host(born: false)));
      expect(find.byType(PrematureSection), findsNothing);
      expect(find.text('PREMATÜRE DOĞDU MU?'), findsNothing);
    });

    testWidgets('kapalıyken gebelik haftası alanı gizli', (tester) async {
      await tester.pumpWidget(_wrap(const _Host(born: true)));
      // Stepper ("hf" birimi) henüz yok.
      expect(find.text('GEBELIK HAFTASI'), findsNothing);
      expect(find.byType(AdStepper), findsNothing);
    });

    testWidgets('"Evet" toggle\'ı gebelik haftası alanını açar (varsayılan 38)',
        (tester) async {
      await tester.pumpWidget(_wrap(const _Host(born: true)));
      await tester.tap(find.text('Evet'));
      await tester.pumpAndSettle();

      // Haftalar + gün stepperları belirir.
      expect(find.text('GEBELIK HAFTASI'), findsOneWidget);
      expect(find.byType(AdStepper), findsNWidgets(2));
      // Hiç türetme yokken toggle açılınca varsayılan 38 hafta.
      expect(find.text('38'), findsOneWidget);
    });

    testWidgets('açıkken "Hayır" toggle\'ı haftaları temizler ve alanı gizler',
        (tester) async {
      await tester.pumpWidget(_wrap(const _Host(born: true)));
      await tester.tap(find.text('Evet'));
      await tester.pumpAndSettle();
      expect(find.byType(AdStepper), findsNWidgets(2));

      await tester.tap(find.text('Hayır'));
      await tester.pumpAndSettle();
      expect(find.byType(AdStepper), findsNothing);
      expect(find.text('GEBELIK HAFTASI'), findsNothing);
    });

    testWidgets('ön-doldurulmuş haftalarla açık başlar (otomatik türetme)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PrematureSection(weeks: 32, days: 4, onChanged: (w, d) {}),
      ));
      // weeks != null → açık; stepperlar ve değerler görünür.
      expect(find.byType(AdStepper), findsNWidgets(2));
      expect(find.text('32'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  });
}

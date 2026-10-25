import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/modal_gate.dart';
import 'package:adena_baby/core/tour.dart';

/// Kapıyı ömrü boyunca tutan sahte "öncelikli modal" (Premium Karşılama gibi):
/// initState'te tutar, dispose'ta — widget ağacı kilitliyken — bırakır.
class _GateHolder extends StatefulWidget {
  const _GateHolder();

  @override
  State<_GateHolder> createState() => _GateHolderState();
}

class _GateHolderState extends State<_GateHolder> {
  @override
  void initState() {
    super.initState();
    ModalGate.acquire();
  }

  @override
  void dispose() {
    ModalGate.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Regresyon: Premium Karşılama kapanınca (kapı dispose'ta bırakılınca) ana
/// sayfa turu o oturumda HİÇ açılmıyordu — setState kilitli ağaçta etkisizdi.
void main() {
  setUp(() {
    I18n.instance.apply('tr', const {});
    // Keychain göçü zaten yapılmış say → tur kümesi prefs'ten anında okunur.
    SharedPreferences.setMockInitialValues({'kcx_tour_seen_v1': true});
    ModalGate.resetForTest();
  });
  tearDown(ModalGate.resetForTest);

  testWidgets('kapı başka bir widget dispose olurken bırakılınca tur açılır',
      (tester) async {
    final holderVisible = ValueNotifier<bool>(true);
    addTearDown(holderVisible.dispose);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            const TourMount(tourKey: 'home', child: SizedBox.expand()),
            ValueListenableBuilder<bool>(
              valueListenable: holderVisible,
              builder: (_, v, _) => v ? const _GateHolder() : const SizedBox(),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tanıtım'), findsNothing,
        reason: 'öncelikli modal açıkken tur ertelenmeli');

    holderVisible.value = false; // "paywall kapandı" → dispose'ta release
    await tester.pumpAndSettle();
    expect(find.text('Tanıtım'), findsOneWidget);
    expect(ModalGate.isBlocked, isTrue, reason: 'tur açıkken kapıyı tutar');
  });
}

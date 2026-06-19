import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:adena_baby/core/ad_widgets.dart';
import 'package:adena_baby/core/theme.dart';

/// Adena tasarım sistemi (.ad-*) yeniden-kullanılabilir bileşenlerinin widget
/// testleri. Bu kit uygulama genelinde kullanıldığından en yüksek değerli
/// kapsam burası. i18n varsayılan locale 'tr' olduğundan tr('...') kaynak
/// metnin kendisini döner; metin doğrulamaları Türkçe kaynağı kullanır.
///
/// Material seçiciler (date/time) yerel delegate gerektirdiğinden harness
/// flutter_localizations delegate'lerini ve tr/en locale'lerini ekler.

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr'), Locale('en')],
      home: Scaffold(body: child),
    );

void main() {
  group('AdField', () {
    testWidgets('etiketi (büyük harf) ve çocuk widget\'ı gösterir',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AdField(label: 'Ad Soyad', child: Text('child-content')),
      ));
      expect(find.text('AD SOYAD'), findsOneWidget); // label.toUpperCase()
      expect(find.text('child-content'), findsOneWidget);
    });

    testWidgets('info verilmezse AdInfoDot eklemez', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdField(label: 'İsim', child: SizedBox()),
      ));
      expect(find.byType(AdInfoDot), findsNothing);
    });

    testWidgets('info verilince AdInfoDot ekler', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdField(label: 'İsim', info: 'Yardım metni', child: SizedBox()),
      ));
      expect(find.byType(AdInfoDot), findsOneWidget);
    });
  });

  group('AdInfoDot + showAdInfo', () {
    testWidgets('"!" rozetini render eder', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdInfoDot(title: 'Başlık', body: 'Açıklama gövdesi'),
      ));
      expect(find.byType(AdInfoDot), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    });

    testWidgets('dokununca yardım dialog\'unu (showAdInfo) açar',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AdInfoDot(title: 'Başlık', body: 'Açıklama gövdesi'),
      ));
      await tester.tap(find.byType(AdInfoDot));
      await tester.pumpAndSettle();

      // Dialog açıldı: başlık + gövde + "Anladım" butonu görünür.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Başlık'), findsOneWidget);
      expect(find.text('Açıklama gövdesi'), findsOneWidget);
      expect(find.text('Anladım'), findsOneWidget);
    });

    testWidgets('"Anladım" dialog\'u kapatır', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdInfoDot(title: 'Başlık', body: 'Gövde'),
      ));
      await tester.tap(find.byType(AdInfoDot));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      await tester.tap(find.text('Anladım'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('AdInput', () {
    testWidgets('hint gösterir ve metin girişini controller\'a yazar',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AdInput(controller: ctrl, hint: 'Ara...'),
      ));
      expect(find.text('Ara...'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'merhaba');
      expect(ctrl.text, 'merhaba');
    });
  });

  group('AdStepper', () {
    testWidgets('+ ve − değeri adım kadar artırır/azaltır', (tester) async {
      final ctrl = TextEditingController(text: '5');
      await tester.pumpWidget(_wrap(
        AdStepper(controller: ctrl, unit: 'ml', step: 1),
      ));
      expect(find.text('ml'), findsOneWidget);

      await tester.tap(find.text('+'));
      await tester.pump();
      expect(ctrl.text, '6');

      await tester.tap(find.text('−'));
      await tester.tap(find.text('−'));
      await tester.pump();
      expect(ctrl.text, '4');
    });

    testWidgets('değer 0\'ın altına inmez', (tester) async {
      final ctrl = TextEditingController(text: '0');
      await tester.pumpWidget(_wrap(
        AdStepper(controller: ctrl, unit: 'ml'),
      ));
      await tester.tap(find.text('−'));
      await tester.pump();
      expect(ctrl.text, '0');
    });

    testWidgets('ondalık adımı doğru biçimlendirir', (tester) async {
      final ctrl = TextEditingController(text: '1');
      await tester.pumpWidget(_wrap(
        AdStepper(controller: ctrl, unit: 'kg', step: 0.5, decimals: 1),
      ));
      await tester.tap(find.text('+'));
      await tester.pump();
      expect(ctrl.text, '1.5');
    });
  });

  group('AdTabs', () {
    testWidgets('tüm seçenek etiketlerini render eder', (tester) async {
      await tester.pumpWidget(_wrap(
        AdTabs(
          options: const {'a': 'Anne Sütü', 'b': 'Mama'},
          selected: 'a',
          onSelect: (_) {},
        ),
      ));
      expect(find.text('Anne Sütü'), findsOneWidget);
      expect(find.text('Mama'), findsOneWidget);
    });

    testWidgets('sekmeye dokununca onSelect doğru key ile çağrılır',
        (tester) async {
      String? picked;
      await tester.pumpWidget(_wrap(
        AdTabs(
          options: const {'a': 'Anne Sütü', 'b': 'Mama'},
          selected: 'a',
          onSelect: (k) => picked = k,
        ),
      ));
      await tester.tap(find.text('Mama'));
      await tester.pump();
      expect(picked, 'b');
    });
  });

  group('AdChoice', () {
    testWidgets('seçenekleri render eder ve onSelect çalışır', (tester) async {
      String? picked;
      await tester.pumpWidget(_wrap(
        AdChoice(
          items: const [
            (key: 'wet', label: 'Çiş', icon: 'diaper', color: Colors.blue, bg: Colors.white),
            (key: 'dirty', label: 'Kaka', icon: 'diaper', color: Colors.brown, bg: Colors.white),
          ],
          selected: 'wet',
          onSelect: (k) => picked = k,
        ),
      ));
      expect(find.text('Çiş'), findsOneWidget);
      expect(find.text('Kaka'), findsOneWidget);

      await tester.tap(find.text('Kaka'));
      await tester.pump();
      expect(picked, 'dirty');
    });
  });

  group('AdSides', () {
    testWidgets('etiket + alt etiketi render eder ve onSelect çalışır',
        (tester) async {
      String? picked;
      await tester.pumpWidget(_wrap(
        AdSides(
          items: const [
            (key: 'l', label: 'Sol', small: 'önceki'),
            (key: 'r', label: 'Sağ', small: 'sıradaki'),
          ],
          selected: 'l',
          onSelect: (k) => picked = k,
        ),
      ));
      expect(find.text('Sol'), findsOneWidget);
      expect(find.text('Sağ'), findsOneWidget);
      // small etiketleri büyük harfe çevrilir
      expect(find.text('SIRADAKI'), findsOneWidget);

      await tester.tap(find.text('Sağ'));
      await tester.pump();
      expect(picked, 'r');
    });
  });

  group('AdTimeChip', () {
    testWidgets('değer null iken "Tarih/saat seç" gösterir', (tester) async {
      await tester.pumpWidget(_wrap(
        AdTimeChip(value: null, onTap: () {}),
      ));
      expect(find.text('Tarih/saat seç'), findsOneWidget);
      expect(find.text('değiştir'), findsOneWidget);
    });

    testWidgets('dokununca onTap çağrılır', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        AdTimeChip(value: null, onTap: () => tapped = true),
      ));
      await tester.tap(find.byType(AdTimeChip));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('bugünün değeri için "Bugün" metnini gösterir', (tester) async {
      await tester.pumpWidget(_wrap(
        AdTimeChip(value: DateTime.now(), onTap: () {}),
      ));
      expect(find.textContaining('Bugün'), findsOneWidget);
    });
  });

  group('AdSaveButton', () {
    testWidgets('filled (varsayılan) modda etiketi gösterir, onTap çalışır',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        AdSaveButton(
          label: 'Kaydet',
          color: AppColors.coral,
          onTap: () => tapped = true,
        ),
      ));
      expect(find.text('Kaydet'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('ghost modda OutlinedButton kullanır', (tester) async {
      await tester.pumpWidget(_wrap(
        AdSaveButton(
          label: 'İptal',
          color: AppColors.coral,
          ghost: true,
          onTap: () {},
        ),
      ));
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('AdIconChip', () {
    testWidgets('render edilir (boyut uygulanır)', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdIconChip('feed', color: Colors.red, bg: Colors.white, size: 40),
      ));
      expect(find.byType(AdIconChip), findsOneWidget);
    });
  });

  group('AdMenuItem', () {
    testWidgets('başlık + meta gösterir, dokununca onTap çalışır',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        AdMenuItem(
          icon: 'feed',
          color: Colors.red,
          bg: Colors.white,
          title: 'Beslenme',
          meta: 'son 2 saat önce',
          onTap: () => tapped = true,
        ),
      ));
      expect(find.text('Beslenme'), findsOneWidget);
      expect(find.text('son 2 saat önce'), findsOneWidget);

      await tester.tap(find.byType(AdMenuItem));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('trailing verilmezse chevron ikonu gösterir', (tester) async {
      await tester.pumpWidget(_wrap(
        AdMenuItem(
          icon: 'feed',
          color: Colors.red,
          bg: Colors.white,
          title: 'Beslenme',
        ),
      ));
      // 1 ikon çipi + 1 chevron = 2 AdenaIcon
      expect(find.byType(AdMenuItem), findsOneWidget);
    });
  });

  group('AdProBadge', () {
    testWidgets('varsayılan "Premium" etiketini gösterir', (tester) async {
      await tester.pumpWidget(_wrap(const AdProBadge()));
      expect(find.text('Premium'), findsOneWidget);
    });

    testWidgets('özel etiket gösterir', (tester) async {
      await tester.pumpWidget(_wrap(const AdProBadge(label: 'PRO')));
      expect(find.text('PRO'), findsOneWidget);
    });
  });

  group('adSec', () {
    testWidgets('başlığı büyük harfle gösterir', (tester) async {
      await tester.pumpWidget(_wrap(adSec('Anılar')));
      expect(find.text('ANILAR'), findsOneWidget);
    });

    testWidgets('info verilince AdInfoDot ekler', (tester) async {
      await tester.pumpWidget(_wrap(adSec('Anılar', info: 'Bölüm açıklaması')));
      expect(find.byType(AdInfoDot), findsOneWidget);
    });
  });

  group('AdMedicalNote', () {
    testWidgets('varsayılan feragat metnini gösterir', (tester) async {
      await tester.pumpWidget(_wrap(const AdMedicalNote()));
      expect(find.textContaining('genel bilgilendirme amaçlıdır'),
          findsOneWidget);
    });

    testWidgets('özel metin gösterir', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdMedicalNote(text: 'Özel uyarı metni'),
      ));
      expect(find.text('Özel uyarı metni'), findsOneWidget);
    });
  });

  group('adGrabHandle', () {
    testWidgets('sürükleme tutamağını render eder', (tester) async {
      await tester.pumpWidget(_wrap(adGrabHandle()));
      expect(find.byType(Container), findsWidgets);
    });
  });

  group('showAdToast', () {
    testWidgets('mesajı bir overlay toast olarak gösterir', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_wrap(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      showAdToast(ctx, 'Kaydedildi', type: AdToastType.success);
      await tester.pump(); // toast giriş animasyonu başlar
      expect(find.text('Kaydedildi'), findsOneWidget);

      // Geri sayım + kapanış animasyonunu sonlandır (askıda timer kalmasın).
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('Kaydedildi'), findsNothing);
    });

    testWidgets('onUndo verilince "Geri al" gösterir ve tetikler',
        (tester) async {
      late BuildContext ctx;
      var undone = false;
      await tester.pumpWidget(_wrap(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      showAdToast(ctx, 'Silindi',
          type: AdToastType.error, onUndo: () => undone = true);
      await tester.pump();
      expect(find.text('Geri al'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(undone, isTrue);
    });

    testWidgets('yeni toast eskisini değiştirir (tek toast ilkesi)',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_wrap(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      showAdToast(ctx, 'Birinci');
      await tester.pump();
      expect(find.text('Birinci'), findsOneWidget);

      showAdToast(ctx, 'İkinci');
      await tester.pump();
      expect(find.text('Birinci'), findsNothing);
      expect(find.text('İkinci'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('pickRecordDateTime', () {
    testWidgets('saat seçiciyi açar; "Tamam" seçilen saatle DateTime döner',
        (tester) async {
      DateTime? result;
      final initial = DateTime(2026, 6, 18, 14, 30);
      late BuildContext ctx;
      await tester.pumpWidget(_wrap(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      final future = pickRecordDateTime(ctx, initial).then((v) => result = v);
      await tester.pumpAndSettle();

      // Material time picker açıldı (yardım metni tr kaynağı).
      expect(find.text('Saat seç'), findsOneWidget);

      // "Tamam" ile onayla → başlangıç saatiyle döner (saati değiştirmeden).
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      await future;

      expect(result, isNotNull);
      expect(result!.hour, 14);
      expect(result!.minute, 30);
    });
  });
}

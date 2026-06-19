import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/models/article.dart';
import 'package:adena_baby/features/content/content_ui.dart';
import 'package:adena_baby/features/community/community_ui.dart';

/// Ağ/router/firebase olmadan render olan SUNUMSAL (presentational) bileşenlerin
/// widget testleri. Tam ekranlar (DiscoverScreen, AppearanceScreen, milestones,
/// teeth) ConsumerWidget'tır ve baby/theme/locale/health provider'larına +
/// go_router'a bağlıdır; bunlar repository/controller katmanında zaten test
/// edildiğinden burada KAPSAM DIŞI bırakıldı (bkz final rapor). Onların yerine
/// bu ekranların yapı taşı olan paylaşılan sunum widget'larını test ediyoruz.
///
/// i18n varsayılan locale 'tr' → tr('...') kaynak metni döner; metin
/// doğrulamaları Türkçe kaynağı kullanır.

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

Article _article({
  String title = 'Bebek Uykusu Rehberi',
  String summary = 'İlk aylarda uyku düzeni nasıl kurulur.',
  String categoryName = 'Uyku',
  int readMinutes = 5,
}) =>
    Article(
      slug: 'bebek-uykusu',
      title: title,
      summary: summary,
      categoryName: categoryName,
      readMinutes: readMinutes,
    );

void main() {
  group('content_ui yardımcıları (saf fonksiyonlar)', () {
    test('parseHexColor geçerli hex\'i çözer, geçersizde null döner', () {
      expect(parseHexColor('#FF8A7A'), const Color(0xFFFF8A7A));
      expect(parseHexColor('9B8CE8'), const Color(0xFF9B8CE8));
      expect(parseHexColor(null), isNull);
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('zzz'), isNull);
    });

    test('categoryColor hex yoksa mercana düşer', () {
      expect(categoryColor(null), AppColors.coralDd);
      expect(categoryColor('#123456'), const Color(0xFF123456));
    });

    test('ageRangeLabel aralıkları okunur etikete çevirir', () {
      expect(ageRangeLabel(0, 240), 'Her yaş');
      expect(ageRangeLabel(0, 6), '6 aya kadar');
      expect(ageRangeLabel(6, 12), '6 ay – 12 ay');
      expect(ageRangeLabel(24, 240), '2 yaş+');
    });
  });

  group('ArticleCard', () {
    testWidgets('başlık, özet, kategori ve okuma süresini gösterir',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SizedBox(width: 360, child: ArticleCard(article: _article())),
      ));
      expect(find.text('Bebek Uykusu Rehberi'), findsOneWidget);
      expect(find.text('İlk aylarda uyku düzeni nasıl kurulur.'),
          findsOneWidget);
      expect(find.text('UYKU'), findsOneWidget); // kategori büyük harf
      expect(find.text('5 dk'), findsOneWidget); // okuma süresi
    });

    testWidgets('özet boşken özet satırı çizmez ama hata vermez',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 360,
          child: ArticleCard(article: _article(summary: '')),
        ),
      ));
      expect(find.text('Bebek Uykusu Rehberi'), findsOneWidget);
    });
  });

  group('AuthorRow', () {
    testWidgets('isim ve baş harf avatarı gösterir', (tester) async {
      await tester.pumpWidget(_wrap(
        AuthorRow(
          name: 'Ayşe',
          color: '#FF8A7A',
          anonymous: false,
          isMine: false,
          time: DateTime.now(),
        ),
      ));
      expect(find.text('Ayşe'), findsOneWidget);
      expect(find.text('A'), findsOneWidget); // avatar baş harfi
    });

    testWidgets('anonimde "Anonim" gösterir', (tester) async {
      await tester.pumpWidget(_wrap(
        AuthorRow(
          name: 'Ayşe',
          color: '#FF8A7A',
          anonymous: true,
          isMine: false,
          time: DateTime.now(),
        ),
      ));
      expect(find.textContaining('Anonim'), findsOneWidget);
    });

    testWidgets('isMine ise "(sen)" ekler', (tester) async {
      await tester.pumpWidget(_wrap(
        AuthorRow(
          name: 'Ben',
          color: '#FF8A7A',
          anonymous: false,
          isMine: true,
          time: DateTime.now(),
        ),
      ));
      expect(find.textContaining('(sen)'), findsOneWidget);
    });
  });

  group('VoteControl', () {
    testWidgets('skoru gösterir', (tester) async {
      await tester.pumpWidget(_wrap(
        VoteControl(score: 7, myVote: 0, onVote: (_) {}),
      ));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('yukarı oka basınca +1 gönderir', (tester) async {
      int? sent;
      await tester.pumpWidget(_wrap(
        VoteControl(score: 0, myVote: 0, onVote: (v) => sent = v),
      ));
      // İlk (üstteki) oy butonu = yukarı.
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(sent, 1);
    });

    testWidgets('zaten yukarı oyluyken tekrar basınca oyu kaldırır (0)',
        (tester) async {
      int? sent;
      await tester.pumpWidget(_wrap(
        VoteControl(score: 1, myVote: 1, onVote: (v) => sent = v),
      ));
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(sent, 0);
    });

    testWidgets('aşağı oka basınca -1 gönderir', (tester) async {
      int? sent;
      await tester.pumpWidget(_wrap(
        VoteControl(score: 0, myVote: 0, onVote: (v) => sent = v),
      ));
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump();
      expect(sent, -1);
    });
  });

  group('BestBadge', () {
    testWidgets('"En iyi cevap" etiketini gösterir', (tester) async {
      await tester.pumpWidget(_wrap(const BestBadge()));
      expect(find.text('En iyi cevap'), findsOneWidget);
    });
  });

  group('OwnerMenu', () {
    testWidgets('açılınca Düzenle/Sil sunar ve seçim callback\'i tetikler',
        (tester) async {
      var edited = false;
      var deleted = false;
      await tester.pumpWidget(_wrap(
        OwnerMenu(
          onEdit: () => edited = true,
          onDelete: () => deleted = true,
        ),
      ));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);

      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
      expect(edited, isFalse);
    });
  });
}

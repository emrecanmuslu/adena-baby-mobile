import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/data/community_repository.dart';
import 'package:adena_baby/data/content_repository.dart';
import 'package:adena_baby/features/community/community_feed_screen.dart';
import 'package:adena_baby/features/community/community_ui.dart';
import 'package:adena_baby/models/community.dart';

class _MockRepo extends Mock implements CommunityRepository {}

Question _q(String id) =>
    Question(id: id, title: 'Soru $id', createdAt: DateTime(2026, 1, 1));

/// D36 — reset (sıralama/kategori/arama/yenile) sürerken bekleyen loadMore
/// yanıtı yeni listeye EKLENMEZ (fetch epoch).
void main() {
  testWidgets('loadMore uçuştayken sıralama değişir → bayat sayfa listeye girmez',
      (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _MockRepo();
    final calls = <({String sort, int offset, Completer<List<Question>> c})>[];
    when(() => repo.feed(
          category: any(named: 'category'),
          sort: any(named: 'sort'),
          search: any(named: 'search'),
          offset: any(named: 'offset'),
          limit: any(named: 'limit'),
        )).thenAnswer((inv) {
      final c = Completer<List<Question>>();
      calls.add((
        sort: inv.namedArguments[#sort] as String,
        offset: inv.namedArguments[#offset] as int,
        c: c,
      ));
      return c.future;
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        communityRepositoryProvider.overrideWithValue(repo),
        contentCategoriesProvider.overrideWith((_) async => const []),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const CommunityFeedScreen()),
    ));
    await tester.pump();
    // 1) ilk sayfa: 20 soru (hasMore)
    expect(calls, hasLength(1));
    calls[0].c.complete([for (var i = 0; i < 20; i++) _q('a$i')]);
    await tester.pump();
    expect(find.byType(QuestionCard), findsWidgets);

    // 2) sona kaydır → loadMore (offset 20) uçuşta kalır
    await tester.drag(find.byType(QuestionCard).first, const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // kaydırma fiziği otursun
    expect(calls.where((c) => c.offset == 20), hasLength(1), reason: 'loadMore başladı');
    final loadMore = calls.firstWhere((c) => c.offset == 20);

    // 3) sıralamayı değiştir → reset (offset 0, sort=popular)
    await tester.tap(find.text('Popüler'));
    await tester.pump();
    final reset = calls.lastWhere((c) => c.offset == 0 && c.sort != 'new');
    reset.c.complete([_q('z1'), _q('z2')]);
    await tester.pump();

    // 4) bayat loadMore sonra döner → yeni listeye eklenmemeli
    loadMore.c.complete([for (var i = 0; i < 20; i++) _q('stale$i')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Soru z1'), findsOneWidget);
    expect(find.text('Soru stale0'), findsNothing, reason: 'bayat sayfa (D36)');
    expect(find.textContaining('Soru stale'), findsNothing);
  });
}

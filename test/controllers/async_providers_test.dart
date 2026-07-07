import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/data/community_repository.dart';
import 'package:adena_baby/data/content_repository.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/mom_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/models/article.dart';
import 'package:adena_baby/models/community.dart';
import 'package:adena_baby/models/cycle.dart';
import 'package:adena_baby/models/mom_entry.dart';
import 'package:adena_baby/models/user.dart';

class MockCommunityRepository extends Mock implements CommunityRepository {}

class MockContentRepository extends Mock implements ContentRepository {}

class MockCycleRepository extends Mock implements CycleRepository {}

class MockMomRepository extends Mock implements MomRepository {}

/// Oturumsuz auth stub'ı — cycle provider'ları auth çözülmesini beklediği için
/// (açılış yarışı koruması) testte gerçek AuthController.build koşturulmaz.
class _StubAuthController extends AuthController {
  @override
  Future<User?> build() async => null;
}

/// Polls a listened AsyncValue subscription until it leaves the loading state.
/// Used for error paths where reading `.future` can hang instead of rejecting.
Future<AsyncValue<T>> drain<T>(ProviderSubscription<AsyncValue<T>> sub) async {
  for (var i = 0; i < 50; i++) {
    final v = sub.read();
    if (!v.isLoading) return v;
    await Future<void>.delayed(Duration.zero);
  }
  return sub.read();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Question q(String id) =>
      Question(id: id, title: 'T$id', createdAt: DateTime(2026, 1, 1));

  // ---------------------------------------------------------------------------
  group('communityFeedProvider (family FeedQuery)', () {
    late MockCommunityRepository repo;
    setUp(() => repo = MockCommunityRepository());

    ProviderContainer make() {
      final c = ProviderContainer(overrides: [
        communityRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('resolves to repo.feed result with category + sort', () async {
      when(() => repo.feed(category: 'health', sort: 'top'))
          .thenAnswer((_) async => [q('1'), q('2')]);

      final c = make();
      final out = await c.read(
          communityFeedProvider((category: 'health', sort: 'top')).future);

      expect(out.map((e) => e.id), ['1', '2']);
      verify(() => repo.feed(category: 'health', sort: 'top')).called(1);
    });

    test('error → AsyncError', () async {
      when(() => repo.feed(category: any(named: 'category'), sort: any(named: 'sort')))
          .thenAnswer((_) async => throw Exception('boom'));

      final c = make();
      final key = (category: null, sort: 'new');
      final sub = c.listen(communityFeedProvider(key), (_, _) {},
          fireImmediately: true);
      final v = await drain(sub);
      expect(v.hasError, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('content providers', () {
    late MockContentRepository repo;
    setUp(() => repo = MockContentRepository());

    ProviderContainer make() {
      final c = ProviderContainer(overrides: [
        contentRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('contentCategoriesProvider resolves to repo.categories()', () async {
      when(() => repo.categories()).thenAnswer((_) async =>
          [const ArticleCategory(slug: 'sleep', name: 'Uyku')]);

      final c = make();
      final out = await c.read(contentCategoriesProvider.future);

      expect(out.single.slug, 'sleep');
      verify(() => repo.categories()).called(1);
    });

    test('articlesProvider passes the ArticleQuery to repo.articles', () async {
      when(() => repo.articles(category: 'sleep', ageMonths: 6))
          .thenAnswer((_) async => [const Article(slug: 'a1', title: 'A1')]);

      final c = make();
      final out = await c
          .read(articlesProvider((category: 'sleep', ageMonths: 6)).future);

      expect(out.single.slug, 'a1');
      verify(() => repo.articles(category: 'sleep', ageMonths: 6)).called(1);
    });

    test('articleProvider resolves a single article by slug', () async {
      when(() => repo.article('a1')).thenAnswer(
          (_) async => const Article(slug: 'a1', title: 'A1', body: '# Hi'));

      final c = make();
      final out = await c.read(articleProvider('a1').future);

      expect(out.body, '# Hi');
    });

    test('contentCategoriesProvider error → AsyncError', () async {
      when(() => repo.categories())
          .thenAnswer((_) async => throw Exception('net'));

      final c = make();
      final sub = c.listen(contentCategoriesProvider, (_, _) {},
          fireImmediately: true);
      final v = await drain(sub);
      expect(v.hasError, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('cycle providers', () {
    late MockCycleRepository repo;
    setUp(() => repo = MockCycleRepository());

    ProviderContainer make() {
      final c = ProviderContainer(overrides: [
        cycleRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(_StubAuthController.new),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('cycleSettingsProvider resolves to repo.getSettings()', () async {
      when(() => repo.getSettings())
          .thenAnswer((_) async => const CycleSettings(enabled: false));

      final c = make();
      final out = await c.read(cycleSettingsProvider.future);

      expect(out.enabled, isFalse);
      verify(() => repo.getSettings()).called(1);
    });

    test('cycleEntriesProvider resolves to repo.listEntries()', () async {
      when(() => repo.listEntries()).thenAnswer(
          (_) async => [CycleEntry(id: 'e1', date: DateTime(2026, 6, 1))]);

      final c = make();
      final out = await c.read(cycleEntriesProvider.future);

      expect(out.single.id, 'e1');
      verify(() => repo.listEntries()).called(1);
    });

    test('cycleSettingsProvider error → AsyncError', () async {
      when(() => repo.getSettings())
          .thenAnswer((_) async => throw Exception('db'));

      final c = make();
      final sub = c.listen(cycleSettingsProvider, (_, _) {},
          fireImmediately: true);
      final v = await drain(sub);
      expect(v.hasError, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('momEntriesProvider (family String)', () {
    late MockMomRepository repo;
    setUp(() => repo = MockMomRepository());

    ProviderContainer make() {
      final c = ProviderContainer(overrides: [
        momRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('resolves to repo.list(babyId)', () async {
      when(() => repo.list('b1')).thenAnswer((_) async => [
            MomEntry(id: 'm1', kind: MomKind.weight, date: DateTime(2026, 6, 1),
                weightKg: 60),
          ]);

      final c = make();
      final out = await c.read(momEntriesProvider('b1').future);

      expect(out.single.id, 'm1');
      expect(out.single.weightKg, 60);
      verify(() => repo.list('b1')).called(1);
    });

    test('error → AsyncError', () async {
      when(() => repo.list('b1'))
          .thenAnswer((_) async => throw Exception('boom'));

      final c = make();
      final sub = c.listen(momEntriesProvider('b1'), (_, _) {},
          fireImmediately: true);
      final v = await drain(sub);
      expect(v.hasError, isTrue);
    });
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/data/sync_merge.dart';

void main() {
  final t1 = DateTime.utc(2026, 1, 1, 10);
  final t2 = DateTime.utc(2026, 1, 1, 11);

  group('decideServerRow (R1/R2) — dirty × deleted × damga matrisi', () {
    test('yerel satır yok → apply', () {
      expect(decideServerRow(localExists: false), MergeDecision.apply);
      expect(
          decideServerRow(
              localExists: false, localDirty: true, localDeleted: true),
          MergeDecision.apply,
          reason: 'localExists=false iken diğer bayraklar anlamsız');
    });

    test('temiz satır → apply (damgadan bağımsız)', () {
      expect(decideServerRow(localExists: true), MergeDecision.apply);
      expect(
          decideServerRow(localExists: true, localStamp: t2, serverStamp: t1),
          MergeDecision.apply,
          reason: 'temiz satırda yerel damga daha yeni olsa da sunucu otoriter');
    });

    test('temiz + silinmiş (onaylanmış tombstone) → apply (sunucu otoriter)', () {
      expect(decideServerRow(localExists: true, localDeleted: true),
          MergeDecision.apply);
    });

    test('dirty, damga yok → keepDirty', () {
      expect(decideServerRow(localExists: true, localDirty: true),
          MergeDecision.keepDirty);
    });

    test('dirty, yerel damga sunucudan yeni → keepDirty', () {
      expect(
          decideServerRow(
              localExists: true,
              localDirty: true,
              localStamp: t2,
              serverStamp: t1),
          MergeDecision.keepDirty);
    });

    test('dirty, damgalar eşit → keepDirty (çakışma değil)', () {
      expect(
          decideServerRow(
              localExists: true,
              localDirty: true,
              localStamp: t1,
              serverStamp: t1),
          MergeDecision.keepDirty);
    });

    test('dirty, sunucu damgası yerelden yeni → keepDirtyConflict (yine yerel kalır)',
        () {
      expect(
          decideServerRow(
              localExists: true,
              localDirty: true,
              localStamp: t1,
              serverStamp: t2),
          MergeDecision.keepDirtyConflict);
    });

    test('dirty, yalnız sunucu damgası var → keepDirty (karşılaştırılamaz)', () {
      expect(
          decideServerRow(localExists: true, localDirty: true, serverStamp: t2),
          MergeDecision.keepDirty);
    });

    test('dirty + silinmiş (bekleyen tombstone) → keepDeleted, damga ne olursa olsun',
        () {
      expect(
          decideServerRow(
              localExists: true, localDirty: true, localDeleted: true),
          MergeDecision.keepDeleted);
      expect(
          decideServerRow(
              localExists: true,
              localDirty: true,
              localDeleted: true,
              localStamp: t1,
              serverStamp: t2),
          MergeDecision.keepDeleted,
          reason: 'sunucu daha yeni olsa da tombstone geri alınmaz (R2)');
    });
  });

  group('staleLocalIds (R4 + K-2 korumaları)', () {
    LocalRowState clean(String id) =>
        LocalRowState(id, dirty: false, deleted: false);
    LocalRowState dirty(String id) =>
        LocalRowState(id, dirty: true, deleted: false);
    LocalRowState tomb(String id) =>
        LocalRowState(id, dirty: true, deleted: true);

    test('sunucuda olmayan temiz satır silinir; dirty ve tombstone asla aday değil',
        () {
      final r = staleLocalIds(
        local: [clean('a'), clean('b'), dirty('c'), tomb('d')],
        serverIds: {'a'},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.skipped, isFalse);
      expect(r.ids, {'b'});
    });

    test('hepsi sunucuda → boş küme, atlama yok', () {
      final r = staleLocalIds(
        local: [clean('a'), clean('b')],
        serverIds: {'a', 'b', 'z'},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.ids, isEmpty);
      expect(r.skipped, isFalse);
    });

    test('HTTP 200 dışı → silme atlanır (untrusted_response)', () {
      final r = staleLocalIds(
        local: [clean('a')],
        serverIds: {},
        statusCode: 206,
        parsedOk: true,
      );
      expect(r.skipped, isTrue);
      expect(r.skippedReason, 'untrusted_response');
      expect(r.ids, isEmpty);
    });

    test('yanıt tam parse edilemedi → silme atlanır', () {
      final r = staleLocalIds(
        local: [clean('a')],
        serverIds: {'x'},
        statusCode: 200,
        parsedOk: false,
      );
      expect(r.skippedReason, 'untrusted_response');
    });

    test('sunucu listesi boş → hiç silme (server_list_empty)', () {
      final r = staleLocalIds(
        local: [clean('a')],
        serverIds: {},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.skippedReason, 'server_list_empty');
      expect(r.ids, isEmpty);
    });

    test('sunucu boş ama yerelde temiz aday yok → atlama değil, boş sonuç', () {
      final r = staleLocalIds(
        local: [dirty('a'), tomb('b')],
        serverIds: {},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.skipped, isFalse);
      expect(r.ids, isEmpty);
    });

    test('oran koruması: >5 VE temizlerin >%50\'si → atlanır', () {
      // 10 temiz, 6'sı sunucuda yok (6 > 5 ve 6*2 > 10).
      final local = [for (var i = 0; i < 10; i++) clean('r$i')];
      final r = staleLocalIds(
        local: local,
        serverIds: {'r0', 'r1', 'r2', 'r3', 'other'},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.skipped, isTrue);
      expect(r.skippedReason, startsWith('too_many_deletions:6/10'));
    });

    test('>5 ama temizlerin ≤%50\'si → silinir', () {
      // 12 temiz, 6'sı yok: 6 > 5 ama 6*2 > 12 değil → uygula.
      final local = [for (var i = 0; i < 12; i++) clean('r$i')];
      final r = staleLocalIds(
        local: local,
        serverIds: {'r0', 'r1', 'r2', 'r3', 'r4', 'r5'},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.skipped, isFalse);
      expect(r.ids, hasLength(6));
    });

    test('≤5 ama temizlerin >%50\'si → silinir (eşik VE koşulu)', () {
      // 3 temiz, 2'si yok: 2 ≤ 5 → oran bakılmaz.
      final r = staleLocalIds(
        local: [clean('a'), clean('b'), clean('c')],
        serverIds: {'a', 'x'},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.skipped, isFalse);
      expect(r.ids, {'b', 'c'});
    });

    test('oran hesabında dirty/tombstone satırlar paydaya girmez', () {
      // 10 temiz (6 yok) + 20 dirty: temiz paydası 10 → 6/10 → atlanır.
      final local = [
        for (var i = 0; i < 10; i++) clean('r$i'),
        for (var i = 0; i < 20; i++) dirty('d$i'),
      ];
      final r = staleLocalIds(
        local: local,
        serverIds: {'r0', 'r1', 'r2', 'r3'},
        statusCode: 200,
        parsedOk: true,
      );
      expect(r.skipped, isTrue);
    });
  });

  group('classifyPushFailure (R3)', () {
    test('ağ/timeout (kod yok) → transient', () {
      expect(classifyPushFailure(statusCode: null), PushFailure.transient);
    });

    test('5xx, 401, 403, 408, 429 → transient', () {
      for (final c in [500, 502, 503, 401, 403, 408, 429]) {
        expect(classifyPushFailure(statusCode: c), PushFailure.transient,
            reason: 'kod $c');
      }
    });

    test('400, 404, 409, 413, 422 → permanent', () {
      for (final c in [400, 404, 409, 413, 422]) {
        expect(classifyPushFailure(statusCode: c), PushFailure.permanent,
            reason: 'kod $c');
      }
    });

    test('classifyDioError: yanıtsız bağlantı hatası → transient, 422 → permanent',
        () {
      final opts = RequestOptions(path: '/x');
      expect(
          classifyDioError(DioException(
              requestOptions: opts, type: DioExceptionType.connectionError)),
          PushFailure.transient);
      expect(
          classifyDioError(DioException(
              requestOptions: opts,
              response: Response(requestOptions: opts, statusCode: 422))),
          PushFailure.permanent);
    });
  });
}

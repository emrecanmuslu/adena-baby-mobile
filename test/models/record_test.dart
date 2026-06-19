import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/models/record.dart';

void main() {
  group('RecordType.fromString', () {
    test('bilinen tüm tip stringleri doğru enum\'a çözülür', () {
      expect(RecordType.fromString('diaper'), RecordType.diaper);
      expect(RecordType.fromString('feed'), RecordType.feed);
      expect(RecordType.fromString('pumping'), RecordType.pumping);
      expect(RecordType.fromString('sleep'), RecordType.sleep);
      expect(RecordType.fromString('growth'), RecordType.growth);
      expect(RecordType.fromString('temperature'), RecordType.temperature);
      expect(RecordType.fromString('medication'), RecordType.medication);
      expect(RecordType.fromString('bath'), RecordType.bath);
      expect(RecordType.fromString('appointment'), RecordType.appointment);
      expect(RecordType.fromString('symptom'), RecordType.symptom);
    });

    test('bilinmeyen değer feed\'e düşer (fallback)', () {
      expect(RecordType.fromString('uzaylı'), RecordType.feed);
      expect(RecordType.fromString(''), RecordType.feed);
      expect(RecordType.fromString('Diaper'), RecordType.feed); // büyük/küçük harf duyarlı
    });
  });

  group('Record.fromJson', () {
    test('zorunlu alanlar + data Map olarak ayrıştırılır', () {
      final r = Record.fromJson({
        'id': 'rec-1',
        'baby': 'baby-1',
        'type': 'diaper',
        'ts': '2026-06-18T10:30:00Z',
        'data': {'sub': 'wet', 'amount': 2},
        'is_deleted': false,
        'created_by': 'user-9',
      });
      expect(r.id, 'rec-1');
      expect(r.baby, 'baby-1');
      expect(r.type, RecordType.diaper);
      expect(r.data['sub'], 'wet');
      expect(r.data['amount'], 2);
      expect(r.isDeleted, false);
      expect(r.createdBy, 'user-9');
    });

    test('baby_id alanı baby alternatifi olarak kullanılır', () {
      final r = Record.fromJson({
        'id': 'rec-1',
        'baby_id': 'baby-alt',
        'type': 'feed',
        'ts': '2026-06-18T10:30:00Z',
      });
      expect(r.baby, 'baby-alt');
    });

    test('ts UTC stringi yerele çevrilir (toLocal)', () {
      final r = Record.fromJson({
        'id': 'rec-1',
        'baby': 'b',
        'type': 'feed',
        'ts': '2026-06-18T10:30:00Z',
      });
      expect(r.ts.isUtc, isFalse);
      // Aynı ana karşılık gelir (UTC değeri korunur).
      expect(r.ts.toUtc(), DateTime.utc(2026, 6, 18, 10, 30));
    });

    test('data alanı yoksa boş map, is_deleted/created_by opsiyonel', () {
      final r = Record.fromJson({
        'id': 'rec-1',
        'baby': 'b',
        'type': 'feed',
        'ts': '2026-06-18T10:30:00Z',
      });
      expect(r.data, isEmpty);
      expect(r.isDeleted, false);
      expect(r.createdBy, isNull);
    });

    test('data string (JSON-encoded) olarak gelirse decode edilir', () {
      final r = Record.fromJson({
        'id': 'rec-1',
        'baby': 'b',
        'type': 'growth',
        'ts': '2026-06-18T10:30:00Z',
        'data': jsonEncode({'weight_g': 4200, 'height_cm': 55.5}),
      });
      expect(r.data['weight_g'], 4200);
      expect(r.data['height_cm'], 55.5);
    });

    test('is_deleted true geçince korunur', () {
      final r = Record.fromJson({
        'id': 'rec-1',
        'baby': 'b',
        'type': 'feed',
        'ts': '2026-06-18T10:30:00Z',
        'is_deleted': true,
      });
      expect(r.isDeleted, true);
    });
  });

  group('Record dataJson round-trip (polimorfik data — tip başına)', () {
    // Tipe özgü alanlar Record.data içinde opak Map; encode/decode korunmalı.
    final payloads = <RecordType, Map<String, dynamic>>{
      RecordType.diaper: {'sub': 'dirty', 'color': 'yellow', 'consistency': 'soft'},
      RecordType.feed: {'sub': 'formula', 'amount_ml': 120},
      RecordType.pumping: {'left_ml': 60, 'right_ml': 50, 'duration_min': 15},
      RecordType.sleep: {'start_ts': '2026-06-18T01:00:00Z', 'end_ts': '2026-06-18T03:30:00Z'},
      RecordType.growth: {'weight_g': 4200, 'height_cm': 55.5, 'head_cm': 38.2},
      RecordType.temperature: {'celsius': 37.8, 'method': 'forehead'},
      RecordType.medication: {'name': 'D vitamini', 'dose': '400 IU'},
      RecordType.bath: {'note': 'akşam banyosu'},
      RecordType.appointment: {'title': 'Çocuk doktoru', 'with': 'Dr. X'},
      RecordType.symptom: {'key': 'cough', 'severity': 'mild'},
    };

    payloads.forEach((type, data) {
      test('${type.name} data fromJson→dataJson→decode aynı kalır', () {
        final r = Record.fromJson({
          'id': 'rec-${type.name}',
          'baby': 'b',
          'type': type.name,
          'ts': '2026-06-18T10:30:00Z',
          'data': data,
        });
        expect(r.type, type);
        final decoded = jsonDecode(r.dataJson) as Map<String, dynamic>;
        expect(decoded, equals(data));
      });
    });
  });

  group('isOngoingSleep getter', () {
    Record sleep(Map<String, dynamic> data) => Record(
          id: 's',
          baby: 'b',
          type: RecordType.sleep,
          ts: DateTime(2026, 6, 18),
          data: data,
        );

    test('end_ts yoksa süren uyku', () {
      expect(sleep({'start_ts': '2026-06-18T01:00:00Z'}).isOngoingSleep, isTrue);
      expect(sleep({}).isOngoingSleep, isTrue);
    });

    test('end_ts varsa süren değil', () {
      expect(
        sleep({'start_ts': 'x', 'end_ts': '2026-06-18T03:00:00Z'}).isOngoingSleep,
        isFalse,
      );
    });

    test('uyku olmayan tip için her zaman false', () {
      final r = Record(
        id: 's',
        baby: 'b',
        type: RecordType.feed,
        ts: DateTime(2026, 6, 18),
        data: const {},
      );
      expect(r.isOngoingSleep, isFalse);
    });
  });

  group('isOngoingBreast getter', () {
    Record feed(Map<String, dynamic> data) => Record(
          id: 'f',
          baby: 'b',
          type: RecordType.feed,
          ts: DateTime(2026, 6, 18),
          data: data,
        );

    test('breast + start_ts var + end_ts yok → süren emzirme', () {
      expect(
        feed({'sub': 'breast', 'start_ts': '2026-06-18T01:00:00Z'}).isOngoingBreast,
        isTrue,
      );
    });

    test('end_ts varsa süren değil', () {
      expect(
        feed({'sub': 'breast', 'start_ts': 'x', 'end_ts': 'y'}).isOngoingBreast,
        isFalse,
      );
    });

    test('start_ts yoksa (elle girilmiş) süren değil', () {
      expect(feed({'sub': 'breast'}).isOngoingBreast, isFalse);
    });

    test('sub breast değilse süren değil', () {
      expect(
        feed({'sub': 'formula', 'start_ts': 'x'}).isOngoingBreast,
        isFalse,
      );
    });
  });

  group('Record.copyWith', () {
    final base = Record(
      id: 'rec-1',
      baby: 'baby-1',
      type: RecordType.feed,
      ts: DateTime(2026, 6, 18, 10),
      data: const {'sub': 'breast'},
      isDeleted: false,
      createdBy: 'user-1',
    );

    test('hiç argüman verilmezse tüm alanlar korunur', () {
      final c = base.copyWith();
      expect(c.id, base.id);
      expect(c.baby, base.baby);
      expect(c.type, base.type);
      expect(c.ts, base.ts);
      expect(c.data, base.data);
      expect(c.isDeleted, base.isDeleted);
      expect(c.createdBy, base.createdBy);
    });

    test('yalnız verilen alan değişir — id/baby/type asla değişmez', () {
      final c = base.copyWith(isDeleted: true);
      expect(c.isDeleted, true);
      expect(c.id, base.id);
      expect(c.baby, base.baby);
      expect(c.type, base.type);
      expect(c.data, base.data);
      expect(c.ts, base.ts);
    });

    test('data ve ts birlikte değiştirilebilir', () {
      final newTs = DateTime(2026, 6, 19, 12);
      final c = base.copyWith(data: const {'sub': 'formula'}, ts: newTs);
      expect(c.data, const {'sub': 'formula'});
      expect(c.ts, newTs);
      expect(c.createdBy, base.createdBy); // dokunulmadı
    });

    test('createdBy değiştirilebilir', () {
      final c = base.copyWith(createdBy: 'user-2');
      expect(c.createdBy, 'user-2');
    });
  });
}

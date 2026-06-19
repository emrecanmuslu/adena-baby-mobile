import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/models/quiet_hours.dart';
import 'package:adena_baby/models/feed_reminder.dart';
import 'package:adena_baby/models/reminder.dart';

void main() {
  group('QuietHours.fromMap / toMap', () {
    test('null map → varsayılan (kapalı, 22:00–07:00)', () {
      final q = QuietHours.fromMap(null);
      expect(q.enabled, isFalse);
      expect(q.startMin, 22 * 60);
      expect(q.endMin, 7 * 60);
    });

    test('tam map okunur', () {
      final q = QuietHours.fromMap({
        'enabled': true,
        'start_min': 1320,
        'end_min': 360,
      });
      expect(q.enabled, isTrue);
      expect(q.startMin, 1320);
      expect(q.endMin, 360);
    });

    test('eksik alanlar varsayılana, asInt num-olmayan değeri yok sayar', () {
      final q = QuietHours.fromMap({'enabled': true, 'start_min': 'çöp'});
      expect(q.startMin, 22 * 60); // num değil → default
      expect(q.endMin, 7 * 60);
    });

    test('toMap → fromMap round-trip', () {
      const original = QuietHours(enabled: true, startMin: 1290, endMin: 420);
      final round = QuietHours.fromMap(original.toMap());
      expect(round.enabled, original.enabled);
      expect(round.startMin, original.startMin);
      expect(round.endMin, original.endMin);
    });

    test('copyWith yalnız verilen alanı değiştirir', () {
      const q = QuietHours(enabled: false, startMin: 100, endMin: 200);
      final c = q.copyWith(enabled: true);
      expect(c.enabled, isTrue);
      expect(c.startMin, 100);
      expect(c.endMin, 200);
    });

    test('hhmm sıfır dolgulu HH:MM üretir', () {
      expect(QuietHours.hhmm(0), '00:00');
      expect(QuietHours.hhmm(9 * 60 + 5), '09:05');
      expect(QuietHours.hhmm(22 * 60), '22:00');
    });
  });

  group('QuietHours.covers', () {
    test('kapalıyken her zaman false', () {
      const q = QuietHours(enabled: false, startMin: 0, endMin: 600);
      expect(q.covers(DateTime(2026, 6, 18, 5)), isFalse);
    });

    test('sıfır genişlik (start == end) → false', () {
      const q = QuietHours(enabled: true, startMin: 600, endMin: 600);
      expect(q.covers(DateTime(2026, 6, 18, 10)), isFalse);
    });

    test('aynı gün aralığı (start < end): 09:00–17:00', () {
      const q = QuietHours(enabled: true, startMin: 9 * 60, endMin: 17 * 60);
      expect(q.covers(DateTime(2026, 6, 18, 12)), isTrue); // içinde
      expect(q.covers(DateTime(2026, 6, 18, 9)), isTrue); // sınır dahil
      expect(q.covers(DateTime(2026, 6, 18, 17)), isFalse); // bitiş hariç
      expect(q.covers(DateTime(2026, 6, 18, 8, 59)), isFalse);
    });

    test('gece yarısını aşan aralık (start > end): 22:00–07:00', () {
      const q = QuietHours(enabled: true, startMin: 22 * 60, endMin: 7 * 60);
      expect(q.covers(DateTime(2026, 6, 18, 23)), isTrue); // gece
      expect(q.covers(DateTime(2026, 6, 18, 3)), isTrue); // sabah erken
      expect(q.covers(DateTime(2026, 6, 18, 12)), isFalse); // öğlen
      expect(q.covers(DateTime(2026, 6, 18, 7)), isFalse); // bitiş hariç
    });
  });

  group('FeedReminderConfig.fromMap / toMap', () {
    test('null map → varsayılanlar', () {
      final c = FeedReminderConfig.fromMap(null);
      expect(c.enabled, isFalse);
      expect(c.intervalMin, 120);
      expect(c.baseType, 'all');
      expect(c.preMin, 30);
      expect(c.soundEnabled, isFalse);
    });

    test('tam map okunur (sound → soundEnabled)', () {
      final c = FeedReminderConfig.fromMap({
        'enabled': true,
        'interval_min': 180,
        'base_type': 'breast',
        'pre_min': 15,
        'sound': true,
      });
      expect(c.enabled, isTrue);
      expect(c.intervalMin, 180);
      expect(c.baseType, 'breast');
      expect(c.preMin, 15);
      expect(c.soundEnabled, isTrue);
    });

    test('toMap → fromMap round-trip', () {
      const original = FeedReminderConfig(
        enabled: true,
        intervalMin: 240,
        baseType: 'formula',
        preMin: 10,
        soundEnabled: true,
      );
      final round = FeedReminderConfig.fromMap(original.toMap());
      expect(round.enabled, original.enabled);
      expect(round.intervalMin, original.intervalMin);
      expect(round.baseType, original.baseType);
      expect(round.preMin, original.preMin);
      expect(round.soundEnabled, original.soundEnabled);
    });

    test('copyWith tek alan değişimi', () {
      const c = FeedReminderConfig();
      final n = c.copyWith(intervalMin: 90);
      expect(n.intervalMin, 90);
      expect(n.baseType, 'all'); // korunur
      expect(n.enabled, isFalse);
    });
  });

  group('Reminder.fromJson', () {
    test('tam payload okunur', () {
      final r = Reminder.fromJson({
        'id': 5,
        'type': 'custom',
        'schedule': {'repeat': 'daily', 'time': '08:00', 'title': 'D vitamini'},
        'enabled': true,
        'created_at': '2026-06-18T08:00:00Z',
      });
      expect(r.id, 5);
      expect(r.type, 'custom');
      expect(r.schedule['repeat'], 'daily');
      expect(r.schedule['time'], '08:00');
      expect(r.enabled, isTrue);
    });

    test('type yoksa vitamin, schedule yoksa boş, enabled default true', () {
      final r = Reminder.fromJson({'id': 1});
      expect(r.type, 'vitamin');
      expect(r.schedule, isEmpty);
      expect(r.enabled, isTrue);
    });

    test('created_at geçersiz/eksik → now (çökmeden)', () {
      final r = Reminder.fromJson({'id': 1, 'created_at': ''});
      expect(r.createdAt, isNotNull);
    });

    test('once tipi schedule okunur', () {
      final r = Reminder.fromJson({
        'id': 2,
        'type': 'appt',
        'schedule': {'repeat': 'once', 'at': '2026-07-01T14:00:00Z'},
        'enabled': false,
      });
      expect(r.schedule['repeat'], 'once');
      expect(r.enabled, isFalse);
    });
  });
}

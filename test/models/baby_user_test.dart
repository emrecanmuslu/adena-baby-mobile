import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/user.dart';
import 'package:adena_baby/models/membership.dart';
import 'package:adena_baby/models/subscription.dart';
import 'package:adena_baby/models/activity_event.dart';

void main() {
  group('Baby.fromJson', () {
    test('tam payload tüm alanlara ayrıştırılır', () {
      final b = Baby.fromJson({
        'id': 'baby-1',
        'name': 'Adena',
        'gender': 'female',
        'photo': 'https://x/p.jpg',
        'status': 'born',
        'birth_date': '2025-01-15',
        'due_date': '2025-01-20',
        'last_menstrual_date': '2024-04-10',
        'my_role': 'owner',
        'member_count': 3,
      });
      expect(b.id, 'baby-1');
      expect(b.name, 'Adena');
      expect(b.gender, BabyGender.female);
      expect(b.photo, 'https://x/p.jpg');
      expect(b.status, BabyStatus.born);
      expect(b.birthDate, DateTime(2025, 1, 15));
      expect(b.dueDate, DateTime(2025, 1, 20));
      expect(b.lastMenstrualDate, DateTime(2024, 4, 10));
      expect(b.myRole, 'owner');
      expect(b.memberCount, 3);
    });

    test('eksik/null alanlar varsayılanlara düşer', () {
      final b = Baby.fromJson({'id': 'baby-1'});
      expect(b.name, '');
      expect(b.gender, BabyGender.unknown);
      expect(b.photo, isNull);
      expect(b.status, BabyStatus.born); // expecting değilse born
      expect(b.birthDate, isNull);
      expect(b.myRole, isNull);
      expect(b.memberCount, 1);
    });

    test('gender bilinmeyen değer → unknown', () {
      expect(Baby.fromJson({'id': 'x', 'gender': 'attila'}).gender, BabyGender.unknown);
      expect(Baby.fromJson({'id': 'x', 'gender': 'male'}).gender, BabyGender.male);
    });

    test('status expecting algılanır', () {
      final b = Baby.fromJson({'id': 'x', 'status': 'expecting'});
      expect(b.status, BabyStatus.expecting);
      expect(b.isExpecting, isTrue);
    });

    test('boş tarih string → null', () {
      final b = Baby.fromJson({'id': 'x', 'birth_date': ''});
      expect(b.birthDate, isNull);
    });
  });

  group('Baby.toCreateJson', () {
    test('birth_date YYYY-MM-DD gün hassasiyetinde biçimlenir', () {
      final b = Baby(
        id: 'baby-1',
        name: 'Adena',
        status: BabyStatus.born,
        birthDate: DateTime(2025, 1, 5, 14, 30),
      );
      final j = b.toCreateJson();
      expect(j['birth_date'], '2025-01-05'); // saat atılır, sıfır dolgulu
      expect(j['id'], 'baby-1');
      expect(j['status'], 'born');
    });

    test('gender unknown ise alan eklenmez', () {
      final b = Baby(id: 'x', name: 'n', gender: BabyGender.unknown);
      expect(b.toCreateJson().containsKey('gender'), isFalse);
    });

    test('gender bilinirse name olarak eklenir', () {
      final b = Baby(id: 'x', name: 'n', gender: BabyGender.male);
      expect(b.toCreateJson()['gender'], 'male');
    });

    test('null tarihler atlanır', () {
      final b = Baby(id: 'x', name: 'n');
      final j = b.toCreateJson();
      expect(j.containsKey('birth_date'), isFalse);
      expect(j.containsKey('due_date'), isFalse);
      expect(j.containsKey('last_menstrual_date'), isFalse);
    });
  });

  group('Baby computed getters', () {
    test('isShared member_count > 1 olunca true', () {
      expect(Baby(id: 'x', name: 'n', memberCount: 1).isShared, isFalse);
      expect(Baby(id: 'x', name: 'n', memberCount: 2).isShared, isTrue);
    });

    test('canFullWrite: owner/parent/null → true, caregiver → false', () {
      expect(Baby(id: 'x', name: 'n', myRole: 'owner').canFullWrite, isTrue);
      expect(Baby(id: 'x', name: 'n', myRole: 'parent').canFullWrite, isTrue);
      expect(Baby(id: 'x', name: 'n', myRole: null).canFullWrite, isTrue);
      expect(Baby(id: 'x', name: 'n', myRole: 'caregiver').canFullWrite, isFalse);
    });

    test('isCaregiver yalnız caregiver rolünde', () {
      expect(Baby(id: 'x', name: 'n', myRole: 'caregiver').isCaregiver, isTrue);
      expect(Baby(id: 'x', name: 'n', myRole: 'owner').isCaregiver, isFalse);
    });

    test('notifSlot deterministik 0..999 aralığında', () {
      final b = Baby(id: 'baby-determinist', name: 'n');
      final slot = b.notifSlot;
      expect(slot, inInclusiveRange(0, 999));
      expect(b.notifSlot, slot); // aynı id → aynı slot
    });
  });

  group('User serialization', () {
    test('fromJson tüm alanları okur', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'name': 'Ada',
        'avatar_color': '#FF8A7A',
        'created_at': '2026-01-01T08:00:00Z',
      });
      expect(u.id, 'u1');
      expect(u.email, 'a@b.com');
      expect(u.name, 'Ada');
      expect(u.avatarColor, '#FF8A7A');
      expect(u.createdAt, isNotNull);
      expect(u.consentRequired, isFalse); // fromJson default
    });

    test('eksik email/name boş stringe düşer, created_at null', () {
      final u = User.fromJson({'id': 'u1'});
      expect(u.email, '');
      expect(u.name, '');
      expect(u.createdAt, isNull);
      expect(u.avatarColor, isNull);
    });

    test('toJson fromJson round-trip alanları korur', () {
      final original = User(
        id: 'u1',
        email: 'a@b.com',
        name: 'Ada',
        avatarColor: '#FF8A7A',
        createdAt: DateTime.utc(2026, 1, 1, 8),
      );
      final round = User.fromJson(original.toJson());
      expect(round.id, original.id);
      expect(round.email, original.email);
      expect(round.name, original.name);
      expect(round.avatarColor, original.avatarColor);
      expect(round.createdAt!.toUtc(), original.createdAt!.toUtc());
    });

    test('copyWith yalnız consentRequired\'ı değiştirir', () {
      final u = User(id: 'u1', email: 'a@b.com', name: 'Ada');
      final c = u.copyWith(consentRequired: true);
      expect(c.consentRequired, isTrue);
      expect(c.id, u.id);
      expect(c.email, u.email);
      expect(c.name, u.name);
    });

    test('displayName boş ad için e-postanın yerel kısmı', () {
      expect(User(id: 'u', email: 'ada@b.com', name: '').displayName, 'ada');
      expect(User(id: 'u', email: 'ada@b.com', name: '  ').displayName, 'ada');
      expect(User(id: 'u', email: 'ada@b.com', name: 'Ada').displayName, 'Ada');
    });
  });

  group('Membership.fromJson', () {
    test('iç içe user + role + joined_at ayrıştırılır', () {
      final m = Membership.fromJson({
        'user': {'id': 'u1', 'email': 'a@b.com', 'name': 'Ada'},
        'role': 'owner',
        'joined_at': '2026-01-01T08:00:00Z',
      });
      expect(m.user.id, 'u1');
      expect(m.role, 'owner');
      expect(m.isOwner, isTrue);
      expect(m.joinedAt, isNotNull);
    });

    test('role yoksa parent, joined_at yoksa null', () {
      final m = Membership.fromJson({
        'user': {'id': 'u1'},
      });
      expect(m.role, 'parent');
      expect(m.isOwner, isFalse);
      expect(m.joinedAt, isNull);
    });
  });

  group('Subscription.fromJson + getters', () {
    test('premium aktif + bitiş tarihi', () {
      final s = Subscription.fromJson({
        'tier': 'premium',
        'platform': 'android',
        'store': 'play',
        'product_id': 'p1',
        'expires_at': '2030-01-01T00:00:00Z',
        'will_renew': true,
        'is_premium': true,
      });
      expect(s.tier, 'premium');
      expect(s.isPremium, isTrue);
      expect(s.isLifetime, isFalse); // expiresAt var
      expect(s.isLapsed, isFalse);
      expect(s.willRenew, isTrue);
    });

    test('tier yoksa free', () {
      final s = Subscription.fromJson({});
      expect(s.tier, 'free');
      expect(s.isPremium, isFalse);
    });

    test('eski yanıtta is_premium yoksa tier\'a düşer', () {
      final s = Subscription.fromJson({'tier': 'premium'});
      expect(s.isPremium, isTrue); // is_premium yok → tier==premium
    });

    test('isLifetime: premium + expiresAt null', () {
      final s = Subscription(tier: 'premium', isPremium: true);
      expect(s.isLifetime, isTrue);
    });

    test('isLapsed: tier premium ama is_premium false + expiresAt var', () {
      final s = Subscription.fromJson({
        'tier': 'premium',
        'is_premium': false,
        'expires_at': '2020-01-01T00:00:00Z',
      });
      expect(s.isLapsed, isTrue);
    });

    test('graceDaysLeft: expiresAt null → 0', () {
      expect(Subscription(tier: 'free').graceDaysLeft(), 0);
    });

    test('graceDaysLeft: çok eski bitiş → 0 (negatif değil)', () {
      final s = Subscription(
        tier: 'premium',
        expiresAt: DateTime.now().subtract(const Duration(days: 100)),
      );
      expect(s.graceDaysLeft(graceDays: 60), 0);
    });

    test('graceDaysLeft: yeni biten → kalan gün > 0', () {
      final s = Subscription(
        tier: 'premium',
        expiresAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(s.graceDaysLeft(graceDays: 60), inInclusiveRange(49, 50));
    });
  });

  group('ActivityEvent.fromJson', () {
    test('actor Map → User, ts toLocal', () {
      final e = ActivityEvent.fromJson({
        'id': 'e1',
        'actor': {'id': 'u1', 'email': 'a@b.com', 'name': 'Ada'},
        'action': 'created_feed',
        'record_ref': 'rec-1',
        'ts': '2026-06-18T10:00:00Z',
      });
      expect(e.id, 'e1');
      expect(e.actor, isNotNull);
      expect(e.actor!.id, 'u1');
      expect(e.action, 'created_feed');
      expect(e.recordRef, 'rec-1');
      expect(e.ts.isUtc, isFalse);
    });

    test('actor null (SET_NULL) güvenle işlenir', () {
      final e = ActivityEvent.fromJson({
        'id': 'e1',
        'actor': null,
        'action': 'created_diaper',
        'ts': '2026-06-18T10:00:00Z',
      });
      expect(e.actor, isNull);
      expect(e.recordRef, isNull);
    });

    test('ts geçersizse now\'a düşer (çökmeden)', () {
      final e = ActivityEvent.fromJson({
        'id': 'e1',
        'action': 'x',
        'ts': 'çöp',
      });
      expect(e.ts, isNotNull);
      expect(e.action, 'x');
    });
  });
}

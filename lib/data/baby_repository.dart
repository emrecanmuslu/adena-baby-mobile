import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics_service.dart';
import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/baby.dart';
import '../models/membership.dart';
import 'local/app_database.dart';
import 'local_session.dart';

/// Bebek deposu — **local-first**. Bebek telefonda doğar (istemci-üretimli UUID),
/// drift'te birincil tutulur. Premium'da `/babies` ile aynalanır (push dirty +
/// pull list). Free'de hiç ağ çağrısı yok. Üyelik/davet (paylaşım) cloud/premium
/// özellikleridir — REST kalır, yalnız hesaplı/paylaşımlı akışta çağrılır.
class BabyRepository {
  final AppDatabase _db;
  final ApiClient _api;

  BabyRepository(this._db, this._api);

  // ---- Yerel okuma (yalnız aktif hesabın bebekleri) ----

  Stream<List<Baby>> watchAll({String? accountId}) {
    final acct = accountId ?? LocalSession.activeAccountId;
    if (acct == null) return Stream.value(const []);
    final q = _db.select(_db.babies)
      ..where((b) => b.isDeleted.equals(false) & b.accountId.equals(acct))
      ..orderBy([(b) => OrderingTerm.asc(b.name)]);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Buluttan inmiş (dirty=false) en az bir bebek var mı? initialImport sonrası
  /// kullanılır: bulut bu hesabın verisini zaten taşıyorsa free→premium "yükleme
  /// göçü" overlay'i tetiklenmemeli (veri indirildi, yüklenmedi).
  Future<bool> hasCleanBabies() async {
    final acct = LocalSession.activeAccountId;
    if (acct == null) return false;
    final rows = await (_db.select(_db.babies)
          ..where((b) =>
              b.accountId.equals(acct) &
              b.isDeleted.equals(false) &
              b.dirty.equals(false)))
        .get();
    return rows.isNotEmpty;
  }

  Future<List<Baby>> getAll({String? accountId}) async {
    final acct = accountId ?? LocalSession.activeAccountId;
    if (acct == null) return const [];
    final rows = await (_db.select(_db.babies)
          ..where((b) => b.isDeleted.equals(false) & b.accountId.equals(acct))
          ..orderBy([(b) => OrderingTerm.asc(b.name)]))
        .get();
    return rows.map(_toModel).toList();
  }

  // ---- Yerel yazma (offline-first) ----

  Future<Baby> create(Baby baby) async {
    await _db.into(_db.babies).insertOnConflictUpdate(
          BabiesCompanion.insert(
            id: baby.id,
            accountId: Value(LocalSession.activeAccountId),
            name: baby.name,
            gender: Value(baby.gender.name),
            photo: Value(baby.photo),
            status: Value(baby.status.name),
            birthDate: Value(baby.birthDate),
            dueDate: Value(baby.dueDate),
            lastMenstrualDate: Value(baby.lastMenstrualDate),
            gestationalWeeks: Value(baby.gestationalWeeks),
            gestationalDays: Value(baby.gestationalDays),
            myRole: Value(baby.myRole ?? 'owner'),
            memberCount: Value(baby.memberCount),
            clientUpdatedAt: Value(DateTime.now().toUtc()),
            dirty: const Value(true),
          ),
        );
    return (await _byId(baby.id))!;
  }

  /// Alan-bazlı güncelleme (API fields sözlüğüyle uyumlu: name/gender/status/
  /// birth_date/due_date/last_menstrual_date/photo).
  Future<Baby> update(String babyId, Map<String, dynamic> fields) async {
    DateTime? d(dynamic v) =>
        (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;
    final c = BabiesCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      gender: fields.containsKey('gender')
          ? Value(fields['gender'] as String)
          : const Value.absent(),
      status: fields.containsKey('status')
          ? Value(fields['status'] as String)
          : const Value.absent(),
      photo: fields.containsKey('photo')
          ? Value(fields['photo'] as String?)
          : const Value.absent(),
      birthDate: fields.containsKey('birth_date')
          ? Value(d(fields['birth_date']))
          : const Value.absent(),
      dueDate: fields.containsKey('due_date')
          ? Value(d(fields['due_date']))
          : const Value.absent(),
      lastMenstrualDate: fields.containsKey('last_menstrual_date')
          ? Value(d(fields['last_menstrual_date']))
          : const Value.absent(),
      gestationalWeeks: fields.containsKey('gestational_age_weeks')
          ? Value((fields['gestational_age_weeks'] as num?)?.toInt())
          : const Value.absent(),
      gestationalDays: fields.containsKey('gestational_age_days')
          ? Value((fields['gestational_age_days'] as num?)?.toInt() ?? 0)
          : const Value.absent(),
      clientUpdatedAt: Value(DateTime.now().toUtc()),
      dirty: const Value(true),
    );
    await (_db.update(_db.babies)..where((b) => b.id.equals(babyId))).write(c);
    return (await _byId(babyId))!;
  }

  Future<void> delete(String babyId) async {
    await (_db.update(_db.babies)..where((b) => b.id.equals(babyId))).write(
      BabiesCompanion(
        isDeleted: const Value(true),
        dirty: const Value(true),
        clientUpdatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ---- Aile ayarları (yerel JSON; premium'da /babies/{id}/settings) ----

  Future<Map<String, dynamic>> familySettings(String babyId) async {
    final row = await _byIdRow(babyId);
    if (row == null) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(row.settings) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> updateFamilySettings(
      String babyId, Map<String, dynamic> fields) async {
    final current = await familySettings(babyId);
    current.addAll(fields);
    await (_db.update(_db.babies)..where((b) => b.id.equals(babyId))).write(
      BabiesCompanion(
        settings: Value(jsonEncode(current)),
        clientUpdatedAt: Value(DateTime.now().toUtc()),
        dirty: const Value(true),
      ),
    );
    return current;
  }

  // ---- Cloud senkron (premium) ----

  /// Sunucudan bebek listesini çekip yerele yansıtır (premium pull). Erişimi
  /// kaldırılan (sunucuda olmayan) yerel-temiz bebekleri döner (çağıran temizler).
  Future<List<Baby>> pullFromServer() async {
    final acct = LocalSession.activeAccountId;
    if (acct == null) return const [];
    final resp = await _api.dio.get('/babies');
    final data = resp.data as List<dynamic>;
    final fresh =
        data.map((e) => Baby.fromJson(e as Map<String, dynamic>)).toList();
    final freshIds = fresh.map((b) => b.id).toSet();
    // Reconcile yalnız bu hesabın bebekleri içinde.
    final localRows = await (_db.select(_db.babies)
          ..where((b) => b.isDeleted.equals(false) & b.accountId.equals(acct)))
        .get();
    final removed = <Baby>[];
    await _db.transaction(() async {
      for (final b in fresh) {
        await _db.into(_db.babies).insertOnConflictUpdate(
              BabiesCompanion.insert(
                id: b.id,
                accountId: Value(acct),
                name: b.name,
                gender: Value(b.gender.name),
                photo: Value(b.photo),
                status: Value(b.status.name),
                birthDate: Value(b.birthDate),
                dueDate: Value(b.dueDate),
                lastMenstrualDate: Value(b.lastMenstrualDate),
                gestationalWeeks: Value(b.gestationalWeeks),
                gestationalDays: Value(b.gestationalDays),
                myRole: Value(b.myRole),
                memberCount: Value(b.memberCount),
                clientUpdatedAt: const Value.absent(),
                dirty: const Value(false),
              ),
            );
      }
      // Yalnız PAYLAŞILAN (sahibi başkası) bebek otomatik kaldırılır: sunucudan
      // düşüp yerelde temizse erişim kalkmıştır (paylaşımdan çıkarılma / sahibin
      // premium'unun bitmesi). KENDİ (sahip) bebeğim asla pull ile silinmez — pull
      // artık free/lapsed oturumda da koşuyor, local-first gereği sahip verisi korunur
      // (kendi bebeğimin silinmesi yalnız açık delete ile, pushDirty üzerinden olur).
      for (final r in localRows) {
        final shared = r.myRole == 'parent' || r.myRole == 'caregiver';
        if (shared && !freshIds.contains(r.id) && !r.dirty) {
          removed.add(_toModel(r));
          await (_db.delete(_db.babies)..where((b) => b.id.equals(r.id))).go();
        }
      }
    });
    return removed;
  }

  /// free→premium migrasyonunda TAM yükleme garanti et: aktif hesabın tüm
  /// bebeklerini dirty işaretle. Grace sonrası cloud silinmişse (ya da kullanıcı
  /// "buluttan sil" demişse) eski temiz kayıtlar da yeniden yüklensin diye gerekir.
  Future<void> markAllDirty() async {
    final acct = LocalSession.activeAccountId;
    if (acct == null) return;
    // YALNIZ sahip olunan bebekler. Paylaşımlı (myRole='parent'/'caregiver') bebek
    // sahibine ait → üye onu buluta YÜKLEMEZ (POST /babies 403 döner) ve migrasyon
    // overlay'i de göstermez. Yerelde myRole owner/null = sahiplik.
    await (_db.update(_db.babies)
          ..where((b) =>
              b.accountId.equals(acct) &
              (b.myRole.equals('owner') | b.myRole.isNull())))
        .write(const BabiesCompanion(dirty: Value(true)));
  }

  /// Yerel dirty bebekleri sunucuya gönderir (premium push). Migrasyon/edit sonrası.
  /// YALNIZ aktif hesabın SAHİP olduğu bebekler — çoklu yerel hesapta başka hesabın
  /// verisini yüklememek + paylaşımlı (sahibi başkası) bebeği POST'layıp 403 almamak için.
  Future<void> pushDirty() async {
    final acct = LocalSession.activeAccountId;
    if (acct == null) return;
    final dirty = await (_db.select(_db.babies)
          ..where((b) =>
              b.dirty.equals(true) &
              b.accountId.equals(acct) &
              (b.myRole.equals('owner') | b.myRole.isNull())))
        .get();
    for (final r in dirty) {
      try {
        final b = _toModel(r);
        if (r.isDeleted) {
          await _api.dio.delete('/babies/${b.id}');
        } else {
          // İdempotent: id istemci-üretimli → POST upsert. Sunucu 200/201 döner.
          await _api.dio.post('/babies', data: b.toCreateJson());
          final settings = await familySettings(b.id);
          if (settings.isNotEmpty) {
            await _api.dio.patch('/babies/${b.id}/settings', data: settings);
          }
        }
        await (_db.update(_db.babies)..where((x) => x.id.equals(r.id)))
            .write(const BabiesCompanion(dirty: Value(false)));
      } catch (_) {
        // Çevrimdışı/çakışma — yerel korunur, sonra tekrar denenir.
      }
    }
  }

  // ---- Üyelik & davet (cloud/premium — paylaşım) ----

  Future<List<Membership>> members(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/members');
    final data = resp.data as List<dynamic>;
    return data
        .map((e) => Membership.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createInvitation(String babyId,
      {required String role, String? email}) async {
    final resp = await _api.dio.post('/babies/$babyId/invitations', data: {
      'role': role,
      if (email != null && email.isNotEmpty) 'email': email,
    });
    await AnalyticsService.instance.log('family_invite_sent', {'role': role});
    return resp.data as Map<String, dynamic>;
  }

  Future<Baby> acceptInvitation(String code) async {
    final resp = await _api.dio.post('/invitations/accept', data: {'code': code});
    final baby = Baby.fromJson(
        (resp.data as Map<String, dynamic>)['baby'] as Map<String, dynamic>);
    // Paylaşımlı bebeği yerele de yaz (premium akışı; sonraki sync kayıtları çeker).
    await create(baby);
    await (_db.update(_db.babies)..where((b) => b.id.equals(baby.id)))
        .write(const BabiesCompanion(dirty: Value(false)));
    return baby;
  }

  Future<void> updateMemberRole(String babyId, String userId, String role) =>
      _api.dio.patch('/babies/$babyId/members/$userId', data: {'role': role});

  Future<void> removeMember(String babyId, String userId) =>
      _api.dio.delete('/babies/$babyId/members/$userId');

  // ---- iç yardımcılar ----

  Future<BabyRow?> _byIdRow(String id) =>
      (_db.select(_db.babies)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<Baby?> _byId(String id) async {
    final r = await _byIdRow(id);
    return r == null ? null : _toModel(r);
  }

  Baby _toModel(BabyRow r) => Baby(
        id: r.id,
        name: r.name,
        gender: switch (r.gender) {
          'male' => BabyGender.male,
          'female' => BabyGender.female,
          _ => BabyGender.unknown,
        },
        photo: r.photo,
        status: r.status == 'expecting' ? BabyStatus.expecting : BabyStatus.born,
        birthDate: r.birthDate,
        dueDate: r.dueDate,
        lastMenstrualDate: r.lastMenstrualDate,
        gestationalWeeks: r.gestationalWeeks,
        gestationalDays: r.gestationalDays,
        myRole: r.myRole,
        memberCount: r.memberCount,
      );
}

final babyRepositoryProvider = Provider<BabyRepository>(
  (ref) => BabyRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
  ),
);

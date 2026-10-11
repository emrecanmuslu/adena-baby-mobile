import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/analytics_service.dart';
import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/baby.dart';
import '../models/membership.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'sync_merge.dart';

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

  /// Bakıcı (caregiver) bebek profilini/ayarını YAZAMAZ (backend PATCH 403 döner;
  /// pushDirty rol filtresi göndermez). Yerelde dirty üretilirse K2 sonrası pull
  /// da ezmediğinden satır sonsuza dek ayrışırdı (BULGULAR.md O20, karar K-7).
  /// UI `canFullWrite` ile zaten kilitler; bu son savunma hattıdır.
  Future<void> _requireFullWrite(String babyId) async {
    final row = await _byIdRow(babyId);
    if (row?.myRole == 'caregiver') {
      throw StateError('caregiver_readonly: $babyId');
    }
  }

  /// Alan-bazlı güncelleme (API fields sözlüğüyle uyumlu: name/gender/status/
  /// birth_date/due_date/last_menstrual_date/photo).
  Future<Baby> update(String babyId, Map<String, dynamic> fields) async {
    await _requireFullWrite(babyId);
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

  /// Bebek fotoğrafını seçilen (image_picker geçici) yoldan kalıcı uygulama
  /// dizinine kopyalar ve `photo` alanına yerel yol olarak yazar (dirty=true).
  /// Bir sonraki `pushDirty` bunu bulutta varsa multipart yükler.
  Future<Baby> updatePhoto(String babyId, String pickedPath) async {
    await _requireFullWrite(babyId);
    final stored = await _persistPhoto(babyId, pickedPath);
    await (_db.update(_db.babies)..where((b) => b.id.equals(babyId))).write(
      BabiesCompanion(
        photo: Value(stored),
        clientUpdatedAt: Value(DateTime.now().toUtc()),
        dirty: const Value(true),
      ),
    );
    return (await _byId(babyId))!;
  }

  /// Foto'yu kalıcı uygulama dizinine kopyalar, kalıcı yolu döner. Dosya adı
  /// HER güncellemede benzersiz üretilir (babyId+zaman damgası): sabit bir ad
  /// (yalnız babyId+ext) yeniden kullanılsaydı, Flutter'ın ImageCache'i
  /// FileImage'ı yalnızca YOLA göre anahtarladığından (mtime'a bakmadan)
  /// dosya içeriği değişse bile eski baytları göstermeye devam ediyordu —
  /// ikinci kez foto değiştirildiğinde ekranda hiç güncellenmiyormuş gibi
  /// görünüyordu. Yol her seferinde farklı olunca bu önbellek sorunu kökten
  /// ortadan kalkıyor. Eski dosya artık gereksiz — silinir.
  Future<String> _persistPhoto(String babyId, String srcPath) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final babiesDir = Directory(p.join(dir.path, 'babies'));
      if (!await babiesDir.exists()) await babiesDir.create(recursive: true);
      final ext = p.extension(srcPath);
      final dest = p.join(
          babiesDir.path, '$babyId-${DateTime.now().microsecondsSinceEpoch}$ext');
      await File(srcPath).copy(dest);
      final oldPhoto = (await _byIdRow(babyId))?.photo;
      if (oldPhoto != null && oldPhoto != dest && !oldPhoto.startsWith('http')) {
        try {
          final oldFile = File(oldPhoto);
          if (await oldFile.exists()) await oldFile.delete();
        } catch (_) {}
      }
      return dest;
    } catch (_) {
      return srcPath; // kopyalanamazsa orijinal (geçici) yolu kullan
    }
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

  /// O4/R6: aile ayarı bebek profilinden AYRI bayrak (`settingsDirty`) taşır;
  /// profil `dirty` açılmaz (profil push'u ayar PATCH'i içermez). Değişen alan
  /// `settingsBase` (sunucunun son onayladığı JSON) ile diff'lenir (K-5).
  Future<Map<String, dynamic>> updateFamilySettings(
      String babyId, Map<String, dynamic> fields) async {
    await _requireFullWrite(babyId);
    final current = await familySettings(babyId);
    current.addAll(fields);
    await (_db.update(_db.babies)..where((b) => b.id.equals(babyId))).write(
      BabiesCompanion(
        settings: Value(jsonEncode(current)),
        settingsDirty: const Value(true),
      ),
    );
    return current;
  }

  // ---- Aile ayarı senkronu (O4; TASARIM-SENKRON.md §5C) ----

  static Map<String, dynamic> _decodeMap(String? json) {
    if (json == null) return <String, dynamic>{};
    try {
      final v = jsonDecode(json);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Anahtar sırası bağımsız kanonik JSON (sunucu/yerel sözlük eşitliği için).
  static String _canon(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canon(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(_canon).join(',')}]';
    return jsonEncode(v);
  }

  /// Yerelde değişmiş üst-düzey anahtarlar (K-5): `local[k] != base[k]`.
  /// `base` yoksa (ilk kez / migration) yerelde olan her anahtar değişmiş sayılır.
  static List<String> changedSettingsKeys(
      Map<String, dynamic> local, Map<String, dynamic>? base) {
    return [
      for (final k in local.keys)
        if (base == null || _canon(local[k]) != _canon(base[k])) k
    ];
  }

  /// `settingsDirty` bebeklerin ayarını PATCH'ler — YALNIZ değişen anahtarlar
  /// (K-5). Rol filtresi `pushDirty` ile aynı (owner/null + parent; caregiver
  /// asla). 2xx → yerel = base = sunucu yanıtı, `settingsDirty=false` (R5: PATCH
  /// sırasında yerel yeniden değiştiyse dirty kalır, yalnız base güncellenir).
  /// Kalıcı 4xx → `pushError` (R3); geçici → dirty kalır, sessiz.
  Future<void> pushSettings({String? accountId, bool includeOwned = true}) async {
    final acct = accountId ?? LocalSession.activeAccountId;
    if (acct == null) return;
    final ownerCond = _db.babies.myRole.equals('owner') | _db.babies.myRole.isNull();
    final roleCond = includeOwned
        ? (ownerCond | _db.babies.myRole.equals('parent'))
        : _db.babies.myRole.equals('parent');
    final rows = await (_db.select(_db.babies)
          ..where((b) =>
              b.settingsDirty.equals(true) &
              b.isDeleted.equals(false) &
              b.accountId.equals(acct) &
              roleCond))
        .get();
    for (final r in rows) {
      final local = _decodeMap(r.settings);
      final base = r.settingsBase == null ? null : _decodeMap(r.settingsBase);
      final changed = changedSettingsKeys(local, base);
      if (changed.isEmpty) {
        await (_db.update(_db.babies)..where((x) => x.id.equals(r.id)))
            .write(const BabiesCompanion(settingsDirty: Value(false)));
        continue;
      }
      try {
        final resp = await _api.dio.patch('/babies/${r.id}/settings',
            data: {for (final k in changed) k: local[k]});
        final server = resp.data is Map
            ? Map<String, dynamic>.from(resp.data as Map)
            : local;
        final cur = await _byIdRow(r.id);
        final unchangedMeanwhile = cur != null && cur.settings == r.settings;
        await (_db.update(_db.babies)..where((x) => x.id.equals(r.id))).write(
          BabiesCompanion(
            settingsBase: Value(jsonEncode(server)),
            settings: unchangedMeanwhile
                ? Value(jsonEncode(server))
                : const Value.absent(),
            settingsDirty: Value(!unchangedMeanwhile),
            pushError: const Value(null),
          ),
        );
      } on DioException catch (e) {
        if (classifyDioError(e) == PushFailure.permanent) {
          await (_db.update(_db.babies)..where((x) => x.id.equals(r.id))).write(
              BabiesCompanion(pushError: Value('HTTP ${e.response?.statusCode}')));
        }
        // geçici (ağ/5xx/401/403) → settingsDirty kalır, sonraki tur.
      } catch (_) {}
    }
  }

  /// `GET /babies/{id}/settings` → yerele uygular (O4). Çağıran YALNIZ bulut
  /// senkronlu bebekler için çağırmalı (free sahibin yerel ayarını sunucu
  /// varsayılanı ezmesin). Temiz satır: yerel = base = sunucu. `settingsDirty`
  /// satır: yalnız DEĞİŞMEMİŞ anahtarlar (`local[k] == base[k]`) sunucudan
  /// güncellenir, değişmişler korunur (R1); base = sunucu. Yalnız 200 + Map.
  /// Döner: yerel ayar değişti mi.
  Future<bool> pullSettings(String babyId) async {
    final r = await _byIdRow(babyId);
    if (r == null || r.isDeleted) return false;
    final Map<String, dynamic> server;
    try {
      final resp = await _api.dio.get('/babies/$babyId/settings');
      if (resp.statusCode != 200 || resp.data is! Map) return false;
      server = Map<String, dynamic>.from(resp.data as Map);
    } catch (_) {
      return false;
    }
    final local = _decodeMap(r.settings);
    Map<String, dynamic> next;
    if (!r.settingsDirty) {
      next = server;
    } else {
      final base = r.settingsBase == null ? null : _decodeMap(r.settingsBase);
      final changed = changedSettingsKeys(local, base).toSet();
      next = Map<String, dynamic>.from(server);
      for (final k in changed) {
        next[k] = local[k]; // yerel değişiklik korunur
      }
    }
    final changedLocally = _canon(next) != _canon(local);
    await (_db.update(_db.babies)..where((x) => x.id.equals(babyId))).write(
      BabiesCompanion(
        settings: changedLocally ? Value(jsonEncode(next)) : const Value.absent(),
        settingsBase: Value(jsonEncode(server)),
      ),
    );
    return changedLocally;
  }

  // ---- Cloud senkron (premium) ----

  /// Sunucudan bebek listesini çekip yerele yansıtır (premium pull). Erişimi
  /// kaldırılan (sunucuda olmayan) yerel-temiz bebekleri döner (çağıran temizler).
  ///
  /// [accountId] verilmezse statik `LocalSession.activeAccountId`'e düşer.
  /// KRİTİK: login/logout geçişinde bu statik `_postLogin()` içinde asenkron
  /// set edilir; `activeAccountIdProvider`'ı izleyen reaktif çağıranlar (ör.
  /// BabyController._pull) statik henüz güncellenmeden tetiklenebilir ve acct
  /// null gelip pull'u sessizce boş listeyle sonuçlandırabilir (bebek "kayıp"
  /// görünüp onboarding'e atar). Böyle çağıranlar reaktif değeri BURADA açıkça
  /// geçirmeli.
  Future<List<Baby>> pullFromServer({String? accountId}) async {
    final acct = accountId ?? LocalSession.activeAccountId;
    if (acct == null) return const [];
    final resp = await _api.dio.get('/babies');
    final data = resp.data as List<dynamic>;
    final fresh =
        data.map((e) => Baby.fromJson(e as Map<String, dynamic>)).toList();
    final freshIds = fresh.map((b) => b.id).toSet();
    // Reconcile yalnız bu hesabın bebekleri içinde. Tombstone'lar da okunur:
    // bekleyen silme (R2) sunucu kopyasıyla geri getirilmemeli.
    final allLocal = await (_db.select(_db.babies)
          ..where((b) => b.accountId.equals(acct)))
        .get();
    final localById = {for (final r in allLocal) r.id: r};
    final localRows = allLocal.where((r) => !r.isDeleted).toList();
    // K2-3b: listeden düşen paylaşılan temiz bebekler silinmeden ÖNCE erişimin
    // gerçekten kalktığı doğrulanır (ağ çağrısı transaction DIŞINDA, sıralı;
    // her aday kendi try/catch'inde → biri düşse diğerleri etkilenmez).
    final confirmedGone = <String>{};
    for (final r in localRows) {
      final shared = r.myRole == 'parent' || r.myRole == 'caregiver';
      if (shared && !freshIds.contains(r.id) && !r.dirty) {
        if (await _accessRevoked(r.id)) confirmedGone.add(r.id);
      }
    }
    final removed = <Baby>[];
    await _db.transaction(() async {
      for (final b in fresh) {
        // R1/R2 (TASARIM-SENKRON.md, K2): push'u henüz başarmamış dirty satır
        // (düzenleme, yüklenmemiş yerel foto) ve bekleyen tombstone sunucu
        // kopyasıyla EZİLMEZ; bir sonraki push LWW'ye bırakır.
        final l = localById[b.id];
        // Bebek-repo'ya özel istisna (sync_merge rol bilmez): caregiver satırında
        // dirty anlamsızdır — bu rol yazamaz, push göndermez; K2 öncesinden kalmış
        // yetim dirty düzenleme ancak sunucu kopyasıyla düzelir (O20, şemasız).
        final caregiverRow = l?.myRole == 'caregiver';
        final decision = caregiverRow
            ? MergeDecision.apply
            : decideServerRow(
                localExists: l != null,
                localDirty: l?.dirty ?? false,
                localDeleted: l?.isDeleted ?? false,
              );
        if (decision != MergeDecision.apply) continue;
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
      // Yalnız erişimi 403/404 ile DOĞRULANMIŞ adaylar silinir; 200 ile gelen
      // eksik/boş liste ya da ağ hatası, üyenin gönderilmemiş child verisini
      // (purge) kaybettirmesin (TASARIM-SENKRON.md R4 bebek listesi istisnası).
      for (final r in localRows) {
        if (confirmedGone.contains(r.id)) {
          removed.add(_toModel(r));
          await (_db.delete(_db.babies)..where((b) => b.id.equals(r.id))).go();
        }
      }
    });
    return removed;
  }

  /// Paylaşılan bebeğe erişim gerçekten kalktı mı? `GET /babies/{id}`:
  /// 403/404 → evet (üyelikten çıkarıldı / bebek silindi). 200 → hayır (liste
  /// geçici tutarsızdı). Ağ hatası / 5xx / timeout → BİLİNMİYOR → hayır (silme).
  Future<bool> _accessRevoked(String babyId) async {
    try {
      await _api.dio.get('/babies/$babyId');
      return false;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      return code == 403 || code == 404;
    } catch (_) {
      return false;
    }
  }

  /// free→premium migrasyonunda TAM yükleme garanti et: aktif hesabın tüm
  /// bebeklerini dirty işaretle. Grace sonrası cloud silinmişse (ya da kullanıcı
  /// "buluttan sil" demişse) eski temiz kayıtlar da yeniden yüklensin diye gerekir.
  Future<void> markAllDirty({String? accountId}) async {
    final acct = accountId ?? LocalSession.activeAccountId;
    if (acct == null) return;
    // YALNIZ sahip olunan bebekler. Paylaşımlı (myRole='parent'/'caregiver') bebek
    // sahibine ait → üye onu buluta YÜKLEMEZ (POST /babies 403 döner) ve migrasyon
    // overlay'i de göstermez. Yerelde myRole owner/null = sahiplik.
    await (_db.update(_db.babies)
          ..where((b) =>
              b.accountId.equals(acct) &
              (b.myRole.equals('owner') | b.myRole.isNull())))
        .write(const BabiesCompanion(dirty: Value(true)));
    // Dolu yerel ayar da ilk yüklemede gitsin (O4; pushSettings tam sözlük
    // PATCH'ler çünkü base yok).
    await (_db.update(_db.babies)
          ..where((b) =>
              b.accountId.equals(acct) &
              (b.myRole.equals('owner') | b.myRole.isNull()) &
              b.settings.equals('{}').not()))
        .write(const BabiesCompanion(settingsDirty: Value(true)));
  }

  /// Yerel dirty bebekleri sunucuya gönderir (premium push). Migrasyon/edit sonrası.
  /// Aktif hesabın SAHİP olduğu bebekler + paylaşımlı (myRole='parent') bebekler —
  /// üye tam-yazma yetkiliyse (owner/parent, backend FULL_WRITE_ROLES) profil/foto
  /// değişikliğini de göndermeli, yoksa üye tarafında yapılan değişiklik (ör. foto)
  /// hiç buluta çıkmaz ve bir sonraki pull'da sessizce yerelden silinir.
  /// [includeOwned] false ise yalnız paylaşımlı (parent) bebekler gönderilir — kendi
  /// premium'u olmayan üye kendi SAHİP olduğu bebeği buluta yüklemez (ücretsiz katman
  /// yerel-önce kalır), ama paylaşılan bebek sahibin premium'una bağlı olduğundan
  /// bağımsız senkronlanır.
  Future<void> pushDirty({String? accountId, bool includeOwned = true}) async {
    final acct = accountId ?? LocalSession.activeAccountId;
    if (acct == null) return;
    final ownerCond = _db.babies.myRole.equals('owner') | _db.babies.myRole.isNull();
    final roleCond =
        includeOwned ? (ownerCond | _db.babies.myRole.equals('parent')) : _db.babies.myRole.equals('parent');
    final dirty = await (_db.select(_db.babies)
          ..where((b) => b.dirty.equals(true) & b.accountId.equals(acct) & roleCond))
        .get();
    for (final r in dirty) {
      try {
        final b = _toModel(r);
        final isOwner = r.myRole == null || r.myRole == 'owner';
        if (r.isDeleted) {
          // Yalnız sahip silebilir (backend 403 döner değilse) — üyenin "ayrılma"sı
          // ayrı bir akıştır (removeMember), buradan sunucuya silme gönderilmez.
          if (!isOwner) continue;
          try {
            await _api.dio.delete('/babies/${b.id}');
          } on DioException catch (e) {
            // I7: 404 = sunucuda zaten yok → başarı (anı/anne/adet ile tutarlı;
            // aksi hâlde pushError='HTTP 404' + "Silme gönderilemedi" banner'ı).
            if (e.response?.statusCode != 404) rethrow;
          }
          // J9 (R5): DELETE uçuştayken satır canlandırıldıysa (yeniden oluşturma /
          // K-1 geri al) ya da damgası değiştiyse dirty temizlenmez → sonraki tur
          // güncel hâli gönderir; yalnız pushError silinir.
          final cur = await _byIdRow(r.id);
          if (cur == null) continue; // bu arada purge edilmiş
          if (!(cur.isDeleted && cur.clientUpdatedAt == r.clientUpdatedAt)) {
            await (_db.update(_db.babies)..where((x) => x.id.equals(r.id)))
                .write(const BabiesCompanion(pushError: Value(null)));
            continue;
          }
        } else {
          // `photo` yerel bir dosya yoluysa (henüz yüklenmemiş) multipart ekle;
          // zaten sunucu URL'i (http) ise partial=True update'te dokunmadan
          // bırakılsın diye gövdeye HİÇ eklenmez (yeniden yüklenmez).
          final needsPhotoUpload =
              b.photo != null && !b.photo!.startsWith('http');
          final json = b.toCreateJson();
          final body = needsPhotoUpload
              ? FormData.fromMap({
                  for (final e in json.entries) e.key: '${e.value}',
                  'photo': await MultipartFile.fromFile(b.photo!),
                })
              : json;
          // Sahip: id istemci-üretimli → POST idempotent upsert (200/201).
          // Paylaşımlı üye (parent): POST her zaman 403 döner (sahiplik başkasına
          // ait) — PATCH /babies/{id} kullanılmalı (backend owner+parent'a izin verir).
          final resp = isOwner
              ? await _api.dio.post('/babies', data: body)
              : await _api.dio.patch('/babies/${b.id}', data: body);
          // Aile ayarı artık ayrı bayrakla, ayrı turda gider (pushSettings, O4/R6).
          // R5 / I2: POST sürerken (özellikle multipart foto) kullanıcı yeniden
          // düzenlemiş olabilir → satırın GÖNDERİLEN hâliyle aynı olduğu
          // doğrulanmadan dirty temizlenmez, foto URL'i yeni yerel yolu ezmez.
          final cur = await _byIdRow(r.id);
          final unchanged = cur != null && _samePushedState(cur, r);
          if (needsPhotoUpload && unchanged) {
            // Sunucudan dönen imzalı foto URL'ini yerele yaz (yeniden yüklenmesin).
            final srvPhoto = (resp.data as Map<String, dynamic>)['photo'] as String?;
            if (srvPhoto != null) {
              await (_db.update(_db.babies)..where((x) => x.id.equals(r.id)))
                  .write(BabiesCompanion(photo: Value(srvPhoto)));
            }
          }
          if (!unchanged) {
            // Uçuş içi düzenleme/silme → dirty kalır, bir sonraki tur gönderir.
            await (_db.update(_db.babies)..where((x) => x.id.equals(r.id)))
                .write(const BabiesCompanion(pushError: Value(null)));
            continue;
          }
        }
        await (_db.update(_db.babies)..where((x) => x.id.equals(r.id)))
            .write(const BabiesCompanion(dirty: Value(false), pushError: Value(null)));
      } on DioException catch (e) {
        // R3: yerel değişiklik her durumda KORUNUR (dirty kalır). Kalıcı red
        // (4xx; sunucu bunu hiç kabul etmeyecek) `pushError` kolonuna yazılır
        // (K-1: banner + "geri al"); sessizce sonsuza dek yeniden denenmez.
        if (classifyDioError(e) == PushFailure.permanent) {
          final code = e.response?.statusCode;
          await (_db.update(_db.babies)..where((x) => x.id.equals(r.id)))
              .write(BabiesCompanion(pushError: Value('HTTP $code')));
          debugPrint('[baby-push] kalıcı red ${r.id}: HTTP $code ${e.response?.data}');
        }
      } catch (_) {
        // Beklenmeyen (ör. dosya okunamadı) — yerel korunur, sonra tekrar denenir.
      }
    }
  }

  /// R5 (I2): satır, push'a verilen anlık görüntüyle aynı mı? Damga drift'te
  /// saniye çözünürlüklü → aynı saniyedeki düzenlemeyi kaçırmamak için
  /// gönderilen alanlar da karşılaştırılır (records D3 deseni).
  static bool _samePushedState(BabyRow cur, BabyRow sent) =>
      cur.clientUpdatedAt == sent.clientUpdatedAt &&
      cur.isDeleted == sent.isDeleted &&
      cur.name == sent.name &&
      cur.gender == sent.gender &&
      cur.photo == sent.photo &&
      cur.status == sent.status &&
      cur.birthDate == sent.birthDate &&
      cur.dueDate == sent.dueDate &&
      cur.lastMenstrualDate == sent.lastMenstrualDate &&
      cur.gestationalWeeks == sent.gestationalWeeks &&
      cur.gestationalDays == sent.gestationalDays;

  /// K-1 "geri al": `GET /babies/{id}` → 200: sunucu profili uygulanır
  /// (ayar JSON'u dokunulmaz; dirty=false, pushError=null, tombstone kalkar).
  /// 403/404: sunucuda yok → `notOnServer`. Diğer → `failed`.
  Future<RevertResult> revertToServer(String babyId) async {
    final Map<String, dynamic> data;
    try {
      final resp = await _api.dio.get('/babies/$babyId');
      if (resp.statusCode != 200 || resp.data is! Map) return RevertResult.failed;
      data = Map<String, dynamic>.from(resp.data as Map);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return RevertResult.notOnServer;
      return RevertResult.failed;
    } catch (_) {
      return RevertResult.failed;
    }
    final b = Baby.fromJson(data);
    await (_db.update(_db.babies)..where((x) => x.id.equals(babyId))).write(
      BabiesCompanion(
        name: Value(b.name),
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
        isDeleted: const Value(false),
        dirty: const Value(false),
        pushError: const Value(null),
      ),
    );
    return RevertResult.applied;
  }

  /// Sunucuda olmayan sahip bebeği SİLMEZ (yerel veri korunur, KARAR-BEKLEYEN):
  /// bayraklar temizlenir, satır yalnız bu cihazda kalır. Tombstone (bekleyen
  /// silme) + sunucuda yok → satır kaldırılır (çocuk verisi çağıranın işi).
  Future<void> keepLocalOnly(String babyId) async {
    final r = await _byIdRow(babyId);
    if (r == null) return;
    if (r.isDeleted) {
      await (_db.delete(_db.babies)..where((x) => x.id.equals(babyId))).go();
      return;
    }
    await (_db.update(_db.babies)..where((x) => x.id.equals(babyId))).write(
        const BabiesCompanion(dirty: Value(false), pushError: Value(null)));
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

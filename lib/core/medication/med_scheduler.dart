import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/medication_plan.dart';
import '../../models/record.dart';
import '../i18n.dart';
import '../medication.dart';
import '../notification_service.dart';
import '../widget_service.dart';

/// İlaç v2 bildirim planlayıcısı (ILAC-TASARIM §3) — TÜM bebekler için tek,
/// serileştirilmiş yeniden kurma:
///
/// 1. [planMedNotifications] (SAF): planlar + kayıtlar + tercihler → istenen
///    tek seferlik bildirimler (doz ana hatırlatması, K4 +30 dk "işaretlenmedi",
///    S12 kür bitiş günü 20:00, pencere sonu "uygulamayı aç") + çözülmüş doz
///    anahtarları. Pencere: Android 7 gün; iOS en çok [kIosMedBudget] bildirim.
/// 2. [MedicationScheduler.rebuild]: kalıcı KAYIT DEFTERİ (anahtar → id, an,
///    içerik karması) ile fark: değişmeyene DOKUNMAZ (M8 — ekrandaki bildirim
///    silinmez); değişen aynı id ile yeniden kurulur; artık istenmeyen bekleyen
///    iptal edilir; doz ÇÖZÜLDÜYSE ekrandaki "İlaç zamanı" da kaldırılır.
/// 3. Defter iOS'ta App Group'a aynalanır → NSE (uygulama kapalıyken) doz
///    olayında ilgili id'leri iptal eder / geri ekler (A6).

const kMedWindow = Duration(days: 7);
const kIosMedBudget = 40;
const kAndroidMedBudget = 300;
const kMedMissedDelay = Duration(minutes: 30);

/// Bildirim türü (anahtarın son parçası).
abstract final class MedNotifKind {
  static const main = 'm';
  static const missed = 'x';
  static const courseEnd = 'c';
  static const windowEnd = 'w';
}

/// Bir bebeğin planlayıcı girdisi.
class MedSchedBaby {
  final String id;
  final String name;
  final bool expecting;
  final List<MedicationPlan> plans;
  final List<Record> records; // en az dün + bugün (+ erken işaretlenmiş gelecek dozlar)
  /// W2: bu bebeğin son BAŞARILI kayıt senkronunun (başlangıç) anı; yoksa null.
  final DateTime? recordsSyncedAt;
  const MedSchedBaby({
    required this.id,
    required this.name,
    this.expecting = false,
    required this.plans,
    required this.records,
    this.recordsSyncedAt,
  });
}

class MedSchedInput {
  final List<MedSchedBaby> babies;
  /// "İlaç hatırlatmaları" (cihaz-yerel, varsayılan AÇIK).
  final bool enabled;
  /// K4 "Kaçırılan doz hatırlatması (30 dk sonra)" (varsayılan AÇIK).
  final bool missedOn;
  const MedSchedInput({required this.babies, this.enabled = true, this.missedOn = true});
}

typedef MedSchedLoader = Future<MedSchedInput> Function();

/// İstenen tek bildirim.
class MedNotifSpec {
  final String key; // planUuid|date|time|kind
  final String babyId;
  final String planUuid;
  final DateTime fireAt;
  final String title;
  final String body;
  const MedNotifSpec(this.key, this.babyId, this.planUuid, this.fireAt, this.title, this.body);
}

class MedPlanResult {
  final Map<String, MedNotifSpec> desired;
  /// Penceredeki çözülmüş dozların ana/K4 anahtarları (ekrandaysa kaldırılır).
  final Set<String> resolvedKeys;
  const MedPlanResult(this.desired, this.resolvedKeys);
}

String _ymd(DateTime d) => medDateToWire(d)!;

/// SAF planlama. [ios] → bütçe [kIosMedBudget], aksi [kAndroidMedBudget].
MedPlanResult planMedNotifications(MedSchedInput input, DateTime now, {required bool ios}) {
  final resolved = <String>{};
  if (!input.enabled) return MedPlanResult(const {}, resolved);
  final end = now.add(kMedWindow);
  final budget = ios ? kIosMedBudget : kAndroidMedBudget;
  final cands = <MedNotifSpec>[];
  var beyond = false; // pencere/bütçe dışında kalan doz var mı (pencere sonu uyarısı)
  final courseEnds = <MedNotifSpec>[];

  for (final b in input.babies) {
    if (b.expecting) continue;
    final prefix = b.name.isNotEmpty ? '${b.name} · ' : '';
    final plans = [
      for (final p in b.plans)
        if (!p.isPrn && !p.isCompletedAt(now)) p
    ];
    if (plans.isEmpty) continue;
    final doses = resolveDoses(plans, b.records,
        from: now.subtract(const Duration(days: 1)), to: end.add(const Duration(days: 1)), now: now);
    for (final d in doses) {
      // V2: uuid'siz plan (henüz kimlik atanmamış) yerel anahtarla kurulur.
      final pk = medPlanKey(d.plan);
      final base = '$pk|${_ymd(d.doseDate)}|${d.time}';
      if (d.isResolved) {
        resolved
          ..add('$base|${MedNotifKind.main}')
          ..add('$base|${MedNotifKind.missed}');
        continue;
      }
      final body = d.plan.dose.trim().isNotEmpty ? d.plan.dose.trim() : tr('İlaç zamanı');
      if (d.dueAt.isAfter(now)) {
        if (d.dueAt.isAfter(end)) {
          beyond = true;
        } else {
          cands.add(MedNotifSpec('$base|${MedNotifKind.main}', b.id, pk, d.dueAt,
              '$prefix${trp('{name} · {t}', {'name': d.plan.name, 't': d.time})}', body));
        }
      }
      final missedAt = d.dueAt.add(kMedMissedDelay);
      if (input.missedOn && missedAt.isAfter(now) && !missedAt.isAfter(end)) {
        cands.add(MedNotifSpec(
            '$base|${MedNotifKind.missed}',
            b.id,
            pk,
            missedAt,
            '$prefix${trp('{name} {t} dozu işaretlenmedi', {'name': d.plan.name, 't': d.time})}',
            tr('Verildiyse uygulamadan işaretle.')));
      }
    }
    // S12: kür bitiş günü 20:00 (cihaz başına tek).
    for (final p in plans) {
      final e = p.endDate;
      if (e == null) continue;
      final at = DateTime(e.year, e.month, e.day, 20);
      if (!at.isAfter(now) || at.isAfter(end)) continue;
      courseEnds.add(MedNotifSpec('${medPlanKey(p)}|${_ymd(e)}|20:00|${MedNotifKind.courseEnd}', b.id,
          medPlanKey(p), at, '$prefix${trp('{name} · kür bugün bitiyor', {'name': p.name})}',
          tr('Son dozları işaretlemeyi unutma.')));
    }
  }

  cands.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  final desired = <String, MedNotifSpec>{};
  final room = budget - 1 - courseEnds.length; // 1 = pencere sonu
  for (final c in cands) {
    if (desired.length >= room) {
      beyond = true;
      break;
    }
    desired[c.key] = c;
  }
  for (final c in courseEnds) {
    desired[c.key] = c;
  }
  if (beyond) {
    DateTime? last;
    for (final c in desired.values) {
      if (!c.key.endsWith('|${MedNotifKind.main}')) continue;
      if (last == null || c.fireAt.isAfter(last)) last = c.fireAt;
    }
    final at = last?.subtract(const Duration(hours: 2));
    if (at != null && at.isAfter(now)) {
      desired['window|${MedNotifKind.windowEnd}'] = MedNotifSpec(
          'window|${MedNotifKind.windowEnd}', '', '', at,
          tr('İlaç hatırlatmaları duracak'), tr("Hatırlatmaların devam etmesi için Adena'yı aç."));
    }
  }
  return MedPlanResult(desired, resolved);
}

/// Defter girdisi. V6 — Dart ve iOS NSE AYNI modeli kullanır: doz olayıyla
/// iptal edilen bildirimin girdisi defterde KALIR ([canceled] işaretli, App
/// Group aynasında da); "geri alındı"da NSE id/an/içerikten geri ekler,
/// yeniden kurma canlılık (bekleyen mi) kontrolüyle doğru kurar.
class _Entry {
  final int id;
  final int at; // ms
  final String hash;
  final String plan;
  final String baby;
  final String title;
  final String body;
  final bool canceled;
  const _Entry(this.id, this.at, this.hash, this.plan, this.baby, this.title, this.body,
      {this.canceled = false});

  _Entry asCanceled() => _Entry(id, at, hash, plan, baby, title, body, canceled: true);

  Map<String, dynamic> toJson() => {
        'id': id, 'at': at, 'h': hash, 'p': plan, 'b': baby, 't': title, 'y': body,
        if (canceled) 'c': true,
      };
  static _Entry fromJson(Map<String, dynamic> j) => _Entry(j['id'] as int, j['at'] as int,
      j['h'] as String? ?? '', j['p'] as String? ?? '', j['b'] as String? ?? '',
      j['t'] as String? ?? '', j['y'] as String? ?? '',
      canceled: j['c'] == true);
}

/// W7 (ILAC-INCELEME-3): planlayıcının kalıcı anahtar-değer deposu. Üretimde
/// SharedPreferences (isolate başına ÖNBELLEKLİ — [reload] diskten tazeler);
/// testte iki isolate ayrı önbellekle simüle edilir.
abstract class MedKv {
  Future<void> reload();
  String? getString(String key);
  Future<void> setString(String key, String value);
  int? getInt(String key);
  Future<void> setInt(String key, int value);
  List<String>? getStringList(String key);
  Future<void> setStringList(String key, List<String> value);
  bool? getBool(String key);
  Future<void> setBool(String key, bool value);
  Future<void> remove(String key);
}

class _PrefsKv implements MedKv {
  _PrefsKv(this._p);
  final SharedPreferences _p;
  @override
  Future<void> reload() async {
    try {
      await _p.reload();
    } catch (_) {}
  }

  @override
  String? getString(String key) => _p.getString(key);
  @override
  Future<void> setString(String key, String value) => _p.setString(key, value);
  @override
  int? getInt(String key) => _p.getInt(key);
  @override
  Future<void> setInt(String key, int value) => _p.setInt(key, value);
  @override
  List<String>? getStringList(String key) => _p.getStringList(key);
  @override
  Future<void> setStringList(String key, List<String> value) => _p.setStringList(key, value);
  @override
  bool? getBool(String key) => _p.getBool(key);
  @override
  Future<void> setBool(String key, bool value) => _p.setBool(key, value);
  @override
  Future<void> remove(String key) => _p.remove(key);
}

/// Planlayıcı. [instance] üretimde [NotificationService.instance] ile çalışır;
/// testler [MedicationScheduler.forTest] ile sahte servis/saat/platform verir.
class MedicationScheduler {
  MedicationScheduler._(this._svc, this._now, this._ios, this._mirror, this._groupRead,
      this._groupWrite, this._kv);

  static MedicationScheduler instance = MedicationScheduler._(NotificationService.instance,
      DateTime.now, Platform.isIOS, _defaultMirror, WidgetService.readGroupString,
      WidgetService.writeGroupString, _defaultKv);

  static Future<MedKv> _defaultKv() async => _PrefsKv(await _prefs());

  @visibleForTesting
  static MedicationScheduler forTest(NotificationService svc,
          {DateTime Function()? now,
          bool ios = false,
          Future<void> Function(String)? mirror,
          Future<String?> Function(String key)? groupRead,
          Future<void> Function(String key, String? value)? groupWrite,
          Future<MedKv> Function()? kv}) =>
      MedicationScheduler._(svc, now ?? DateTime.now, ios, mirror ?? (_) async {},
          groupRead ?? (_) async => null, groupWrite ?? (_, _) async {}, kv ?? _defaultKv);

  /// iOS App Group aynası (NSE okur) — `WidgetService` ile aynı kanal; Android'de
  /// no-op. Ön plan ve arka plan isolate'ında aynı.
  static Future<void> _defaultMirror(String json) => WidgetService.saveMedRegistry(json);

  final NotificationService _svc;
  final DateTime Function() _now;
  final bool _ios;
  final Future<void> Function(String json) _mirror;
  /// App Group (iOS NSE ile paylaşılan) metin anahtarları; Android'de null / no-op.
  final Future<String?> Function(String key) _groupRead;
  final Future<void> Function(String key, String? value) _groupWrite;
  /// Her iş TAZE (reload edilmiş) depoyla başlar (V5).
  final Future<MedKv> Function() _kv;

  /// W2 (ILAC-INCELEME-3): NSE'nin "verildi/atlandı" ile iptal ettiği defter
  /// anahtarları → iptal anı (ms). NSE yazar, "geri alındı"da siler; Dart her işin
  /// başında okuyup yerel defterde iptal işaretler ve pencere dışına çıkanları
  /// temizler. Anahtar adı `NotificationService.swift` ile BİREBİR.
  static const kNseCanceled = 'med_nse_canceled';

  /// W8 (ILAC-INCELEME-3): force-quit'te `access_removed`'ı yalnız NSE işlerse
  /// App Group'a yazdığı bebek id'leri (JSON dizi). Dart yeniden kurmada [kRevoked]
  /// ile birleştirir; [clearRevoked] siler. Anahtar adı Swift ile BİREBİR.
  static const kNseRevoked = 'med_revoked_babies';

  static String _syncKey(String babyId) => 'med_rec_synced_$babyId';

  /// W2: kayıt senkronu bu bebek için BAŞARIYLA bitti; [startedAt] = isteğin
  /// başladığı an (uçuştaki NSE iptali "senkrondan sonra" sayılmasın diye).
  static Future<void> markRecordsSynced(String babyId, DateTime startedAt) async {
    try {
      final p = await _prefs();
      await p.setInt(_syncKey(babyId), startedAt.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// W2: [markRecordsSynced] ile yazılan an (başka isolate'ınki dahil, taze okunur).
  static Future<DateTime?> recordsSyncedAt(String babyId) async {
    try {
      final ms = (await _prefs()).getInt(_syncKey(babyId));
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> _readNse() async {
    try {
      final raw = await _groupRead(kNseCanceled);
      if (raw == null || raw.isEmpty) return {};
      final m = jsonDecode(raw) as Map;
      return {
        for (final e in m.entries)
          if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt()
      };
    } catch (_) {
      return {};
    }
  }

  /// NSE iptallerini yerel deftere işler (iptal işareti). Değiştiyse true.
  static bool _absorbNse(Map<String, _Entry> reg, Map<String, int> nse) {
    var changed = false;
    for (final k in nse.keys) {
      final e = reg[k];
      if (e != null && !e.canceled) {
        reg[k] = e.asCanceled();
        changed = true;
      }
    }
    return changed;
  }

  /// [drop] anahtarlarını App Group'tan siler — TAZE okunan kümeden (bu arada
  /// NSE'nin eklediği anahtar kaybolmasın).
  Future<void> _pruneNse(Set<String> drop) async {
    if (drop.isEmpty) return;
    try {
      final fresh = await _readNse();
      final before = fresh.length;
      fresh.removeWhere((k, _) => drop.contains(k));
      if (fresh.length == before) return;
      await _groupWrite(kNseCanceled, fresh.isEmpty ? null : jsonEncode(fresh));
    } catch (_) {}
  }

  static const kRegistry = 'med_notif_registry_v2';
  static const kNextId = 'med_notif_next_id';
  static const kLegacyCleaned = 'med_notif_legacy_cleaned_v1';
  /// V5: `access_removed` alınan bebekler — yerel veri ön planda temizlenene
  /// (ya da bebek listesi başarıyla tazelenene) dek ilaç bildirimi kurulmaz.
  static const kRevoked = 'med_notif_revoked_babies';

  Future<void> _chain = Future.value();

  /// V5: SharedPreferences isolate başına önbelleklidir; ön plan, FCM bg ve
  /// workmanager isolate'ları birbirinin yazdığını görmez. Her iş diskten
  /// TAZE okuyarak başlar.
  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    try {
      await p.reload();
    } catch (_) {}
    return p;
  }

  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _chain.then((_) => f());
    _chain = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<Map<String, _Entry>> _load(MedKv p) async {
    try {
      final raw = p.getString(kRegistry);
      if (raw == null) return {};
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return {for (final e in m.entries) e.key: _Entry.fromJson((e.value as Map).cast())};
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(MedKv p, Map<String, _Entry> reg) async {
    final json = jsonEncode({for (final e in reg.entries) e.key: e.value.toJson()});
    await p.setString(kRegistry, json);
    try {
      await _mirror(json);
    } catch (_) {}
  }

  int _alloc(MedKv p, Set<int> used) {
    var n = p.getInt(kNextId) ?? NotificationService.medIdLo;
    final span = NotificationService.medIdHi - NotificationService.medIdLo;
    for (var i = 0; i < span; i++) {
      if (n < NotificationService.medIdLo || n >= NotificationService.medIdHi) {
        n = NotificationService.medIdLo;
      }
      if (!used.contains(n)) {
        p.setInt(kNextId, n + 1);
        return n;
      }
      n++;
    }
    return NotificationService.medIdLo; // pratikte erişilmez (100 000 slot)
  }

  /// Yeniden kurma. [load] DB'den TAZE girdi okur; fırlatırsa hiçbir şey
  /// değişmez (yanlış iptal yok). Serileştirilir: sıra gelince güncel durum okunur.
  Future<void> rebuild(MedSchedLoader load, {String reason = ''}) => _serial(() async {
        final MedSchedInput input;
        try {
          input = await load();
        } catch (e) {
          debugPrint('[med-sched] girdi okunamadı ($reason): $e');
          return;
        }
        final p = await _kv();
        await _cleanLegacy(p, input);
        final now = _now();
        final revoked = (p.getStringList(kRevoked) ?? const <String>[]).toSet();
        // W8: NSE'nin işlediği access_removed'lar da (Dart defteri habersiz).
        final nseRevoked = await _readNseRevoked();
        if (!revoked.containsAll(nseRevoked)) {
          revoked.addAll(nseRevoked);
          await p.setStringList(kRevoked, revoked.toList());
        }
        final plan = planMedNotifications(
            revoked.isEmpty
                ? input
                : MedSchedInput(
                    babies: [for (final b in input.babies) if (!revoked.contains(b.id)) b],
                    enabled: input.enabled,
                    missedOn: input.missedOn),
            now,
            ios: _ios);
        final reg = await _load(p);
        final nse = await _readNse();
        _absorbNse(reg, nse);
        final synced = {
          for (final b in input.babies) b.id: b.recordsSyncedAt?.millisecondsSinceEpoch
        };
        final nseUndone = <String>{};
        final mode = await _svc.medScheduleMode();
        final pending =
            await _svc.pendingIdsIn(NotificationService.medIdLo, NotificationService.medIdHi);
        final next = <String, _Entry>{};
        final used = {for (final e in reg.values) e.id};

        // Artık istenmeyenler.
        for (final e in reg.entries) {
          if (plan.desired.containsKey(e.key)) continue;
          final shown = e.value.at <= now.millisecondsSinceEpoch;
          final resolved = plan.resolvedKeys.contains(e.key);
          final inWindow = now.millisecondsSinceEpoch - e.value.at < kMedOpenWindow.inMilliseconds;
          if (resolved) {
            // W1 (ILAC-INCELEME-3): çözülmüş doz (bekleyen + ekrandaki) iptal; girdi
            // an + 12 sa geçene dek iptal İŞARETLİ kalır — "geri alındı"yı yalnız
            // NSE işlese de (force-quit) id/an/içerikten geri ekleyebilsin.
            if (!e.value.canceled || pending == null || pending.contains(e.value.id)) {
              await _svc.cancelId(e.value.id);
            }
            if (inWindow) {
              next[e.key] = e.value.canceled ? e.value : e.value.asCanceled();
              continue;
            }
          } else if (!shown) {
            await _svc.cancelId(e.value.id);
          } else if (now.millisecondsSinceEpoch - e.value.at <
              kMedOpenWindow.inMilliseconds) {
            // V10: gösterilmiş ve çözülmemiş — doz penceresi (12 sa) boyunca
            // defterde KALIR (ekrandakine dokunulmaz, M8); doz sonradan çözülürse
            // (yerel / push cancelDose / NSE) ekrandaki de kaldırılabilsin.
            next[e.key] = e.value;
            continue;
          }
          used.remove(e.value.id);
        }
        // W7 (ILAC-INCELEME-3): id ayırmadan ÖNCE taze oku — başka isolate'ın bu
        // arada kaydettiği id'ler ve sayaç; bekleyen id'ler de kullanılmaz.
        await p.reload();
        used
          ..addAll({for (final e in (await _load(p)).values) e.id})
          ..addAll(pending ?? const <int>{});
        // İstenenler.
        for (final d in plan.desired.values) {
          final hash = '${d.title}|${d.body}|$mode';
          final old = reg[d.key];
          final at = d.fireAt.millisecondsSinceEpoch;
          final alive = pending == null
              ? old?.canceled != true
              : (old != null && pending.contains(old.id));
          if (old != null && old.at == at && old.hash == hash && alive) {
            // Bekliyor (NSE "geri alındı"da geri eklemiş olabilir) → iptal işareti düşer.
            next[d.key] = old.canceled
                ? _Entry(old.id, old.at, old.hash, old.plan, old.baby, old.title, old.body)
                : old;
            continue;
          }
          // W2: NSE "verildi" ile iptal etti, bekleyen değil. Kayıt senkronu bunu
          // izleyen bir anda doz hâlâ açık demiyorsa (senkron yok / NSE iptalinden
          // önce) "verildi" henüz yerele gelmemiş say → yeniden KURMA.
          final nseAt = nse[d.key];
          if (old != null && nseAt != null && !alive) {
            final s = synced[d.babyId];
            if (s == null || s <= nseAt) {
              next[d.key] = old.canceled ? old : old.asCanceled();
              continue;
            }
            nseUndone.add(d.key); // senkron sonrası hâlâ açık → geri alınmış
          }
          final id = old?.id ?? _alloc(p, used);
          used.add(id);
          await _svc.scheduleMedOnce(
              id: id, when: d.fireAt, title: d.title, body: d.body, payload: 'med:${d.key}');
          next[d.key] = _Entry(id, at, hash, d.planUuid, d.babyId, d.title, d.body);
        }
        // W7: kaydetmeden önce TAZE defterle birleştir — bu tur sırasında başka
        // isolate'ın eklediği (bu turun başında defterde olmayan, bu turun da
        // dokunmadığı) anahtarlar korunur; aynı anahtarda bu turun sonucu geçerli.
        await p.reload();
        final fresh = await _load(p);
        final mine = {for (final e in next.values) e.id};
        final dupOf = <int>{}; // başka isolate'ın AYNI doz için ayırdığı ikinci id
        for (final e in fresh.entries) {
          if (reg.containsKey(e.key) || mine.contains(e.value.id)) continue;
          if (next.containsKey(e.key)) {
            dupOf.add(e.value.id);
          } else {
            next[e.key] = e.value;
          }
        }
        // Yetim: bekleyen ama hiçbir defterde olmayan. W7: yalnız bu turun BAŞINDA
        // zaten bekleyen id'ler (ya da aynı dozun ikinci id'si, V5) — tur sırasında
        // başka isolate'ın kurup henüz kaydetmediği id'lere dokunulmaz.
        final after = pending == null
            ? null
            : await _svc.pendingIdsIn(NotificationService.medIdLo, NotificationService.medIdHi);
        if (after != null) {
          final known = {for (final e in next.values) e.id};
          for (final id in after) {
            if (known.contains(id)) continue;
            if (pending!.contains(id) || dupOf.contains(id)) await _svc.cancelId(id);
          }
        }
        await _save(p, next);
        // W2: artık defterde olmayan / penceresi geçmiş / geri alınmış NSE anahtarları.
        final nowMs = now.millisecondsSinceEpoch;
        await _pruneNse({
          for (final k in nse.keys)
            if (nseUndone.contains(k) ||
                next[k] == null ||
                nowMs - next[k]!.at >= kMedOpenWindow.inMilliseconds)
              k
        });
      });

  /// Push/NSE eşleniği: dozun ([planUuid] + [date] + [time]) ana ve K4
  /// bildirimlerini HEMEN iptal eder (ekrandaki dahil) — ağsız, DB'siz.
  /// V6: girdi defterden SİLİNMEZ, iptal işaretlenir (NSE ile aynı model) —
  /// ardından gelen "geri alındı"yı yalnız NSE işlese de geri ekleyebilsin.
  Future<void> cancelDose(String planUuid, String date, String time) => _serial(() async {
        final p = await _kv();
        final reg = await _load(p);
        var changed = _absorbNse(reg, await _readNse());
        final base = '$planUuid|$date|$time';
        for (final k in ['$base|${MedNotifKind.main}', '$base|${MedNotifKind.missed}']) {
          final e = reg[k];
          if (e != null) {
            await _svc.cancelId(e.id);
            reg[k] = e.asCanceled();
            changed = true;
          }
        }
        if (changed) await _save(p, reg);
      });

  /// Bebek silindi / erişim kalktı: o bebeğin TÜM ilaç bildirimleri.
  /// [revoke] (V5, `access_removed`): yerel veri henüz temizlenmediği için
  /// sonraki yeniden kurmalar (bg turu) bu bebeği [clearRevoked]'a dek atlar.
  Future<void> cancelBaby(String babyId, {bool revoke = false}) => _serial(() async {
        final p = await _kv();
        if (revoke) {
          await p.setStringList(
              kRevoked, {...?p.getStringList(kRevoked), babyId}.toList());
        }
        final reg = await _load(p);
        final absorbed = _absorbNse(reg, await _readNse());
        final drop = [for (final e in reg.entries) if (e.value.baby == babyId) e.key];
        for (final k in drop) {
          await _svc.cancelId(reg.remove(k)!.id);
        }
        // Bebeğe ait olmayan "pencere sonu" uyarısı: başka bebeğin ilaç
        // bildirimi kalmadıysa o da gitsin (yanıltıcı "duracak" uyarısı olmasın).
        const w = 'window|${MedNotifKind.windowEnd}';
        if (reg.containsKey(w) && !reg.values.any((e) => e.baby.isNotEmpty)) {
          await _svc.cancelId(reg.remove(w)!.id);
          drop.add(w);
        }
        if (drop.isNotEmpty || absorbed) await _save(p, reg);
      });

  /// Çıkış: defteri temizler (bildirimleri `NotificationService.cancelAll` siler).
  Future<void> clearRegistry() => _serial(() async {
        final p = await _kv();
        await p.remove(kRevoked);
        await _save(p, {});
        try {
          await _groupWrite(kNseCanceled, null);
          await _groupWrite(kNseRevoked, null);
        } catch (_) {}
      });

  /// V5: ön plan bebek listesini sunucudan BAŞARIYLA tazeledi — erişimi gerçekten
  /// kalkan bebek yerelden temizlendi, kalan (yeniden davet) bebek yine kurulur.
  Future<void> clearRevoked() => _serial(() async {
        final p = await _kv();
        await p.remove(kRevoked);
        try {
          await _groupWrite(kNseRevoked, null);
        } catch (_) {}
      });

  Future<Set<String>> _readNseRevoked() async {
    try {
      final raw = await _groupRead(kNseRevoked);
      if (raw == null || raw.isEmpty) return {};
      return {for (final x in jsonDecode(raw) as List) if (x is String && x.isNotEmpty) x};
    } catch (_) {
      return {};
    }
  }

  /// Eski günlük-tekrar id'leri (670000–679999) — bir kez. V4: bekleyen listeye
  /// BAĞLI DEĞİL — yerel planların eski şemadaki id'leri (`670000 +
  /// (planId % 1000) * 10 + i`, i < 10) doğrudan iptal edilir; liste
  /// okunabiliyorsa aralıktaki diğer bekleyenler de.
  Future<void> _cleanLegacy(MedKv p, MedSchedInput input) async {
    if (p.getBool(kLegacyCleaned) == true) return;
    final ids = <int>{
      for (final b in input.babies)
        for (final plan in b.plans)
          for (var i = 0; i < 10; i++)
            NotificationService.legacyMedLo + (plan.id % 1000) * 10 + i,
      ...?await _svc.pendingIdsIn(NotificationService.legacyMedLo, NotificationService.legacyMedHi),
    };
    for (final id in ids) {
      await _svc.cancelId(id);
    }
    await p.setBool(kLegacyCleaned, true);
  }
}

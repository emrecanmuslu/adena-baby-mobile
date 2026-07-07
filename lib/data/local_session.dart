import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/analytics_service.dart';
import 'local_prefs.dart';

/// Local-first kimlik & rıza deposu (hesapsız çalışma için).
///
/// Free kullanıcı hesap açmadan başlar: ilk açılışta yerel bir `localUserId`
/// (UUID) üretilir — yerel kayıtların `createdBy`'si ve rıza öznesi olur. KVKK
/// rıza + 18+ yaş kapısı hesaptan bağımsız, yerelde alınır. Premium/aile/topluluk
/// isteyince gerçek hesap açılır; o anda yerel rıza sunucuya da yazılır.
class LocalSession {
  static const _kUserId = 'local_user_id';
  static const _kConsent = 'local_consent_v1'; // KVKK + Şartlar + 18+ yerel onayı
  static const _kAnalyticsConsent = 'local_analytics_consent_v1'; // opsiyonel kullanım analitiği rızası (varsayılan KAPALI)
  static const _kImportedAccts = 'cloud_imported_accounts_v1'; // göçü yapılmış hesaplar (CSV)
  static const _kPremiumSynced = 'premium_synced_accounts_v1'; // tam buluta yükleme yapılmış hesaplar (CSV)
  static const _kPurgeHandled = 'purge_handled_v1'; // hesap → işlenen son cloud_purged_at (acct=iso;...)
  static const _kName = 'local_user_name'; // ebeveyn adı (hesapsız profil)
  static const _kCachedUser = 'cached_auth_user_v1'; // son başarılı /auth/me (offline açılış için)
  static const _kGuest = 'guest_mode_v1'; // "kayıt olmadan devam et" — hesapsız yerel oturum açık mı
  static const _kGuestMigResolved = 'guest_migration_resolved_v1'; // misafir→hesap "aktaralım mı?" sorusu bu misafir turunda yanıtlandı mı
  static const _kCycleFirst = 'cycle_first_entry_v1'; // "bebeğim yok — sadece adet/gebelik takibi" ile girildi mi (Flo-tarzı bebeksiz dal)

  /// Açılışta okunup belleğe alınan değerler (senkron erişim için).
  static String? _userId;
  static bool? _consent;
  static bool? _analyticsConsent;
  static String? _name;
  static bool? _guest; // "kayıt olmadan devam et" oturumu açık mı (kalıcı)
  static bool? _guestMigResolved; // misafir→hesap göç sorusu yanıtlandı mı
  static bool? _cycleFirst; // bebeksiz adet/gebelik dalı seçildi mi (kalıcı)
  static String? _activeAccountId; // o an oturum açık hesap (yerel izolasyon anahtarı)
  static Set<String> _importedAccounts = {}; // cloud→local göçü yapılmış hesaplar
  static Set<String> _premiumSyncedAccounts = {}; // free→premium tam yüklemesi yapılmış hesaplar
  static Map<String, String> _purgeHandled = {}; // hesap → işlenen son cloud_purged_at (iso)

  /// main()'de bir kez çağrılır; localUserId + rıza durumunu belleğe yükler,
  /// localUserId yoksa üretip kalıcılaştırır.
  ///
  /// Depo: SharedPreferences (eskiden Keychain). Soğuk başlatmada Keychain takılıp
  /// uygulamayı koyu splash'te donduruyordu → taşındı. Eski Keychain değerleri
  /// [LocalPrefs.migrateString] ile tek seferlik göç eder. KRİTİK: localUserId
  /// Keychain'den OKUNAMAZSA (hata/timeout) YENİ UUID ÜRETİLMEZ — mevcut kullanıcının
  /// yerel verisi yetim kalmasın; bir sonraki açılış göçü yeniden dener.
  static Future<void> ensureLoaded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final (existingId, idFailed) =
          await LocalPrefs.migrateString(prefs, _kUserId);
      if (existingId != null && existingId.isNotEmpty) {
        _userId = existingId;
      } else if (!idFailed) {
        // Keychain temiz okundu + değer gerçekten yok → yeni kullanıcı → üret+kalıcılaştır.
        final id = const Uuid().v4();
        await prefs.setString(_kUserId, id);
        _userId = id;
      } else {
        // Keychain okunamadı → ÜRETME (yetim veri riski). Bu açılış geçici boş.
        _userId = null;
      }
      final (consent, _) = await LocalPrefs.migrateString(prefs, _kConsent);
      _consent = consent == '1';
      final (ac, _) = await LocalPrefs.migrateString(prefs, _kAnalyticsConsent);
      _analyticsConsent = ac == '1';
      final (nm, _) = await LocalPrefs.migrateString(prefs, _kName);
      _name = nm ?? '';
      final (g, _) = await LocalPrefs.migrateString(prefs, _kGuest);
      _guest = g == '1';
      final (gmr, _) = await LocalPrefs.migrateString(prefs, _kGuestMigResolved);
      _guestMigResolved = gmr == '1';
      final (cf, _) = await LocalPrefs.migrateString(prefs, _kCycleFirst);
      _cycleFirst = cf == '1';
      // Misafir oturumu açıksa + gerçek oturum yoksa: yerel veri kapsamını
      // localUserId'ye bağla (repo'lar bunu account anahtarı gibi kullanır).
      // Gerçek oturum varsa AuthController.build bunu kendi user.id'siyle ezer.
      if (_guest == true && (_userId ?? '').isNotEmpty) {
        _activeAccountId = _userId;
      }
      final (csv, _) = await LocalPrefs.migrateString(prefs, _kImportedAccts);
      _importedAccounts =
          (csv ?? '').split(',').where((s) => s.isNotEmpty).toSet();
      final (psv, _) = await LocalPrefs.migrateString(prefs, _kPremiumSynced);
      _premiumSyncedAccounts =
          (psv ?? '').split(',').where((s) => s.isNotEmpty).toSet();
      final (ph, _) = await LocalPrefs.migrateString(prefs, _kPurgeHandled);
      _purgeHandled = {
        for (final p in (ph ?? '').split(';').where((s) => s.contains('=')))
          p.substring(0, p.indexOf('=')): p.substring(p.indexOf('=') + 1)
      };
    } catch (_) {
      // prefs bile açılamadı (çok nadir): localUserId'yi UYDURMA (yetim riski),
      // rıza/ad güvenli varsayılanlar. Sonraki açılış yeniden dener.
      _consent ??= false;
      _analyticsConsent ??= false;
      _name ??= '';
      _guest ??= false;
      _guestMigResolved ??= false;
      _cycleFirst ??= false;
    }
  }

  static String get userId => _userId ?? '';
  static bool get consent => _consent ?? false;

  /// Opsiyonel kullanım analitiği rızası (varsayılan KAPALI). Yalnız kullanıcı
  /// açıkça onaylarsa Firebase Analytics toplama açılır ([[acik-riza-yas-kapisi]]).
  static bool get analyticsConsent => _analyticsConsent ?? false;

  /// O an oturum açık hesabın id'si (yerel izolasyon anahtarı). null = oturum yok.
  static String? get activeAccountId => _activeAccountId;
  static void setActiveAccount(String? id) => _activeAccountId = id;

  /// "Kayıt olmadan devam et" oturumu açık mı (kalıcı; hesapsız yerel kullanım).
  static bool get guest => _guest ?? false;

  /// Misafir oturumunu başlatır: bayrağı kalıcılaştırır + yerel veri kapsamını
  /// localUserId'ye bağlar. localUserId henüz yoksa (Keychain hatası) kapsam
  /// bağlanmaz; sonraki açılış göçü yeniden dener.
  static Future<void> enterGuest() async {
    _guest = true;
    // Misafir yerel veri kapsamı localUserId'ye bağlı. ensureLoaded, secure-storage
    // okuma hatasında userId'yi ÜRETMEMİŞ olabilir (yetim-koruma guard'ı) → boş kalırsa
    // misafir bebekleri account_id=null ile yazılıp GÖRÜNMEZ olur ve onboarding donar.
    // Misafire GİRERKEN userId yoksa burada üret+kalıcılaştır (prefs artık kanonik depo).
    if ((_userId ?? '').isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final id = const Uuid().v4();
        await prefs.setString(_kUserId, id);
        _userId = id;
      } catch (_) {}
    }
    if ((_userId ?? '').isNotEmpty) _activeAccountId = _userId;
    // Yeni misafir turu → göç sorusu yeniden sorulabilsin (önceki tur "Hayır"
    // demiş olabilir; bu turda yeni veri için tekrar sorulmalı).
    _guestMigResolved = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGuest, '1');
      await prefs.remove(_kGuestMigResolved);
    } catch (_) {}
  }

  /// "Bebeğim yok — adet & gebelik takibi" dalıyla mı girildi (Flo-tarzı bebeksiz
  /// kullanım). true → router bebek zorunluluğunu esnetip doğrudan Adet Takvimi'ni
  /// açar; bebek eklenince yine tam uygulama kullanılır (bayrak yalnız bebek yokken
  /// dikkate alınır).
  static bool get cycleFirst => _cycleFirst ?? false;

  static Future<void> setCycleFirst(bool v) async {
    _cycleFirst = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (v) {
        await prefs.setString(_kCycleFirst, '1');
      } else {
        await prefs.remove(_kCycleFirst);
      }
    } catch (_) {}
  }

  /// Misafir→hesap göç sorusu ("kayıtlarını aktaralım mı?") bu turda yanıtlandı mı.
  /// true → login sonrası bir daha sorma. enterGuest'te sıfırlanır.
  static bool get guestMigrationResolved => _guestMigResolved ?? false;

  static Future<void> setGuestMigrationResolved(bool v) async {
    _guestMigResolved = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGuestMigResolved, v ? '1' : '0');
    } catch (_) {}
  }

  /// Misafir oturumunu kapatır (gerçek giriş/kayıt yapılınca çağrılır). Yerel
  /// veri kapsamını KAPATMAZ — çağıran (AuthController) gerçek hesap id'sini set eder.
  static Future<void> exitGuest() async {
    _guest = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kGuest);
    } catch (_) {}
  }

  /// Bu hesabın sunucu verisi yerele bir kez indirildi mi?
  static bool importedForAccount(String accountId) =>
      _importedAccounts.contains(accountId);

  /// Bu hesabın yereli buluta bir kez TAM yüklendi mi (free→premium göçü tamam)?
  /// false → bir sonraki cloudSync açılışında tam yükleme (markAllDirty) + overlay.
  /// Lapse'te temizlenir (cloud silinecek → yeniden abone olunca tam yükleme gerekir).
  static bool premiumSyncedForAccount(String accountId) =>
      _premiumSyncedAccounts.contains(accountId);

  /// Ebeveynin adı (yerel profil). Boş → henüz girilmedi.
  static String get name => _name ?? '';

  static Future<void> acceptConsent() async {
    _consent = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kConsent, '1');
    } catch (_) {}
  }

  /// Opsiyonel analitik rızasını ayarlar (onboarding checkbox / ayarlar toggle).
  static Future<void> setAnalyticsConsent(bool granted) async {
    _analyticsConsent = granted;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAnalyticsConsent, granted ? '1' : '0');
    } catch (_) {}
  }

  static Future<void> setName(String name) async {
    _name = name.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kName, _name ?? '');
    } catch (_) {}
  }

  static Future<void> markImportedForAccount(String accountId) async {
    _importedAccounts.add(accountId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kImportedAccts, _importedAccounts.join(','));
    } catch (_) {}
  }

  /// free→premium tam yüklemesi tamamlandı işaretle (bir daha overlay gösterme).
  static Future<void> markPremiumSyncedForAccount(String accountId) async {
    _premiumSyncedAccounts.add(accountId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPremiumSynced, _premiumSyncedAccounts.join(','));
    } catch (_) {}
  }

  /// Cloud purge sonrası tam yeniden-yükleme için çağrılır: bu hesabın "senkronlu"
  /// durumunu kaldır → yeniden premium olunca tam yükleme (markAllDirty) yeniden yapılır.
  static Future<void> clearPremiumSyncedForAccount(String accountId) async {
    if (!_premiumSyncedAccounts.remove(accountId)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPremiumSynced, _premiumSyncedAccounts.join(','));
    } catch (_) {}
  }

  /// Bu hesap için en son İŞLENEN cloud_purged_at damgası (null → hiç işlenmedi).
  /// subscription_repository bununla "cloud son tam yüklememizden sonra silindi mi"
  /// kararını verir → yalnız gerçek purge'te tam yeniden-yükleme tetiklenir.
  static DateTime? lastPurgeHandled(String accountId) {
    final v = _purgeHandled[accountId];
    return v == null ? null : DateTime.tryParse(v);
  }

  static Future<void> setPurgeHandled(String accountId, DateTime stamp) async {
    _purgeHandled[accountId] = stamp.toUtc().toIso8601String();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kPurgeHandled,
          _purgeHandled.entries.map((e) => '${e.key}=${e.value}').join(';'));
    } catch (_) {}
  }

  /// Son başarılı `/auth/me` kullanıcısını (JSON) önbelleğe alır. Soğuk açılışta
  /// internet/sunucu yokken kullanıcıyı login'e atmadan oturumu sürdürmek için.
  /// SharedPreferences kullanılır (Keychain soğuk-başlatma kilidi yaşamasın).
  static Future<void> cacheAuthUser(Map<String, dynamic> json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedUser, jsonEncode(json));
    } catch (_) {}
  }

  /// Önbellekteki son kullanıcı (yoksa null). Offline açılışta build() kullanır.
  static Future<Map<String, dynamic>?> cachedAuthUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_kCachedUser);
      if (s == null || s.isEmpty) return null;
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Çıkış/hesap silme/gerçek auth reddinde önbelleği temizler.
  static Future<void> clearCachedAuthUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCachedUser);
    } catch (_) {}
  }

  /// "Yerel verileri sil" sonrası: ebeveyn adı + göç bayraklarını temizler
  /// (rıza + localUserId korunur). Kullanıcı tekrar baştan başlar.
  static Future<void> clearLocalProfile() async {
    _name = '';
    _importedAccounts = {};
    _premiumSyncedAccounts = {};
    _purgeHandled = {};
    _cycleFirst = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kName);
      await prefs.remove(_kImportedAccts);
      await prefs.remove(_kPremiumSynced);
      await prefs.remove(_kPurgeHandled);
      await prefs.remove(_kCycleFirst);
    } catch (_) {}
  }
}

/// Yerel kullanıcı kimliği (createdBy). main()'de gerçek değerle override edilir.
final localUserIdProvider = Provider<String>((_) => LocalSession.userId);

/// "Kayıt olmadan devam et" oturumu — router bunu izler (misafir yolunu açar).
/// enter() misafiri başlatır, exit() gerçek giriş/kayıtta kapatır.
class GuestModeController extends Notifier<bool> {
  @override
  bool build() => LocalSession.guest;

  Future<void> enter() async {
    await LocalSession.enterGuest();
    // enterGuest userId'yi yeni üretmiş olabilir → localUserIdProvider'ın stale ''
    // cache'ini tazele (createdBy vb. doğru id'yi alsın).
    ref.invalidate(localUserIdProvider);
    state = true;
  }

  Future<void> exit() async {
    await LocalSession.exitGuest();
    state = false;
  }
}

final guestModeProvider =
    NotifierProvider<GuestModeController, bool>(GuestModeController.new);

/// "Bebeğim yok — adet & gebelik takibi" bebeksiz dalı — router bunu izler
/// (bebek zorunluluğunu esnetip doğrudan /cycle'ı açar). set(true) onboarding'de
/// kullanıcı bu seçeneği seçince çağrılır.
class CycleFirstController extends Notifier<bool> {
  @override
  bool build() => LocalSession.cycleFirst;

  Future<void> set(bool v) async {
    await LocalSession.setCycleFirst(v);
    state = v;
  }
}

final cycleFirstProvider =
    NotifierProvider<CycleFirstController, bool>(CycleFirstController.new);

/// Yerel rıza durumu — router bunu izler (kabul edilince kapıdan çıkar).
class LocalConsentController extends Notifier<bool> {
  @override
  bool build() => LocalSession.consent;

  Future<void> accept() async {
    await LocalSession.acceptConsent();
    state = true;
  }
}

final localConsentProvider =
    NotifierProvider<LocalConsentController, bool>(LocalConsentController.new);

/// Opsiyonel analitik rızası — onboarding checkbox + ayarlar toggle bunu bağlar.
/// Değişince AnalyticsService.instance.setConsent ile toplama açılır/kapanır.
class LocalAnalyticsConsentController extends Notifier<bool> {
  @override
  bool build() => LocalSession.analyticsConsent;

  Future<void> set(bool granted) async {
    await AnalyticsService.instance.setConsent(granted);
    state = LocalSession.analyticsConsent;
  }
}

final localAnalyticsConsentProvider =
    NotifierProvider<LocalAnalyticsConsentController, bool>(
        LocalAnalyticsConsentController.new);

/// Ebeveyn adı (hesapsız profil) — router bunu izler (girilince ad kapısından çıkar).
class LocalNameController extends Notifier<String> {
  @override
  String build() => LocalSession.name;

  Future<void> set(String name) async {
    await LocalSession.setName(name);
    state = LocalSession.name;
    unawaited(AnalyticsService.instance.log('onboarding_name_set'));
  }
}

final localNameProvider =
    NotifierProvider<LocalNameController, String>(LocalNameController.new);

import 'dart:async';

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

  /// Açılışta okunup belleğe alınan değerler (senkron erişim için).
  static String? _userId;
  static bool? _consent;
  static bool? _analyticsConsent;
  static String? _name;
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

  /// "Yerel verileri sil" sonrası: ebeveyn adı + göç bayraklarını temizler
  /// (rıza + localUserId korunur). Kullanıcı tekrar baştan başlar.
  static Future<void> clearLocalProfile() async {
    _name = '';
    _importedAccounts = {};
    _premiumSyncedAccounts = {};
    _purgeHandled = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kName);
      await prefs.remove(_kImportedAccts);
      await prefs.remove(_kPremiumSynced);
      await prefs.remove(_kPurgeHandled);
    } catch (_) {}
  }
}

/// Yerel kullanıcı kimliği (createdBy). main()'de gerçek değerle override edilir.
final localUserIdProvider = Provider<String>((_) => LocalSession.userId);

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

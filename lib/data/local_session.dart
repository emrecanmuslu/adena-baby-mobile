import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Local-first kimlik & rıza deposu (hesapsız çalışma için).
///
/// Free kullanıcı hesap açmadan başlar: ilk açılışta yerel bir `localUserId`
/// (UUID) üretilir — yerel kayıtların `createdBy`'si ve rıza öznesi olur. KVKK
/// rıza + 18+ yaş kapısı hesaptan bağımsız, yerelde alınır. Premium/aile/topluluk
/// isteyince gerçek hesap açılır; o anda yerel rıza sunucuya da yazılır.
class LocalSession {
  static const _storage = FlutterSecureStorage();
  static const _kUserId = 'local_user_id';
  static const _kConsent = 'local_consent_v1'; // KVKK + Şartlar + 18+ yerel onayı
  static const _kImportedAccts = 'cloud_imported_accounts_v1'; // göçü yapılmış hesaplar (CSV)
  static const _kName = 'local_user_name'; // ebeveyn adı (hesapsız profil)

  /// Açılışta okunup belleğe alınan değerler (senkron erişim için).
  static String? _userId;
  static bool? _consent;
  static String? _name;
  static String? _activeAccountId; // o an oturum açık hesap (yerel izolasyon anahtarı)
  static Set<String> _importedAccounts = {}; // cloud→local göçü yapılmış hesaplar

  /// main()'de bir kez çağrılır; localUserId + rıza durumunu belleğe yükler,
  /// localUserId yoksa üretip kalıcılaştırır.
  static Future<void> ensureLoaded() async {
    try {
      var id = await _storage.read(key: _kUserId);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await _storage.write(key: _kUserId, value: id);
      }
      _userId = id;
      _consent = (await _storage.read(key: _kConsent)) == '1';
      _name = (await _storage.read(key: _kName)) ?? '';
      final csv = await _storage.read(key: _kImportedAccts) ?? '';
      _importedAccounts = csv.split(',').where((s) => s.isNotEmpty).toSet();
    } catch (_) {
      _userId ??= const Uuid().v4();
      _consent ??= false;
      _name ??= '';
    }
  }

  static String get userId => _userId ?? '';
  static bool get consent => _consent ?? false;

  /// O an oturum açık hesabın id'si (yerel izolasyon anahtarı). null = oturum yok.
  static String? get activeAccountId => _activeAccountId;
  static void setActiveAccount(String? id) => _activeAccountId = id;

  /// Bu hesabın sunucu verisi yerele bir kez indirildi mi?
  static bool importedForAccount(String accountId) =>
      _importedAccounts.contains(accountId);

  /// Ebeveynin adı (yerel profil). Boş → henüz girilmedi.
  static String get name => _name ?? '';

  static Future<void> acceptConsent() async {
    _consent = true;
    try {
      await _storage.write(key: _kConsent, value: '1');
    } catch (_) {}
  }

  static Future<void> setName(String name) async {
    _name = name.trim();
    try {
      await _storage.write(key: _kName, value: _name);
    } catch (_) {}
  }

  static Future<void> markImportedForAccount(String accountId) async {
    _importedAccounts.add(accountId);
    try {
      await _storage.write(
          key: _kImportedAccts, value: _importedAccounts.join(','));
    } catch (_) {}
  }

  /// "Yerel verileri sil" sonrası: ebeveyn adı + göç bayraklarını temizler
  /// (rıza + localUserId korunur). Kullanıcı tekrar baştan başlar.
  static Future<void> clearLocalProfile() async {
    _name = '';
    _importedAccounts = {};
    try {
      await _storage.delete(key: _kName);
      await _storage.delete(key: _kImportedAccts);
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

/// Ebeveyn adı (hesapsız profil) — router bunu izler (girilince ad kapısından çıkar).
class LocalNameController extends Notifier<String> {
  @override
  String build() => LocalSession.name;

  Future<void> set(String name) async {
    await LocalSession.setName(name);
    state = LocalSession.name;
  }
}

final localNameProvider =
    NotifierProvider<LocalNameController, String>(LocalNameController.new);

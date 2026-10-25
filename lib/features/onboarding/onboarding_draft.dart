import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Yarım kalan kurulumun taslağı — uygulama kapatılır ya da sistem arka
/// plandaki süreci öldürürse kullanıcı karşılamaya değil KALDIĞI forma, girdiği
/// bilgilerle döner. Hedef seçilince yazılır, kurulum tamamlanınca silinir.
///
/// Tek JSON değeri: `{route, fields:{...}}`. Alanlar ekrana özgüdür (bebek
/// profili: ad/tarih/cinsiyet…; adet: son adet/döngü süresi).
class OnboardingDraft {
  OnboardingDraft._();

  static const _k = 'onboarding_draft_v1';

  /// Taslak — yoksa null.
  static Future<({String route, Map<String, dynamic> fields})?> read() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(_k);
      if (s == null) return null;
      final j = jsonDecode(s) as Map<String, dynamic>;
      final route = j['route'] as String?;
      if (route == null || !route.startsWith('/onboarding/')) return null;
      return (
        route: route,
        fields: (j['fields'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }

  /// Hedef seçildi → taslağı başlat (alanlar boş).
  static Future<void> start(String route) => _write(route, const {});

  /// Form alanlarını güncelle (rota korunur; farklı rotadaysa yazılmaz).
  static Future<void> saveFields(String route, Map<String, dynamic> fields) async {
    final cur = await read();
    if (cur != null && cur.route != route) return;
    await _write(route, fields);
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_k);
    } catch (_) {}
  }

  static Future<void> _write(String route, Map<String, dynamic> fields) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_k, jsonEncode({'route': route, 'fields': fields}));
    } catch (_) {}
  }

  /// Tarih ↔ JSON (yalnız gün).
  static String? day(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseDay(Object? s) =>
      s is String ? DateTime.tryParse(s) : null;
}

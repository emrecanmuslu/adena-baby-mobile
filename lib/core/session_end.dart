import 'package:shared_preferences/shared_preferences.dart';

/// Oturumun sunucu tarafından sonlandırılma nedeni (BULGULAR.md O1).
enum SessionEndReason {
  /// Başka cihazdan giriş yapıldı; bu cihazın oturumu düşürüldü (tek-aktif-
  /// oturum). Gövdede `code == "session_superseded"` (backend talebi #8).
  superseded,

  /// Refresh token süresi doldu / geçersiz: `code == "token_not_valid"`.
  expired,

  /// Diğer her 401/400 (kodsuz dahil) — genel mesaj. Kodsuz yanıt superseded
  /// SAYILMAZ; `detail` metniyle eşleme yapılmaz (dil bağımlı).
  unknown,
}

/// `/auth/refresh` reddinin gövdesinden neden çıkarır.
SessionEndReason sessionEndReasonFromBody(dynamic data) {
  if (data is Map) {
    final code = data['code'];
    if (code == 'session_superseded') return SessionEndReason.superseded;
    if (code == 'token_not_valid') return SessionEndReason.expired;
  }
  return SessionEndReason.unknown;
}

/// Bekleyen "oturum sona erdi" nedeni — prefs'te tutulur ki başka isolate'te
/// (bg turu) ya da önceki süreçte düşen oturum ön planda bir kez
/// gösterilebilsin. Giriş ekranı gösterince, başarılı giriş ve kullanıcı çıkışı
/// temizler.
class SessionEndCache {
  static const key = 'auth_session_end_reason';

  static Future<void> write(SessionEndReason r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, r.name);
    } catch (_) {}
  }

  static Future<SessionEndReason?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(key);
      if (v == null) return null;
      for (final r in SessionEndReason.values) {
        if (r.name == v) return r;
      }
      return SessionEndReason.unknown;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}

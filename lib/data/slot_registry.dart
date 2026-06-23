import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bebek-başına KALICI bildirim "slot"u (0,1,2…). Beslenme/uyku/emzirme bildirim
/// id'leri slot'tan türer (NotificationService.feedMainIdFor(slot) vb.). Eski
/// yöntem `id.hashCode % 1000` idi → bir kullanıcının iki bebeği aynı slota
/// düşebiliyor (≈%0.1) ve bildirimleri birbirini eziyordu. Bu registry her bebeğe
/// BENZERSİZ slot atayıp kalıcılaştırır → çakışma İMKÂNSIZ.
///
/// Ana isolate: bellek haritası (sync `slotFor`); kayıt main()'de [load] edilir.
/// Arka plan isolate (push handler): ayrı bellek → depodan okur (async [slotForStored]).
class SlotRegistry {
  SlotRegistry._();
  static final SlotRegistry instance = SlotRegistry._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'baby_notif_slots'; // JSON: {babyId: slot}

  Map<String, int> _cache = {};

  /// Uygulama açılışında bir kez (main) — kalıcı haritayı belleğe yükle.
  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _cache = m.map((k, v) => MapEntry(k, (v as num).toInt()));
      }
    } catch (_) {}
  }

  /// Bebeğin slotu (ANA isolate, sync). Atanmamışsa en küçük boş slotu verir,
  /// belleğe ekler ve kalıcılaştırır (fire-and-forget). Aynı kullanıcının iki
  /// bebeği asla aynı slotu almaz.
  int slotFor(String babyId) {
    final existing = _cache[babyId];
    if (existing != null) return existing;
    final used = _cache.values.toSet();
    var slot = 0;
    while (used.contains(slot)) {
      slot++;
    }
    _cache[babyId] = slot;
    _persist();
    return slot;
  }

  /// Bebeğin slotu (ARKA PLAN isolate, async): yalnız depodan OKUR — atama yapmaz.
  /// Yoksa null (o bebeğe dair zamanlanmış bir bildirim de yoktur → iptal gereksiz).
  Future<int?> slotForStored(String babyId) async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final v = m[babyId];
      return v == null ? null : (v as num).toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.write(key: _key, value: jsonEncode(_cache));
    } catch (_) {}
  }

  /// Çıkış/hesap silme: harita temizlenir (yeni hesabın bebekleri 0'dan başlasın).
  Future<void> clear() async {
    _cache = {};
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

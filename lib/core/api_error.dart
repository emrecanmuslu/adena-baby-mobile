import 'package:dio/dio.dart';

import 'i18n.dart';

/// Bilinen alan adları → Türkçe etiket (çok-alanlı hatada önek için).
const _fieldLabels = {
  'email': 'E-posta',
  'password': 'Şifre',
  'name': 'Ad',
  'title': 'Başlık',
  'text': 'Metin',
};

/// Django/DRF hata gövdesinden kullanıcıya gösterilecek anlaşılır mesaj çıkarır.
/// Desteklenen biçimler:
///  - {"detail": "..."}                         (auth/izin/404 vb. — öncelikli)
///  - {"alan": ["mesaj", ...], ...}             (doğrulama; tek alan→sade, çok→etiketli)
///  - {"error":"kod","detail":"insan mesajı"}   ('detail' alınır, 'error' kodu atlanır)
///  - {"non_field_errors": ["..."]}             (öneksiz)
///  - ["..."] / iç içe Map                      (recursive)
/// Gövde yoksa Dio tipi / HTTP koduna göre genel mesaja düşer.
String apiErrorText(Object? error) {
  if (error is! DioException) return tr('Bir hata oluştu, tekrar dene.');

  final msg = _extract(error.response?.data);
  if (msg != null && msg.isNotEmpty) return msg;

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return tr('Sunucuya ulaşılamadı. Bağlantını kontrol et.');
    default:
      final code = error.response?.statusCode;
      if (code == 401) return tr('Oturum gerekli. Lütfen tekrar giriş yap.');
      if (code == 403) return tr('Bu işlem için yetkin yok.');
      if (code == 404) return tr('Bulunamadı.');
      if (code != null && code >= 500) return tr('Sunucu hatası. Biraz sonra tekrar dene.');
      return tr('Bir hata oluştu, tekrar dene.');
  }
}

/// Gövdeden ilk anlamlı mesaj(lar)ı çıkarır (recursive).
String? _extract(dynamic data) {
  if (data is String) {
    final s = data.trim();
    return (s.isNotEmpty && s.length < 400) ? s : null;
  }
  if (data is List) {
    for (final item in data) {
      final m = _extract(item);
      if (m != null && m.isNotEmpty) return m;
    }
    return null;
  }
  if (data is Map) {
    // 1) İnsan-okunur 'detail' önce (auth/izin mesajları).
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();

    // 2) Alan hataları — 'error' makine kodunu atla.
    final pairs = <MapEntry<String, String>>[];
    data.forEach((key, value) {
      if (key == 'error') return;
      final m = _extract(value);
      if (m != null && m.isNotEmpty) pairs.add(MapEntry(key.toString(), m));
    });
    if (pairs.length == 1) return pairs.first.value; // tek alan → sade mesaj
    if (pairs.length > 1) {
      return pairs.map((p) {
        final label = _fieldLabels[p.key];
        return (label != null) ? '$label: ${p.value}' : p.value;
      }).join('\n');
    }

    // 3) Son çare: 'error' string (detail yoksa).
    final err = data['error'];
    if (err is String && err.trim().isNotEmpty) return err.trim();
  }
  return null;
}

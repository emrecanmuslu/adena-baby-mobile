import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/api_error.dart';

/// apiErrorText, Django/DRF hata gövdesini kullanıcıya gösterilecek mesaja
/// çevirir. Testler varsayılan locale (tr) ile çalışır → tr() kaynağı aynen
/// döndürür, böylece beklenen metinler birebir kontrol edilebilir.

DioException _withData(dynamic data, {int? status, String? path}) {
  final req = RequestOptions(path: path ?? '/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: req,
      data: data,
      statusCode: status,
    ),
  );
}

DioException _ofType(DioExceptionType type, {int? status, dynamic data}) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: type,
    response: status != null || data != null
        ? Response(requestOptions: req, data: data, statusCode: status)
        : null,
  );
}

void main() {
  group('apiErrorText — DioException olmayan girdiler', () {
    test('null → genel hata mesajı', () {
      expect(apiErrorText(null), 'Bir hata oluştu, tekrar dene.');
    });

    test('düz string (DioException değil) → genel hata mesajı', () {
      expect(apiErrorText('herhangi bir hata'), 'Bir hata oluştu, tekrar dene.');
    });

    test('Exception → genel hata mesajı', () {
      expect(apiErrorText(Exception('boom')), 'Bir hata oluştu, tekrar dene.');
    });
  });

  group('apiErrorText — gövdeden mesaj çıkarımı', () {
    test('{"detail": "..."} → detail aynen döner', () {
      final e = _withData({'detail': 'Geçersiz kimlik bilgileri.'}, status: 401);
      expect(apiErrorText(e), 'Geçersiz kimlik bilgileri.');
    });

    test('detail öncelikli: kod fallback yerine detail kullanılır', () {
      // status 401 ama gövdede insan-okunur detail var → detail kazanır
      final e = _withData({'detail': 'Özel mesaj'}, status: 401);
      expect(apiErrorText(e), 'Özel mesaj');
    });

    test('tek alan hatası → sade mesaj (etiketsiz)', () {
      final e = _withData({'email': ['Bu e-posta zaten kayıtlı.']}, status: 400);
      expect(apiErrorText(e), 'Bu e-posta zaten kayıtlı.');
    });

    test('çok alan hatası → bilinen alanlar etiketli, satırlarla birleşir', () {
      final e = _withData({
        'email': ['Geçersiz e-posta.'],
        'password': ['Çok kısa.'],
      }, status: 400);
      final out = apiErrorText(e);
      expect(out, contains('E-posta: Geçersiz e-posta.'));
      expect(out, contains('Şifre: Çok kısa.'));
      expect(out, contains('\n'));
    });

    test('bilinmeyen alanlar etiketsiz (çok alan), değer döner', () {
      final e = _withData({
        'foo': ['hata1'],
        'bar': ['hata2'],
      }, status: 400);
      final out = apiErrorText(e);
      expect(out, contains('hata1'));
      expect(out, contains('hata2'));
    });

    test('non_field_errors → öneksiz mesaj', () {
      final e = _withData({'non_field_errors': ['Bir şeyler ters gitti.']});
      expect(apiErrorText(e), 'Bir şeyler ters gitti.');
    });

    test('{"error":"kod","detail":"insan"} → detail alınır, error kodu atlanır', () {
      final e = _withData({'error': 'invalid_grant', 'detail': 'Token süresi doldu.'});
      expect(apiErrorText(e), 'Token süresi doldu.');
    });

    test('yalnız {"error":"kod"} (detail yok) → son çare error string döner', () {
      final e = _withData({'error': 'something_failed'});
      expect(apiErrorText(e), 'something_failed');
    });

    test('error tek alanken pairs hesabına katılmaz (atlanır)', () {
      // error atlanır; geriye email kalır → tek alan sade mesaj
      final e = _withData({
        'error': 'code',
        'email': ['E-posta hatası'],
      });
      expect(apiErrorText(e), 'E-posta hatası');
    });

    test('düz string gövde → trim edilip döner', () {
      final e = _withData('  Beklenmeyen sunucu yanıtı  ');
      expect(apiErrorText(e), 'Beklenmeyen sunucu yanıtı');
    });

    test('liste gövde → ilk anlamlı mesaj döner (recursive)', () {
      final e = _withData(['İlk hata', 'İkinci hata']);
      expect(apiErrorText(e), 'İlk hata');
    });

    test('iç içe map → recursive ilk mesaj', () {
      final e = _withData({
        'nested': {'deep': ['Derin hata']}
      });
      expect(apiErrorText(e), 'Derin hata');
    });

    test('400 karakterden uzun string → mesaj olarak kabul edilmez, koda düşer', () {
      final long = 'x' * 500;
      final e = _withData(long, status: 500);
      // _extract null döner → status 500 fallback
      expect(apiErrorText(e), 'Sunucu hatası. Biraz sonra tekrar dene.');
    });
  });

  group('apiErrorText — gövdesiz HTTP kodu fallback', () {
    test('401 → oturum gerekli', () {
      expect(apiErrorText(_ofType(DioExceptionType.badResponse, status: 401)),
          'Oturum gerekli. Lütfen tekrar giriş yap.');
    });

    test('403 → yetki yok', () {
      expect(apiErrorText(_ofType(DioExceptionType.badResponse, status: 403)),
          'Bu işlem için yetkin yok.');
    });

    test('404 → bulunamadı', () {
      expect(apiErrorText(_ofType(DioExceptionType.badResponse, status: 404)),
          'Bulunamadı.');
    });

    test('500 → sunucu hatası', () {
      expect(apiErrorText(_ofType(DioExceptionType.badResponse, status: 500)),
          'Sunucu hatası. Biraz sonra tekrar dene.');
    });

    test('503 (>=500) → sunucu hatası', () {
      expect(apiErrorText(_ofType(DioExceptionType.badResponse, status: 503)),
          'Sunucu hatası. Biraz sonra tekrar dene.');
    });

    test('tanımsız kod (418) → genel hata', () {
      expect(apiErrorText(_ofType(DioExceptionType.badResponse, status: 418)),
          'Bir hata oluştu, tekrar dene.');
    });

    test('response null → genel hata', () {
      expect(apiErrorText(_ofType(DioExceptionType.badResponse)),
          'Bir hata oluştu, tekrar dene.');
    });
  });

  group('apiErrorText — bağlantı/zaman aşımı tipleri', () {
    test('connectionTimeout → sunucuya ulaşılamadı', () {
      expect(apiErrorText(_ofType(DioExceptionType.connectionTimeout)),
          'Sunucuya ulaşılamadı. Bağlantını kontrol et.');
    });

    test('receiveTimeout → sunucuya ulaşılamadı', () {
      expect(apiErrorText(_ofType(DioExceptionType.receiveTimeout)),
          'Sunucuya ulaşılamadı. Bağlantını kontrol et.');
    });

    test('sendTimeout → sunucuya ulaşılamadı', () {
      expect(apiErrorText(_ofType(DioExceptionType.sendTimeout)),
          'Sunucuya ulaşılamadı. Bağlantını kontrol et.');
    });

    test('connectionError → sunucuya ulaşılamadı', () {
      expect(apiErrorText(_ofType(DioExceptionType.connectionError)),
          'Sunucuya ulaşılamadı. Bağlantını kontrol et.');
    });

    test('zaman aşımı tipi ama gövdede mesaj varsa → gövde mesajı öncelikli', () {
      final e = _ofType(DioExceptionType.connectionTimeout,
          data: {'detail': 'Zaman aşımı detayı'});
      expect(apiErrorText(e), 'Zaman aşımı detayı');
    });
  });
}

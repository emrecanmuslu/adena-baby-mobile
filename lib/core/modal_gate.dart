import 'dart:async';

import 'package:flutter/foundation.dart';

/// Kendiliğinden açılan modalların (tanıtım turu, karşılama paywall'ı) aynı
/// karede üst üste binmesini engelleyen basit **öncelik kapısı**.
///
/// Sorun: ikisi de `addPostFrameCallback` ile ve birbirinden habersiz açılıyordu
/// → yeni hesapla onboarding bitince ana sayfada tur dialogu ile Premium
/// Karşılama Ekranı aynı anda çıkıyordu (bekleme modunda da aynısı).
///
/// Kural: **öncelikli olan tarafın kapıyı tutması**, düşük öncelikli tarafın
/// (tur) kapı açılana kadar beklemesi. Bekleyen taraf turu "görüldü"
/// işaretlemez — sadece göstermeyi erteler; kapı açılınca [listenable] ile
/// haber alıp tekrar dener.
///
/// [acquire]/[release] daima çift olmalı (çağıran tarafta `try/finally`).
class ModalGate {
  ModalGate._();

  static final ValueNotifier<int> _holds = ValueNotifier<int>(0);

  /// Kapı durumu değişince haber verir (bekleyen taraf yeniden denesin diye).
  static ValueListenable<int> get listenable => _holds;

  /// Şu an öncelikli bir modal sırada/açık mı?
  static bool get isBlocked => _holds.value > 0;

  /// Kapıyı tut — düşük öncelikli modallar bu süre boyunca açılmaz.
  static void acquire() => _holds.value++;

  /// Kapıyı bırak. Fazladan çağrı sayacı eksiye düşürmez.
  static void release() {
    if (_holds.value > 0) _holds.value--;
  }

  /// YALNIZ testler için: sayacı sıfırla (testler arası sızıntı olmasın).
  @visibleForTesting
  static void resetForTest() => _holds.value = 0;
}

/// Sistem izin pencerelerinin (bildirim izni) **ne zaman** açılabileceği.
///
/// Sorun: izin isteği bildirim planlayan herhangi bir yerden (bebek kurulunca,
/// kayıt olunca FCM) bağlamsız açılıyordu → onboarding ekranının, Premium
/// Karşılama'nın ya da tanıtım turunun ÜSTÜNE biniyordu.
///
/// Kural: uygulama asıl ekranına ([markAppReady] — ana sayfa / Adet Takvimi)
/// ulaşmadan ve [ModalGate] tutulurken (paywall, tur) izin penceresi açılmaz;
/// [whenClear] uygun anı bekler. Arka plan isolate'inde hiç hazır olmaz → orada
/// asla izin sorulmaz (zaten sorulamaz).
class SystemPromptGate {
  SystemPromptGate._();

  static final ValueNotifier<bool> _appReady = ValueNotifier<bool>(false);

  /// Modal kapandıktan sonra sıradaki modalın (ör. tur) kapıyı tutmasına fırsat
  /// tanıyan kısa bekleme — izin penceresi onun üstüne binmesin.
  static Duration settle = const Duration(milliseconds: 900);

  /// Asıl ekran (ana sayfa / Adet Takvimi) ilk kez kuruldu.
  static void markAppReady() => _appReady.value = true;

  static bool get _clear => _appReady.value && !ModalGate.isBlocked;

  /// Uygulama hazır ve öncelikli modal yokken tamamlanır.
  static Future<void> whenClear() async {
    while (true) {
      if (!_clear) {
        final changed = Completer<void>();
        void onChange() {
          if (_clear && !changed.isCompleted) changed.complete();
        }

        _appReady.addListener(onChange);
        ModalGate.listenable.addListener(onChange);
        try {
          onChange(); // dinleyici kurulurken durum değişmiş olabilir
          await changed.future;
        } finally {
          _appReady.removeListener(onChange);
          ModalGate.listenable.removeListener(onChange);
        }
      }
      await Future<void>.delayed(settle);
      if (_clear) return;
    }
  }

  /// YALNIZ testler için.
  @visibleForTesting
  static void resetForTest() {
    _appReady.value = false;
    settle = const Duration(milliseconds: 900);
  }
}

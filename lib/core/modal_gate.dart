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

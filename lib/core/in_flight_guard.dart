/// Çift dokunma / uçuş-içi tekrar koruması (BULGULAR.md O8, O22, D23 ailesi).
///
/// Bir iş sürerken ikinci çağrı ÇALIŞTIRILMAZ ve `false` döner; iş bitince
/// (başarı ya da hata) kilit açılır. Stateless widget'larda dosya düzeyinde,
/// State'lerde alan olarak tutulur. Saf Dart, birim testli.
class InFlightGuard {
  bool _busy = false;

  /// Şu an bir iş sürüyor mu (düğmeyi pasifleştirmek için).
  bool get busy => _busy;

  /// [body] çalıştırıldıysa `true`, başka bir iş sürdüğü için atlandıysa `false`.
  /// [body]'nin hatası yukarı geçer; kilit `finally` ile her durumda açılır.
  Future<bool> run(Future<void> Function() body) async {
    if (_busy) return false;
    _busy = true;
    try {
      await body();
      return true;
    } finally {
      _busy = false;
    }
  }
}

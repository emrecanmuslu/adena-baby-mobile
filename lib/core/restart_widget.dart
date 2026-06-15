import 'package:flutter/widgets.dart';

/// Tüm widget ağacını sıfırdan kurar. Dil değişiminde kullanılır: anahtar
/// değişince alt ağaç (ProviderScope dahil) yeniden oluşturulur, böylece zaten
/// build edilmiş/const ekranlardaki tüm `tr()` çağrıları yeni dilde değerlenir.
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  /// En yakın [RestartWidget]'i bulup ağacı yeniden kurar.
  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

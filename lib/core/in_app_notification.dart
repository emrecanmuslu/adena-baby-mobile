import 'package:flutter/material.dart';

import 'ad_service.dart' show rootNavigatorKey;
import 'theme.dart';

/// Uygulama ÖN PLANDAYKEN gelen push için üstten kayan in-app bildirim banner'ı.
/// OS bildirimi ön planda basılmaz (iOS'ta OS sunumu kapalı, Android'de istemci
/// bastırır) → kullanıcı uygulamanın içindeyken de "yeni etkinlik geldi"yi görür.
///
/// Kök navigator overlay'ine tek bir OverlayEntry olarak eklenir (aynı anda tek
/// banner — yenisi gelince eskisi kapanır). Dokunarak ya da yukarı kaydırarak
/// kapatılır; ~4 sn sonra otomatik kapanır.
OverlayEntry? _activeBanner;

void showInAppNotification({required String title, required String body}) {
  final overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  _activeBanner?.remove();
  _activeBanner = null;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _InAppBanner(
      title: title,
      body: body,
      onClose: () {
        if (entry.mounted) entry.remove();
        if (identical(_activeBanner, entry)) _activeBanner = null;
      },
    ),
  );
  _activeBanner = entry;
  overlay.insert(entry);
}

class _InAppBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onClose;
  const _InAppBanner(
      {required this.title, required this.body, required this.onClose});

  @override
  State<_InAppBanner> createState() => _InAppBannerState();
}

class _InAppBannerState extends State<_InAppBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260))
    ..forward();
  late final Animation<Offset> _slide = Tween(
          begin: const Offset(0, -1), end: Offset.zero)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    // ~4 sn sonra otomatik kapan.
    Future.delayed(const Duration(milliseconds: 4200), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _c.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: media.padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _dismiss,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) _dismiss();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notifications_rounded,
                        color: AppColors.coral, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.title.trim().isNotEmpty)
                          Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        if (widget.body.trim().isNotEmpty)
                          Text(widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

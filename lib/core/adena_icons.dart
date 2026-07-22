import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Tasarımın özel çizgi-ikon seti (design/AdenaBaby/icons.jsx ile birebir).
/// Tutarlı stroke (1.8), yuvarlak uçlar. AdenaIcon('feed') gibi kullanılır.
class AdenaIcons {
  static const paths = <String, String>{
    // kategoriler
    'feed': '<path d="M9 2h6M10 2c0 1.5-1 2-1 3.5C9 7 8 8 8 10v9a3 3 0 003 3h2a3 3 0 003-3v-9c0-2-1-3-1-4.5C15 4 14 3.5 14 2"/><path d="M8.5 11h7M9 15h6"/>',
    'diaper': '<path d="M3 6h18l-1.2 5.5A8 8 0 0112 18a8 8 0 01-7.8-6.5L3 6z"/><path d="M9.5 10.5c1.5 1 3.5 1 5 0"/>',
    'sleep': '<path d="M20 14.5A8 8 0 119.5 4a6.5 6.5 0 0010.5 10.5z"/><path d="M15 4h4l-4 4h4"/>',
    'pump': '<path d="M12 3c2.5 3.5 4 5.7 4 8a4 4 0 11-8 0c0-2.3 1.5-4.5 4-8z"/><path d="M9.5 12.5a2.5 2.5 0 002.5 2.5"/>',
    'growth': '<path d="M5 3v18M5 21h16"/><path d="M5 17l4-4 3 3 6-7"/><path d="M18 9h2v2"/>',
    'fever': '<path d="M14 14.8V5a2 2 0 10-4 0v9.8a4 4 0 104 0z"/><path d="M12 15.5a1.5 1.5 0 100 3 1.5 1.5 0 000-3z" fill="currentColor" stroke="none"/>',
    'med': '<rect x="3.5" y="8.5" width="17" height="7" rx="3.5" transform="rotate(-45 12 12)"/><path d="M9 9l6 6"/>',
    'bath': '<path d="M4 12h16v3a4 4 0 01-4 4H8a4 4 0 01-4-4v-3z"/><path d="M6 12V6a2.5 2.5 0 015 0M9.5 6h3"/><path d="M5 19l-1 2M19 19l1 2"/>',
    'doctor': '<path d="M6 3v5a4 4 0 008 0V3"/><path d="M6 3H4.5M9.5 3H8"/><path d="M10 12v2.5a5.5 5.5 0 0011 0V13"/><circle cx="20" cy="11" r="2"/>',
    'solid': '<path d="M5 11a7 7 0 0114 0"/><path d="M3.5 11h17"/><path d="M6 11v3a6 6 0 0012 0v-3"/><path d="M12 4V2.5"/>',
    'pulse': '<path d="M3 12h3.5l2-6 3.5 12 2.5-7 1.5 3H21"/>', // EKG/nabız — belirti
    'tooth': '<path d="M6 4C4.3 4 3 5.4 3 7.3c0 1.2.4 2.3.8 3.7.5 1.8.6 5 .9 6.7.2 1 .5 2 1.3 2 .9 0 1-1.3 1.4-3 .3-1.3.6-2.4 1.6-2.4s1.3 1.1 1.6 2.4c.4 1.7.5 3 1.4 3 .8 0 1.1-1 1.3-2 .3-1.7.4-4.9.9-6.7.4-1.4.8-2.5.8-3.7C21 5.4 19.7 4 18 4c-1.5 0-2.5.8-3.8.8S13.5 4 12 4s-2 .8-3.2.8S7.5 4 6 4z"/>', // süt dişi
    // navigasyon
    'home': '<path d="M4 11l8-7 8 7"/><path d="M6 9.5V20h12V9.5"/><path d="M10 20v-5h4v5"/>',
    'timeline': '<circle cx="5" cy="6.5" r="1.5"/><circle cx="5" cy="12" r="1.5"/><circle cx="5" cy="17.5" r="1.5"/><path d="M9.5 6.5H20M9.5 12H20M9.5 17.5H17"/>',
    'charts': '<path d="M4 4v16h16"/><path d="M7 15l3.5-4 3 2.5L20 7"/>',
    'plus': '<path d="M12 5v14M5 12h14"/>',
    'more': '<circle cx="5" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.6" fill="currentColor" stroke="none"/>',
    'gear': '<circle cx="12" cy="12" r="3"/><path d="M12 2.5l1.2 2.3 2.5-.6.4 2.6 2.3 1.2-1.2 2.3 1.2 2.3-2.3 1.2-.4 2.6-2.5-.6L12 21.5l-1.2-2.3-2.5.6-.4-2.6-2.3-1.2 1.2-2.3-1.2-2.3 2.3-1.2.4-2.6 2.5.6z"/>',
    // menü / ayarlar
    'family': '<circle cx="8" cy="8" r="3"/><circle cx="17" cy="9.5" r="2.3"/><path d="M2.5 19a5.5 5.5 0 0111 0"/><path d="M14.5 19a4 4 0 017 0"/>',
    'bell': '<path d="M6 9a6 6 0 0112 0c0 5 2 6 2 6H4s2-1 2-6z"/><path d="M10 19a2 2 0 004 0"/>',
    'ai': '<path d="M9.5 3l1.2 3.3L14 7.5l-3.3 1.2L9.5 12 8.3 8.7 5 7.5l3.3-1.2z"/><path d="M17 12l.8 2.2 2.2.8-2.2.8L17 18l-.8-2.2-2.2-.8 2.2-.8z"/>',
    'star': '<path d="M12 3l2.6 5.7 6.2.7-4.6 4.2 1.3 6.1L12 16.8 6.5 19.7l1.3-6.1L3.2 9.4l6.2-.7z"/>',
    'baby': '<circle cx="12" cy="12" r="8.5"/><path d="M9 11.5h.01M15 11.5h.01"/><path d="M9.5 15.5a3.5 3.5 0 005 0"/><path d="M12 3.5c1.5 0 2 1 2 1"/>',
    'moon': '<path d="M20 14.5A8 8 0 119.5 4a6.5 6.5 0 0010.5 10.5z"/>',
    'shield': '<path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z"/><path d="M9 12l2 2 4-4"/>',
    // genel
    'chevR': '<path d="M9 5l7 7-7 7"/>',
    'chevL': '<path d="M15 5l-7 7 7 7"/>',
    'chevD': '<path d="M5 9l7 7 7-7"/>',
    'arrowUp': '<path d="M12 19V5"/><path d="M5.5 11.5L12 5l6.5 6.5"/>',
    'compass': '<circle cx="12" cy="12" r="9"/><path d="M14.6 9.4l-1.9 4.3-4.3 1.9 1.9-4.3z"/>',
    'comment': '<path d="M21 7v6a3 3 0 01-3 3h-6.5L7.5 19.8V16H7a3 3 0 01-3-3V7a3 3 0 013-3h11a3 3 0 013 3z"/>',
    'send': '<path d="M21 3L10.5 13.5"/><path d="M21 3l-6.8 17-3.7-6.5L4 9.8 21 3z"/>',
    'shieldAlert': '<path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z"/><path d="M12 8.5V12"/><path d="M12 15h.01"/>',
    'check': '<path d="M5 12.5l4.5 4.5L19 6.5"/>',
    'clock': '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    'edit': '<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="M14 6l4 4"/>',
    'trash': '<path d="M4 7h16M9 7V5a1.5 1.5 0 013 0v2M6 7l1 13h10l1-13"/>',
    'calendar': '<rect x="4" y="5" width="16" height="16" rx="3"/><path d="M4 9.5h16M8 3v4M16 3v4"/>',
    'mail': '<rect x="3" y="5.5" width="18" height="13" rx="3"/><path d="M4 7l8 6 8-6"/>',
    'link': '<path d="M10 14a4 4 0 005.7 0l3-3a4 4 0 10-5.7-5.7L11 7"/><path d="M14 10a4 4 0 00-5.7 0l-3 3a4 4 0 105.7 5.7L13 17"/>',
    'camera': '<path d="M4 8h3l1.5-2h7L17 8h3a1 1 0 011 1v9a1 1 0 01-1 1H4a1 1 0 01-1-1V9a1 1 0 011-1z"/><circle cx="12" cy="13" r="3.5"/>',
    'syringe': '<path d="M14 3l7 7M18 6l-9 9-4 1 1-4 9-9z"/><path d="M9 12l3 3M3 21l3-3"/>',
    'heart': '<path d="M12 20s-7-4.4-9-9c-1.3-3 1-6 4-6 2 0 3.3 1.2 5 3 1.7-1.8 3-3 5-3 3 0 5.3 3 4 6-2 4.6-9 9-9 9z"/>',
    'user': '<circle cx="12" cy="8" r="4"/><path d="M4.5 20a7.5 7.5 0 0115 0"/>',
    'download': '<path d="M12 4v10M8 11l4 4 4-4"/><path d="M5 19h14"/>',
    'logout': '<path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4"/><path d="M16 17l5-5-5-5M21 12H9"/>',
    // gelişim atakları (design/Gelişim Atakları.html ikonları)
    'eye': '<path d="M2 12s3.5-6.5 10-6.5S22 12 22 12s-3.5 6.5-10 6.5S2 12 2 12z"/><circle cx="12" cy="12" r="2.8"/>',
    'ear': '<path d="M6 9a6 6 0 1112 0c0 4-3 4.5-3.5 7a3 3 0 01-5.9.5"/><path d="M9.5 9a2.5 2.5 0 015 0c0 1.6-1.2 2-1.7 3.2"/>',
    'hand': '<path d="M7 11V6.5a1.5 1.5 0 013 0V11m0-5.5v-1a1.5 1.5 0 013 0V11m0-5v1a1.5 1.5 0 013 0v5.5"/><path d="M16 12.5a1.5 1.5 0 013 0c0 5-2 9-6.5 9S6 18 5 15c-.6-1.8-1.5-3.4-1.5-3.4a1.4 1.4 0 012.4-1.3L7 12"/>',
    'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v2.5M12 19.5V22M22 12h-2.5M4.5 12H2M18.7 5.3L17 7M7 17l-1.7 1.7M18.7 18.7L17 17M7 7L5.3 5.3"/>',
    'search': '<circle cx="11" cy="11" r="7.5"/><path d="M20.5 20.5L16.5 16.5"/>',
    'quote': '<path d="M10 7H6a3 3 0 00-3 3v1a3 3 0 003 3h1.2A5.8 5.8 0 013 17.5V19a7.3 7.3 0 007-7.3zM21 7h-4a3 3 0 00-3 3v1a3 3 0 003 3h1.2a5.8 5.8 0 01-4.2 3.5V19a7.3 7.3 0 007-7.3z" fill="currentColor" stroke="none"/>',
    'userHeart': '<circle cx="9" cy="7" r="3.2"/><path d="M3.5 21c0-3.5 2.5-5.8 5.5-5.8s5.5 2.3 5.5 5.8"/><path d="M17.5 3.5a3 3 0 012.7 4.4c-.6 1.3-2.7 2.9-2.7 2.9s-2.1-1.6-2.7-2.9a3 3 0 012.7-4.4z"/>',
  };

  static String svg(String name, Color color, double sw) {
    final hex =
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final inner = (paths[name] ?? '').replaceAll('currentColor', hex);
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
        'stroke="$hex" stroke-width="$sw" stroke-linecap="round" stroke-linejoin="round">$inner</svg>';
  }
}

/// Tasarımın çizgi ikonu. [name] = AdenaIcons.paths anahtarı.
class AdenaIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final double sw;
  /// Erişilebilirlik: anlamlı (tek başına bilgi taşıyan) ikona ekran okuyucu
  /// etiketi ver. Boş bırakılırsa ikon DEKORATİF sayılır (etiketli bir butonun
  /// içindeyken doğru davranış — okuyucu butonun kendi etiketini okur).
  final String? semanticLabel;
  const AdenaIcon(this.name,
      {super.key, this.size = 24, this.color, this.sw = 1.8, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? AppColors.ink;
    return SvgPicture.string(
      AdenaIcons.svg(name, c, sw),
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

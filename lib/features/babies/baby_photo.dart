import 'dart:io';

import 'package:flutter/material.dart';

/// Bebek dairesel avatarı — foto varsa gösterir (yerel dosya yolu / sunucu
/// URL'i, local-first: `photo` alanı ikisini de tutabilir), yoksa ya da
/// yükleme hatasında [placeholder] gösterilir (mevcut gradyan+ikon rozeti).
class BabyAvatar extends StatelessWidget {
  final String? photo;
  final double size;
  final Widget placeholder;
  const BabyAvatar(
      {super.key, required this.photo, required this.size, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    final p = photo;
    if (p == null || p.isEmpty) return placeholder;
    final image = p.startsWith('http')
        ? Image.network(p,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder)
        : Image.file(File(p),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder);
    return ClipOval(child: image);
  }
}

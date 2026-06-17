import 'package:flutter/foundation.dart';

import '../core/i18n.dart';

/// Anı / fotoğraf günlüğü kaydı — API §babies/memories.
/// [firstTag] boşsa düz anı; doluysa bir "ilk" (katalog: [kFirstTags]).
@immutable
class Memory {
  final String id;
  final DateTime date;
  final String title;
  final String note;
  final String? photo; // sunucu mutlak URL'i (yoksa null)
  final String firstTag;

  const Memory({
    required this.id,
    required this.date,
    this.title = '',
    this.note = '',
    this.photo,
    this.firstTag = '',
  });

  bool get isFirst => firstTag.isNotEmpty;

  /// Foto yerel dosya yolu mu (free, henüz yüklenmemiş) yoksa sunucu URL'i mi?
  /// Local-first: free kullanıcıda foto telefonda tutulur (http ile başlamaz).
  bool get hasPhoto => photo != null && photo!.isNotEmpty;
  bool get isLocalPhoto => hasPhoto && !photo!.startsWith('http');

  factory Memory.fromJson(Map<String, dynamic> json) => Memory(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        title: (json['title'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        photo: (json['photo'] as String?)?.isEmpty ?? true
            ? null
            : json['photo'] as String?,
        firstTag: (json['first_tag'] as String?) ?? '',
      );
}

/// "İlk" etiketi kataloğu (anahtar → emoji + etiket). Boş anahtar = düz anı.
/// Backend `first_tag` serbest string; mobil bu sabit listeyi sunar.
class FirstTagInfo {
  final String key;
  final String emoji;
  final String Function() label; // tr() taze değerlensin diye fonksiyon
  const FirstTagInfo(this.key, this.emoji, this.label);
}

/// Katalog — getter (tr() dile göre taze; `static final` dondururdu).
List<FirstTagInfo> get kFirstTags => [
      FirstTagInfo('smile', '😊', () => tr('İlk gülümseme')),
      FirstTagInfo('roll', '🔄', () => tr('İlk dönme')),
      FirstTagInfo('sit', '🪑', () => tr('İlk oturma')),
      FirstTagInfo('crawl', '🐢', () => tr('İlk emekleme')),
      FirstTagInfo('tooth', '🦷', () => tr('İlk diş')),
      FirstTagInfo('stand', '🧍', () => tr('İlk ayakta durma')),
      FirstTagInfo('step', '👣', () => tr('İlk adım')),
      FirstTagInfo('word', '💬', () => tr('İlk kelime')),
      FirstTagInfo('food', '🥄', () => tr('İlk ek gıda')),
      FirstTagInfo('haircut', '✂️', () => tr('İlk saç kesimi')),
      FirstTagInfo('other', '⭐', () => tr('Diğer ilk')),
    ];

/// Bir anahtarın katalog bilgisini bulur (yoksa null).
FirstTagInfo? firstTagInfo(String key) {
  if (key.isEmpty) return null;
  for (final t in kFirstTags) {
    if (t.key == key) return t;
  }
  return null;
}

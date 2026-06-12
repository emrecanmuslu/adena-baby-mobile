import 'package:flutter/material.dart';

import 'theme.dart';

/// Hafif, tema-duyarlı Markdown görüntüleyici. Uzman makaleleri admin-kontrollü
/// olduğundan tam bir Markdown motoru yerine yalnız kullanılan blokları işler:
/// `#`/`##`/`###` başlık · `-`/`*` madde · `1.` numaralı · `>` not/alıntı ·
/// boş satır = paragraf · satır içi `**kalın**` ve `*italik*`.
///
/// Düz Material yerine [AppColors] tipografisini kullanır (uygulama diliyle
/// tutarlı görünmesi için).
class AdMarkdown extends StatelessWidget {
  final String data;
  const AdMarkdown(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final b in blocks) b.build(context)],
    );
  }

  List<_Block> _parse(String src) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_Block>[];
    final para = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      blocks.add(_ParagraphBlock(para.join(' ').trim()));
      para.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      final t = line.trim();
      if (t.isEmpty) {
        flushPara();
        continue;
      }
      if (t.startsWith('### ')) {
        flushPara();
        blocks.add(_HeadingBlock(t.substring(4), 3));
      } else if (t.startsWith('## ')) {
        flushPara();
        blocks.add(_HeadingBlock(t.substring(3), 2));
      } else if (t.startsWith('# ')) {
        flushPara();
        blocks.add(_HeadingBlock(t.substring(2), 1));
      } else if (t.startsWith('> ')) {
        flushPara();
        blocks.add(_QuoteBlock(t.substring(2)));
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        flushPara();
        blocks.add(_ListItemBlock(t.substring(2), null));
      } else if (_numbered.hasMatch(t)) {
        flushPara();
        final m = _numbered.firstMatch(t)!;
        blocks.add(_ListItemBlock(m.group(2)!, m.group(1)!));
      } else {
        para.add(t);
      }
    }
    flushPara();
    return blocks;
  }

  static final _numbered = RegExp(r'^(\d+)\.\s+(.*)$');
}

/// Satır içi `**kalın**` / `*italik*` → [TextSpan] listesi.
List<TextSpan> mdInlineSpans(String text, TextStyle base) {
  final spans = <TextSpan>[];
  final pattern = RegExp(r'(\*\*([^*]+)\*\*)|(\*([^*]+)\*)');
  var i = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > i) {
      spans.add(TextSpan(text: text.substring(i, m.start), style: base));
    }
    if (m.group(2) != null) {
      spans.add(TextSpan(
          text: m.group(2),
          style: base.copyWith(fontWeight: FontWeight.w900)));
    } else if (m.group(4) != null) {
      spans.add(TextSpan(
          text: m.group(4),
          style: base.copyWith(fontStyle: FontStyle.italic)));
    }
    i = m.end;
  }
  if (i < text.length) {
    spans.add(TextSpan(text: text.substring(i), style: base));
  }
  return spans;
}

abstract class _Block {
  Widget build(BuildContext context);
}

class _HeadingBlock extends _Block {
  final String text;
  final int level;
  _HeadingBlock(this.text, this.level);

  @override
  Widget build(BuildContext context) {
    final (double size, double top) = switch (level) {
      1 => (22.0, 4.0),
      2 => (17.0, 18.0),
      _ => (14.5, 14.0),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(0, top, 0, 8),
      child: Text(text,
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              height: 1.25,
              color: AppColors.ink)),
    );
  }
}

class _ParagraphBlock extends _Block {
  final String text;
  _ParagraphBlock(this.text);

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
        fontSize: 14.5,
        height: 1.55,
        fontWeight: FontWeight.w600,
        color: AppColors.ink2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Text.rich(TextSpan(children: mdInlineSpans(text, base))),
    );
  }
}

class _ListItemBlock extends _Block {
  final String text;
  final String? number; // null = madde imi
  _ListItemBlock(this.text, this.number);

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
        fontSize: 14.5,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: AppColors.ink2);
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          number == null
              ? Container(
                  margin: const EdgeInsets.only(top: 8, right: 11, left: 2),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.coral, shape: BoxShape.circle),
                )
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('$number.',
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.coralDd)),
                ),
          Expanded(
            child: Text.rich(TextSpan(children: mdInlineSpans(text, base))),
          ),
        ],
      ),
    );
  }
}

class _QuoteBlock extends _Block {
  final String text;
  _QuoteBlock(this.text);

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
        fontSize: 13.5,
        height: 1.5,
        fontWeight: FontWeight.w700,
        color: AppColors.ink2);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.feedBg,
        borderRadius: BorderRadius.circular(14),
        border: const Border(
            left: BorderSide(color: AppColors.coral, width: 3.5)),
      ),
      child: Text.rich(TextSpan(children: mdInlineSpans(text, base))),
    );
  }
}

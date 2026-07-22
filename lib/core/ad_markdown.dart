import 'package:flutter/material.dart';

import 'theme.dart';

/// Hafif, tema-duyarlı Markdown görüntüleyici. Uzman makaleleri admin-kontrollü
/// olduğundan tam bir Markdown motoru yerine yalnız kullanılan blokları işler:
/// `#`/`##`/`###` başlık · `-`/`*` madde · `1.` numaralı · `>` not/alıntı ·
/// `| a | b |` tablo (GFM-basit, hizalama yok) · boş satır = paragraf ·
/// satır içi `**kalın**` ve `*italik*`.
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

    bool isTableRow(String t) => t.startsWith('|') && t.endsWith('|') && t.length > 1;

    var i = 0;
    while (i < lines.length) {
      final t = lines[i].trimRight().trim();

      if (isTableRow(t)) {
        flushPara();
        final rows = <List<String>>[];
        while (i < lines.length) {
          final rt = lines[i].trim();
          if (!isTableRow(rt)) break;
          final cells = rt
              .substring(1, rt.length - 1)
              .split('|')
              .map((c) => c.trim())
              .toList();
          // Ayraç satırı (|---|---|) atlanır.
          if (!cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c))) {
            rows.add(cells);
          }
          i++;
        }
        if (rows.isNotEmpty) blocks.add(_TableBlock(rows));
        continue;
      }

      if (t.isEmpty) {
        flushPara();
      } else if (t.startsWith('### ')) {
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
      i++;
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

/// Basit tablo — ilk satır başlık (mercan zeminde kalın), sonraki satırlar
/// gövde (çizgiyle ayrılmış). Hizalama/rowspan yok, GFM'in en sık kullanılan
/// alt kümesi (referans tabloları için yeterli).
class _TableBlock extends _Block {
  final List<List<String>> rows;
  _TableBlock(this.rows);

  @override
  Widget build(BuildContext context) {
    final cols = rows.first.length;
    // Table widget tüm satırların hücre sayısı eşit olmasını ister — eksik/
    // fazla hücreli (bozuk içerik) satırları normalize et.
    List<String> fit(List<String> r) => List.generate(
        cols, (c) => c < r.length ? r[c] : '');
    final header = fit(rows.first);
    final body = rows.skip(1).map(fit).toList();
    final headerStyle = const TextStyle(
        fontSize: 12.5,
        height: 1.3,
        fontWeight: FontWeight.w900,
        color: AppColors.coralDd);
    final cellStyle = TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: AppColors.ink2);
    Widget cell(String text, TextStyle style) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Text(text, style: style),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: {
          for (var c = 0; c < header.length; c++)
            c: const IntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(color: AppColors.feedBg),
            children: [for (final h in header) cell(h, headerStyle)],
          ),
          for (var r = 0; r < body.length; r++)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line, width: 1)),
              ),
              children: [
                for (final c in body[r]) cell(c, cellStyle),
              ],
            ),
        ],
      ),
    );
  }
}

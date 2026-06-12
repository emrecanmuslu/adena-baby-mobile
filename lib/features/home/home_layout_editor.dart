import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/record.dart';
import '../records/record_ui.dart';
import 'home_layout.dart';

/// Hızlı Giriş / Son Aktivite kart türlerini seçtiren sheet.
/// [isQuick] true → Hızlı Giriş (quick_actions), false → Son Aktivite (home_cards).
Future<void> showHomeLayoutEditor(BuildContext context, WidgetRef ref,
    {required bool isQuick, required List<RecordType> current}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _Editor(ref: ref, isQuick: isQuick, current: current),
  );
}

class _Editor extends StatefulWidget {
  final WidgetRef ref;
  final bool isQuick;
  final List<RecordType> current;
  const _Editor(
      {required this.ref, required this.isQuick, required this.current});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final List<RecordType> _sel = [...widget.current];
  bool _saving = false;

  void _toggle(RecordType t) {
    setState(() {
      if (_sel.contains(t)) {
        if (_sel.length > 1) {
          _sel.remove(t);
        } else {
          showAdError(context, tr('En az 1 kart kalmalı.'));
        }
      } else {
        if (_sel.length < 4) {
          _sel.add(t);
        } else {
          showAdError(context, tr('En fazla 4 kart seçebilirsin.'));
        }
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final c = widget.ref.read(homeLayoutControllerProvider.notifier);
    if (widget.isQuick) {
      await c.setQuick(_sel);
    } else {
      await c.setLastActivity(_sel);
    }
    if (mounted) {
      Navigator.pop(context);
      showAdToast(context, tr('Kaydedildi'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: adGrabHandle()),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Text(
                    widget.isQuick
                        ? tr('Hızlı Giriş kartları')
                        : tr('Son Aktivite kartları'),
                    style:
                        const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 14),
                child: Text(
                    tr('Görmek istediğin türleri seç (1–4). Numara sırayı '
                        'belirtir. İpucu: yenidoğanlar çoğunlukla uyur; uyku '
                        'takibi genelde ~3-4 aydan sonra daha anlamlı olur.'),
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted)),
              ),
              for (final t in kHomeCardChoices) _row(t),
              const SizedBox(height: 6),
              AdSaveButton(
                label: _saving ? tr('Kaydediliyor…') : tr('Kaydet'),
                color: AppColors.coral,
                onTap: _saving ? () {} : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(RecordType t) {
    final sel = _sel.contains(t);
    final order = _sel.indexOf(t) + 1;
    return GestureDetector(
      onTap: () => _toggle(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? AppColors.feedBg : fieldBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: sel ? AppColors.coral : AppColors.line, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: RecordUi.bg(t), borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: AdenaIcon(RecordUi.iconName(t),
                  size: 18, color: RecordUi.color(t)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(RecordUi.label(t),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            if (sel)
              Container(
                width: 22,
                height: 22,
                decoration:
                    const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('$order',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
              )
            else
              Icon(Icons.add_circle_outline,
                  color: AppColors.muted2, size: 22),
          ],
        ),
      ),
    );
  }
}

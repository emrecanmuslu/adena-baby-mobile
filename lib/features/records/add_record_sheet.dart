import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../models/record.dart';
import 'entry_widgets.dart';
import 'record_form.dart';
import 'record_ui.dart';

/// + butonu → tüm kayıt tiplerinin ızgarası; seçince ilgili form açılır.
Future<void> showAddRecordMenu(
    BuildContext context, WidgetRef ref, String babyId) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: false,
    shape: adSheetShape,
    isScrollControlled: true, // içerik uzunsa kaydırılabilsin (taşma olmasın)
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: adGrabHandle()),
              Padding(
                padding: const EdgeInsets.only(bottom: 14, left: 2),
                child: Text(tr('Kayıt Ekle'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: RecordType.values.map((type) {
                  return _TypeCell(
                    type: type,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      showRecordForm(context, ref, babyId, type);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TypeCell extends StatelessWidget {
  final RecordType type;
  final VoidCallback onTap;
  const _TypeCell({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: fieldBg(context),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            RecordUi.chip(type, size: 46, radius: 14),
            const SizedBox(height: 8),
            Flexible(
              child: Text(RecordUi.label(type),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}


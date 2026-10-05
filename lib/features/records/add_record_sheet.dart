import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/record.dart';
import '../health/medication_widgets.dart';
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
                  // İlaç hücresi doğrudan forma değil, İlaç & Vitamin sayfasına
                  // gider: bugünün dozları + plan dışı kayıt + planları yönet.
                  if (type == RecordType.medication) {
                    return Consumer(
                      builder: (_, cellRef, _) => _TypeCell(
                        type: type,
                        label: tr('İlaç & Vitamin'),
                        pending:
                            cellRef.watch(medicationDayProvider(babyId))?.overdue ?? 0,
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          showMedicationSheet(context, ref, babyId);
                        },
                      ),
                    );
                  }
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
  final String? label;

  /// Bekleyen (saati geçmiş) doz sayısı — >0 ise köşede rozet + alt satırda
  /// "N doz bekliyor" (yalnız İlaç & Vitamin hücresi kullanır).
  final int pending;
  const _TypeCell(
      {required this.type, required this.onTap, this.label, this.pending = 0});

  @override
  Widget build(BuildContext context) {
    final cell = InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: fieldBg(context),
          borderRadius: BorderRadius.circular(18),
          border: pending > 0 ? Border.all(color: AppColors.med, width: 2) : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            RecordUi.chip(type, size: pending > 0 ? 40 : 46, radius: 14),
            SizedBox(height: pending > 0 ? 5 : 8),
            Flexible(
              child: Text(label ?? RecordUi.label(type),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
            if (pending > 0)
              Flexible(
                child: Text(trp('{n} doz bekliyor', {'n': pending}),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 9.5,
                        color: AppColors.coralDd)),
              ),
          ],
        ),
      ),
    );
    if (pending == 0) return cell;
    return Stack(
      fit: StackFit.expand,
      children: [
        cell,
        PositionedDirectional(
          top: 8,
          end: 14,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 19),
              height: 19,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fieldBg(context), width: 2),
              ),
              alignment: Alignment.center,
              child: Text('$pending',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      height: 1,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ],
    );
  }
}

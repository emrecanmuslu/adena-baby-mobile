import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/exact_alarm_prompt.dart';
import '../../core/i18n.dart';
import '../../core/medication.dart';
import '../../core/medication/dose_write.dart';
import '../../core/modal_gate.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../data/home_nudge_prefs.dart';
import '../../data/local_session.dart';
import '../../data/sync_gate.dart';
import '../../models/medication_plan.dart';
import '../../models/record.dart';
import '../auth/auth_controller.dart';
import '../babies/exact_alarm_resync.dart';
import '../babies/members_screen.dart' show membersProvider;
import '../records/record_controller.dart';
import '../records/record_form.dart';
import 'medication_plan_sheet.dart';

/// İlaç & Vitamin ortak parçaları (design/AdenaBaby Mobile/İlaç & Vitamin
/// Takibi.html): günün doz kartı, bölüm başlığı, keşif kartı, + menüsünden
/// açılan sayfa ve işaretleme/geri alma akışı. Ana sayfa, + menüsü ve yönetim
/// ekranı aynı parçaları ve aynı kuralları kullanır.

const _uuid = Uuid();

/// Dakikada bir tetiklenir — "saati geçti" / "öne çıkar" durumları kayıt
/// değişmeden, yalnız saat ilerleyince de güncellensin.
final _minuteTickProvider = StreamProvider.autoDispose<int>(
    (ref) => Stream.periodic(const Duration(minutes: 1), (i) => i));

/// Bugünün ilaç/vitamin özeti. Plan ya da bugünün kayıtları henüz yüklenmediyse
/// null (yüklenirken "saati geçti" yanıp sönmesin, bölüm yer değiştirmesin).
final medicationDayProvider =
    Provider.autoDispose.family<MedicationDay?, String>((ref, babyId) {
  ref.watch(_minuteTickProvider);
  final plans = ref.watch(medicationPlansProvider(babyId)).asData?.value;
  if (plans == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final records =
      ref.watch(dayRecordsProvider((babyId: babyId, day: today))).asData?.value;
  // İlaç v2 (M4/S6): dünün açık dozu ve gece yarısından sonra işaretlenen
  // dünkü doz için dünün kayıtları da gerekir.
  final prev =
      ref.watch(dayRecordsProvider((babyId: babyId, day: yesterday))).asData?.value;
  if (records == null || prev == null) return null;
  return medicationDay(plans, [...prev, ...records], now: now);
});

/// Ana sayfa keşif kartı kapatıldı mı (cihaz-yerel bayrak).
final medDiscoverDismissedProvider = FutureProvider<bool>(
    (ref) => HomeNudgePrefs.instance.dismissed('med_discover'));

// ───────── kim verdi ─────────

const _avatarPalette = [
  Color(0xFFE2553F),
  Color(0xFF7C6BE0),
  Color(0xFF349970),
  Color(0xFF2F92C8),
  Color(0xFFB5821C),
];

typedef MedGiver = ({String name, String initial, Color color});

/// Üye rengi (id'ye göre sabit) — akıştaki avatar paletiyle aynı.
Color medAvatarColor(String id) => _avatarPalette[id.hashCode.abs() % _avatarPalette.length];

/// Dozu BAŞKA bir aile üyesi verdiyse onun adı/baş harfi/rengi; kendi kaydıysa
/// (ya da henüz senkronlanmamış yerel kayıtsa — createdBy null) null. Üye
/// listesi yüklenemediyse ad boş, baş harf "?" döner (yine "başkası" sayılır).
/// [watch] false → build dışı (dokunma işleyicisi) kullanım.
MedGiver? medOtherGiver(WidgetRef ref, String babyId, Record? record,
    {bool watch = true}) {
  final cb = record?.createdBy;
  if (cb == null) return null;
  final me = (watch ? ref.watch(authControllerProvider) : ref.read(authControllerProvider))
      .asData
      ?.value;
  final localId = watch ? ref.watch(localUserIdProvider) : ref.read(localUserIdProvider);
  if (cb == me?.id || cb == localId) return null;
  final members =
      (watch ? ref.watch(membersProvider(babyId)) : ref.read(membersProvider(babyId)))
              .asData
              ?.value ??
          const [];
  final color = _avatarPalette[cb.hashCode.abs() % _avatarPalette.length];
  for (final m in members) {
    if (m.user.id == cb) {
      final name = m.user.displayName;
      return (
        name: name,
        initial: (name.characters.firstOrNull ?? '?').toUpperCaseTr(),
        color: color,
      );
    }
  }
  return (name: '', initial: '?', color: color);
}

// ───────── işaretleme / atlama / düzeltme (İlaç v2) ─────────

/// Doza dokunma (ILAC-TASARIM §5.2):
/// - İşaretlenmiş doz → doz sayfası (kayıtlar, saat düzelt, geri al, K3).
/// - Çözülmemiş doz → "verildi" (K3 çift doz denetimiyle); saatine 2 saatten
///   fazla varsa önce onay (S9).
Future<void> medTapDose(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) async {
  if (dose.isResolved) return _showDoseSheet(context, ref, babyId, dose);
  if (!await _confirmEarly(context, dose)) return;
  if (!context.mounted) return;
  await _markGiven(context, ref, babyId, dose);
}

/// Çözülmemiş doza uzun basma → "Verildi / Bu dozu atla" seçenekleri.
Future<void> medLongPressDose(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) async {
  if (dose.isResolved) return _showDoseSheet(context, ref, babyId, dose);
  final skip = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => _SheetFrame(
      title: _doseTitle(dose),
      children: [
        Text(
            tr('Bilinçli olarak verilmediyse atla. Atlanan doz "saati geçti" '
                'uyarısından çıkar, ailen de görür.'),
            style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.muted)),
        const SizedBox(height: 16),
        AdSaveButton(
            label: tr('Verildi olarak işaretle'),
            color: AppColors.coral,
            onTap: () => Navigator.pop(ctx, false)),
        const SizedBox(height: 10),
        AdSaveButton(
            label: tr('Bu dozu atla'),
            color: AppColors.coralDd,
            ghost: true,
            onTap: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (skip == null || !context.mounted) return;
  if (skip) return _markSkipped(context, ref, babyId, dose);
  if (!await _confirmEarly(context, dose) || !context.mounted) return;
  await _markGiven(context, ref, babyId, dose);
}

/// Çözülmemiş dozu "atlandı" işaretler (satırdaki "Atla" bağlantısı) — önce
/// isteğe bağlı neden (K10).
Future<void> medSkipDose(
        BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) =>
    dose.isResolved ? Future.value() : _markSkipped(context, ref, babyId, dose);

String _doseTitle(MedicationDose d) => d.fromYesterday
    ? trp('{name} · dün {t} dozu', {'name': d.plan.name, 't': d.time})
    : trp('{name} · {t} dozu', {'name': d.plan.name, 't': d.time});

/// S9: saatine 2 saatten fazla olan dozu işaretlemeden önce onay.
Future<bool> _confirmEarly(BuildContext context, MedicationDose dose) async {
  if (dose.role != MedicationDoseRole.early) return true;
  final ok = await _confirm(
    context,
    title: tr('Erken işaretleme'),
    body: trp('Bu doz {t} için. Şimdi verildi olarak işaretlensin mi?', {'t': dose.time}),
    yes: tr('Verildi olarak işaretle'),
  );
  return ok;
}

Future<bool> _confirm(BuildContext context,
    {required String title, required String body, required String yes}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Vazgeç'),
                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes,
                style: const TextStyle(color: AppColors.coralDd, fontWeight: FontWeight.w900))),
      ],
    ),
  );
  return ok == true;
}

/// Kaydı kimin girdiği — kısa ad ("Sen" / üye adı / "Başka bir aile üyesi").
String medWhoName(WidgetRef ref, String babyId, Record r) {
  final other = medOtherGiver(ref, babyId, r, watch: false);
  if (other == null) return tr('Sen');
  return other.name.isEmpty ? tr('Başka bir aile üyesi') : other.name;
}

String _ago(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h > 0 && m > 0) return trp('{h} sa {m} dk', {'h': h, 'm': m});
  if (h > 0) return trp('{h} sa', {'h': h});
  return trp('{m} dk', {'m': m});
}

/// K3 denetimi için yakın kayıtlar — kartın izlediği akışlardan (bugün + dün),
/// BEKLEMEDEN (dokunma gecikmesin). [extra]: çağıranın elindeki kayıtlar (doz
/// nesnesindekiler, PRN kartının izlediği geniş pencere).
List<Record> _recentRecords(WidgetRef ref, String babyId, [Iterable<Record> extra = const []]) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final out = <String, Record>{for (final r in extra) r.id: r};
  for (final day in [today, DateTime(now.year, now.month, now.day - 1)]) {
    final recs = ref.read(dayRecordsProvider((babyId: babyId, day: day))).asData?.value;
    for (final r in recs ?? const <Record>[]) {
      out[r.id] = r;
    }
  }
  return out.values.toList();
}

/// K3: "verildi" yazmadan önce çift doz uyarısı. true → yazılabilir.
Future<bool> medConfirmNotDuplicate(BuildContext context, WidgetRef ref, String babyId,
    MedicationPlan plan, MedicationDose? dose, {Iterable<Record> extra = const []}) async {
  final recent = _recentRecords(ref, babyId, [...?dose?.records, ...extra]);
  final now = DateTime.now();
  final hit = medDuplicateCheck(plan, dose, recent, now: now);
  if (hit == null || !context.mounted) return hit == null;
  final who = medWhoName(ref, babyId, hit.record);
  final at = fmtTime(hit.record.ts);
  final body = hit.sameDose
      ? trp('Bu doz {who} tarafından verildi · {time}. Yine de kaydedilsin mi?',
          {'who': who, 'time': at})
      : trp('Bu ilaç {ago} önce {who} tarafından verildi · {time}. Yine de kaydedilsin mi?',
          {'ago': _ago(now.difference(hit.record.ts)), 'who': who, 'time': at});
  return _confirm(context,
      title: tr('Bu doz zaten verildi'), body: body, yes: tr('Yine de kaydet'));
}

/// O22: aynı doz için uçuş-içi / çift-dokunma koruması. Drift akışı yeni kaydı
/// yayınlayana kadar ikinci dokunuş da çözülmemiş dozu görür → hayalet ikinci
/// "verildi" kaydı.
final _inFlightDoses = <String>{};
const _doseGuard = Duration(seconds: 2);

bool _claim(String key) {
  if (_inFlightDoses.contains(key)) return false;
  _inFlightDoses.add(key);
  // Akış güncellenene dek kısa koruma; hata olsa da serbest kalır.
  Future<void>.delayed(_doseGuard, () => _inFlightDoses.remove(key));
  return true;
}

/// "Verildi" kaydı (kimlikli, ILAC-TASARIM §1b). [force] → K3 denetimi atlanır
/// (çağıran zaten onay aldı).
Future<void> _markGiven(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose,
    {bool force = false}) async {
  if (!_claim(dose.key)) return;
  if (!force && !await medConfirmNotDuplicate(context, ref, babyId, dose.plan, dose)) return;
  if (!context.mounted) return;
  await _write(context, ref, babyId, dose, skipped: false);
}

Future<void> _markSkipped(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) async {
  final r = await showMedSkipReasonSheet(context, dose);
  if (r == null || !context.mounted) return;
  if (!_claim(dose.key)) return;
  await _write(context, ref, babyId, dose, skipped: true, reason: r.reason, note: r.note);
}

Future<void> _write(BuildContext context, WidgetRef ref, String babyId, MedicationDose dose,
    {required bool skipped, MedSkipReason? reason, String? note}) async {
  final actions = ref.read(recordActionsProvider);
  final rec = medDoseRecord(
    id: _uuid.v4(),
    babyId: babyId,
    plan: dose.plan,
    doseDate: dose.doseDate,
    doseTime: dose.time,
    at: DateTime.now(),
    skipped: skipped,
    reason: reason,
    note: note,
  );
  await actions.upsertQuiet(rec);
  if (!context.mounted) return;
  showAdToast(
    context,
    trp(skipped ? '{name} · {t} atlandı' : '{name} · {t} verildi',
        {'name': dose.plan.name, 't': dose.time}),
    type: skipped ? AdToastType.info : AdToastType.success,
    duration: const Duration(seconds: 4),
    onUndo: () => actions.delete(rec.id),
  );
}

/// Atlama nedeni seçimi (K10, isteğe bağlı). null → vazgeçildi.
Future<({MedSkipReason? reason, String? note})?> showMedSkipReasonSheet(
    BuildContext context, MedicationDose dose) {
  return showModalBottomSheet<({MedSkipReason? reason, String? note})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _SkipReasonSheet(title: _doseTitle(dose)),
    ),
  );
}

String medSkipReasonLabel(MedSkipReason r) => switch (r) {
      MedSkipReason.vomited => tr('Kustu'),
      MedSkipReason.asleep => tr('Uyuyordu'),
      MedSkipReason.outOfStock => tr('İlaç bitti'),
      MedSkipReason.doctor => tr('Doktor önerisi'),
      MedSkipReason.other => tr('Diğer'),
    };

/// Kayıttaki atlama nedeni metni ("Diğer" + not → not).
String? medSkipReasonText(Record r) {
  final reason = MedSkipReason.fromWire(r.data['skip_reason'] as String?);
  if (reason == null) return null;
  final note = (r.data['skip_note'] as String?)?.trim();
  if (reason == MedSkipReason.other && note != null && note.isNotEmpty) return note;
  return medSkipReasonLabel(reason);
}

class _SkipReasonSheet extends StatefulWidget {
  final String title;
  const _SkipReasonSheet({required this.title});
  @override
  State<_SkipReasonSheet> createState() => _SkipReasonSheetState();
}

class _SkipReasonSheetState extends State<_SkipReasonSheet> {
  MedSkipReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: widget.title,
      children: [
        Text(tr('Neden atlandı? (isteğe bağlı)'),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in MedSkipReason.values)
              ChoiceChip(
                label: Text(medSkipReasonLabel(r)),
                selected: _reason == r,
                onSelected: (v) => setState(() => _reason = v ? r : null),
              ),
          ],
        ),
        if (_reason == MedSkipReason.other) ...[
          const SizedBox(height: 10),
          AdInput(
            controller: _note,
            hint: tr('Kısa not (isteğe bağlı)'),
            formatters: [LengthLimitingTextInputFormatter(kMedSkipNoteMax)],
            capitalization: TextCapitalization.sentences,
          ),
        ],
        const SizedBox(height: 16),
        AdSaveButton(
            label: tr('Bu dozu atla'),
            color: AppColors.coralDd,
            onTap: () => Navigator.pop(context, (reason: _reason, note: _note.text))),
      ],
    );
  }
}

/// Sayfa iskeleti: tutamak + ilaç ikonlu başlık + içerik.
class _SheetFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SheetFrame({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2, bottom: 12),
              child: Row(
                children: [
                  AdIconChip('med', color: AppColors.med, bg: AppColors.medBg, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

Future<void> _showDoseSheet(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _DoseSheet(babyId: babyId, dose: dose),
  );
}

/// İşaretlenmiş dozun sayfası (İlaç v2): bağlı TÜM kayıtlar (kim, saat, neden);
/// çift işaret uyarısı; kayıt başına saat düzeltme / sil (M16: bakıcı yalnız
/// kendi kaydını); atlananı "verildi"ye çevirme; "yine de verildi" (K3).
class _DoseSheet extends ConsumerStatefulWidget {
  final String babyId;
  final MedicationDose dose;
  const _DoseSheet({required this.babyId, required this.dose});

  @override
  ConsumerState<_DoseSheet> createState() => _DoseSheetState();
}

class _DoseSheetState extends ConsumerState<_DoseSheet> {
  MedicationDose get _dose => widget.dose;

  /// M16: tam yazma (sahip/ebeveyn) her kaydı, bakıcı yalnız kendi kaydını.
  bool _canModify(Record r) =>
      ref.read(canFullWriteProvider(widget.babyId)) ||
      medOtherGiver(ref, widget.babyId, r, watch: false) == null;

  Future<void> _editTime(Record r) async {
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(r.ts));
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    var t = DateTime(r.ts.year, r.ts.month, r.ts.day, picked.hour, picked.minute);
    // Gece yarısı: seçilen saat bugün için gelecekteyse önceki gün kastedilmiştir.
    if (t.isAfter(now)) t = DateTime(t.year, t.month, t.day - 1, t.hour, t.minute);
    if (t.isAfter(now)) {
      showAdError(context, tr('Gelecek bir saat seçilemez'));
      return;
    }
    if (t.isBefore(_dose.dueAt.subtract(kMedOpenWindow))) {
      showAdError(context, tr('Bu saat dozun saatinden çok önce'));
      return;
    }
    final data = Map<String, dynamic>.from(r.data)
      ..['at_hm'] = fmtTime(t)
      ..remove('time_assumed');
    await ref.read(recordActionsProvider).upsertQuiet(r.copyWith(ts: t, data: data));
    if (!mounted) return;
    Navigator.pop(context);
    showAdToast(context, tr('Saat güncellendi'));
  }

  Future<void> _undo(Record r) async {
    await ref.read(recordActionsProvider).delete(r.id);
    if (!mounted) return;
    Navigator.pop(context);
    showAdToast(context, tr('Geri alındı'), type: AdToastType.info);
  }

  Future<void> _skipToGiven(Record r) async {
    final data = Map<String, dynamic>.from(r.data)
      ..remove('skipped')
      ..remove('skip_reason')
      ..remove('skip_note')
      ..['given'] = true;
    await ref.read(recordActionsProvider).upsertQuiet(r.copyWith(data: data));
    if (!mounted) return;
    Navigator.pop(context);
    showAdToast(
        context, trp('{name} · {t} verildi', {'name': _dose.plan.name, 't': _dose.time}));
  }

  Future<void> _givenAnyway() async {
    final nav = Navigator.of(context);
    if (!await medConfirmNotDuplicate(context, ref, widget.babyId, _dose.plan, _dose)) return;
    if (!mounted) return;
    nav.pop();
    if (!context.mounted) return;
    await _markGiven(context, ref, widget.babyId, _dose, force: true);
  }

  Widget _recordRow(Record r) {
    final skipped = r.data['skipped'] == true;
    final who = medWhoName(ref, widget.babyId, r);
    final reason = skipped ? medSkipReasonText(r) : null;
    final assumed = r.data['time_assumed'] == true;
    final can = _canModify(r);
    final muted = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted);
    final action = TextStyle(
        fontSize: 12.5, fontWeight: FontWeight.w900, color: AppColors.coralDark);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: fieldBg(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdenaIcon(skipped ? 'close' : 'check',
                  size: 18, color: skipped ? AppColors.muted : AppColors.growth),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    skipped
                        ? trp('{who} · atlandı', {'who': who})
                        : trp('{who} · verildi', {'who': who}),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              Text(fmtTime(r.ts),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          if (reason != null || assumed)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 28, top: 2),
              child: Text(
                  [?reason, if (assumed) tr('Plan saatinde kaydedildi')].join(' · '),
                  style: muted),
            ),
          if (can)
            Wrap(
              spacing: 4,
              children: [
                if (!skipped)
                  TextButton(
                      onPressed: () => _editTime(r),
                      child: Text(tr('Saati düzelt'), style: action)),
                if (skipped)
                  TextButton(
                      onPressed: () => _skipToGiven(r),
                      child: Text(tr('Verildi yap'), style: action)),
                TextButton(
                    onPressed: () => _undo(r),
                    child: Text(tr('Kaydı geri al'), style: action)),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
        fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w700, color: AppColors.muted);
    final others = _dose.records.any((r) => medOtherGiver(ref, widget.babyId, r) != null);
    return _SheetFrame(
      title: _doseTitle(_dose),
      children: [
        if (_dose.multiple)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.feverBg, borderRadius: BorderRadius.circular(13)),
            child: Text(
                trp('Bu doz {n} kez verildi olarak işaretlendi. Gerçekten iki kez verildiyse doktoruna danış.',
                    {'n': _dose.givenRecords.length}),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.coralDd)),
          ),
        AdField(
          label: tr('Verildiği saat'),
          child: Column(children: [for (final r in _dose.records) _recordRow(r)]),
        ),
        if (_dose.conflict)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr('Hem verildi hem atlandı işaretlenmiş; verildi sayılır.'), style: muted),
          ),
        if (others)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr('Geri alırsan ailede herkes için silinir.'), style: muted),
          ),
        const SizedBox(height: 6),
        AdSaveButton(
            label: tr('Tamam'), color: AppColors.coral, onTap: () => Navigator.pop(context)),
        const SizedBox(height: 10),
        AdSaveButton(
            label: tr('Yine de verildi olarak kaydet'),
            color: AppColors.coralDd,
            ghost: true,
            onTap: _givenAnyway),
      ],
    );
  }
}

// ───────── küçük parçalar ─────────

/// RTL'de aynalanan "ileri" oku.
String medChevron(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl ? 'chevL' : 'chevR';

/// Kesikli çerçeve (daire ya da yuvarlak-köşe) — "henüz sırası gelmedi" /
/// "ekle" / "duraklatıldı" görünümü.
class MedDashedBorder extends CustomPainter {
  final Color color;
  final double radius; // double.infinity → tam yuvarlak
  final double width;
  const MedDashedBorder({required this.color, required this.radius, this.width = 1.5});

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius.isFinite ? radius : size.shortestSide / 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(width / 2), Radius.circular(r)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    const dash = 4.0, gap = 3.5;
    for (final PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(MedDashedBorder old) =>
      old.color != color || old.radius != radius || old.width != width;
}

/// Hap biçimli çip (öneri / "Başka ekle" / "Saat ekle").
class MedChip extends StatelessWidget {
  final String label;
  final String? icon;
  final bool selected;
  final bool dashed;
  final double height;
  final VoidCallback onTap;
  const MedChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.dashed = false,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? AppColors.coralDd
        : (dashed ? AppColors.coralDark : AppColors.ink2);
    final body = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: dashed
          ? null
          : BoxDecoration(
              color: selected ? AppColors.feedBg : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: selected ? AppColors.coral : AppColors.line, width: 1.5),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AdenaIcon(icon!, size: 14, color: fg, sw: 2.4),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: fg)),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: dashed
            ? CustomPaint(
                painter: MedDashedBorder(color: AppColors.line2, radius: double.infinity),
                child: body)
            : body,
      ),
    );
  }
}

/// Küçük üye rozeti (baş harf) — doz düğmesi/çipi köşesinde "kim verdi".
class MedWhoDot extends StatelessWidget {
  final MedGiver who;
  final double size;
  final bool ring;
  const MedWhoDot(this.who, {super.key, this.size = 19, this.ring = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: who.color,
        shape: BoxShape.circle,
        border: ring
            ? Border.all(color: Theme.of(context).colorScheme.surface, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(who.initial,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1,
              fontSize: size * 0.47)),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int done;
  final int total;
  const _CountPill({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppColors.smallShadow,
      ),
      child: Text('$done/$total',
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: AppColors.ink2,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// Bölüm başlığı: "İLAÇ & VİTAMİN" + verilen/toplam + sağda "Planlar ›".
class MedSectionHeader extends StatelessWidget {
  final String title;
  final MedicationDay? day;
  final VoidCallback? onPlans;
  final double top;
  const MedSectionHeader(
      {super.key, required this.title, this.day, this.onPlans, this.top = 18});

  @override
  Widget build(BuildContext context) {
    final d = day;
    return Padding(
      padding: EdgeInsets.fromLTRB(3, top, 3, 10),
      child: Row(
        children: [
          // Başlık + sayaç solda kalan alanı doldurur; "Planlar" hep en sağda.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(title.toUpperCaseTr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.muted,
                          letterSpacing: 0.7)),
                ),
                if (d != null && d.total > 0) ...[
                  const SizedBox(width: 8),
                  _CountPill(done: d.done, total: d.total),
                ],
              ],
            ),
          ),
          if (onPlans != null) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPlans,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Planlar'),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.coralDark)),
                      const SizedBox(width: 2),
                      AdenaIcon(medChevron(context),
                          size: 13, color: AppColors.coralDark, sw: 2.4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────── doz düğmesi ─────────

/// Saati geçmiş sıradaki dozun etrafındaki nazik nabız halkası. Sistem
/// "hareketi azalt" açıksa sabit kalır.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        // 0→.5: halka açılıp söner, .5→1: dinlenir.
        final t = (_c.value * 2).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.coral.withValues(alpha: 0.45 * (1 - t)),
                spreadRadius: 6 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Dozun görsel tonu — düğme (ana sayfa) ve çip (yönetim) ortak kullanır.
/// Bilgi üçlü verilir: renk + simge + metin (gece yarı uykulu okunabilsin).
({Color bg, Color? border, bool dashed, Color text, bool faded}) _doseTone(
    MedicationDose d) {
  final next = d.role == MedicationDoseRole.next;
  switch (d.status) {
    case MedicationDoseStatus.given:
      return (
        bg: AppColors.growth,
        border: null,
        dashed: false,
        text: AppColors.growth,
        faded: false
      );
    case MedicationDoseStatus.skipped:
      return (
        bg: AppColors.line,
        border: null,
        dashed: false,
        text: AppColors.muted,
        faded: false
      );
    case MedicationDoseStatus.overdue:
    case MedicationDoseStatus.missed: // kartta görünmez (geçmiş ekranı)
      return (
        bg: AppColors.feverBg,
        border: AppColors.coral,
        dashed: false,
        text: AppColors.coralDd,
        faded: !next
      );
    case MedicationDoseStatus.upcoming:
      return next
          ? (
              bg: AppColors.medBg,
              border: AppColors.med,
              dashed: false,
              text: AppColors.med,
              faded: false
            )
          : (
              bg: Colors.transparent,
              border: AppColors.line2,
              dashed: true,
              text: AppColors.muted,
              faded: true
            );
  }
}

String _doseSemantics(MedicationDose d) => switch (d.status) {
      MedicationDoseStatus.given => trp('Verildi · {t}', {'t': d.time}),
      MedicationDoseStatus.skipped => trp('Atlandı · {t}', {'t': d.time}),
      MedicationDoseStatus.overdue ||
      MedicationDoseStatus.missed =>
        trp('Saati geçti · {t}', {'t': d.time}),
      MedicationDoseStatus.upcoming => trp('Planlanan · {t}', {'t': d.time}),
    };

/// Ana sayfa doz düğmesi: 46×58 dokunma hedefi, 40px daire + altında saat.
class MedDoseButton extends ConsumerWidget {
  final String babyId;
  final MedicationDose dose;
  const MedDoseButton({super.key, required this.babyId, required this.dose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dose;
    final tone = _doseTone(d);
    final who = d.isResolved ? medOtherGiver(ref, babyId, d.record) : null;

    Widget circle = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tone.bg,
        shape: BoxShape.circle,
        border: tone.border != null && !tone.dashed
            ? Border.all(color: tone.border!, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: d.isGiven
          ? const AdenaIcon('check', size: 20, color: Colors.white, sw: 2.8)
          : (d.isSkipped
              ? AdenaIcon('close', size: 16, color: AppColors.muted, sw: 2.4)
              : null),
    );
    if (tone.dashed) {
      circle = CustomPaint(
        foregroundPainter:
            MedDashedBorder(color: tone.border!, radius: double.infinity, width: 2),
        child: circle,
      );
    }
    if (tone.faded) circle = Opacity(opacity: 0.6, child: circle);
    if (d.isOverdue && d.role == MedicationDoseRole.next) circle = _Pulse(child: circle);

    return Semantics(
      // İlaç v2: her doz dokunulabilir (erken doz onay ister — S9).
      button: true,
      label: '${d.plan.name} · ${_doseSemantics(d)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => medTapDose(context, ref, babyId, d),
        onLongPress: () => medLongPressDose(context, ref, babyId, d),
        // 46×58 en küçük hedef; büyük sistem yazı boyutunda saat etiketi
        // büyürse düğme uzar (taşmaz), genişlik sabit kalır.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58, minWidth: 46, maxWidth: 46),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  circle,
                  if (who != null)
                    PositionedDirectional(bottom: -4, end: -5, child: MedWhoDot(who)),
                ],
              ),
              const SizedBox(height: 4),
              Text(d.time,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: tone.text,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yönetim ekranı saat çipi — aynı kurallar, hap biçimi.
class MedTimeChip extends ConsumerWidget {
  final String babyId;
  final MedicationDose dose;
  const MedTimeChip({super.key, required this.babyId, required this.dose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dose;
    final tone = _doseTone(d);
    final who = d.isResolved ? medOtherGiver(ref, babyId, d.record) : null;
    final given = d.isGiven;

    Widget chip = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: given ? AppColors.growthBg : tone.bg,
        borderRadius: BorderRadius.circular(999),
        border: !given && tone.border != null && !tone.dashed
            ? Border.all(color: tone.border!, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (given) ...[
            AdenaIcon('check', size: 14, color: tone.text, sw: 2.8),
            const SizedBox(width: 6),
          ] else if (d.isSkipped) ...[
            AdenaIcon('close', size: 12, color: tone.text, sw: 2.4),
            const SizedBox(width: 6),
          ],
          Text(d.time,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: tone.text,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (who != null) ...[
            const SizedBox(width: 6),
            MedWhoDot(who, size: 16, ring: false),
          ],
        ],
      ),
    );
    if (tone.dashed) {
      chip = CustomPaint(
        foregroundPainter: MedDashedBorder(color: tone.border!, radius: double.infinity),
        child: chip,
      );
    }
    return Semantics(
      // İlaç v2: her doz dokunulabilir (erken doz onay ister — S9).
      button: true,
      label: _doseSemantics(d),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => medTapDose(context, ref, babyId, d),
        onLongPress: () => medLongPressDose(context, ref, babyId, d),
        child: chip,
      ),
    );
  }
}

// ───────── gün kartı ─────────

/// Günün doz kartı: üstte gün çubuğu (her doz bir segment), saati geçen varsa
/// uyarı şeridi, her plan bir satır, her saat bir düğme. Hepsi verildiyse tek
/// satıra iner; 3'ten fazla planda tamamlananlar "+N plan" satırında toplanır.
/// [flat] → sayfa (sheet) içinde gölgesiz/alan zeminli.
class MedDayCard extends ConsumerStatefulWidget {
  final String babyId;
  final MedicationDay day;
  final bool flat;
  const MedDayCard({super.key, required this.babyId, required this.day, this.flat = false});

  @override
  ConsumerState<MedDayCard> createState() => _MedDayCardState();
}

class _MedDayCardState extends ConsumerState<MedDayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final decoration = BoxDecoration(
      color: widget.flat ? fieldBg(context) : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      boxShadow: widget.flat ? null : AppColors.softShadow,
    );

    if (day.allDone && !_expanded) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: _doneRow(day),
      );
    }

    final hideDone = day.rows.length > 3 && !_expanded;
    final doneRows = day.rows.where((r) => r.complete).toList();
    final shown = hideDone ? day.rows.where((r) => !r.complete).toList() : day.rows;

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(day),
          if (day.overdue > 0) _strip(day.overdue),
          for (var i = 0; i < shown.length; i++)
            _PlanRow(babyId: widget.babyId, row: shown[i], divider: i > 0),
          if (hideDone && doneRows.isNotEmpty)
            _FootRow(
              leading: _CheckStack(count: doneRows.length.clamp(1, 3)),
              label: trp('+{n} plan · bugün tamam', {'n': doneRows.length}),
              up: false,
              onTap: () => setState(() => _expanded = true),
            ),
          if (_expanded && (day.rows.length > 3 || day.allDone))
            _FootRow(
              label: tr('Daha az göster'),
              up: true,
              onTap: () => setState(() => _expanded = false),
            ),
        ],
      ),
    );
  }

  Widget _bar(MedicationDay day) {
    final segs = day.timeline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 3),
      child: Row(
        children: [
          for (var i = 0; i < segs.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: switch (segs[i].status) {
                    MedicationDoseStatus.given => AppColors.growth,
                    MedicationDoseStatus.skipped => AppColors.muted2,
                    MedicationDoseStatus.overdue ||
                    MedicationDoseStatus.missed =>
                      AppColors.coral,
                    MedicationDoseStatus.upcoming => AppColors.line,
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _strip(int n) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: AppColors.feverBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                n == 1
                    ? tr('1 dozun saati geçti — verdiysen dokun')
                    : trp('{n} dozun saati geçti — verdiysen dokun', {'n': n}),
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: AppColors.coralDd)),
          ),
        ],
      ),
    );
  }

  Widget _doneRow(MedicationDay day) {
    // Dozu veren diğer aile üyeleri (tekrarsız) — "kim verdi" bir bakışta.
    final givers = <String, MedGiver>{};
    for (final d in day.timeline) {
      final g = medOtherGiver(ref, widget.babyId, d.record);
      if (g != null) givers[d.record!.createdBy!] = g;
    }
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.growthBg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const AdenaIcon('check', size: 22, color: AppColors.growth, sw: 2.8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Bugünün dozları tamam'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      trp('{done}/{total} verildi · yarın ilk doz {t}',
                          {'done': day.done, 'total': day.total, 't': day.firstTime}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
            for (final g in givers.values.take(3))
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 3),
                child: MedWhoDot(g, size: 22, ring: false),
              ),
            const SizedBox(width: 8),
            AdenaIcon('chevD', size: 16, color: AppColors.muted2),
          ],
        ),
      ),
    );
  }
}

/// Bir planın satırı: ikon + ad·doz + durum metni + doz düğmeleri.
class _PlanRow extends ConsumerWidget {
  final String babyId;
  final MedicationPlanDay row;
  final bool divider;
  const _PlanRow({required this.babyId, required this.row, required this.divider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = row.plan;
    final late = row.firstOverdue;
    final (String text, Color color) = () {
      if (late != null) {
        return (trp('Saati geçti · {t}', {'t': late.time}), AppColors.coralDd);
      }
      if (row.complete) {
        final g = row.lastResolved!;
        if (g.isSkipped) {
          return (trp('Atlandı · {t}', {'t': g.time}), AppColors.muted);
        }
        final at = fmtTime(g.record!.ts);
        final who = medOtherGiver(ref, babyId, g.record);
        return (
          who != null && who.name.isNotEmpty
              ? trp('Verildi · {t} · {who}', {'t': at, 'who': who.name})
              : trp('Verildi · {t}', {'t': at}),
          AppColors.growth,
        );
      }
      final k = row.givenCount, n = row.doses.length;
      return (
        n > 1 && k > 0
            ? trp('Sıradaki · {t} · {k}/{n}', {'t': row.next!.time, 'k': k, 'n': n})
            : trp('Sıradaki · {t}', {'t': row.next!.time}),
        AppColors.muted,
      );
    }();

    // 3+ dozda düğmeler alt satıra geçer: dar telefonda ad/durum (ve "Atla")
    // sıkışmasın, düğmeler küçülmesin.
    final wide = row.doses.length > 2;
    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: p.name,
              children: [
                if (p.dose.isNotEmpty)
                  TextSpan(
                      text: ' · ${p.dose}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.muted)),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, height: 1.25),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
              ),
              // Saati geçen doz bilinçli verilmediyse tek dokunuşla "atlandı".
              if (late != null && !late.isResolved)
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => medSkipDose(context, ref, babyId, late),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 6, 4),
                      child: Text(tr('Atla'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink2,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.muted2)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    final doses = [
      for (final d in row.doses) MedDoseButton(babyId: babyId, dose: d),
    ];

    return Container(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: AppColors.line)) : null,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 7),
      child: Column(
        children: [
          Row(
            children: [
              AdIconChip('med', color: AppColors.med, bg: AppColors.medBg),
              const SizedBox(width: 12),
              info,
              if (!wide) ...[
                const SizedBox(width: 8),
                Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: doses),
              ],
            ],
          ),
          if (wide)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 50),
                child: Wrap(spacing: 4, children: doses),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckStack extends StatelessWidget {
  final int count;
  const _CheckStack({required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16.0 + (count - 1) * 11,
      height: 16,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            PositionedDirectional(
              start: i * 11.0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.growth,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: const AdenaIcon('check', size: 8, color: Colors.white, sw: 3.4),
              ),
            ),
        ],
      ),
    );
  }
}

class _FootRow extends StatelessWidget {
  final Widget? leading;
  final String label;
  final bool up;
  final VoidCallback onTap;
  const _FootRow({required this.label, required this.up, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.muted)),
            ),
            RotatedBox(
              quarterTurns: up ? 2 : 0,
              child: AdenaIcon('chevD', size: 15, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────── keşif kartı (plan yok) ─────────

/// Hiç plan yokken ana sayfada modülü keşfettiren, kapatılabilir kart. Öneri
/// çipleri adı dolu bir "Yeni plan" sayfası açar.
class MedDiscoverCard extends ConsumerWidget {
  final String babyId;
  const MedDiscoverCard({super.key, required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.smallShadow,
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [AppColors.medBg, surface],
          stops: const [0, 0.85],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 28),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: AppColors.smallShadow,
                        ),
                        alignment: Alignment.center,
                        child: const AdenaIcon('med', size: 21, color: AppColors.med, sw: 1.9),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(tr('Her gün verdiğin vitaminleri takip et'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 14.5, height: 1.25)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 9, bottom: 11),
                  child: Text(
                      tr('Saatini kur, hatırlatalım. Tek dokunuşla işaretle; ailen '
                          'de görsün, çift doz verilmesin.'),
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
                ),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final s in medicationSuggestions().take(3))
                      MedChip(
                        label: s.name,
                        icon: 'plus',
                        onTap: () => showMedicationPlanSheet(context, babyId,
                            presetName: s.name, presetTime: s.time),
                      ),
                    MedChip(
                      label: tr('Başka ekle'),
                      dashed: true,
                      onTap: () => showMedicationPlanSheet(context, babyId),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Semantics(
              button: true,
              label: tr('Kapat'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await HomeNudgePrefs.instance.dismiss('med_discover');
                  ref.invalidate(medDiscoverDismissedProvider);
                },
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                      child: AdenaIcon('close', size: 16, color: AppColors.muted, sw: 2.2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── ana sayfa bölümü ─────────

/// Ana sayfa "İlaç & Vitamin" bölümü. Aktif plan varsa günün doz kartı; hiç
/// plan yoksa (ve kapatılmadıysa) keşif kartı; aksi halde gizli. Bölümün
/// sayfadaki YERİ çağıran tarafından [medicationDayProvider]`.promote`'a göre
/// seçilir (bkz. home_screen.dart _HomeTab).
/// M14: ilaç planı bu cihaza SENKRONLA gelse de (planı oluşturan cihaz değil)
/// kesin alarm açıklaması bir kez gösterilsin. Testler üreticiyi değiştirir.
@visibleForTesting
ExactAlarmPrompt Function(WidgetRef ref) medExactPromptFactory = (ref) =>
    ExactAlarmPrompt(onGranted: () => resyncAfterExactAlarmGranted(ref));
bool _medExactTried = false;
@visibleForTesting
void resetMedExactPromptForTest() => _medExactTried = false;

void _maybePromptExact(BuildContext context, WidgetRef ref) {
  if (_medExactTried) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (_medExactTried || ModalGate.isBlocked || !context.mounted) return;
    _medExactTried = true; // oturumda bir kez dene (kalıcı bayrak prompt'ta)
    await medExactPromptFactory(ref).maybeShow(context);
  });
}

class MedHomeSection extends ConsumerWidget {
  final String babyId;
  const MedHomeSection({super.key, required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(medicationDayProvider(babyId));
    if (day == null) return const SizedBox.shrink();
    void openPlans() => context.push('/medications');

    if (day.rows.isNotEmpty) _maybePromptExact(context, ref);
    if (day.hasActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MedSectionHeader(title: tr('İlaç & Vitamin'), day: day, onPlans: openPlans),
          MedDayCard(babyId: babyId, day: day),
        ],
      );
    }
    // Yalnız duraklatılmış planı olan kullanıcı modülü zaten biliyor → keşif yok.
    if (day.planCount > 0) return const SizedBox.shrink();
    final dismissed = ref.watch(medDiscoverDismissedProvider).asData?.value ?? true;
    if (dismissed) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MedSectionHeader(title: tr('İlaç & Vitamin'), onPlans: openPlans),
        MedDiscoverCard(babyId: babyId),
      ],
    );
  }
}

// ───────── + menüsü → İlaç & Vitamin sayfası ─────────

/// + → İlaç & Vitamin: bugünün dozları (işaretlenebilir) + plan dışı tek
/// seferlik kayıt + planları yönet. [context]/[ref] sayfa kapandıktan sonra da
/// geçerli olan ÇAĞIRAN ekranınkiler olmalı (form/rota onlarla açılır).
Future<void> showMedicationSheet(BuildContext context, WidgetRef ref, String babyId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Consumer(
          builder: (_, sheetRef, _) {
            final day = sheetRef.watch(medicationDayProvider(babyId));
            final plans = day?.planCount ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: adGrabHandle()),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 2, bottom: 4),
                  child: Row(
                    children: [
                      AdIconChip('med', color: AppColors.med, bg: AppColors.medBg, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('İlaç & Vitamin'),
                            style:
                                const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                if (day != null && day.hasActive) ...[
                  MedSectionHeader(title: tr('Bugünün planı'), day: day, top: 10),
                  MedDayCard(babyId: babyId, day: day, flat: true),
                  const SizedBox(height: 6),
                ] else
                  const SizedBox(height: 8),
                _SheetOption(
                  icon: 'fever',
                  color: AppColors.coralDd,
                  bg: AppColors.feverBg,
                  title: tr('Plan dışı ilaç kaydet'),
                  meta: tr('Ateş düşürücü gibi tek seferlik'),
                  divider: day != null && day.hasActive,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showRecordForm(context, ref, babyId, RecordType.medication);
                  },
                ),
                _SheetOption(
                  icon: 'clock',
                  color: AppColors.med,
                  bg: AppColors.medBg,
                  title: tr('Planları yönet'),
                  meta: plans > 0
                      ? trp('{n} plan · ilaç ekle, saat ve doz değiştir', {'n': plans})
                      : tr('Her gün verdiklerini ekle, saatinde hatırlatalım'),
                  divider: true,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    context.push('/medications');
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _SheetOption extends StatelessWidget {
  final String icon;
  final Color color;
  final Color bg;
  final String title;
  final String meta;
  final bool divider;
  final VoidCallback onTap;
  const _SheetOption({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.meta,
    required this.divider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: divider ? Border(top: BorderSide(color: AppColors.line)) : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
        child: Row(
          children: [
            AdIconChip(icon, color: color, bg: bg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
            AdenaIcon(medChevron(context), size: 18, color: AppColors.muted2),
          ],
        ),
      ),
    );
  }
}

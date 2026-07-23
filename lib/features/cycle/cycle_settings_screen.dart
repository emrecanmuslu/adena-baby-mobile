import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import '../babies/baby_controller.dart';
import 'cycle_engine.dart';
import 'cycle_kit.dart';
import 'cycle_lifecycle.dart';
import 'cycle_pregnancy_bridge.dart';
import 'cycle_widgets.dart';

/// Varsayılan hatırlatıcı yapısı (ayar boşsa).
Map<String, dynamic> _defaultReminders() => {
      'period': {'on': true},
      'fertile': {'on': true},
      'pms': {'on': false},
      'log': {'on': true, 'time': '21:00'},
    };

/// Ekran 8 — Adet modülü ayarları & hatırlatıcılar.
class CycleSettingsScreen extends ConsumerWidget {
  const CycleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(cycleSettingsProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 18, 4),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Icon(Icons.chevron_left_rounded, size: 28, color: AppColors.ink),
                  ),
                ),
                const SizedBox(width: 4),
                Text(tr('Ayarlar'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
            ),
            Expanded(
              child: settingsAsync.when(
                loading: () =>
                    Center(child: CircularProgressIndicator(color: AppColors.rose)),
                error: (e, _) => Center(child: Text(apiErrorText(e))),
                data: (settings) => _Body(settings: settings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  final CycleSettings settings;
  const _Body({required this.settings});

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late Map<String, dynamic> _reminders;
  late bool _fertilityWarn;
  late bool _smart; // akıllı tahmin (son loglardan öğren) — My Calendar pariteli
  late bool _weekSunday; // takvimde hafta Pazar mı başlasın
  late int _cycleLen; // beklenen döngü uzunluğu (gün); ölçüm yokken kullanılır
  late int _periodLen; // adet (kanama) süresi (gün); ölçüm yokken kullanılır
  late int _lutealLen; // luteal faz uzunluğu (gün); ovülasyon konumunu belirler

  @override
  void initState() {
    super.initState();
    _cycleLen = widget.settings.expectedCycleLength ?? 28;
    _periodLen = widget.settings.periodLength ?? 5;
    _lutealLen = widget.settings.lutealPhaseLength ?? 14;
    final r = widget.settings.reminders;
    // Değerler {on, time} map'i olmalı; ama eski/seed veri {key: bool} biçiminde
    // olabilir → map'e normalize et (yoksa 'bool is not a subtype of Map' patlar).
    _reminders = r.isEmpty
        ? _defaultReminders()
        : {
            for (final e in r.entries)
              e.key: e.value is Map
                  ? Map<String, dynamic>.from(e.value as Map)
                  : {'on': e.value == true},
          };
    _fertilityWarn = widget.settings.showFertilityWarning;
    _smart = widget.settings.smartPrediction;
    _weekSunday = widget.settings.weekStartsSunday;
  }

  bool _on(String k) => _reminders[k]?['on'] == true;

  Future<void> _persist() async {
    final next = widget.settings.copyWith(
      reminders: _reminders,
      showFertilityWarning: _fertilityWarn,
      smartPrediction: _smart,
      weekStartsSunday: _weekSunday,
      expectedCycleLength: _cycleLen,
      periodLength: _periodLen,
      lutealPhaseLength: _lutealLen,
    );
    try {
      await ref.read(cycleRepositoryProvider).patchSettings(next.toPatchJson());
      ref.invalidate(cycleSettingsProvider);
      // Hatırlatıcıları döngü tahminine göre yeniden planla.
      final entries = await ref.read(cycleRepositoryProvider).listEntries();
      final status = computeStatus(next, entries);
      await NotificationService.instance.syncCycle(
        reminders: next.reminders,
        nextPeriod: status.nextPeriod,
        // Yaklaşan pencere → mevcut döngününki geçmişse hatırlatıcı sonraki
        // döngünün penceresine kurulur (eskiden geçmiş tarih → hiç kurulmuyordu).
        fertileStart: status.upcomingFertileStart,
      );
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  void _toggle(String k, bool v) {
    setState(() => _reminders[k] = {..._reminders[k] ?? {}, 'on': v});
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        CycEyebrow(tr('Hedefim'),
            info: widget.settings.lifecycleMode == CycleLifecycleMode.postpartum
                ? tr('Doğum sonrası takip aktif. İlk adetin gelene kadar seçim '
                    'gerekmez, mod otomatik güncellenir.')
                : tr('Adet takibini gebe kalmaya çalışma (ovülasyon planlama) veya '
                    'gebelik moduna geçirebilirsin. Tümü aynı verini kullanır.')),
        CycleModeSwitcher(
          settings: widget.settings,
          onPregnant: () => startCyclePregnancy(context, ref, widget.settings),
        ),
        const SizedBox(height: 6),
        CycEyebrow(tr('Hatırlatıcılar'),
            info: tr('Hatırlatıcılar cihaz bildirimleri olarak gelir; sessiz saat '
                'ayarına uyar.')),
        _card([
          _switchRow(tr('Yaklaşan adet'), tr('3 gün öncesinden bildir'), 'period'),
          _switchRow(tr('Doğurganlık penceresi'), tr('Pencere başında bildir'), 'fertile'),
          _switchRow(tr('PMS hatırlatıcısı'), tr('Adetten ~5 gün önce'), 'pms'),
          _switchRow(tr('Günlük kayıt'), tr('Her gün 21:00'), 'log', last: true),
        ]),
        CycEyebrow(tr('Emzirme & Doğurganlık'), info: CycleInfo.lam),
        _card([
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tr('LAM / doğurganlık uyarıları'),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 5),
                          AdInfoDot(title: tr('LAM'), body: CycleInfo.lam),
                        ],
                      ),
                      Text(tr('Emziren anneler için hatırlatmalar'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
                Switch(
                  value: _fertilityWarn,
                  activeThumbColor: AppColors.rose,
                  onChanged: (v) {
                    setState(() => _fertilityWarn = v);
                    _persist();
                  },
                ),
              ],
            ),
          ),
        ]),
        CycEyebrow(tr('Takvim')),
        _card([
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Hafta Pazar başlasın'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(_weekSunday ? tr('Paz – Cmt') : tr('Pzt – Paz'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              Switch(
                value: _weekSunday,
                activeThumbColor: AppColors.rose,
                onChanged: (v) {
                  setState(() => _weekSunday = v);
                  _persist();
                },
              ),
            ]),
          ),
        ]),
        CycEyebrow(tr('Tahmin ayarları'),
            info: tr('Tahminler bu değerlere göre yapılır. Yeterli kayıt birikince '
                'sistem döngü ve adet süresini kendi öğrenir; luteal faz ise '
                'ovülasyon gününü belirler. Emin değilsen varsayılanlarda bırak.')),
        _card([
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(tr('Akıllı tahmin'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 5),
                      AdInfoDot(
                          title: tr('Akıllı tahmin'),
                          body: tr('Açıkken döngü ve adet süresini son kayıtlarından '
                              '(yakın döngüler) otomatik öğrenir. Kapalıyken aşağıdaki '
                              'sabit değerleri kullanır.')),
                    ]),
                    Text(tr('Son loglardan otomatik öğren'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              Switch(
                value: _smart,
                activeThumbColor: AppColors.rose,
                onChanged: (v) {
                  setState(() => _smart = v);
                  _persist();
                },
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.line),
          _lenRow(
            tr('Ortalama döngü uzunluğu'),
            _cycleLen,
            21,
            40,
            (v) {
              setState(() => _cycleLen = v);
              _persist();
            },
          ),
          Divider(height: 1, color: AppColors.line),
          _lenRow(
            tr('Adet (kanama) süresi'),
            _periodLen,
            2,
            10,
            (v) {
              setState(() => _periodLen = v);
              _persist();
            },
            info: tr('Adet kanamasının kaç gün sürdüğü. Tahmini adet aralığını '
                'belirler. Tipik 4–7 gün.'),
          ),
          Divider(height: 1, color: AppColors.line),
          _lenRow(
            tr('Luteal faz uzunluğu'),
            _lutealLen,
            10,
            16,
            (v) {
              setState(() => _lutealLen = v);
              _persist();
            },
            info: tr('Ovülasyon ile sonraki adet arasındaki süre. Ovülasyon günü '
                'buna göre hesaplanır (sonraki adet − luteal). Çoğu kişide ~14 gün.'),
          ),
        ]),
        CycEyebrow(tr('Emzirme Durumu')),
        AdMenuItem(
          icon: 'heart',
          color: AppColors.roseD,
          bg: AppColors.roseBg,
          title: _bfLabel(widget.settings.breastfeeding),
          meta: tr('Güncelle'),
          onTap: _editBreastfeeding,
        ),
        // Bebeksiz dalda "Bebek ekle" burada yaşar (alt menüden kaldırıldı —
        // henüz gebe olmayan kullanıcının ana menüsünde anlamı yoktu).
        if (ref.watch(activeBabyProvider) == null) ...[
          CycEyebrow(tr('Bebek')),
          AdMenuItem(
            icon: 'baby',
            color: AppColors.coralDark,
            bg: AppColors.peachLight,
            title: tr('Bebek ekle'),
            meta: tr('Bebeğin doğduysa veya gebeliğini eklemek istersen'),
            onTap: () => context.push('/baby-add'),
          ),
        ],
        CycEyebrow(tr('Veri')),
        _card([
          InkWell(
            onTap: _confirmResetAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Adet takvimini sıfırla'),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.coralDd)),
                        Text(tr('Tüm kayıtlar ve kurulum silinir — geri alınamaz'),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.delete_outline, size: 20, color: AppColors.coralDd),
                ],
              ),
            ),
          ),
        ]),
      ],
    );
  }

  /// Tahmin ayarı satırı — etiket + opsiyonel bilgi rozeti + − [N gün] + (min–max).
  /// Değişince [onSet] çağrılır (state güncelle + kaydet).
  Widget _lenRow(
    String label,
    int value,
    int min,
    int max,
    void Function(int) onSet, {
    String? info,
  }) {
    void set(int v) {
      final clamped = v.clamp(min, max);
      if (clamped == value) return;
      onSet(clamped);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                if (info != null) ...[
                  const SizedBox(width: 5),
                  AdInfoDot(title: label, body: info),
                ],
              ],
            ),
          ),
          _stepBtn('−', value > min ? () => set(value - 1) : null),
          SizedBox(
            width: 64,
            child: Text(trp('{n} gün', {'n': value}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ),
          _stepBtn('+', value < max ? () => set(value + 1) : null),
        ],
      ),
    );
  }

  Widget _stepBtn(String label, VoidCallback? onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppColors.smallShadow,
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: onTap == null ? AppColors.muted2 : AppColors.coralDark)),
        ),
      );

  Widget _card(List<Widget> children) => cycCard(context,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(children: children));

  Widget _switchRow(String title, String sub, String key, {bool last = false}) {
    return Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
              ],
            ),
          ),
          Switch(
            value: _on(key),
            activeThumbColor: AppColors.rose,
            onChanged: (v) => _toggle(key, v),
          ),
        ],
      ),
    );
  }

  String _bfLabel(Breastfeeding? b) => switch (b) {
        Breastfeeding.exclusive => '🤱 ${tr('Sadece anne sütü')}',
        Breastfeeding.mixed => '🍼 ${tr('Karışık beslenme')}',
        Breastfeeding.none => '🥛 ${tr('Emzirmiyorum')}',
        null => tr('Seçilmedi'),
      };

  Future<void> _editBreastfeeding() async {
    final picked = await showModalBottomSheet<Breastfeeding>(
      context: context,
      shape: adSheetShape,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            adGrabHandle(),
            for (final b in Breastfeeding.values)
              ListTile(
                title: Text(_bfLabel(b),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: widget.settings.breastfeeding == b
                    ? Icon(Icons.check, color: AppColors.rose)
                    : null,
                onTap: () => Navigator.pop(ctx, b),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final next = widget.settings.copyWith(breastfeeding: picked);
    try {
      await ref.read(cycleRepositoryProvider).patchSettings(next.toPatchJson());
      ref.invalidate(cycleSettingsProvider);
      if (mounted) showAdToast(context, tr('Güncellendi'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  /// TAM sıfırlama: kayıtlar + kurulum/yaşam-döngüsü ayarları + bildirimler.
  /// Eski davranış yalnız kayıtları siliyordu → modül "kurulu" kalıyor, sihirbaz
  /// bir daha açılmıyordu ("sıfırlama işe yaramıyor" şikâyetinin sebebi).
  Future<void> _confirmResetAll() async {
    final ok = await _confirm(
        tr('Adet takvimini sıfırla'),
        tr('Tüm adet/loşia kayıtların ve adet takvimi kurulumun (hedef, tarihler, '
            'hatırlatıcılar) kalıcı olarak silinecek. Bu işlem geri alınamaz.'));
    if (!ok) return;
    try {
      final repo = ref.read(cycleRepositoryProvider);
      final entries = await repo.listEntries();
      for (final e in entries) {
        await repo.deleteEntry(e.id);
      }
      // Ayarları fabrika durumuna çek: breastfeeding boş → kabuk kurulum
      // sihirbazını yeniden gösterir; yaşam-döngüsü de başa döner.
      await repo.patchSettings({
        'birth_date': null,
        'breastfeeding': '',
        'first_period_date': null,
        'reminders': <String, dynamic>{},
        'show_fertility_warning': true,
        'enabled': false,
        'expected_cycle_length': null,
        'period_length': null,
        'luteal_phase_length': null,
        'smart_prediction': true,
        'week_starts_sunday': false,
        'lifecycle_mode': CycleLifecycleMode.tracking.name,
        'ttc_started_at': null,
        'predictions_hidden': false,
        'last_loss_date': null,
        'learning_window': null,
      });
      // Planlı adet bildirimlerini de iptal et (boş yapı → yalnız cancel).
      await NotificationService.instance.syncCycle(reminders: const {});
      ref.invalidate(cycleEntriesProvider);
      ref.invalidate(cycleSettingsProvider);
      if (mounted) {
        showAdToast(context, tr('Adet takvimi sıfırlandı'));
        // Ayarlar sayfası kurulumu silinen kabuğun üstünde kalmasın.
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
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
              child: Text(tr('Devam'),
                  style: const TextStyle(
                      color: AppColors.coralDd, fontWeight: FontWeight.w900))),
        ],
      ),
    );
    return r ?? false;
  }
}

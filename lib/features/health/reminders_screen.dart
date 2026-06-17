import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/premium_gate.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../data/subscription_repository.dart';
import '../auth/auth_controller.dart';
import '../../models/feed_reminder.dart';
import '../../models/quiet_hours.dart';
import '../../models/reminder.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';

/// Hatırlatıcılar (design ScrReminders): nazik bildirim açıklaması + aktif
/// hatırlatıcı listesi (aç/kapa anahtarı, kaydır-sil) + "Hatırlatıcı ekle".
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  // Silinip ağaçtan hemen kaldırılan id'ler (Dismissible "still in tree" hatasını
  // önlemek için liste bunları anında gizler; refetch'te zaten gelmezler).
  final Set<int> _hidden = {};

  /// Hatırlatıcıyı siler: önce ağaçtan kaldır (Dismissible gereği), sonra API +
  /// bildirim iptali. Başarısızsa geri getirir. Toast ekran context'inde (mounted).
  Future<void> _delete(String babyId, Reminder r) async {
    setState(() => _hidden.add(r.id));
    try {
      await ref.read(healthRepositoryProvider).deleteReminder(r.id);
      await NotificationService.instance.cancelReminder(r.id);
      if (mounted) showAdToast(context, tr('Hatırlatıcı silindi'));
    } catch (e) {
      if (mounted) {
        setState(() => _hidden.remove(r.id)); // geri getir
        showAdError(context, apiErrorText(e));
      }
    }
    ref.invalidate(remindersProvider(babyId));
  }

  // Aynı anda bir budama turu (tekrar tetiklenmeyi önle).
  bool _pruning = false;

  /// Süresi geçmiş TEK-SEFERLİK ('once') hatırlatıcıları otomatik temizle —
  /// tetiklendikten sonra durmasının anlamı yok. Bildirim zaten yerelde planlı
  /// olduğundan geçmiş zamanı iptal etmek no-op'tur (kullanıcıyı etkilemez).
  Future<void> _pruneExpiredOnce(String babyId, List<Reminder> list) async {
    if (_pruning) return;
    final now = DateTime.now();
    final expired = list.where((r) {
      if (r.type != 'custom' || r.schedule['repeat'] != 'once') return false;
      if (_hidden.contains(r.id)) return false;
      final at = DateTime.tryParse(r.schedule['at'] as String? ?? '')?.toLocal();
      return at != null && at.isBefore(now);
    }).toList();
    if (expired.isEmpty) return;
    _pruning = true;
    try {
      for (final r in expired) {
        await ref.read(healthRepositoryProvider).deleteReminder(r.id);
        await NotificationService.instance.cancelReminder(r.id);
      }
    } catch (_) {
      // Geçici hata — sonraki yüklemede tekrar denenir.
    }
    _pruning = false;
    if (mounted) ref.invalidate(remindersProvider(babyId));
  }

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final isPremium = ref.watch(isPremiumProvider);
    // Özel (sunucu) hatırlatıcılar hesap gerektirir. Beslenme + sessiz saat
    // ZATEN yerel (hesapsızda da çalışır) → onları her zaman gösteririz.
    final loggedIn = ref.watch(authControllerProvider).asData?.value != null;
    final async = loggedIn ? ref.watch(remindersProvider(baby.id)) : null;
    // Free limit: en fazla 2 özel (custom) hatırlatıcı.
    final customCount = (async?.asData?.value ?? const [])
        .where((r) => r.type == 'custom' && !_hidden.contains(r.id))
        .length;

    // Liste değiştikçe cihaz bildirimlerini eşitle + süresi geçmiş tek-seferlikleri
    // temizle. Yalnız hesaplı kullanıcıda (hesapsızda sunucu listesi yok).
    if (loggedIn) {
      ref.listen(remindersProvider(baby.id), (_, next) {
        final list = next.asData?.value;
        if (list != null) {
          NotificationService.instance.sync(list);
          _pruneExpiredOnce(baby.id, list);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Hatırlatıcılar')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _NudgeBanner(),
          adSec(tr('Beslenme hatırlatıcısı')),
          _FeedReminderCard(babyId: baby.id),
          adSec(tr('Sessiz saat')),
          _QuietHoursCard(babyId: baby.id),
          adSec(tr('Aktif hatırlatıcılar')),
          // Hesapsız: özel hatırlatıcılar (ilaç/randevu) cloud + hesap gerektirir.
          if (!loggedIn)
            const _CustomRemindersLocked()
          else ...[
            async!.when(
              loading: () => Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Skeleton(height: 68, radius: 16),
                    ),
                ],
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(apiErrorText(e),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.muted, fontWeight: FontWeight.w700)),
              ),
              data: (reminders) {
                final visible =
                    reminders.where((r) => !_hidden.contains(r.id)).toList();
                if (visible.isEmpty) return const _Empty();
                return Column(
                  children: [
                    for (final r in visible)
                      _ReminderTile(
                        reminder: r,
                        babyId: baby.id,
                        onDelete: () => _delete(baby.id, r),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            AdSaveButton(
              label: tr('Hatırlatıcı ekle'),
              color: AppColors.coralDd,
              ghost: true,
              onTap: () {
                if (!isPremium && customCount >= 2) {
                  showPremiumUpsell(
                    context,
                    feature: tr('Sınırsız hatırlatıcı'),
                    desc: tr('Ücretsizde 2 özel hatırlatıcı kurabilirsin. Premium '
                        'ile sınırsız hatırlatıcı + reklamsız.'),
                  ).then((go) {
                    if (go == true && context.mounted) context.push('/premium');
                  });
                } else {
                  _showAddReminderSheet(context, ref, baby.id);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Bildirim tonu açıklaması (design .ad-nudge) — nazik tutuyoruz mesajı.
class _NudgeBanner extends StatelessWidget {
  const _NudgeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.feedBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const AdIconChip('bell', color: AppColors.coralDd, bg: Colors.white, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink2),
                children: [
                  TextSpan(text: tr('Bildirimler yorgun ebeveyn için ')),
                  TextSpan(
                      text: tr('nazik'),
                      style: const TextStyle(color: AppColors.coralDd)),
                  TextSpan(text: tr(' tutulur — istediğini kapat.')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek hatırlatıcı kartı: ikon + başlık + zamanlama + aç/kapa. Sola kaydır=sil.
class _ReminderTile extends ConsumerWidget {
  final Reminder reminder;
  final String babyId;
  final VoidCallback onDelete;
  const _ReminderTile(
      {required this.reminder, required this.babyId, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reminder;
    final (icon, color, bg) = _typeVisual(r.type);

    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: AppColors.feverBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const AdenaIcon('trash', size: 20, color: AppColors.fever),
      ),
      onDismissed: (_) => onDelete(), // ağaçtan kaldırma + silme ekranda yönetilir
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.softShadow,
        ),
        child: Row(
          children: [
            AdIconChip(icon, color: color, bg: bg),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_typeLabel(r),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 1),
                  Text(_scheduleLabel(r),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
            Switch.adaptive(
              value: r.enabled,
              activeThumbColor: AppColors.coral,
              onChanged: (v) => _toggle(context, ref, v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool enabled) async {
    try {
      await ref.read(healthRepositoryProvider).setReminderEnabled(reminder.id, enabled);
      ref.invalidate(remindersProvider(babyId));
    } catch (e) {
      ref.invalidate(remindersProvider(babyId));
      if (context.mounted) showAdError(context, apiErrorText(e));
    }
  }
}

/// Hesapsız kullanıcıya özel hatırlatıcıların hesap gerektirdiğini anlatan kart.
/// Beslenme hatırlatıcısı + sessiz saat zaten yerel çalışır; bu yalnız özel
/// (ilaç/randevu) hatırlatıcılar için.
class _CustomRemindersLocked extends StatelessWidget {
  const _CustomRemindersLocked();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          AdenaIcon('bell', size: 38, color: AppColors.peach),
          const SizedBox(height: 10),
          Text(tr('Özel hatırlatıcılar için giriş yap'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              tr('İlaç, vitamin ve randevu hatırlatıcıları hesabınla cihazların '
                  'arasında senkronlanır. Beslenme hatırlatıcısı ve sessiz saat '
                  'hesapsız da çalışır.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          AdSaveButton(
            label: tr('Giriş yap / Hesap oluştur'),
            color: AppColors.coral,
            onTap: () => context.push('/login'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          AdenaIcon('bell', size: 40, color: AppColors.peach),
          const SizedBox(height: 10),
          Text(tr('Henüz hatırlatıcı yok'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('İlaç, vitamin, randevu ya da kendi istediğin için bir hatırlatıcı ekle.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Tür meta yardımcıları ──

(String, Color, Color) _typeVisual(String type) => switch (type) {
      'feed' => ('feed', AppColors.feed, AppColors.feedBg),
      'vaccine' => ('syringe', AppColors.fever, AppColors.feverBg),
      'nudge' => ('bell', AppColors.coral, AppColors.peachLight),
      'appt' => ('calendar', AppColors.med, AppColors.medBg),
      'custom' => ('bell', AppColors.coral, AppColors.peachLight),
      _ => ('med', AppColors.med, AppColors.medBg), // vitamin
    };

String _typeLabel(Reminder r) => switch (r.type) {
      'feed' => tr('Sonraki beslenme'),
      'vaccine' => tr('Yaklaşan aşı'),
      'nudge' => tr('Akıllı dürtükleme'),
      'appt' => (r.schedule['title'] as String?)?.trim().isNotEmpty == true
          ? r.schedule['title'] as String
          : tr('Randevu'),
      'custom' => (r.schedule['title'] as String?)?.trim().isNotEmpty == true
          ? r.schedule['title'] as String
          : tr('Hatırlatıcı'),
      _ => tr('Vitamin / İlaç'),
    };

String _scheduleLabel(Reminder r) {
  // Şekil-tabanlı: tek-seferlik ('at') ya da günlük ('time').
  final at = DateTime.tryParse(r.schedule['at'] as String? ?? '')?.toLocal();
  if (at != null) return fmtDayMonTime(at);
  final time = r.schedule['time'] as String?;
  if (time != null && time.isNotEmpty) return trp('Her gün {t}', {'t': time});
  switch (r.type) {
    case 'feed':
      return tr('Tahmini beslenme saatinde');
    case 'vaccine':
      final n = _intOf(r.schedule['days_before'], 1);
      return n <= 0 ? tr('Aşı günü') : trp('{n} gün önce', {'n': n});
    case 'nudge':
      final n = _intOf(r.schedule['idle_hours'], 3);
      return trp('{n} saat kayıt yoksa', {'n': n});
    default:
      return tr('Her gün');
  }
}

int _intOf(dynamic v, int fallback) => v is num ? v.toInt() : fallback;

/// Yeni hatırlatıcı ekleme sheet'i — tür seçimi + türe göre zamanlama editörü.
Future<void> _showAddReminderSheet(
    BuildContext context, WidgetRef ref, String babyId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (sheetCtx) => _AddReminderSheet(babyId: babyId, ref: ref),
  );
}

class _AddReminderSheet extends StatefulWidget {
  final String babyId;
  final WidgetRef ref;
  const _AddReminderSheet({required this.babyId, required this.ref});

  @override
  State<_AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<_AddReminderSheet> {
  final _title = TextEditingController();
  String _repeat = 'daily'; // 'daily' | 'once'
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  late DateTime _onceAt = _roundedSoon();
  bool _saving = false;

  static DateTime _roundedSoon() {
    final n = DateTime.now().add(const Duration(hours: 1));
    return DateTime(n.year, n.month, n.day, n.hour, 0);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 14),
              child: Text(tr('Hatırlatıcı ekle'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ),
            AdField(
              label: tr('Başlık'),
              child: AdInput(
                controller: _title,
                hint: tr('örn. D vitamini, Doktoru ara'),
                capitalization: TextCapitalization.sentences,
              ),
            ),
            AdField(
              label: tr('Tekrar'),
              child: AdTabs(
                options: {'daily': tr('Her gün'), 'once': tr('Bir kez')},
                selected: _repeat,
                onSelect: (v) => setState(() => _repeat = v),
              ),
            ),
            if (_repeat == 'daily')
              AdField(
                label: tr('Saat'),
                child: _pickerRow(trp('Her gün {t}', {'t': _fmt(_time)}), () async {
                  final picked =
                      await showTimePicker(context: context, initialTime: _time);
                  if (picked != null) setState(() => _time = picked);
                }),
              )
            else
              AdField(
                label: tr('Tarih & saat'),
                child: _pickerRow(
                    fmtDayMonthTime(_onceAt), _pickOnce),
              ),
            const SizedBox(height: 6),
            AdSaveButton(
              label: _saving ? tr('Ekleniyor…') : tr('Ekle'),
              color: AppColors.coral,
              onTap: _saving ? () {} : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerRow(String text, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
                color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                AdenaIcon('clock', size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                Text(text,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink2)),
                const Spacer(),
                Text(tr('değiştir'),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.coralDark)),
              ],
            ),
          ),
        ),
      );

  Future<void> _pickOnce() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _onceAt.isBefore(now) ? now : _onceAt,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_onceAt));
    if (t == null) return;
    setState(() => _onceAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> _schedule() {
    final title = _title.text.trim();
    return _repeat == 'once'
        ? {'repeat': 'once', 'at': _onceAt.toUtc().toIso8601String(), 'title': title}
        : {'repeat': 'daily', 'time': _fmt(_time), 'title': title};
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showAdError(context, tr('Başlık gir'));
      return;
    }
    if (_repeat == 'once' && !_onceAt.isAfter(DateTime.now())) {
      showAdError(context, tr('Geçmiş bir zaman seçtin'));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.ref
          .read(healthRepositoryProvider)
          .createReminder(widget.babyId, type: 'custom', schedule: _schedule());
      widget.ref.invalidate(remindersProvider(widget.babyId));
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Hatırlatıcı eklendi'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }
}

/// Beslenme hatırlatıcısı kartı — özet + aç/kapa; dokununca ayar sheet'i açılır.
class _FeedReminderCard extends ConsumerWidget {
  final String babyId;
  const _FeedReminderCard({required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(feedReminderProvider(babyId));
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showFeedReminderSheet(context, ref, babyId, cfg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                AdIconChip('feed', color: AppColors.feed, bg: AppColors.feedBg),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Sonraki beslenme'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      const SizedBox(height: 1),
                      Text(cfg.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: cfg.enabled,
                  activeThumbColor: AppColors.coral,
                  onChanged: (v) {
                    final next = cfg.copyWith(enabled: v);
                    updateFeedReminder(ref, babyId, next);
                    // Açılınca ayar sheet'i otomatik açılır (detayları ayarlasın).
                    if (v) showFeedReminderSheet(context, ref, babyId, next);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Beslenme hatırlatıcısı ayar sheet'ini açar (hem Hatırlatıcılar ekranı kartı
/// hem ana sayfadaki "Sonraki beslenme" kartı kullanır). Sheet içinde aç/kapa
/// anahtarı da var.
Future<void> showFeedReminderSheet(
    BuildContext context, WidgetRef ref, String babyId, FeedReminderConfig cfg) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _FeedReminderSheet(babyId: babyId, ref: ref, initial: cfg),
  );
}

class _FeedReminderSheet extends StatefulWidget {
  final String babyId;
  final WidgetRef ref;
  final FeedReminderConfig initial;
  const _FeedReminderSheet(
      {required this.babyId, required this.ref, required this.initial});

  @override
  State<_FeedReminderSheet> createState() => _FeedReminderSheetState();
}

class _FeedReminderSheetState extends State<_FeedReminderSheet> {
  late bool _enabled = widget.initial.enabled;
  late int _interval = widget.initial.intervalMin;
  late String _base = widget.initial.baseType;
  late int _pre = widget.initial.preMin;
  late bool _sound = widget.initial.soundEnabled;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Row(
                children: [
                  Text(tr('Beslenme hatırlatıcısı'),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  AdInfoDot(
                    title: tr('Beslenme hatırlatıcısı'),
                    body: tr('Bebeğini beslemeyi unutmamak için bir sonraki beslenme '
                        'zamanında telefonuna hatırlatma gönderir. Süreyi son '
                        'beslemeye göre hesaplar. Üstteki anahtarla açıp kapatırsın.'),
                    size: 16,
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: _enabled,
                    activeThumbColor: AppColors.coral,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ],
              ),
            ),
            _InfoNote(_enabled
                ? tr('Son beslemeden belirlediğin süre sonra seni uyarır.')
                : tr('Açmak için üstteki anahtarı kullan — ayrıntılar burada görünür.')),
            // Ayrıntılı seçenekler yalnız hatırlatıcı AÇIKKEN görünür.
            if (_enabled) ...[
              AdField(
                label: tr('Aralık'),
                info: tr('Son beslemeden kaç saat/dakika sonra hatırlatılsın? Örneğin '
                    '2 saat seçersen, her beslemeden 2 saat sonra uyarı gelir. '
                    '− ve + ile ayarla.'),
                child: _intervalControl(),
              ),
              AdField(
                label: tr('Baz alınan beslenme'),
                info: tr('Hatırlatıcı hangi beslemeleri saysın? "Hepsi" tüm beslemeleri '
                    'dikkate alır (çoğu kullanıcı için en iyisi). "Anne sütü" yalnız '
                    'emzirmeyi, "Mama" yalnız biberonu baz alır.'),
                child: AdTabs(
                  options: {'all': tr('Hepsi'), 'breast': tr('Anne sütü'), 'formula': tr('Mama')},
                  selected: _base,
                  onSelect: (v) => setState(() => _base = v),
                ),
              ),
              AdField(
                label: tr('Ön-hatırlatma'),
                child: AdTabs(
                  options: {'0': tr('Kapalı'), '5': tr('5 dk'), '15': tr('15 dk'), '30': tr('30 dk')},
                  selected: _pre.toString(),
                  onSelect: (v) => setState(() => _pre = int.parse(v)),
                ),
              ),
              AdField(
                label: tr('Sesli alarm'),
                info: tr('"Sesli" → bildirim sesli ve titreşimli gelir (önemli alarm gibi). '
                    '"Sessiz" → ses çıkmadan yalnız bildirim çubuğunda görünür. Geceleri '
                    'otomatik susturmak için Hatırlatıcılar\'daki "Sessiz saat"i kullan.'),
                child: AdTabs(
                  options: {'off': tr('Sessiz'), 'on': tr('Sesli')},
                  selected: _sound ? 'on' : 'off',
                  onSelect: (v) => setState(() => _sound = v == 'on'),
                ),
              ),
            ],
            const SizedBox(height: 6),
            AdSaveButton(
              label: _saving ? tr('Kaydediliyor…') : tr('Kaydet'),
              color: AppColors.coral,
              onTap: _saving ? () {} : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _intervalControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration:
          BoxDecoration(color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          _stepBtn('−', _interval > 30 ? () => setState(() => _interval -= 15) : null),
          Expanded(
            child: Text(_hm(_interval),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ),
          _stepBtn('+', _interval < 360 ? () => setState(() => _interval += 15) : null),
        ],
      ),
    );
  }

  Widget _stepBtn(String label, VoidCallback? onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: onTap == null ? AppColors.muted2 : AppColors.coralDark)),
          ),
        ),
      );

  static String _hm(int min) {
    final h = min ~/ 60, m = min % 60;
    if (h > 0 && m > 0) return trp('{h} sa {m} dk', {'h': h, 'm': m});
    if (h > 0) return trp('{h} saat', {'h': h});
    return trp('{m} dk', {'m': m});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await updateFeedReminder(
        widget.ref,
        widget.babyId,
        FeedReminderConfig(
          enabled: _enabled,
          intervalMin: _interval,
          baseType: _base,
          preMin: _pre,
          soundEnabled: _sound,
        ),
      );
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Beslenme hatırlatıcısı kaydedildi'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }
}

/// Sessiz saat kartı — özet + aç/kapa; dokununca saat aralığı sheet'i açılır.
class _QuietHoursCard extends ConsumerWidget {
  final String babyId;
  const _QuietHoursCard({required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(quietHoursProvider(babyId));
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showQuietHoursSheet(context, ref, babyId, q),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                AdIconChip('moon', color: AppColors.sleep, bg: AppColors.sleepBg),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Sessiz saat'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      const SizedBox(height: 1),
                      Text(q.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: q.enabled,
                  activeThumbColor: AppColors.coral,
                  onChanged: (v) {
                    final next = q.copyWith(enabled: v);
                    updateQuietHours(ref, babyId, next);
                    // Açılınca saat aralığı sheet'i otomatik açılır.
                    if (v) showQuietHoursSheet(context, ref, babyId, next);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sessiz saat saat-aralığı ayar sheet'i (aç/kapa anahtarı + başlangıç/bitiş).
Future<void> showQuietHoursSheet(
    BuildContext context, WidgetRef ref, String babyId, QuietHours q) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _QuietHoursSheet(babyId: babyId, ref: ref, initial: q),
  );
}

class _QuietHoursSheet extends StatefulWidget {
  final String babyId;
  final WidgetRef ref;
  final QuietHours initial;
  const _QuietHoursSheet(
      {required this.babyId, required this.ref, required this.initial});

  @override
  State<_QuietHoursSheet> createState() => _QuietHoursSheetState();
}

class _QuietHoursSheetState extends State<_QuietHoursSheet> {
  late bool _enabled = widget.initial.enabled;
  late int _start = widget.initial.startMin;
  late int _end = widget.initial.endMin;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Row(
                children: [
                  Text(tr('Sessiz saat'),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  AdInfoDot(
                    title: tr('Sessiz saat'),
                    body: tr('Belirlediğin saat aralığında bildirimler sessizce gelir — '
                        'ses ve titreşim olmaz ama bildirim yine düşer. "Sesli alarm" '
                        'açık olsa bile bu aralıkta her zaman sessizdir. Genelde gece '
                        'uykusu için kullanılır.'),
                    size: 16,
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: _enabled,
                    activeThumbColor: AppColors.coral,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ],
              ),
            ),
            _InfoNote(
                tr('Bu saat aralığında bildirimler sessizce gelir (ses/titreşim yok). '
                '"Sesli alarm" açık olsa bile sessiz saat her zaman önceliklidir.')),
            Row(
              children: [
                Expanded(
                    child: _timeField(tr('Başlangıç'), _start,
                        tr('Sessiz dönemin başladığı saat (ör. 22:00). Dokunup saat seç.'),
                        (m) => setState(() => _start = m))),
                const SizedBox(width: 10),
                Expanded(
                    child: _timeField(tr('Bitiş'), _end,
                        tr('Sessiz dönemin bittiği saat (ör. 07:00). Gece yarısını geçen '
                        'aralıkları da destekler.'),
                        (m) => setState(() => _end = m))),
              ],
            ),
            const SizedBox(height: 6),
            AdSaveButton(
              label: _saving ? tr('Kaydediliyor…') : tr('Kaydet'),
              color: AppColors.coral,
              onTap: _saving ? () {} : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeField(
      String label, int min, String info, ValueChanged<int> onPick) {
    return AdField(
      label: label,
      info: info,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final res = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: min ~/ 60, minute: min % 60),
            );
            if (res != null) onPick(res.hour * 60 + res.minute);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
                color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
            child: Text(QuietHours.hhmm(min),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await updateQuietHours(widget.ref, widget.babyId,
          QuietHours(enabled: _enabled, startMin: _start, endMin: _end));
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Sessiz saat kaydedildi'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(13),
      decoration:
          BoxDecoration(color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink2)),
    );
  }
}

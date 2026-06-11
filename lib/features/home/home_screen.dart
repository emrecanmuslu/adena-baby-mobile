import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/ring.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/health_repository.dart';
import '../../models/baby.dart';
import '../../models/feed_reminder.dart';
import '../../models/milestone.dart';
import '../../models/record.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_controller.dart';
import '../babies/baby_switcher.dart';
import '../babies/family_settings.dart';
import '../charts/charts_view.dart';
import '../health/reminders_screen.dart';
import 'expecting_home.dart';
import '../records/add_record_sheet.dart';
import '../records/record_controller.dart';
import '../records/record_form.dart';
import '../records/record_ui.dart';
import '../records/timeline_view.dart';

/// Ana ekran: aktif bebek başlığı + 3 sekme (Ana Sayfa·Akış·Grafikler) + merkez (+).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(activeBabyProvider);

    if (baby == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }

    // Süren uyku/emzirme sayaçlarını cihaz bildirimine yansıt (her sekmede ayakta;
    // değer değişince build tekrar çalışıp bildirimi günceller/iptal eder).
    _syncSleepTimer(ref.watch(ongoingSleepProvider(baby.id)));
    _syncBreastTimer(ref.watch(ongoingBreastProvider(baby.id)));
    _syncFeedReminder(baby); // beslenme hatırlatıcısı (config + son beslenmeler)

    final appBar = AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Kaydırınca renklenen başlık, alt köşelerinden içeriğe doğru kıvrılır.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      titleSpacing: 16,
      title: const BrandWordmark(fontSize: 23),
      actions: [
        const _SyncBadge(), // yalnız çevrimdışıyken görünür
        // Bekleme modunda hatırlatıcılar (beslenme/aşı/dürtükleme) uygulanmaz → zil gizli.
        if (!baby.isExpecting) const _HeaderBell(),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: _HeaderAvatar(onTap: () => context.push('/settings')),
        ),
      ],
      // Bebek sekmeleri AppBar'ın parçası — kaydırınca logo satırıyla aynı
      // scroll-under rengini birlikte alır (araya dikiş çizgisi girmez).
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: _BabyTabs(),
      ),
    );

    // Gebelik (bekleme) modu: kayıt akışı yerine hafta sayacı + "doğdu" CTA.
    if (baby.isExpecting) {
      return Scaffold(
        appBar: appBar,
        body: ExpectingHome(baby: baby),
      );
    }

    return Scaffold(
      appBar: appBar,
      // Yüzer menü gerçekten yüzsün: içerik menünün arkasından aksın (kenar şerit
      // yok). Sekmelerin alt boşluğu (96) içeriği menünün arkasında bırakmaz.
      extendBody: true,
      // Lazy: yalnız aktif sekme kurulur (çok veride diğer sekmeler boşuna yüklenmesin).
      body: switch (_tab) {
        1 => TimelineView(babyId: baby.id),
        2 => ChartsView(babyId: baby.id),
        _ => _HomeTab(babyId: baby.id),
      },
      // V2 · Yüzen ada — kenarlardan kopuk hap; ikon-odaklı, FAB satır içinde.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x21E2553F), blurRadius: 30, offset: Offset(0, 12)),
                BoxShadow(
                    color: Color(0x0F3D2B26), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem('home', 0),
                _navItem('timeline', 1),
                _navFab(() => showAddRecordMenu(context, ref, baby.id)),
                _navItem('charts', 2),
                _navHealth(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Beslenme hatırlatıcısı → config + son beslenmelerden bir sonraki zamanı
  /// hesaplayıp planlar (kapalı/bekleme/veri yok → iptal).
  void _syncFeedReminder(Baby baby) {
    final cfg = ref.watch(feedReminderProvider(baby.id));
    if (baby.isExpecting || !cfg.enabled) {
      NotificationService.instance
          .scheduleFeedReminder(enabled: false, nextTime: null, preMin: 0);
      return;
    }
    final recs = ref.watch(recentRecordsProvider(baby.id)).asData?.value ?? const [];
    final quiet = ref.watch(quietHoursProvider(baby.id));
    NotificationService.instance.scheduleFeedReminder(
      enabled: true,
      nextTime: nextFeedEstimate(cfg, recs),
      preMin: cfg.preMin,
      sound: cfg.soundEnabled,
      quiet: quiet,
    );
  }

  /// Süren uyku → kronometre bildirimi (yoksa iptal).
  void _syncSleepTimer(Record? r) {
    if (r == null) {
      NotificationService.instance.cancelTimer(NotificationService.sleepTimerId);
      return;
    }
    final start =
        DateTime.tryParse(r.data['start_ts'] as String? ?? '')?.toLocal() ?? r.ts;
    NotificationService.instance.showTimer(
      id: NotificationService.sleepTimerId,
      title: tr('Uyku sürüyor'),
      body: tr('Bebeğiniz uyuyor · dokun ve bitir'),
      since: start,
      running: true,
    );
  }

  /// Süren emzirme → kronometre bildirimi (toplam süre; duraklatınca durur).
  void _syncBreastTimer(Record? r) {
    if (r == null) {
      NotificationService.instance.cancelTimer(NotificationService.breastTimerId);
      return;
    }
    final d = r.data;
    final paused = d['paused'] == true;
    final side = d['side'] == 'right' ? tr('Sağ') : tr('Sol');
    var ms = (((d['left_ms'] as num?) ?? 0) + ((d['right_ms'] as num?) ?? 0)).toInt();
    final seg = DateTime.tryParse(d['seg_start_ts'] as String? ?? '')?.toLocal();
    if (seg != null && !paused) {
      ms += DateTime.now().difference(seg).inMilliseconds.clamp(0, 24 * 3600 * 1000);
    }
    final since = DateTime.now().subtract(Duration(milliseconds: ms));
    NotificationService.instance.showTimer(
      id: NotificationService.breastTimerId,
      title: paused ? tr('Emzirme duraklatıldı') : tr('Emzirme sürüyor'),
      body: paused
          ? trp('{side} meme · {min} dk (duraklatıldı)',
              {'side': side, 'min': ms ~/ 60000})
          : trp('{side} memeden emziriyor · dokun ve bitir', {'side': side}),
      since: since,
      running: !paused,
    );
  }

  Widget _navItem(String icon, int index) {
    final selected = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? AppColors.feedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: AdenaIcon(icon,
            color: selected ? AppColors.coralDd : AppColors.muted2,
            size: 23,
            sw: selected ? 2.1 : 1.8),
      ),
    );
  }

  /// Satır içi merkez FAB — mercan gradyan daire, kayıt ekleme menüsünü açar.
  Widget _navFab(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.coral, AppColors.coralDd],
          ),
          boxShadow: [
            BoxShadow(color: Color(0x66E2553F), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        alignment: Alignment.center,
        child: const AdenaIcon('plus', color: Colors.white, size: 24, sw: 2.4),
      ),
    );
  }

  /// Sağlık Hub — aşı/randevu/ateş & ilaç/hatırlatıcı (sekme değil, sayfa açar).
  /// Ayarlar zaten üst bardaki avatardan açılır; bu slot tekrar olmasın diye
  /// en çok erişilen sağlık sayfasına bağlandı.
  Widget _navHealth(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/health'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: AdenaIcon('heart', color: AppColors.muted2, size: 23),
      ),
    );
  }
}

/// Ana Sayfa sekmesi: uyku banner + hızlı kayıt kartları + son kayıtlar.
/// Üst bardaki eşitlenme rozeti (çevrimiçi/çevrimdışı).
class _SyncBadge extends ConsumerWidget {
  const _SyncBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).asData?.value ?? true;
    // Eşitliyken gizli; yalnız çevrimdışında uyarı göster.
    if (online) return const SizedBox.shrink();
    const c = Color(0xFFD6604A);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFFFBEAE6), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 6,
                height: 6,
                child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c))),
            const SizedBox(width: 5),
            Text(tr('Çevrimdışı'),
                style: const TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// Header'daki bildirim ikonu — beyaz daire içinde zil → Hatırlatıcılar.
class _HeaderBell extends StatelessWidget {
  const _HeaderBell();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/reminders'),
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const AdenaIcon('bell', size: 20, color: AppColors.coralDd),
      ),
    );
  }
}

/// Header'daki kullanıcı avatarı — mercan gradyan daire + gölge, sağ altta
/// çevrimiçi (yeşil) / çevrimdışı (kırmızı) durum rozeti. Dokun → ayarlar.
class _HeaderAvatar extends ConsumerWidget {
  final VoidCallback onTap;
  const _HeaderAvatar({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final online = ref.watch(onlineProvider).asData?.value ?? true;
    final ring = Theme.of(context).scaffoldBackgroundColor;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.coral, AppColors.coralDd],
                ),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                (user?.displayName.characters.firstOrNull ?? '?').toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            // Durum rozeti — sayfa zemini renginde halka ile "kesik" görünür.
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? const Color(0xFF34C759) : const Color(0xFFE5484D),
                  border: Border.all(color: ring, width: 2.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// V6 — Çoklu bebek sekmeleri: marka satırının altında yatay kaydırılabilir
/// bebek çubukları. Aktif olan mercan çerçeveli; dokunulan bebeğe geçer.
/// Sondaki kesik çizgili "+" çubuğu bebek ekle/davet kodu menüsünü açar.
class _BabyTabs extends ConsumerWidget {
  const _BabyTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babies = ref.watch(babyControllerProvider).asData?.value ?? const [];
    final activeId = ref.watch(activeBabyProvider)?.id;

    return SizedBox(
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        child: Row(
          children: [
            for (final b in babies) ...[
              _BabyTab(
                baby: b,
                selected: b.id == activeId,
                onTap: () => ref.read(activeBabyIdProvider.notifier).set(b.id),
              ),
              const SizedBox(width: 8),
            ],
            _AddBabyTab(onTap: () => showAddBabySheet(context, ref)),
          ],
        ),
      ),
    );
  }
}

/// Tek bebek çubuğu: küçük avatar + ad + minik yaş. Aktifken mercan vurgulu.
class _BabyTab extends StatelessWidget {
  final Baby baby;
  final bool selected;
  final VoidCallback onTap;
  const _BabyTab(
      {required this.baby, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? AppColors.feedBg : surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.coral : AppColors.line,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(5, 5, 13, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar — aktif: şeftali gradyan + beyaz ikon; diğer: uyku-bg + mor ikon.
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? null : AppColors.sleepBg,
                  gradient: selected
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFE0D2), Color(0xFFFFC1AC)],
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: baby.isExpecting
                    ? const Text('🤰', style: TextStyle(fontSize: 13))
                    : AdenaIcon('baby',
                        size: 14,
                        color: selected ? Colors.white : AppColors.sleep,
                        sw: 2.0),
              ),
              const SizedBox(width: 7),
              Text(baby.name.isNotEmpty ? baby.name : tr('Bebeğim'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? AppColors.coralDd : null,
                  )),
              const SizedBox(width: 5),
              Text(_babyAgeShort(baby),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.coralDark : AppColors.muted,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kesik çizgili "+" çubuğu — bebek ekle / davet kodu menüsünü açar.
class _AddBabyTab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddBabyTab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedPillBorder(color: AppColors.coralDark),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: AdenaIcon('plus', size: 15, color: AppColors.coralDark, sw: 2.2),
          ),
        ),
      ),
    );
  }
}

/// Kesik çizgili hap (pill) çerçevesi — V6 "+" çubuğu için.
class _DashedPillBorder extends CustomPainter {
  final Color color;
  const _DashedPillBorder({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final path = Path()..addRRect(rrect);
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(
          metric.extractPath(dist, dist + dash),
          paint,
        );
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillBorder oldDelegate) => oldDelegate.color != color;
}

/// Sekme için kısa yaş etiketi — "12 g", "3 ay", "2 yaş", bekleme: "Bekliyor".
String _babyAgeShort(Baby b) {
  if (b.isExpecting) {
    final due = b.dueDate;
    if (due == null) return tr('Bekliyor');
    final daysLeft = due.difference(DateTime.now()).inDays.clamp(0, 400);
    final weeks = ((280 - daysLeft) / 7).floor().clamp(0, 42);
    return '$weeks. hf';
  }
  final birth = b.birthDate;
  if (birth == null) return tr('Takip');
  final days = DateTime.now().difference(birth).inDays;
  if (days < 0) return tr('Takip');
  if (days < 30) return '$days g';
  final months = (days / 30.44).floor();
  if (months < 24) return trp('{n} ay', {'n': months});
  return trp('{n} yaş', {'n': (months / 12).floor()});
}

/// Bölüm başlığı (design .ad-sec): uppercase, muted, kalın, harf aralıklı.
/// [top] ile üst boşluk ayarlanır (ilk bölümde küçük tutulur).
Widget _sec(String title, {double top = 18}) => Padding(
      padding: EdgeInsets.fromLTRB(3, top, 3, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: AppColors.muted,
          letterSpacing: 0.7,
        ),
      ),
    );

/// Ana Sayfa sekmesi — design ScrHome: Hızlı Giriş · Sonraki beslenme · Son
/// Aktivite · Bugün · Yaklaşan.
class _HomeTab extends ConsumerWidget {
  final String babyId;
  const _HomeTab({required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ongoing = ref.watch(ongoingSleepProvider(babyId));
    final ongoingBreast = ref.watch(ongoingBreastProvider(babyId));
    final units = ref.watch(activeUnitsProvider);

    return ListView(
      // Alt: yüzer menü (≈76) + cihaz güvenli alanı + boşluk; içerik menü altında kalmasın.
      padding: EdgeInsets.fromLTRB(16, 2, 16, 92 + MediaQuery.of(context).padding.bottom),
      children: [
        if (ongoing != null) _SleepBanner(sleep: ongoing),
        if (ongoingBreast != null) _BreastBanner(feed: ongoingBreast),
        _sec(tr('Hızlı Giriş'), top: 4),
        Row(
          children: [
            _QuickCard(
              type: RecordType.feed,
              onTap: () => showRecordForm(context, ref, babyId, RecordType.feed),
            ),
            const SizedBox(width: 10),
            _QuickCard(
              type: RecordType.diaper,
              onTap: () => showRecordForm(context, ref, babyId, RecordType.diaper),
            ),
            const SizedBox(width: 10),
            _QuickCard(
              type: RecordType.sleep,
              label: ongoing != null ? tr('Uykuyu bitir') : null,
              onTap: () async {
                if (ongoing != null) {
                  await confirmStopSleep(context, ref, ongoing);
                } else {
                  await ref.read(recordActionsProvider).startSleep(babyId);
                }
              },
            ),
          ],
        ),
        _PredictSection(babyId: babyId),
        _LastActivitySection(babyId: babyId, units: units),
        _DaySummarySection(babyId: babyId),
        _UpcomingSection(babyId: babyId),
        _MilestoneSection(babyId: babyId),
      ],
    );
  }
}

/// Ana sayfa "Gelişim" bölümü — bebeğin yaşına uygun, henüz başarılmamış birkaç
/// kilometre taşını hatırlatır (unutulmasın). Dokun → tüm gelişim ekranı.
/// Hepsi tamamsa ya da veri yoksa gizlenir.
class _MilestoneSection extends ConsumerWidget {
  final String babyId;
  const _MilestoneSection({required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(milestonesProvider(babyId)).asData?.value;
    if (all == null || all.isEmpty) return const SizedBox.shrink();
    final pending = all.where((m) => !m.achieved).toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    final baby = ref.watch(activeBabyProvider);
    final age = _ageMonths(baby);
    // Yaşı gelmiş/yaklaşan (≤ yaş+2 ay) ve henüz yapılmamışlar — takip edilmeli.
    // Hepsi ileride ise sıradakini göster.
    var relevant =
        age == null ? pending : pending.where((m) => m.expectedMonth <= age + 2).toList();
    if (relevant.isEmpty) relevant = pending;
    final shown = relevant.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 18, 3, 10),
          child: Row(
            children: [
              Text(tr('GELİŞİM'),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.muted,
                      letterSpacing: 0.7)),
              const SizedBox(width: 6),
              AdInfoDot(
                title: tr('Gelişim / Kilometre taşları'),
                body: tr('Bebeğinin yaşına uygun, henüz işaretlemediğin gelişim '
                    'basamakları. Başardıkça işaretle — rehberdir, her bebek '
                    'kendi temposunda gelişir.'),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/milestones'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Tümü'),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.coralDark)),
                    const AdenaIcon('chevR', size: 15, color: AppColors.coralDark),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.softShadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/milestones'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      _MilestoneRow(milestone: shown[i], last: i == shown.length - 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static int? _ageMonths(Baby? b) {
    final bd = b?.birthDate;
    if (bd == null) return null;
    final now = DateTime.now();
    var m = (now.year - bd.year) * 12 + (now.month - bd.month);
    if (now.day < bd.day) m -= 1;
    return m < 0 ? 0 : m;
  }
}

class _MilestoneRow extends StatelessWidget {
  final Milestone milestone;
  final bool last;
  const _MilestoneRow({required this.milestone, required this.last});

  @override
  Widget build(BuildContext context) {
    final cat = milestoneCategory(milestone.category);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: last ? 8 : 9),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration:
                BoxDecoration(color: cat.bg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(milestone.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          ),
          const SizedBox(width: 8),
          Text(milestoneAgeLabel(milestone.expectedMonth),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// "Sonraki beslenme" tahmini (design .ad-predict). Son beslemeden + sabit
/// aralıktan (varsayılan 2 saat) bir sonraki zamanı kestirir. Hatırlatıcı
/// kapalıyken de varsayılan 2 saatle gösterir; hiç besleme yoksa gizlenir.
class _PredictSection extends ConsumerStatefulWidget {
  final String babyId;
  const _PredictSection({required this.babyId});

  @override
  ConsumerState<_PredictSection> createState() => _PredictSectionState();
}

class _PredictSectionState extends ConsumerState<_PredictSection> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // "~X dk sonra" ve ilerleme halkası canlı kalsın diye periyodik yeniden çiz.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final babyId = widget.babyId;
    final recent = ref.watch(recentRecordsProvider(babyId)).asData?.value;
    if (recent == null) return const SizedBox.shrink();
    final cfg = ref.watch(feedReminderProvider(babyId));
    // Hatırlatıcı açıksa kendi ayarıyla; kapalıysa varsayılan (her 2 saat, tüm
    // beslenmeler) ile aynı tahmin. Çapa = son (baz türü) beslemesi.
    final next = nextFeedEstimate(cfg.enabled ? cfg : const FeedReminderConfig(), recent);
    if (next == null) return const SizedBox.shrink(); // hiç besleme yok
    final feeds = recent.where((r) => r.type == RecordType.feed).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));
    final last = feeds.first.ts;
    final now = DateTime.now();
    final totalMin = next.difference(last).inMinutes;
    final pct =
        totalMin > 0 ? (now.difference(last).inMinutes / totalMin).clamp(0.0, 1.0) : 1.0;
    final remaining = next.difference(now).inMinutes;
    final whenStr = DateFormat('HH:mm').format(next);
    final relStr = remaining > 0
        ? trp('~{n} dk sonra', {'n': remaining})
        : (remaining == 0 ? tr('şimdi') : trp('~{n} dk gecikti', {'n': -remaining}));
    final subtitle = cfg.enabled
        ? cfg.summary
        : tr('Son beslemeye göre · her 2 saat');

    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFFFFAF9E) : AppColors.coralDd;
    final fg = dark ? Theme.of(context).colorScheme.onSurface : AppColors.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sec(tr('Sonraki beslenme')),
        GestureDetector(
          onTap: () => showFeedReminderSheet(context, ref, babyId, cfg),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF3A2A2E), Color(0xFF3A2F28)]
                  : [AppColors.peachLight, const Color(0xFFFFE0D2)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(
            children: [
              Ring(
                size: 42,
                pct: pct,
                strokeWidth: 5,
                color: accent,
                child: AdenaIcon('clock', size: 20, color: accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900, color: fg),
                        children: [
                          TextSpan(
                              text: whenStr,
                              style: TextStyle(color: accent)),
                          TextSpan(text: ' · $relStr'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink2)),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ],
    );
  }
}

/// "Son Aktivite" (design .ad-last3): beslenme/bez/uyku için son kaydın
/// saati + kısa detayını gösteren 3 kart.
class _LastActivitySection extends ConsumerWidget {
  final String babyId;
  final Units units;
  const _LastActivitySection({required this.babyId, required this.units});

  static const _types = [RecordType.feed, RecordType.diaper, RecordType.sleep];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentRecordsProvider(babyId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sec(tr('Son Aktivite')),
        async.when(
          loading: () => Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                const Expanded(child: Skeleton(height: 92, radius: 18)),
              ],
            ],
          ),
          error: (e, _) => Text(apiErrorText(e),
              style: TextStyle(color: AppColors.muted)),
          data: (recent) {
            Record? latestOf(RecordType t) {
              for (final r in recent) {
                if (r.type == t) return r;
              }
              return null;
            }

            return Row(
              children: [
                for (var i = 0; i < _types.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _LastCard(
                      type: _types[i],
                      record: latestOf(_types[i]),
                      units: units,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LastCard extends StatelessWidget {
  final RecordType type;
  final Record? record;
  final Units units;
  const _LastCard({required this.type, required this.record, required this.units});

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: RecordUi.bg(type),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: AdenaIcon(RecordUi.iconName(type),
                size: 17, color: RecordUi.color(type)),
          ),
          const SizedBox(height: 9),
          Text(RecordUi.label(type).toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                  letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(r != null ? RecordUi.time(r.ts) : '—',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 1),
          Text(
            r != null ? _detail(r) : tr('Kayıt yok'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// Özetten kategori adını çıkarır (başlık zaten üstte) — "Uyku · 1sa" → "1sa".
  String _detail(Record r) {
    final label = RecordUi.label(type);
    final s = RecordUi.summary(r, units);
    if (s.startsWith('$label · ')) return s.substring(label.length + 3);
    if (s == label) return '';
    return s;
  }
}

/// "Bugün" özeti (design .ad-daysum): bez sayısı · beslenme sayısı · uyku saati.
class _DaySummarySection extends ConsumerWidget {
  final String babyId;
  const _DaySummarySection({required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayRecordsProvider(babyId)).asData?.value ??
        const <Record>[];
    final diapers = today.where((r) => r.type == RecordType.diaper).length;
    final feeds = today.where((r) => r.type == RecordType.feed).length;
    var sleepMin = 0;
    for (final r in today) {
      if (r.type == RecordType.sleep && r.data['duration'] is num) {
        sleepMin += (r.data['duration'] as num).toInt();
      }
    }
    final String sleepStr;
    if (sleepMin == 0) {
      sleepStr = '0';
    } else {
      final h = sleepMin / 60;
      sleepStr = h.truncateToDouble() == h
          ? h.toStringAsFixed(0)
          : h.toStringAsFixed(1);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sec(tr('Bugün')),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppColors.softShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _DayCol(n: '$diapers', label: tr('Bez'))),
                _daySep(),
                Expanded(child: _DayCol(n: '$feeds', label: tr('Beslenme'))),
                _daySep(),
                Expanded(
                    child: _DayCol(n: sleepStr, small: tr('sa'), label: tr('Uyku'))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _daySep() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 3),
        color: AppColors.line,
      );
}

class _DayCol extends StatelessWidget {
  final String n;
  final String? small;
  final String label;
  const _DayCol({required this.n, required this.label, this.small});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, height: 1),
            children: [
              TextSpan(text: n),
              if (small != null)
                TextSpan(
                    text: small,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.muted,
                letterSpacing: 0.3)),
      ],
    );
  }
}

/// "Sıradaki aşı" (design .ad-upcoming): ilk bekleyen aşı — yoksa gizlenir.
/// Gecikti/bugün/ileri durumunu sade dille ve renkle gösterir.
class _UpcomingSection extends ConsumerWidget {
  final String babyId;
  const _UpcomingSection({required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaccines = ref.watch(vaccinesProvider(babyId)).asData?.value;
    if (vaccines == null) return const SizedBox.shrink();
    final pending = vaccines.where((v) => !v.done).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (pending.isEmpty) return const SizedBox.shrink();
    final v = pending.first;
    final dateStr = DateFormat('d MMMM', 'tr_TR').format(v.dueDate);

    // Bugüne göre gün farkı (yalnız tarih, saat yok).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(v.dueDate.year, v.dueDate.month, v.dueDate.day);
    final diff = due.difference(today).inDays;
    final overdue = diff < 0;
    final when = diff < 0
        ? trp('{n} gün geç kaldın', {'n': -diff})
        : diff == 0
            ? tr('Bugün yapılmalı')
            : diff == 1
                ? tr('Yarın')
                : trp('{n} gün sonra', {'n': diff});
    // Gecikmiş aşıya dikkat çekmek için kırmızımsı vurgu, değilse terrakota.
    final accent = overdue ? AppColors.coralDd : AppColors.med;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 18, 3, 10),
          child: Row(
            children: [
              Text(tr('SIRADAKİ AŞI'),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.muted,
                      letterSpacing: 0.7)),
              const SizedBox(width: 6),
              AdInfoDot(
                title: tr('Sıradaki aşı'),
                body: tr('Bebeğinin sağlık takvimindeki bir sonraki aşı. Tarih, '
                    'doğum gününe göre Sağlık Bakanlığı takviminden otomatik '
                    'hesaplanır. Karta dokununca tüm aşı listesini görür, '
                    'yapılanları işaretleyebilirsin.'),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.softShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => context.push('/vaccines'),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(width: 4, color: accent),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(13, 14, 15, 14),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.medBg,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: const AdenaIcon('syringe',
                                    size: 21, color: AppColors.med),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(v.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14)),
                                        ),
                                        if (overdue) ...[
                                          const SizedBox(width: 7),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                                color: AppColors.feedBg,
                                                borderRadius:
                                                    BorderRadius.circular(999)),
                                            child: Text(tr('Gecikti'),
                                                style: const TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w900,
                                                    color: AppColors.coralDd)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text('$dateStr · $when',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: overdue
                                                ? AppColors.coralDd
                                                : AppColors.muted)),
                                  ],
                                ),
                              ),
                              AdenaIcon('chevR',
                                  size: 18, color: AppColors.muted),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Uyuyor" canlı banner (design .ad-active): mor gradyan + nabız ikon +
/// HH:mm:ss canlı sayaç + "Uyandı".
class _SleepBanner extends ConsumerStatefulWidget {
  final Record sleep;
  const _SleepBanner({required this.sleep});

  @override
  ConsumerState<_SleepBanner> createState() => _SleepBannerState();
}

class _SleepBannerState extends ConsumerState<_SleepBanner>
    with SingleTickerProviderStateMixin {
  Timer? _tick;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final start =
        DateTime.tryParse(widget.sleep.data['start_ts'] as String? ?? '')?.toLocal() ??
            widget.sleep.ts;
    final d = DateTime.now().difference(start);
    final clock = '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    const purple = Color(0xFF6F5FD6);
    final timeColor = dark ? const Color(0xFFB3A6F2) : purple;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF2C2740), Color(0xFF322A48)]
              : const [Color(0xFFEDE9FC), Color(0xFFE4DFFB)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final v = _pulse.value;
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF251D2E) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9B8CE8).withValues(alpha: 0.4 * (1 - v)),
                      spreadRadius: 8 * v,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: child,
              );
            },
            child: const AdenaIcon('sleep', size: 20, color: purple),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trp('UYUYOR · {n} DK', {'n': d.inMinutes}),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink2,
                        letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(clock,
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: timeColor,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => confirmStopSleep(context, ref, widget.sleep),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                  color: purple, borderRadius: BorderRadius.circular(12)),
              child: Text(tr('Uyandı'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Süren emzirme banner'ı (uyku banner'ının emzirme eşi): canlı sayaç, aktif
/// meme, "Bitir". Dokununca form açılır (meme değiştirmek için).
class _BreastBanner extends ConsumerStatefulWidget {
  final Record feed;
  const _BreastBanner({required this.feed});

  @override
  ConsumerState<_BreastBanner> createState() => _BreastBannerState();
}

class _BreastBannerState extends ConsumerState<_BreastBanner>
    with SingleTickerProviderStateMixin {
  Timer? _tick;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final d = widget.feed.data;
    final side = d['side'] == 'right' ? tr('SAĞ') : tr('SOL');
    final paused = d['paused'] == true;
    // Biriken toplam süre (aktif segment dahil) — sheet'teki sayaçla aynı.
    var ms = (((d['left_ms'] as num?) ?? 0) + ((d['right_ms'] as num?) ?? 0)).toInt();
    final segStart = DateTime.tryParse(d['seg_start_ts'] as String? ?? '')?.toLocal();
    if (segStart != null && !paused) {
      ms += DateTime.now().difference(segStart).inMilliseconds.clamp(0, 24 * 3600 * 1000);
    }
    final totalSec = ms ~/ 1000;
    final clock = '${(totalSec ~/ 60).toString().padLeft(2, '0')}:'
        '${(totalSec % 60).toString().padLeft(2, '0')}';
    final timeColor = dark ? const Color(0xFFFFB3A6) : AppColors.coralDd;

    return GestureDetector(
      onTap: () => showRecordForm(context, ref, widget.feed.baby, RecordType.feed),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF3A2A28), Color(0xFF402E2B)]
                : const [Color(0xFFFFE7E1), Color(0xFFFFDAD0)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppColors.softShadow,
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) {
                final v = _pulse.value;
                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF251D2E) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.coral.withValues(alpha: 0.4 * (1 - v)),
                        spreadRadius: 8 * v,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: const AdenaIcon('feed', size: 20, color: AppColors.coral),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trp('{state} · {side} · {min} DK', {
                    'state': paused ? tr('DURAKLADI') : tr('EMZİRİYOR'),
                    'side': side,
                    'min': totalSec ~/ 60,
                  }),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink2,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 2),
                  Text(clock,
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: timeColor,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
            GestureDetector(
              onTap: () async {
                await ref.read(recordActionsProvider).stopBreast(widget.feed);
                if (context.mounted) showAdToast(context, tr('Kaydedildi'));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                    color: AppColors.coral, borderRadius: BorderRadius.circular(12)),
                child: Text(tr('Bitir'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final RecordType type;
  final String? label;
  final VoidCallback onTap;
  const _QuickCard({required this.type, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.softShadow,
          ),
          child: Column(
            children: [
              RecordUi.chip(type),
              const SizedBox(height: 10),
              Text(label ?? RecordUi.label(type),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}



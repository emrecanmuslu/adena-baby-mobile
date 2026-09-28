import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/theme.dart';
import '../../data/notification_prefs.dart';
import '../babies/activity_watcher.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';
import '../health/reminders_screen.dart';
import 'notification_prefs_controller.dart';

/// Bildirimler — TÜM bildirimlerin (yerel + Firebase push) tek merkezden
/// yönetildiği sayfa. Ayarlar & Profil → Bildirimler.
///
/// Tasarım kararları (2026-08-10):
///  • Anahtarlar YALNIZ GÖRÜNÜRLÜĞÜ kapatır. Push cihaza gelmeye devam eder ve
///    sessizce işlenir → senkron, ana ekran widget'ı ve beslenme hatırlatıcısının
///    yeniden planlanması BOZULMAZ. Sayfadaki uyarı kartları bunu açıkça söyler.
///  • Ayarlar CİHAZ-YEREL'dir (SharedPreferences) — anne telefonunda kapalı,
///    baba telefonunda açık olabilir. İstisna: aile etkinlik tercihi ayrıca
///    sunucuya da yansır (backend opt-out üyeye SESSİZ push seçer).
///  • Mevcut ekranlardaki ayarlar KALDIRILMADI; burası AYNI durumu gösterir
///    (aynı provider'lar) → iki yoldan da yönetilebilir, tek kaynak korunur.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    final prefs = ref.watch(notifPrefsProvider);
    final familyOn = ref.watch(activityNotifEnabledProvider).asData?.value ?? true;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    // Beslenme/sayaç bildirimleri yalnız DOĞMUŞ bebekte anlamlı (bekleme modunda
    // kayıt yok → hatırlatıcı da yok).
    final showBaby = baby != null && !baby.isExpecting;

    void setPref(String key, bool v) =>
        ref.read(notifPrefsProvider.notifier).set(key, v);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Bildirimler'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const _SystemPermissionCard(),

          // ——— Genel (cihaz) ———
          adSec(tr('Genel'),
              info: tr('Bu sayfadaki anahtarlar yalnız BU cihazı etkiler ve '
                  'yalnız bildirimin görünmesini kapatır. Kayıtların '
                  'senkronizasyonu çalışmaya devam eder.')),
          _SwitchTile(
            icon: 'bell',
            color: AppColors.coral,
            bg: AppColors.feedBg,
            title: tr('Uygulama içi bildirim şeridi'),
            meta: tr('Uygulama açıkken üstte beliren kısa bildirim'),
            value: prefs[NotificationPrefs.inAppBanner] ?? true,
            onChanged: (v) => setPref(NotificationPrefs.inAppBanner, v),
          ),
          _SwitchTile(
            icon: 'clock',
            color: AppColors.sleep,
            bg: AppColors.sleepBg,
            title: tr('Süren sayaç bildirimi'),
            meta: tr('Uyku/emzirme sürerken bildirim çubuğunda kalan kronometre'),
            value: prefs[NotificationPrefs.timers] ?? true,
            onChanged: (v) => setPref(NotificationPrefs.timers, v),
          ),
          if (!(prefs[NotificationPrefs.timers] ?? true))
            _Note(tr('Sayaç bildirimi kapalı. Uyku ve emzirme sayaçların normal '
                'şekilde çalışmaya devam eder — yalnız bildirim çubuğunda '
                'görünmezler; uygulamadan takip edip bitirebilirsin.')),

          // ——— Bebeğe özel ———
          if (showBaby) ...[
            adSec(trp('{baby} · beslenme', {'baby': baby.name})),
            _FeedSection(babyId: baby.id),

            adSec(trp('{baby} · sağlık hatırlatıcıları', {'baby': baby.name}),
                info: tr('Zamanlama bebeğinin verisine göre otomatik hesaplanır '
                    '(sen bir şey ayarlamazsın) — burada yalnız açıp kapatırsın.')),
            _SwitchTile(
              icon: 'syringe',
              color: AppColors.med,
              bg: AppColors.medBg,
              title: tr('Aşı hatırlatıcısı'),
              meta: tr('Sıradaki zorunlu aşının tarihinde bir kez'),
              value: prefs[NotificationPrefs.vaccine] ?? true,
              onChanged: (v) => setPref(NotificationPrefs.vaccine, v),
            ),
            _SwitchTile(
              icon: 'ai',
              color: AppColors.coral,
              bg: AppColors.peachLight,
              title: tr('Gelişim atağı hatırlatıcısı'),
              meta: tr('Bir sonraki atak yaklaşırken bir kez'),
              value: prefs[NotificationPrefs.leap] ?? true,
              onChanged: (v) => setPref(NotificationPrefs.leap, v),
            ),
            _SwitchTile(
              icon: 'star',
              color: AppColors.growth,
              bg: AppColors.growthBg,
              title: tr('Gelişim basamağı hatırlatıcısı'),
              meta: tr('Yaşına uygun basamak işaretlenmemişken ara sıra'),
              value: prefs[NotificationPrefs.milestone] ?? true,
              onChanged: (v) => setPref(NotificationPrefs.milestone, v),
            ),
            _SwitchTile(
              icon: 'tooth',
              color: AppColors.pump,
              bg: AppColors.pumpBg,
              title: tr('Diş çıkarma hatırlatıcısı'),
              meta: tr('Diş zamanı geldiğinde, işaretlenmemişken ara sıra'),
              value: prefs[NotificationPrefs.tooth] ?? true,
              onChanged: (v) => setPref(NotificationPrefs.tooth, v),
            ),
            _SwitchTile(
              icon: 'charts',
              color: AppColors.doctor,
              bg: AppColors.doctorBg,
              title: tr('Büyüme ölçümü hatırlatıcısı'),
              meta: tr('Son ölçümden ~30 gün sonra bir kez'),
              value: prefs[NotificationPrefs.growth] ?? true,
              onChanged: (v) => setPref(NotificationPrefs.growth, v),
            ),
            AdMenuItem(
              icon: 'med',
              color: AppColors.med,
              bg: AppColors.medBg,
              title: tr('İlaç & vitamin hatırlatıcıları'),
              meta: tr('Her plan için günlük saat · İlaç & Vitamin Takibi'),
              onTap: () => context.push('/medications'),
              trailing: Switch.adaptive(
                value: prefs[NotificationPrefs.medication] ?? true,
                activeThumbColor: AppColors.coral,
                onChanged: (v) => setPref(NotificationPrefs.medication, v),
              ),
            ),
          ],

          // ——— Gebelik (bekleme modu) ———
          if (baby != null && baby.isExpecting) ...[
            adSec(tr('Gebelik')),
            _SwitchTile(
              icon: 'calendar',
              color: AppColors.coral,
              bg: AppColors.peachLight,
              title: tr('Gebelik haftası hatırlatıcısı'),
              meta: tr('Her hafta değiştiğinde bir kez'),
              value: prefs[NotificationPrefs.pregnancyWeek] ?? true,
              onChanged: (v) => setPref(NotificationPrefs.pregnancyWeek, v),
            ),
          ],

          // ——— Aile paylaşımı ———
          adSec(tr('Aile paylaşımı')),
          _SwitchTile(
            icon: 'family',
            color: AppColors.doctor,
            bg: AppColors.doctorBg,
            title: tr('Aile etkinlik bildirimleri'),
            meta: tr('Bir üye kayıt eklediğinde haber ver'),
            value: familyOn,
            onChanged: (v) =>
                ref.read(activityNotifEnabledProvider.notifier).set(v),
          ),
          // Kapalıyken senkron etkisini AÇIKÇA söyle (kullanıcı "veri gelmiyor"
          // sanmasın); açıkken de aynı bilgi sessiz notla durur.
          if (!familyOn)
            _Warn(
              title: tr('Aile paylaşımı açıksa dikkat'),
              body: isIOS
                  ? tr('Diğer üyelerin eklediği kayıtlar için bildirim almazsın. '
                      'Veriler yine de senkronlanır — uygulamayı açtığında hepsi '
                      'karşına gelir.\n\niPhone\'da ek olarak: bu bildirim '
                      'kapalıyken ve uygulama tamamen kapatılmışken (kaydırılarak '
                      'kapatıldığında) ana ekran widget\'ı ile beslenme '
                      'hatırlatıcısı güncellenmeyebilir. Uygulama açık ya da arka '
                      'plandayken güncellenir.')
                  : tr('Diğer üyelerin eklediği kayıtlar için bildirim almazsın. '
                      'Veriler yine de senkronlanır — uygulamayı açtığında hepsi '
                      'karşına gelir.'),
            )
          else
            _Note(tr('Kayıtlar her hâlükârda senkronlanır; bu anahtar yalnız '
                'bildirimin görünmesini yönetir.')),

          // ——— Topluluk ———
          adSec(tr('Topluluk')),
          _SwitchTile(
            icon: 'comment',
            color: AppColors.growth,
            bg: AppColors.growthBg,
            title: tr('Topluluk bildirimleri'),
            meta: tr('Sorununa cevap gelince · cevabın en iyi seçilince'),
            value: prefs[NotificationPrefs.community] ?? true,
            onChanged: (v) => setPref(NotificationPrefs.community, v),
          ),

          // ——— Diğer modüller (kendi ekranlarında yönetilir) ———
          adSec(tr('Diğer hatırlatıcılar')),
          AdMenuItem(
            icon: 'calendar',
            color: AppColors.med,
            bg: AppColors.medBg,
            title: tr('Özel & randevu hatırlatıcıları'),
            meta: tr('Tek tek aç/kapa · saat ve tekrar ayarı'),
            onTap: () => context.push('/reminders'),
          ),
          AdMenuItem(
            icon: 'heart',
            color: AppColors.rose,
            bg: AppColors.roseBg,
            title: tr('Adet Takvimi hatırlatıcıları'),
            meta: tr('Yaklaşan adet · doğurganlık · PMS · günlük kayıt'),
            onTap: () => context.push('/cycle/settings'),
          ),

          const SizedBox(height: 10),
          _Note(tr('Kapatılan bildirimler bu cihaza özeldir; diğer telefon veya '
              'tabletlerini etkilemez. Hesabındaki veriler ve aile paylaşımı '
              'her koşulda senkronlanmaya devam eder.')),
        ],
      ),
    );
  }
}

/// Aktif bebeğin beslenme bildirimleri — Hatırlatıcılar ekranıyla AYNI
/// provider'ları kullanır (gerçek aynalama; iki ekran da tek kaynağı yazar).
class _FeedSection extends ConsumerWidget {
  final String babyId;
  const _FeedSection({required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(feedReminderProvider(babyId));
    final quiet = ref.watch(quietHoursProvider(babyId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwitchTile(
          icon: 'feed',
          color: AppColors.feed,
          bg: AppColors.feedBg,
          title: tr('Beslenme hatırlatıcısı'),
          meta: cfg.summary,
          value: cfg.enabled,
          onChanged: (v) {
            final next = cfg.copyWith(enabled: v);
            updateFeedReminder(ref, babyId, next);
            if (v) showFeedReminderSheet(context, ref, babyId, next);
          },
          onTap: () => showFeedReminderSheet(context, ref, babyId, cfg),
        ),
        // Alt seçenekler yalnız hatırlatıcı açıkken anlamlı.
        if (cfg.enabled) ...[
          _SwitchTile(
            icon: 'clock',
            color: AppColors.pump,
            bg: AppColors.pumpBg,
            title: tr('"Kaydı unuttun mu?" dürtmesi'),
            meta: tr('Beslenme saatinden 30 dk sonra kayıt yoksa hatırlat'),
            value: cfg.forgotEnabled,
            onChanged: (v) =>
                updateFeedReminder(ref, babyId, cfg.copyWith(forgotEnabled: v)),
          ),
          AdMenuItem(
            icon: 'bell',
            color: AppColors.diaper,
            bg: AppColors.diaperBg,
            title: tr('Ön-hatırlatma'),
            meta: cfg.preMin > 0
                ? trp('Beslenmeden {n} dk önce uyar', {'n': cfg.preMin})
                : tr('Kapalı'),
            onTap: () => showFeedReminderSheet(context, ref, babyId, cfg),
          ),
        ],
        _SwitchTile(
          icon: 'moon',
          color: AppColors.sleep,
          bg: AppColors.sleepBg,
          title: tr('Sessiz saat'),
          meta: quiet.summary,
          value: quiet.enabled,
          onChanged: (v) {
            final next = quiet.copyWith(enabled: v);
            updateQuietHours(ref, babyId, next);
            if (v) showQuietHoursSheet(context, ref, babyId, next);
          },
          onTap: () => showQuietHoursSheet(context, ref, babyId, quiet),
        ),
      ],
    );
  }
}

/// Sistem (cihaz) bildirim izni kapalıysa uyarı + "İzin ver" düğmesi.
/// Uygulama-içi anahtarlar açık olsa bile sistem izni kapalıyken HİÇBİR bildirim
/// gelmez; kullanıcı sebebini göremeden ayarları kurcalıyordu. Kullanıcı sistem
/// ayarlarından izni sonradan açabildiği için öne gelişte yeniden kontrol edilir.
class _SystemPermissionCard extends StatefulWidget {
  const _SystemPermissionCard();

  @override
  State<_SystemPermissionCard> createState() => _SystemPermissionCardState();
}

class _SystemPermissionCardState extends State<_SystemPermissionCard>
    with WidgetsBindingObserver {
  bool? _enabled; // null = henüz bilinmiyor → kart çizilmez
  // "İzin ver"e basıldı ama izin AÇILMADI → OS diyaloğu gösterilmiyor demektir
  // (kalıcı red ya da Android 12 ve altı). Artık tek yol sistem ayar sayfası.
  bool _needsSettings = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final v = await NotificationService.instance.systemEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = v;
      if (v) _needsSettings = false; // ayarlardan açıldı → kart tamamen kalkar
    });
  }

  /// Önce OS diyaloğunu dene; açılmadıysa (diyalog hiç çıkmıyor) kullanıcıyı
  /// sistem ayar sayfasına yönlendiren ikinci adıma geç.
  Future<void> _onPressed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_needsSettings) {
        await NotificationService.instance.openSystemSettings();
        return; // dönüşte didChangeAppLifecycleState → _check()
      }
      final ok = await NotificationService.instance.requestPermission();
      if (!mounted) return;
      setState(() {
        _enabled = ok;
        _needsSettings = !ok;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled != false) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.feverBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.fever.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdenaIcon('shieldAlert', size: 18, color: AppColors.fever),
              const SizedBox(width: 9),
              Expanded(
                child: Text(tr('Cihaz bildirimleri kapalı'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _needsSettings
                ? tr('Bildirim izni daha önce reddedilmiş, bu yüzden uygulama '
                    'artık izin penceresini açamıyor. Telefon ayarlarından '
                    'Adena Baby bildirimlerini aç.')
                : tr('Telefonunun ayarlarında Adena Baby bildirimleri kapalı. '
                    'Aşağıdaki anahtarlar açık olsa bile hiçbir bildirim gelmez.'),
            style: TextStyle(
                fontSize: 12, height: 1.45, fontWeight: FontWeight.w700,
                color: AppColors.ink2),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.fever,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : _onPressed,
              child: Text(
                  _needsSettings ? tr('Telefon ayarlarını aç') : tr('İzin ver'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Anahtarlı menü satırı — AdMenuItem + sağda Switch (satıra dokununca da toggle,
/// [onTap] verilmişse dokunuş ayrıntı sheet'ini açar).
class _SwitchTile extends StatelessWidget {
  final String icon;
  final Color color;
  final Color bg;
  final String title;
  final String? meta;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTap;

  const _SwitchTile({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.value,
    required this.onChanged,
    this.meta,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => AdMenuItem(
        icon: icon,
        color: color,
        bg: bg,
        title: title,
        meta: meta,
        trailing: Switch.adaptive(
          value: value,
          activeThumbColor: AppColors.coral,
          onChanged: onChanged,
        ),
        onTap: onTap ?? () => onChanged(!value),
      );
}

/// Sessiz bilgi notu (kart altı açıklama).
class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: AppColors.muted),
        ),
      );
}

/// Dikkat kartı — bir bildirimin kapatılmasının aile paylaşımı/senkron üzerindeki
/// etkisini açıkça anlatır (sessiz nottan ayrışsın diye altın zemin).
class _Warn extends StatelessWidget {
  final String title;
  final String body;
  const _Warn({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          color: AppColors.goldBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AdenaIcon('shieldAlert', size: 17, color: AppColors.goldD),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              body,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink2),
            ),
          ],
        ),
      );
}

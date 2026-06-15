import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/notification_service.dart';
import '../../core/push_service.dart';
import '../../core/theme.dart';
import '../../data/feed_reminder_cache.dart';
import '../babies/baby_controller.dart';
import '../records/record_controller.dart';

/// Geliştirici / Bildirim Test ekranı — YALNIZ debug derlemede görünür (ayarlardan
/// kDebugMode ile gating'li). İki test türü vardır:
///
/// 1) GERÇEK kayıt → diğer üyelere push: bu cihazda (X) gerçek bir beslenme kaydı
///    ekler. Sunucuya gider, backend diğer üyelere (Y) FCM push gönderir; Y'nin
///    cihazında bildirim düşer ve beslenme hatırlatıcısı yeni kayda göre kayar.
///    Çapraz-cihaz akışın gerçek testi budur (paylaşımlı bebek + Y giriş yapmış +
///    FCM gerekir).
///
/// 2) YEREL testler (bu cihaza): sunucu/paylaşım olmadan, kendi cihazında bildirim
///    üretir — handler'ı ve hatırlatıcıyı tek cihazda denemek için.
///
/// Türkçe metinler kasıtlı tr() ile SARILMADI: salt geliştirici aracı, i18n
/// çeviri toplamasını kirletmesin.
class DevToolsScreen extends ConsumerStatefulWidget {
  const DevToolsScreen({super.key});

  @override
  ConsumerState<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends ConsumerState<DevToolsScreen> {
  String _feedSub = 'formula'; // simüle/eklenecek beslenmenin alt türü
  String? _token;
  FeedReminderSnapshot? _snap;
  List<PendingNotificationRequest> _pending = const [];
  String _log = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (mounted) setState(() => _token = t);
    } catch (e) {
      if (mounted) setState(() => _token = 'alınamadı: $e');
    }
  }

  Future<void> _refresh() async {
    final baby = ref.read(activeBabyProvider);
    final snap = baby == null ? null : await FeedReminderCache().read(baby.id);
    final pending = await NotificationService.instance.pending();
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _pending = pending;
    });
  }

  void _say(String s) => setState(() => _log = s);

  /// Seçilen türde [_feedSub] alt türü için data map'i (tamamlanmış beslenme).
  Map<String, dynamic> _feedData() {
    final now = DateTime.now();
    switch (_feedSub) {
      case 'breast':
        return {
          'sub': 'breast',
          'start_ts': now.subtract(const Duration(minutes: 10)).toUtc().toIso8601String(),
          'end_ts': now.toUtc().toIso8601String(),
          'left_min': 10,
          'right_min': 0,
        };
      case 'pumped':
        return {'sub': 'pumped', 'amount_ml': 90};
      default:
        return {'sub': 'formula', 'amount_ml': 90};
    }
  }

  /// (1) GERÇEK kayıt ekle → sunucu → diğer üyelere (Y) push. Normal uygulama
  /// akışının aynısı; bu cihaz X gibi davranır.
  Future<void> _addRealFeed() async {
    final baby = ref.read(activeBabyProvider);
    if (baby == null) {
      _say('Aktif bebek yok.');
      return;
    }
    await ref.read(recordActionsProvider).addFeed(baby.id, _feedData());
    await _refresh();
    _say('GERÇEK $_feedSub kaydı eklendi → sync → diğer üyelere (Y) push gidecek '
        '(bebek paylaşımlı + Y giriş yapmış + FCM açıksa). Y cihazında bildirim '
        've hatırlatıcı kaymasını kontrol et.');
  }

  /// (2) YEREL: bu cihaza "başka üye ekledi" push'u GELMİŞ gibi davran. Backend'in
  /// göndereceği payload'ı kurup handlePushMessage'ı çağırır — sunucu/paylaşım
  /// gerekmez. Y cihazında push'un ne yapacağını tek cihazda görmek için.
  Future<void> _simulateLocalReceive() async {
    final baby = ref.read(activeBabyProvider);
    if (baby == null) {
      _say('Aktif bebek yok.');
      return;
    }
    final now = DateTime.now();
    final data = <String, String>{
      'type': 'family_activity',
      'baby_id': baby.id,
      'title': baby.name,
      'body': 'Test: $_feedSub kaydı eklendi',
      'last_feed_ts': now.toUtc().toIso8601String(),
      'feed_sub': _feedSub,
      if (_feedSub != 'breast') 'widget_update': 'feed',
    };
    await handlePushMessage(RemoteMessage(data: data));
    await _refresh();

    final s = _snap;
    final String result;
    if (s == null || !s.enabled) {
      result = 'Hatırlatıcı KAPALI (snapshot yok/enabled=false) → yeniden planlama '
          'atlandı. Önce bu bebekte beslenme hatırlatıcısını aç.';
    } else if (!s.matchesBase(_feedSub)) {
      result = 'baseType=${s.baseType}, sub=$_feedSub UYUŞMADI → hatırlatıcı '
          'kasıtlı olarak DEĞİŞMEDİ (doğru davranış).';
    } else {
      final next = now.add(Duration(minutes: s.intervalMin));
      result = 'Yerel handler çalıştı ✓ → sonraki beslenme uyarısı: ${_fmt(next)} '
          '(şimdi + ${s.intervalMin} dk).';
    }
    _say(result);
  }

  Future<void> _scheduleSoon({bool sound = true}) async {
    final baby = ref.read(activeBabyProvider);
    if (baby == null) return;
    final next = DateTime.now().add(const Duration(minutes: 1));
    await NotificationService.instance.scheduleFeedReminder(
      enabled: true,
      nextTime: next,
      preMin: 0,
      slot: baby.notifSlot,
      babyName: baby.name,
      sound: sound,
    );
    await _refresh();
    _say('Beslenme uyarısı +1 dk (${_fmt(next)}) planlandı '
        '(${sound ? 'sesli' : 'sessiz'}).');
  }

  Future<void> _showActivity() async {
    final baby = ref.read(activeBabyProvider);
    await NotificationService.instance.showActivity(
      title: baby?.name ?? 'Adena Baby',
      body: 'Test: bir üye kayıt ekledi',
    );
    _say('Aile etkinlik bildirimi (bu cihazda) gösterildi.');
  }

  Future<void> _cancelAll() async {
    final baby = ref.read(activeBabyProvider);
    if (baby != null) {
      final slot = baby.notifSlot;
      await NotificationService.instance.scheduleFeedReminder(
          enabled: false, nextTime: null, preMin: 0, slot: slot, babyName: baby.name);
      await NotificationService.instance.cancelTimer(NotificationService.sleepIdFor(slot));
      await NotificationService.instance.cancelTimer(NotificationService.breastIdFor(slot));
    }
    await _refresh();
    _say('Aktif bebeğin planlı bildirimleri iptal edildi.');
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(activeBabyProvider);
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(title: const Text('Geliştirici · Bildirim Testi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _info('Aktif bebek',
              baby == null ? '— (önce bir bebek seç)' : '${baby.name}  ·  slot ${baby.notifSlot}'),
          _info(
            'Beslenme hatırlatıcısı (snapshot)',
            snap == null
                ? 'YOK — bu bebekte hatırlatıcı hiç açılmamış'
                : 'enabled=${snap.enabled} · her ${snap.intervalMin}dk · baseType=${snap.baseType}'
                    ' · ön ${snap.preMin}dk · ses=${snap.sound} · sessizSaat=${snap.quiet.enabled}',
          ),

          const SizedBox(height: 8),
          const Text('Beslenme türü (her iki test de bunu kullanır)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'breast', label: Text('Anne sütü')),
              ButtonSegment(value: 'formula', label: Text('Mama')),
              ButtonSegment(value: 'pumped', label: Text('Biberon')),
            ],
            selected: {_feedSub},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _feedSub = s.first),
          ),

          adSec('1) Gerçek kayıt  →  diğer üyelere (Y) push'),
          Text(
            'Bu cihaz (X) için GERÇEK beslenme kaydı ekler; sunucuya gider ve '
            'diğer üyelerin (Y) cihazına push düşer + onların hatırlatıcısı yeni '
            'kayda göre kayar. Gerektirir: bebek PAYLAŞIMLI + Y giriş yapmış + FCM açık.',
            style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _btn('Beslenme ekle (gerçek) → Y\'ye push', 'send', AppColors.coral,
              AppColors.feedBg, _addRealFeed),

          adSec('2) Yerel testler (bu cihaza)'),
          Text(
            'Sunucu/paylaşım olmadan kendi cihazında bildirim üretir.',
            style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _btn('Bu cihaza "$_feedSub eklendi" push\'u geldi gibi davran', 'bell',
              AppColors.doctor, AppColors.doctorBg, _simulateLocalReceive),
          _btn('Beslenme uyarısını +1 dk planla (sesli)', 'clock', AppColors.growth,
              AppColors.growthBg, () => _scheduleSoon(sound: true)),
          _btn('Beslenme uyarısını +1 dk planla (sessiz)', 'clock', AppColors.muted,
              AppColors.line, () => _scheduleSoon(sound: false)),
          _btn('Aile etkinlik bildirimi göster', 'family', AppColors.pump,
              AppColors.pumpBg, _showActivity),
          _btn('Aktif bebeğin bildirimlerini iptal et', 'trash', AppColors.muted,
              AppColors.line, _cancelAll),

          adSec('Durum'),
          _info('Planlı (bekleyen) bildirim', '${_pending.length} adet'),
          for (final p in _pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('  • #${p.id}  ${p.title ?? ''}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          _btn('Durumu yenile', 'clock', AppColors.pump, AppColors.pumpBg, _refresh),

          adSec('FCM token'),
          GestureDetector(
            onTap: () {
              if (_token != null) {
                Clipboard.setData(ClipboardData(text: _token!));
                _say('Token panoya kopyalandı.');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(_token ?? 'yükleniyor…',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ),
          ),

          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.feedBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_log,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w800)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _btn(String title, String icon, Color color, Color bg, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AdMenuItem(
          icon: icon,
          color: color,
          bg: bg,
          title: title,
          onTap: onTap,
        ),
      );
}

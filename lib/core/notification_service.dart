import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/quiet_hours.dart';
import '../models/reminder.dart';
import 'i18n.dart';

/// Yerel bildirim servisi — hatırlatıcıları cihaz bildirimlerine bağlar.
/// Şimdilik yalnız "vitamin" (günlük belirli saat) tipi planlanır; kural-tabanlı
/// tipler (feed/vaccine/nudge) ileride (arka plan iş/hesaplama gerekir).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;

  static const _channelId = 'reminders';
  static final _channelName = tr('Hatırlatıcılar');

  // Süren sayaç bildirimleri (uyku/emzirme) — ayrı sessiz kanal + sabit id'ler.
  static const _timerChannelId = 'timers';
  static final _timerChannelName = tr('Süren sayaçlar');
  static const sleepTimerId = 900001;
  static const breastTimerId = 900002;

  // Beslenme hatırlatıcısı — sesli/heads-up kanal + sabit id'ler.
  static const feedChannelId = 'feed_reminders';
  static final feedChannelName = tr('Beslenme hatırlatıcıları');
  // Sessiz varyant — ayrı kanal (Android'de ses/önem kanala kilitli; aynı kanalda
  // playSound:false sonradan çalışmaz, bu yüzden iki kanal kullanıyoruz).
  static const feedSilentChannelId = 'feed_reminders_silent';
  static final feedSilentChannelName = tr('Beslenme hatırlatıcıları (sessiz)');
  static const feedMainId = 800001; // ana uyarı
  static const feedPreId = 800002; // ön-hatırlatma
  static const snoozeAction = 'snooze_feed';
  bool _exactAsked = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final dynamic res = await FlutterTimezone.getLocalTimezone();
      // flutter_timezone 5.x: TimezoneInfo(.identifier); eski sürüm: String.
      final name = res is String ? res : (res as dynamic).identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // tz.local UTC'de kalır — saat kayması olabilir ama çökmez.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onResponse, // ön planda aksiyon (ertele)
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    _ready = true;
  }

  /// Android 12+ kesin alarm iznini ister (yalnız bir kez). Beslenme uyarısının
  /// tam dakikasında gelmesi için gerekir.
  Future<void> _ensureExactAlarm() async {
    if (_exactAsked) return;
    _exactAsked = true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
  }

  /// Android 13+ bildirim iznini ister (yalnız bir kez sorar).
  Future<void> _ensurePermission() async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: tr('Vitamin/ilaç ve bakım hatırlatıcıları'),
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  /// Süren sayaç bildirimi (uyku/emzirme). [since]'dan itibaren Android'in
  /// kronometresiyle kendi kendine sayar (uygulama saniye saniye güncellemez).
  /// [running] false ise (duraklatıldı) kronometre durur, süre body'de yazılı kalır.
  /// Foreground service yok → uygulama açık/arka plandayken görünür.
  Future<void> showTimer({
    required int id,
    required String title,
    required String body,
    required DateTime since,
    required bool running,
  }) async {
    if (!_ready) await init();
    await _ensurePermission();
    final android = AndroidNotificationDetails(
      _timerChannelId,
      _timerChannelName,
      channelDescription: tr('Süren uyku ve emzirme sayaçları'),
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true, // kaydırarak kapatılamaz
      autoCancel: false,
      onlyAlertOnce: true, // güncellemelerde tekrar ses/titreşim yok
      showWhen: true,
      when: since.millisecondsSinceEpoch,
      usesChronometer: running, // canlı sayan kronometre
      category: AndroidNotificationCategory.stopwatch,
      playSound: false,
      enableVibration: false,
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android),
    );
  }

  Future<void> cancelTimer(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  /// Tek bir hatırlatıcı bildirimini iptal eder (ör. silinince).
  Future<void> cancelReminder(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  /// Beslenme hatırlatıcısını planlar: ana uyarı (kesin/sesli + "Ertele") ve
  /// opsiyonel ön-hatırlatma. [nextTime] geçmişse ya da kapalıysa iptal eder.
  /// Her beslenme kaydında yeniden çağrılır (çapa = son beslenme).
  Future<void> scheduleFeedReminder({
    required bool enabled,
    required DateTime? nextTime,
    required int preMin,
    bool sound = false,
    QuietHours? quiet,
  }) async {
    if (!_ready) await init();
    await _plugin.cancel(id: feedMainId);
    await _plugin.cancel(id: feedPreId);
    if (!enabled || nextTime == null) return;
    await _ensurePermission();
    await _ensureExactAlarm();
    final now = DateTime.now();
    // Efektif ses = "Sesli" açık VE o bildirim anı sessiz saat penceresinde değil.
    // (Sessiz saat her zaman kazanır.) Ana uyarı ve ön-hatırlatma ayrı zamanlarda
    // olduğu için her biri için ayrı hesaplanır.
    if (nextTime.isAfter(now)) {
      await _zonedFeed(feedMainId, nextTime, tr('Beslenme zamanı'),
          tr('Tahmini beslenme vakti geldi 🍼'),
          withSnooze: true, sound: sound && !(quiet?.covers(nextTime) ?? false));
    }
    if (preMin > 0) {
      final pre = nextTime.subtract(Duration(minutes: preMin));
      if (pre.isAfter(now)) {
        await _zonedFeed(feedPreId, pre, trp('Beslenmeye {n} dk', {'n': preMin}),
            trp('Yaklaşık {n} dk sonra beslenme zamanı', {'n': preMin}),
            withSnooze: false, sound: sound && !(quiet?.covers(pre) ?? false));
      }
    }
  }

  Future<void> _zonedFeed(int id, DateTime when, String title, String body,
      {required bool withSnooze, required bool sound}) async {
    final android = AndroidNotificationDetails(
      sound ? feedChannelId : feedSilentChannelId,
      sound ? feedChannelName : feedSilentChannelName,
      channelDescription: tr('Beslenme zamanı hatırlatıcıları'),
      importance: sound ? Importance.max : Importance.low,
      priority: sound ? Priority.high : Priority.low,
      playSound: sound,
      enableVibration: sound,
      category: AndroidNotificationCategory.reminder,
      actions: withSnooze
          ? [
              AndroidNotificationAction(snoozeAction, tr('Ertele 10 dk'),
                  showsUserInterface: false)
            ]
          : null,
    );
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(android: android),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: sound ? 'feed:1' : 'feed:0', // ertele (arka plan) ses tercihini taşır
    );
  }

  /// Ön plandayken "Ertele 10 dk" aksiyonu (arka plan için top-level handler).
  void _onResponse(NotificationResponse r) {
    if (r.actionId == snoozeAction) {
      final when = DateTime.now().add(const Duration(minutes: 10));
      // Ses tercihi, ertelenen bildirimin payload'ında taşınır ('feed:1'/'feed:0').
      _zonedFeed(feedMainId, when, tr('Beslenme zamanı (ertelendi)'), tr('10 dk ertelendi 🍼'),
          withSnooze: true, sound: r.payload == 'feed:1');
    }
  }

  /// Hatırlatıcı listesini bildirimlerle eşitler: yönetilen id'leri temizle (feed/
  /// sayaç id'lerine dokunmadan), sonra schedule şekline göre kur. İki şekil:
  ///   • günlük:  {repeat:'daily', time:'HH:MM', title?}  → her gün o saatte
  ///   • tek-sefer: {repeat:'once', at:ISO8601, title?}   → o anda bir kez (geçmiş atlanır)
  /// Eski/uygulanmamış şekiller (vaccine days_before, nudge idle_hours) atlanır.
  Future<void> sync(List<Reminder> reminders) async {
    if (!_ready) await init();
    final active = reminders.where((r) => r.enabled).toList();
    if (active.isNotEmpty) await _ensurePermission();

    // cancelAll yerine yalnız bu hatırlatıcı id'lerini iptal et (feed 800xxx /
    // sayaç 900xxx bildirimleri korunur).
    for (final r in reminders) {
      await _plugin.cancel(id: r.id);
    }
    final now = DateTime.now();
    for (final r in active) {
      final s = r.schedule;
      final title = (s['title'] as String?)?.trim();
      if (s['repeat'] == 'once' || s['at'] != null) {
        // Tek-seferlik: belirli tarih-saatte bir kez (geçmişse kurma).
        final at = DateTime.tryParse(s['at'] as String? ?? '');
        if (at == null || !at.isAfter(now)) continue;
        await _scheduleOnce(r.id, at, title);
      } else if (s['time'] != null) {
        // Günlük tekrar.
        final parts = (s['time'] as String).split(':');
        if (parts.length != 2) continue;
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h == null || m == null) continue;
        await _scheduleDaily(r.id, h, m, title);
      }
    }
  }

  Future<void> _scheduleDaily(int id, int hour, int minute, [String? title]) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      title: title != null && title.isNotEmpty ? title : tr('Hatırlatıcı'),
      body: tr('Hatırlatma zamanı ⏰'),
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // her gün aynı saat
    );
  }

  /// Tek-seferlik hatırlatıcı (randevu/özel) — belirtilen anda bir kez, kesin alarm.
  Future<void> _scheduleOnce(int id, DateTime when, String? title) async {
    await _ensureExactAlarm();
    await _plugin.zonedSchedule(
      id: id,
      title: title != null && title.isNotEmpty ? title : tr('Hatırlatıcı'),
      body: tr('Hatırlatma zamanı ⏰'),
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}

/// Arka planda (uygulama kapalı/öldürülmüş) "Ertele 10 dk" aksiyonu — beslenme
/// uyarısını 10 dk sonraya yeniden kurar. İzole isolate'ta çalışır.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId != NotificationService.snoozeAction) return;
  _snoozeFeedInBackground(response.payload == 'feed:1'); // ses tercihi payload'da
}

Future<void> _snoozeFeedInBackground(bool sound) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'));
  await plugin.initialize(settings: init);
  tzdata.initializeTimeZones();
  // Göreli +10 dk → tz.local UTC olsa bile mutlak an doğru.
  final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
  final android = AndroidNotificationDetails(
    sound ? NotificationService.feedChannelId : NotificationService.feedSilentChannelId,
    sound
        ? NotificationService.feedChannelName
        : NotificationService.feedSilentChannelName,
    importance: sound ? Importance.max : Importance.low,
    priority: sound ? Priority.high : Priority.low,
    playSound: sound,
    enableVibration: sound,
    category: AndroidNotificationCategory.reminder,
    actions: [
      AndroidNotificationAction(NotificationService.snoozeAction, tr('Ertele 10 dk'),
          showsUserInterface: false),
    ],
  );
  await plugin.zonedSchedule(
    id: NotificationService.feedMainId,
    title: tr('Beslenme zamanı (ertelendi)'),
    body: tr('10 dk ertelendi 🍼'),
    scheduledDate: when,
    notificationDetails: NotificationDetails(android: android),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: sound ? 'feed:1' : 'feed:0',
  );
}

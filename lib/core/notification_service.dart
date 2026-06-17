import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/quiet_hours.dart';
import '../models/reminder.dart';
import 'i18n.dart';

/// Yerel bildirim servisi — hatırlatıcıları cihaz bildirimlerine bağlar.
/// Üç tür: özel/randevu hatırlatıcıları (günlük veya tek-sefer), beslenme uyarısı
/// (son beslenme + aralık) ve süren uyku/emzirme sayaçları.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;

  static const _channelId = 'reminders';
  static final _channelName = tr('Hatırlatıcılar');

  // Süren sayaç bildirimleri (uyku/emzirme) — ayrı sessiz kanal.
  static const _timerChannelId = 'timers';
  static final _timerChannelName = tr('Süren sayaçlar');

  // Beslenme hatırlatıcısı — sesli/heads-up kanal.
  static const feedChannelId = 'feed_reminders';
  static final feedChannelName = tr('Beslenme hatırlatıcıları');
  // Sessiz varyant — ayrı kanal (Android'de ses/önem kanala kilitli; aynı kanalda
  // playSound:false sonradan çalışmaz, bu yüzden iki kanal kullanıyoruz).
  static const feedSilentChannelId = 'feed_reminders_silent';
  static final feedSilentChannelName = tr('Beslenme hatırlatıcıları (sessiz)');

  // Çok-bebek: bildirim id'leri bebek "slot"una (0..999) göre ayrılır → aynı türde
  // iki bebeğin bildirimi çakışmaz. Taban + slot; türler arası 10000 boşluk.
  static const _feedMainBase = 800000;
  static const _feedPreBase = 810000;
  static const _sleepBase = 900000;
  static const _breastBase = 910000;
  static int feedMainIdFor(int slot) => _feedMainBase + slot;
  static int feedPreIdFor(int slot) => _feedPreBase + slot;
  static int sleepIdFor(int slot) => _sleepBase + slot;
  static int breastIdFor(int slot) => _breastBase + slot;
  static const snoozeAction = 'snooze_feed';
  static const snoozeCategoryId = 'feed_snooze'; // iOS: "Ertele" aksiyonlu kategori
  bool _exactAsked = false;

  // Aile etkinlik bildirimleri (başka üye kayıt ekleyince) — ayrı kanal + dönen id.
  static const _activityChannelId = 'family_activity';
  static final _activityChannelName = tr('Aile etkinliği');
  static const _activityGroup = 'adena_family_activity'; // Android bildirim grubu
  static const _activityBaseId = 700000;
  int _activitySeq = 0;

  /// iOS bildirim ayarları (kategori = ertele aksiyonu). İzinler açılışta DEĞİL,
  /// gerektiğinde (_ensurePermission) istenir → açılış engellenmez.
  static DarwinInitializationSettings _darwinInit() => DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            snoozeCategoryId,
            actions: [DarwinNotificationAction.plain(snoozeAction, tr('Ertele 10 dk'))],
          ),
        ],
      );

  Future<void> init() async {
    if (_ready) return;
    _ready = true; // tekrar denemeyi önle; hata olsa da UI engellenmez
    tzdata.initializeTimeZones();
    try {
      final dynamic res = await FlutterTimezone.getLocalTimezone();
      // flutter_timezone 5.x: TimezoneInfo(.identifier); eski sürüm: String.
      final name = res is String ? res : (res as dynamic).identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // tz.local UTC'de kalır — saat kayması olabilir ama çökmez.
    }
    try {
      final android = const AndroidInitializationSettings('@mipmap/ic_launcher');
      final settings = InitializationSettings(android: android, iOS: _darwinInit());
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onResponse, // ön planda aksiyon (ertele)
        onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
      );
    } catch (_) {
      // Bildirim altyapısı kurulamazsa uygulama yine de çalışır.
    }
  }

  /// Geliştirici/teşhis: planlı (bekleyen) bildirimler — yalnız debug ekranı için.
  Future<List<PendingNotificationRequest>> pending() async {
    if (!_ready) await init();
    return _plugin.pendingNotificationRequests();
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

  /// Kesin alarm izni varsa exact, yoksa inexact döner. Android 12+ kullanıcı
  /// "kesin alarm"ı reddederse beslenme/randevu uyarısı TAMAMEN kaybolmasın —
  /// ±birkaç dakika gecikmeyle de olsa gelsin.
  Future<AndroidScheduleMode> _alarmMode() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return AndroidScheduleMode.exactAllowWhileIdle; // iOS
    final can = await android.canScheduleExactNotifications() ?? true;
    return can
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Bildirim iznini ister (yalnız bir kez sorar). Android 13+ ve iOS.
  Future<void> _ensurePermission() async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: tr('Özel hatırlatıcılar ve randevu uyarıları'),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
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
      notificationDetails: NotificationDetails(
        android: android,
        // iOS'ta "ongoing"/kronometre yok → sessiz banner (güncellemede ses yok).
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  Future<void> cancelTimer(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  /// Aile etkinlik bildirimi — başka bir üye kayıt eklediğinde (polling ile bulunur).
  /// [title] bebeğin adı (çok bebekte hangisi olduğu ayırt edilsin), [body] eylem.
  /// Her olay için ayrı id (üst üste binmesin) — 700000..700049 arası döner.
  Future<void> showActivity({required String title, required String body}) async {
    if (!_ready) await init();
    await _ensurePermission();
    final id = _activityBaseId + (_activitySeq++ % 50);
    final android = AndroidNotificationDetails(
      _activityChannelId,
      _activityChannelName,
      channelDescription: tr('Aile üyelerinin eklediği kayıt bildirimleri'),
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.social,
      // Çok aktif ailede ayrı ayrı birikmesin → sistem tek başlık altında toplar.
      groupKey: _activityGroup,
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
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
    int slot = 0,
    String babyName = '',
    bool sound = false,
    QuietHours? quiet,
  }) async {
    if (!_ready) await init();
    await _plugin.cancel(id: feedMainIdFor(slot));
    await _plugin.cancel(id: feedPreIdFor(slot));
    if (!enabled || nextTime == null) return;
    await _ensurePermission();
    await _ensureExactAlarm();
    final now = DateTime.now();
    // Başlığa bebek adı (çok bebekte hangisi olduğu belli olsun).
    final prefix = babyName.isNotEmpty ? '$babyName · ' : '';
    // Efektif ses = "Sesli" açık VE o bildirim anı sessiz saat penceresinde değil.
    // (Sessiz saat her zaman kazanır.) Ana uyarı ve ön-hatırlatma ayrı zamanlarda
    // olduğu için her biri için ayrı hesaplanır.
    if (nextTime.isAfter(now)) {
      await _zonedFeed(feedMainIdFor(slot), nextTime,
          '$prefix${tr('Beslenme zamanı')}', tr('Tahmini beslenme vakti geldi 🍼'),
          withSnooze: true, sound: sound && !(quiet?.covers(nextTime) ?? false),
          slot: slot, babyName: babyName);
    }
    if (preMin > 0) {
      final pre = nextTime.subtract(Duration(minutes: preMin));
      if (pre.isAfter(now)) {
        await _zonedFeed(feedPreIdFor(slot), pre,
            '$prefix${trp('Beslenmeye {n} dk kaldı', {'n': preMin})}',
            trp('Yaklaşık {n} dk sonra beslenme zamanı', {'n': preMin}),
            withSnooze: false, sound: sound && !(quiet?.covers(pre) ?? false),
            slot: slot, babyName: babyName);
      }
    }
  }

  Future<void> _zonedFeed(int id, DateTime when, String title, String body,
      {required bool withSnooze,
      required bool sound,
      required int slot,
      required String babyName}) async {
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
    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: sound,
      categoryIdentifier: withSnooze ? snoozeCategoryId : null,
    );
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(android: android, iOS: ios),
      androidScheduleMode: await _alarmMode(),
      // Ertele (arka plan) için ses + bebek slotu + ad taşınır.
      payload: feedPayload(sound, slot, babyName),
    );
  }

  /// Ertele payload kodla/çöz — ses + slot + bebek adı (\u0001 ayraçlı; ad içinde
  /// görünmez). Format: feed\u00010/1\u0001slot\u0001ad.
  static String feedPayload(bool sound, int slot, String babyName) =>
      'feed\u0001${sound ? 1 : 0}\u0001$slot\u0001$babyName';

  static ({bool sound, int slot, String babyName}) parseFeedPayload(String? p) {
    final parts = (p ?? '').split('\u0001');
    if (parts.length >= 4 && parts[0] == 'feed') {
      return (sound: parts[1] == '1', slot: int.tryParse(parts[2]) ?? 0, babyName: parts[3]);
    }
    // Eski format ('feed:1'/'feed:0') ya da bilinmeyen → güvenli varsayılan.
    return (sound: p == 'feed:1', slot: 0, babyName: '');
  }

  /// Ön plandayken "Ertele 10 dk" aksiyonu (arka plan için top-level handler).
  void _onResponse(NotificationResponse r) {
    if (r.actionId == snoozeAction) {
      final when = DateTime.now().add(const Duration(minutes: 10));
      final fp = parseFeedPayload(r.payload);
      final prefix = fp.babyName.isNotEmpty ? '${fp.babyName} · ' : '';
      _zonedFeed(feedMainIdFor(fp.slot), when,
          '$prefix${tr('Beslenme zamanı (ertelendi)')}', tr('10 dk ertelendi 🍼'),
          withSnooze: true, sound: fp.sound, slot: fp.slot, babyName: fp.babyName);
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
      androidScheduleMode: await _alarmMode(),
    );
  }

  // Adet Takvimi hatırlatıcıları — kullanıcıya özel, kendi id aralığı (feed/sayaç/
  // hatırlatıcı id'lerinden ayrı). 0=adet, 1=doğurganlık, 2=PMS, 3=günlük kayıt.
  static const _cycleBase = 600000;

  /// Adet modülü hatırlatıcılarını cihaz bildirimlerine kurar. Önce kendi
  /// aralığını temizler, sonra ayar + döngü tahminine göre etkin olanları planlar.
  /// [reminders] = {period:{on}, fertile:{on}, pms:{on}, log:{on,time}}.
  Future<void> syncCycle({
    required Map<String, dynamic> reminders,
    DateTime? nextPeriod,
    DateTime? fertileStart,
    int periodLeadDays = 3,
  }) async {
    if (!_ready) await init();
    for (var i = 0; i < 4; i++) {
      await _plugin.cancel(id: _cycleBase + i);
    }
    final now = DateTime.now();
    bool on(String k) => reminders[k] is Map && (reminders[k]['on'] == true);
    final anyOn = ['period', 'fertile', 'pms', 'log'].any(on);
    if (anyOn) await _ensurePermission();

    if (on('period') && nextPeriod != null) {
      final at = DateTime(nextPeriod.year, nextPeriod.month, nextPeriod.day, 9)
          .subtract(Duration(days: periodLeadDays));
      if (at.isAfter(now)) {
        await _scheduleOnce(_cycleBase + 0, at, tr('Adetin yaklaşıyor 🌸'));
      }
    }
    if (on('fertile') && fertileStart != null) {
      final at = DateTime(fertileStart.year, fertileStart.month, fertileStart.day, 9);
      if (at.isAfter(now)) {
        await _scheduleOnce(_cycleBase + 1, at, tr('Doğurganlık pencereniz başlıyor'));
      }
    }
    if (on('pms') && nextPeriod != null) {
      final at = DateTime(nextPeriod.year, nextPeriod.month, nextPeriod.day, 9)
          .subtract(const Duration(days: 5));
      if (at.isAfter(now)) {
        await _scheduleOnce(_cycleBase + 2, at, tr('PMS dönemi yaklaşıyor'));
      }
    }
    if (on('log')) {
      final time = (reminders['log']?['time'] as String?) ?? '21:00';
      final parts = time.split(':');
      final h = int.tryParse(parts.first) ?? 21;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      await _scheduleDaily(_cycleBase + 3, h, m, tr('Bugünü kaydetmeyi unutma 🌙'));
    }
  }
}

/// Arka planda (uygulama kapalı/öldürülmüş) "Ertele 10 dk" aksiyonu — beslenme
/// uyarısını 10 dk sonraya yeniden kurar. İzole isolate'ta çalışır.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId != NotificationService.snoozeAction) return;
  // payload ses + bebek slotu + adı taşır (çok-bebek: doğru bebeğe ertele).
  _snoozeFeedInBackground(NotificationService.parseFeedPayload(response.payload));
}

Future<void> _snoozeFeedInBackground(
    ({bool sound, int slot, String babyName}) fp) async {
  final sound = fp.sound;
  final plugin = FlutterLocalNotificationsPlugin();
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );
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
  final ios = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: sound,
    categoryIdentifier: NotificationService.snoozeCategoryId,
  );
  final prefix = fp.babyName.isNotEmpty ? '${fp.babyName} · ' : '';
  await plugin.zonedSchedule(
    id: NotificationService.feedMainIdFor(fp.slot),
    title: '$prefix${tr('Beslenme zamanı (ertelendi)')}',
    body: tr('10 dk ertelendi 🍼'),
    scheduledDate: when,
    notificationDetails: NotificationDetails(android: android, iOS: ios),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: NotificationService.feedPayload(fp.sound, fp.slot, fp.babyName),
  );
}

import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/quiet_hours.dart';
import '../models/reminder.dart';
import 'i18n.dart';
import 'i18n_warm.dart';

/// Yerel bildirim servisi — hatırlatıcıları cihaz bildirimlerine bağlar.
/// Üç tür: özel/randevu hatırlatıcıları (günlük veya tek-sefer), beslenme uyarısı
/// (son beslenme + aralık) ve süren uyku/emzirme sayaçları.
class NotificationService {
  NotificationService._() : _plugin = FlutterLocalNotificationsPlugin();
  /// Tekil örnek. Yalnız testler sahte plugin'li bir örnekle DEĞİŞTİRİR
  /// (`NotificationService.withPlugin`); üretim kodu atama yapmaz.
  static NotificationService instance = NotificationService._();

  /// Yalnız test: sahte eklentiyle bağımsız bir örnek (platform kanalı yok).
  @visibleForTesting
  NotificationService.withPlugin(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  bool _permissionAsked = false;

  // NOT: kanal adları static final DEĞİL getter — tr() ilk erişimde değerlenirse
  // (dil cache'i yüklenmeden init çağrılırsa) kanal adı kalıcı yanlış dilde donar
  // (bkz static-final-tr/tema tuzağı). Getter her erişimde güncel dili okur.
  static const _channelId = 'reminders';
  static String get _channelName => tr('Hatırlatıcılar');

  // Süren sayaç bildirimleri (uyku/emzirme) — ayrı sessiz kanal.
  static const _timerChannelId = 'timers';
  static String get _timerChannelName => tr('Süren sayaçlar');

  // Beslenme hatırlatıcısı — sesli/heads-up kanal.
  static const feedChannelId = 'feed_reminders';
  static String get feedChannelName => tr('Beslenme hatırlatıcıları');
  // Sessiz varyant — ayrı kanal (Android'de ses/önem kanala kilitli; aynı kanalda
  // playSound:false sonradan çalışmaz, bu yüzden iki kanal kullanıyoruz).
  static const feedSilentChannelId = 'feed_reminders_silent';
  static String get feedSilentChannelName => tr('Beslenme hatırlatıcıları (sessiz)');

  // Çok-bebek: bildirim id'leri bebek "slot"una (0..999) göre ayrılır → aynı türde
  // iki bebeğin bildirimi çakışmaz. Taban + slot; türler arası 10000 boşluk.
  static const _feedMainBase = 800000;
  static const _feedPreBase = 810000;
  static const _feedForgotBase = 820000;
  static const _sleepBase = 900000;
  static const _breastBase = 910000;
  static int feedMainIdFor(int slot) => _feedMainBase + slot;
  static int feedPreIdFor(int slot) => _feedPreBase + slot;
  static int feedForgotIdFor(int slot) => _feedForgotBase + slot;
  static int sleepIdFor(int slot) => _sleepBase + slot;
  static int breastIdFor(int slot) => _breastBase + slot;
  static const snoozeAction = 'snooze_feed';
  static const snoozeCategoryId = 'feed_snooze'; // iOS: "Ertele" aksiyonlu kategori

  // Aile etkinlik bildirimleri (başka üye kayıt ekleyince) — ayrı kanal + dönen id.
  static const _activityChannelId = 'family_activity';
  static String get _activityChannelName => tr('Aile etkinliği');
  static const _activityGroup = 'adena_family_activity'; // Android bildirim grubu
  static const _activityBaseId = 700000;

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

  /// D18 / I6: aile bildirimi id'si — prefs'te KALICI sayaç (FCM bg isolate her
  /// kurulduğunda bellek sayacı sıfırlanıyordu; zaman tabanlı halka ise 500 ms
  /// periyotluydu → ~%2 çarpışma). O35 deseni: reload → artır → yaz. Aralık
  /// 700000..700049 döngüsel. Prefs okunamazsa zaman tabanlı yedek.
  static const _kActivitySeq = 'notif_activity_seq_v1';
  static const activityIdRing = 50;

  /// J7: `reload → oku → yaz` atomik değildir; FCM arka plan servisi isolate
  /// açılırken kuyruktaki mesajları eşzamanlı sevk eder → iki çağrı aynı
  /// sayacı okurdu. Isolate-içi Future zinciriyle serileştirilir (`sync` deseni).
  @visibleForTesting
  Future<int> nextActivityId() {
    final run = _activityIdChain.then((_) => _nextActivityIdNow());
    _activityIdChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _activityIdChain = Future.value();

  Future<int> _nextActivityIdNow() async {
    try {
      final p = await SharedPreferences.getInstance();
      try {
        await p.reload();
      } catch (_) {}
      final n = ((p.getInt(_kActivitySeq) ?? -1) + 1) % activityIdRing;
      await p.setInt(_kActivitySeq, n);
      return _activityBaseId + n;
    } catch (_) {
      return _activityBaseId +
          (DateTime.now().millisecondsSinceEpoch ~/ 10) % activityIdRing;
    }
  }

  /// Android 12+ kesin alarm izni — O16: planlama yolunda ARTIK OTOMATİK
  /// İSTENMEZ (Android 14+'ta varsayılan ret; plugin izin yoksa açıklamasız
  /// sistem Ayarlar sayfasına atıyordu, her soğuk açılışta). İzin yoksa
  /// `_alarmMode` inexact'e düşer (±dakikalar, bildirim kaybolmaz). Açık istek
  /// yalnız kullanıcı eylemiyle: [requestExactAlarmPermission] (ayar ekranı,
  /// KARAR-BEKLEYEN KB-4).
  Future<void> _ensureExactAlarm() async {}

  /// Kullanıcı açıkça isteyince (açıklama gösterildikten sonra) kesin alarm
  /// izni sayfasını açar. Döner: izin şu an var mı.
  Future<bool> requestExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    await android.requestExactAlarmsPermission();
    return await android.canScheduleExactNotifications() ?? false;
  }

  /// Kesin alarm izni var mı (Android; diğer platformlarda true).
  Future<bool> canScheduleExact() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? false;
  }

  /// Kesin alarm izni varsa exact, yoksa inexact döner. Android 12+ kullanıcı
  /// "kesin alarm"ı reddederse beslenme/randevu uyarısı TAMAMEN kaybolmasın —
  /// ±birkaç dakika gecikmeyle de olsa gelsin.
  Future<AndroidScheduleMode> _alarmMode() => alarmModeFor(_plugin);

  /// Ön plan ve arka plan (bildirim eylemi isolate'i, J4) için ORTAK kural:
  /// Android'de kesin alarm izni yoksa inexact, varsa exact; iOS'ta exact.
  static Future<AndroidScheduleMode> alarmModeFor(
      FlutterLocalNotificationsPlugin plugin) async {
    final android = plugin.resolvePlatformSpecificImplementation<
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

  /// Cihaz (sistem) düzeyinde bildirim izni açık mı? Bildirimler ayar sayfası
  /// bunu gösterir: uygulama içi anahtarlar açık olsa bile sistem izni kapalıysa
  /// HİÇBİR bildirim gelmez — kullanıcı sebebini göremeden "bozuk" sanıyordu.
  /// Okunamayan/desteklenmeyen platformda `true` döner (yanlış alarm vermeyelim).
  Future<bool> systemEnabled() async {
    try {
      if (!_ready) await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.areNotificationsEnabled() ?? true;
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final p = await ios.checkPermissions();
        return p?.isEnabled ?? true;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Sistem bildirim iznini AÇIKÇA ister (ayar sayfasındaki "İzin ver" düğmesi).
  /// [_ensurePermission]'ın aksine "bir kez sor" kilidine takılmaz — kullanıcı
  /// bilerek istediği için tekrar denenir.
  ///
  /// Dönüş: istek SONRASINDA izin açık mı. `false` → OS diyaloğu ya hiç
  /// gösterilmedi (kalıcı red / Android 12 ve altı: çalışma-zamanı izni yok) ya
  /// da kullanıcı reddetti. Çağıran bu durumda [openSystemSettings]'e yönlendirir;
  /// aksi halde düğme "hiçbir şey yapmıyor" gibi hissettiriyordu.
  Future<bool> requestPermission() async {
    try {
      if (!_ready) await init();
      _permissionAsked = true;
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
    return systemEnabled();
  }

  /// Uygulamanın SİSTEM bildirim ayarları sayfasını açar (izin kalıcı olarak
  /// reddedildiyse tek çıkış yolu). Android: MainActivity'deki 'adena/settings'
  /// kanalı. iOS: `app-settings:` = UIApplication.openSettingsURLString.
  Future<void> openSystemSettings() async {
    try {
      if (Platform.isIOS) {
        await launchUrl(Uri.parse('app-settings:'));
        return;
      }
      await const MethodChannel('adena/settings')
          .invokeMethod<bool>('openNotificationSettings');
    } catch (_) {
      // Ayar sayfası açılamazsa sessiz kal — kart uyarı metniyle zaten duruyor.
    }
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

  /// Çıkış / hesap silme: bu cihazdaki TÜM zamanlanmış yerel bildirimleri iptal et.
  /// Aksi halde önceki hesabın beslenme/hatırlatıcı bildirimleri yeni hesaba sızar
  /// (ör. çıkış sonrası eski bebeğin "sonraki beslenme" bildirimi çalardı).
  Future<void> cancelAll() async {
    try {
      if (!_ready) await init();
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Aile etkinlik bildirimi — başka bir üye kayıt eklediğinde (polling ile bulunur).
  /// [title] bebeğin adı (çok bebekte hangisi olduğu ayırt edilsin), [body] eylem.
  /// Her olay için ayrı id (üst üste binmesin) — 700000..700049 arası döner.
  Future<void> showActivity({required String title, required String body}) async {
    if (!_ready) await init();
    await _ensurePermission();
    final id = await nextActivityId();
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
    await _clearInterval(id); // J13
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
    bool forgot = true,
  }) async {
    if (!_ready) await init();
    await _plugin.cancel(id: feedMainIdFor(slot));
    await _plugin.cancel(id: feedPreIdFor(slot));
    await _plugin.cancel(id: feedForgotIdFor(slot));
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
    // "Unutmuş olabilir misin?" dürtmesi — tahmini saatten 30 dk sonra, HÂLÂ yeni
    // bir kayıt yoksa (yeni kayıt gelince zaten bu fonksiyon yeniden çağrılıp eski
    // planlama iptal edilir, bkz. yukarıdaki cancel'lar) tetiklenir. Kullanıcı
    // Bildirimler ayarından kapatabilir ([forgot]=false) → hiç planlanmaz.
    final forgotAt = nextTime.add(const Duration(minutes: 30));
    if (forgot && forgotAt.isAfter(now)) {
      await _zonedFeed(feedForgotIdFor(slot),
          forgotAt,
          '$prefix${tr('Kaydı unuttun mu?')}',
          tr('Beslenme saatinin üzerinden 30 dk geçti, henüz kayıt eklenmedi 🍼'),
          withSnooze: true, sound: sound && !(quiet?.covers(forgotAt) ?? false),
          slot: slot, babyName: babyName);
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
  /// sayaç id'lerine dokunmadan), sonra schedule şekline göre kur. Üç şekil:
  ///   • günlük:  {repeat:'daily', time:'HH:MM', title?}  → her gün o saatte
  ///   • tek-sefer: {repeat:'once', at:ISO8601, title?}   → o anda bir kez (geçmiş atlanır)
  ///   • periyodik: {repeat:'interval', every_min:15|30|60, title?} → kapatılana
  ///     dek her X dakikada bir (ateş takibi vb. için)
  /// Eski/uygulanmamış şekiller (vaccine days_before, nudge idle_hours) atlanır.
  ///
  /// [reminders] = TEK bebeğin listesi (kurulacaklar). [allActiveIds] = cihazdaki
  /// TÜM bebeklerin aktif hatırlatıcı id'leri (mutabakat için, DB'den taze okunur).
  /// Eskiden mutabakat yalnız [reminders]'a bakıyordu → B bebeği senkronlanınca
  /// A bebeğinin hatırlatıcıları yetim sanılıp siliniyordu (BULGULAR.md K1).
  Future<void> sync(
    List<Reminder> reminders, {
    required Future<Set<int>> Function() allActiveIds,
  }) {
    // Seri çalıştır: iki dinleyici (Hatırlatıcılar ekranı + global _ReminderSync)
    // aynı anda tetiklenebilir; await'ler arasında birbirine karışan iki sync,
    // iptal edilmiş bir planı geri kurabilir.
    final run = _syncChain.then((_) => _syncNow(reminders, allActiveIds));
    _syncChain = run.catchError((_) {});
    return run;
  }

  Future<void> _syncChain = Future.value();

  Future<void> _syncNow(
    List<Reminder> reminders,
    Future<Set<int>> Function() allActiveIds,
  ) async {
    if (!_ready) await init();
    // Küme, zincirde sıra bize gelince TAZE okunur (çağıranın listesi o ana kadar
    // bayatlamış olabilir). J15: listedeki aktif hatırlatıcı bu kümede değilse
    // (bebeği silinmiş / tombstone) KURULMAZ — silme yarışında `_ReminderSync`
    // rebuild'i yetim plan bırakmasın.
    Set<int>? keep;
    try {
      keep = await allActiveIds();
    } catch (_) {
      // Kaynak okunamadı → başka bebeklerin bildirimlerine DOKUNMA; yalnız bu
      // listede olup kapalı olanlar iptal edilir (aşağıda keep == null dalı).
      keep = null;
    }
    final k = keep;
    final active = reminders
        .where((r) => r.enabled && (k == null || k.contains(r.id)))
        .toList();
    if (active.isNotEmpty) await _ensurePermission();

    // cancelAll yerine yalnız hatırlatıcı id aralığını temizle (feed 800xxx /
    // sayaç 900xxx / adet 600xxx / aile 700xxx korunur). Özel hatırlatıcı id'si
    // = Drift localId, yani _cycleBase altındaki TÜM bekleyen bildirimler bu
    // modülündür. Listeye göre tek tek iptal yerine bekleyenlerle MUTABAKAT:
    // hiçbir bebeğin aktif listesinde olmayan her bekleyen iptal edilir —
    // silinme anındaki bir yarışta yetim kalan periyodik alarm da böylece
    // sonraki sync'te temizlenir. Küme, zincirde sıra bize gelince TAZE okunur
    // (çağıranın listesi o ana kadar bayatlamış olabilir).
    final listIds = {for (final r in reminders) r.id};
    final activeIds = {for (final r in active) r.id};
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= _cycleBase) continue;
        final stale = keep != null
            ? !keep.contains(p.id)
            : (listIds.contains(p.id) && !activeIds.contains(p.id));
        if (stale) {
          await _plugin.cancel(id: p.id);
          await _clearInterval(p.id); // J13: prefs anahtarı birikmesin
        }
      }
    } catch (_) {
      // Bekleyenler okunamazsa eski davranışa düş: listedekileri iptal et.
      for (final r in reminders) {
        await _plugin.cancel(id: r.id);
      }
    }
    final now = DateTime.now();
    Set<int> pendingIds;
    try {
      pendingIds = {for (final p in await _plugin.pendingNotificationRequests()) p.id};
    } catch (_) {
      pendingIds = const {};
    }
    for (final r in active) {
      final s = r.schedule;
      final title = (s['title'] as String?)?.trim();
      if (s['repeat'] == 'interval' || s['every_min'] != null) {
        // Periyodik: her X dakikada bir tekrar eden bildirim. O14: kurulu plan
        // her sync'te YENİDEN KURULMAZ (ilk tetik "şimdi + aralık"a kayıyordu);
        // yalnız bekleyen yoksa ya da aralık değiştiyse kurulur.
        final every = s['every_min'] is num ? (s['every_min'] as num).toInt() : 0;
        if (every < 1) continue;
        if (pendingIds.contains(r.id) && await _storedInterval(r.id) == every) {
          continue;
        }
        await _scheduleInterval(r.id, every, title);
      } else if (s['repeat'] == 'once' || s['at'] != null) {
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

  /// Periyodik hatırlatıcı — ilk bildirim çağrıdan [everyMin] dk sonra, ardından
  /// hatırlatıcı kapatılana/silinene dek her [everyMin] dakikada bir (ateş takibi
  /// gibi kısa aralıklı kontroller için). Kesin alarm izni yoksa inexact kurulur.
  /// Kurulu periyodik planların aralığı — KALICI (prefs, M3): süreç yeniden
  /// başlasa da "bekleyen varsa kurma" kuralı aralık değiştiyse yeniden kurar,
  /// değişmediyse tetik zamanını korur.
  static const _kIntervalPrefix = 'notif_interval_';

  Future<int?> _storedInterval(int id) async {
    try {
      return (await SharedPreferences.getInstance()).getInt('$_kIntervalPrefix$id');
    } catch (_) {
      return null;
    }
  }

  /// J13: iptal edilen hatırlatıcının aralık anahtarı silinir (prefs sızıntısı).
  Future<void> _clearInterval(int id) async {
    try {
      await (await SharedPreferences.getInstance()).remove('$_kIntervalPrefix$id');
    } catch (_) {}
  }

  Future<void> _storeInterval(int id, int everyMin) async {
    try {
      await (await SharedPreferences.getInstance()).setInt('$_kIntervalPrefix$id', everyMin);
    } catch (_) {}
  }

  Future<void> _scheduleInterval(int id, int everyMin, String? title) async {
    await _ensureExactAlarm();
    await _storeInterval(id, everyMin);
    await _plugin.periodicallyShowWithDuration(
      id: id,
      title: title != null && title.isNotEmpty ? title : tr('Hatırlatıcı'),
      body: tr('Hatırlatma zamanı ⏰'),
      repeatDurationInterval: Duration(minutes: everyMin),
      notificationDetails: _details,
      androidScheduleMode: await _alarmMode(),
    );
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
      // J6: günlük tekrar (ilaç dozu / özel hatırlatıcı) da kesin alarm izni
      // varsa exact — M4 diyaloğu "ilaç … tam saatinde" vaadiyle tutarlı.
      androidScheduleMode: await _alarmMode(),
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

  // ── Sağlık modülü hatırlatıcıları (yerelde bebek verisinden hesaplanır,
  // kullanıcı yalnız aç/kapa yapar — bkz NotificationPrefs.vaccine/leap/growth/
  // pregnancyWeek/milestone/tooth). KRİTİK: id'ler _cycleBase (600000) ALTINDA
  // OLAMAZ — _syncNow, o eşiğin altındaki ve aktif özel-hatırlatıcı listesinde
  // olmayan her bekleyen bildirimi "yetim" sayıp iptal ediyor (bkz aşağıdaki
  // yorum). Bu yüzden 600000-700000 (cycle ile aile etkinliği arası) boş
  // aralığa yerleştirildi; her biri bebek slotuna göre ayrışır.
  static const _vaccineBase = 610000;
  static const _leapBase = 620000;
  static const _growthBase = 630000;
  static const _pregWeekBase = 640000;
  static const _milestoneBase = 650000;
  static const _toothBase = 660000;

  /// Aşı hatırlatıcısı — en yakın (zorunlu, yapılmamış) aşının tarihinde
  /// (09:00) tek seferlik. Her senkronda yeniden hesaplanır; bir aşı işaretlenip
  /// sıradaki değişince otomatik yeni tarihe kayar.
  Future<void> syncVaccineReminder({
    required bool enabled,
    required DateTime? dueDate,
    String vaccineName = '',
    int slot = 0,
    String babyName = '',
  }) async {
    if (!_ready) await init();
    final id = _vaccineBase + slot;
    await _plugin.cancel(id: id);
    if (!enabled || dueDate == null) return;
    final at = DateTime(dueDate.year, dueDate.month, dueDate.day, 9);
    if (!at.isAfter(DateTime.now())) return;
    await _ensurePermission();
    final prefix = babyName.isNotEmpty ? '$babyName · ' : '';
    await _scheduleOnce(
        id, at, '$prefix${trp('Aşı zamanı: {name}', {'name': vaccineName})}');
  }

  /// Gelişim atağı hatırlatıcısı — bir sonraki atağın huzursuz öncesi
  /// penceresi başlarken (09:00) tek seferlik.
  Future<void> syncLeapReminder({
    required bool enabled,
    required DateTime? at,
    String leapTitle = '',
    int leapIndex = 0,
    int slot = 0,
    String babyName = '',
  }) async {
    if (!_ready) await init();
    final id = _leapBase + slot;
    await _plugin.cancel(id: id);
    if (!enabled || at == null || !at.isAfter(DateTime.now())) return;
    await _ensurePermission();
    final prefix = babyName.isNotEmpty ? '$babyName · ' : '';
    await _scheduleOnce(id, at,
        '$prefix${trp('{n}. atak yaklaşıyor: {title}', {'n': leapIndex, 'title': leapTitle})}');
  }

  /// Büyüme ölçümü hatırlatıcısı — son ölçümden (yoksa doğumdan) ~30 gün sonra
  /// (09:00) tek seferlik; yeni ölçüm girilince otomatik ötelenir.
  Future<void> syncGrowthReminder({
    required bool enabled,
    required DateTime? at,
    int slot = 0,
    String babyName = '',
  }) async {
    if (!_ready) await init();
    final id = _growthBase + slot;
    await _plugin.cancel(id: id);
    if (!enabled || at == null || !at.isAfter(DateTime.now())) return;
    await _ensurePermission();
    final prefix = babyName.isNotEmpty ? '$babyName · ' : '';
    await _scheduleOnce(id, at, '$prefix${tr('Büyüme ölçümü zamanı 📏')}');
  }

  /// Gebelik haftası hatırlatıcısı — bir sonraki hafta değişiminde (09:00) tek
  /// seferlik (yalnız bekleme modu).
  Future<void> syncPregnancyWeekReminder({
    required bool enabled,
    required DateTime? at,
    int week = 0,
    int slot = 0,
    String babyName = '',
  }) async {
    if (!_ready) await init();
    final id = _pregWeekBase + slot;
    await _plugin.cancel(id: id);
    if (!enabled || at == null || !at.isAfter(DateTime.now())) return;
    await _ensurePermission();
    final prefix = babyName.isNotEmpty ? '$babyName · ' : '';
    await _scheduleOnce(
        id, at, '$prefix${trp('{n}. haftasındasın 🤰', {'n': week})}');
  }

  /// Gelişim basamaklarını işaretlemeyi unutmamak için periyodik (2 haftada
  /// bir) dürtme — yalnız yaşa yakın/işaretlenmemiş basamak varken açık kalır.
  Future<void> syncMilestoneCheckReminder({required bool enabled, int slot = 0}) async {
    if (!_ready) await init();
    final id = _milestoneBase + slot;
    if (!enabled) {
      await _plugin.cancel(id: id);
      return;
    }
    if (await _isPending(id)) return; // O14: 14 günlük sayaç sıfırlanmasın
    await _ensurePermission();
    await _scheduleInterval(id, 14 * 24 * 60, tr('Gelişim basamaklarını kontrol et'));
  }

  Future<bool> _isPending(int id) async {
    try {
      return (await _plugin.pendingNotificationRequests()).any((p) => p.id == id);
    } catch (_) {
      return false;
    }
  }

  /// Diş çıkışlarını işaretlemeyi unutmamak için periyodik (2 haftada bir)
  /// dürtme — bebek en erken tipik diş ayına ulaşınca başlar.
  Future<void> syncToothCheckReminder({required bool enabled, int slot = 0}) async {
    if (!_ready) await init();
    final id = _toothBase + slot;
    if (!enabled) {
      await _plugin.cancel(id: id);
      return;
    }
    if (await _isPending(id)) return; // O14
    await _ensurePermission();
    await _scheduleInterval(id, 14 * 24 * 60, tr('Diş çıkışlarını kontrol et'));
  }

  /// O15: bebek silinince / erişim kalkınca o bebeğin TÜM planlı bildirimleri —
  /// beslenme (ana/ön/unuttun), sayaçlar, aşı/atak/büyüme/gebelik haftası,
  /// periyodik gelişim/diş dürtmeleri — iptal edilir (ilaç bildirimleri:
  /// `MedicationScheduler.cancelBaby`).
  /// [reminderIds]: bebeğin özel/randevu hatırlatıcıları (`localReminders`
  /// id'leri, I5) — satırlar silinmez ama bildirimleri burada iptal edilir.
  Future<void> cancelBabyScheduled(
      {required int slot, Iterable<int> reminderIds = const []}) async {
    if (!_ready) await init();
    for (final id in reminderIds) {
      await _plugin.cancel(id: id);
      await _clearInterval(id); // J13
    }
    for (final id in [
      feedMainIdFor(slot),
      feedPreIdFor(slot),
      feedForgotIdFor(slot),
      sleepIdFor(slot),
      breastIdFor(slot),
      _vaccineBase + slot,
      _leapBase + slot,
      _growthBase + slot,
      _pregWeekBase + slot,
      _milestoneBase + slot,
      _toothBase + slot,
    ]) {
      await _plugin.cancel(id: id);
    }
  }

  // ── İlaç v2 (ILAC-TASARIM §3): doz başına TEK SEFERLİK bildirimler ──
  // Zamanlama/kimlik/fark mantığı `MedicationScheduler`'da; burada yalnız
  // eklenti uçları. Kimlik aralığı [medIdLo, medIdHi) — kayıt defterinden
  // tahsis edilir (KB-13/M19: plan id'sinden türetilmez). Eski günlük-tekrar
  // aralığı [legacyMedLo, legacyMedHi) bir kez temizlenir.
  static const medIdLo = 1100000;
  static const medIdHi = 1200000;
  static const legacyMedLo = 670000;
  static const legacyMedHi = 680000;

  static const medChannelId = 'medication';
  static String get medChannelName => tr('İlaç hatırlatmaları');

  NotificationDetails get _medDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          medChannelId,
          medChannelName,
          channelDescription: tr('İlaç ve vitamin dozları'),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  /// Android'de exact/inexact (kesin alarm izni), iOS'ta exact — ilaç
  /// bildiriminin kurulum kipi (kayıt defteri karmasına girer: kip değişince
  /// yeniden kurulur).
  Future<String> medScheduleMode() async => (await _alarmMode()).name;

  /// Tek seferlik ilaç bildirimi ([when] = yerel an). Aynı [id] öncekinin
  /// yerine geçer (iptal gerekmez).
  Future<void> scheduleMedOnce({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) await init();
    await _ensurePermission();
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: _medDetails,
      androidScheduleMode: await _alarmMode(),
      payload: payload,
    );
  }

  /// Bildirimi iptal eder (bekleyen ve — Android/iOS'ta — ekranda duran).
  Future<void> cancelId(int id) async {
    if (!_ready) await init();
    await _plugin.cancel(id: id);
  }

  /// [lo, hi) aralığındaki BEKLEYEN bildirim id'leri; okunamazsa null.
  Future<Set<int>?> pendingIdsIn(int lo, int hi) async {
    if (!_ready) await init();
    try {
      return {
        for (final p in await _plugin.pendingNotificationRequests())
          if (p.id >= lo && p.id < hi) p.id
      };
    } catch (_) {
      return null;
    }
  }

  /// M17: cihaz saat dilimini yeniden okur; değiştiyse `tz.local`'ı günceller
  /// ve true döner (çağıran günlük/ilaç hatırlatıcılarını yeniden kurar).
  Future<bool> refreshTimezone() async {
    try {
      final dynamic res = await FlutterTimezone.getLocalTimezone();
      final name = res is String ? res : (res as dynamic).identifier as String;
      if (name == tz.local.name) return false;
      tz.setLocalLocation(tz.getLocation(name));
      return true;
    } catch (_) {
      return false;
    }
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
        // C3: tahmine dayalı → "tahmini".
        await _scheduleOnce(_cycleBase + 0, at, tr('Adetin yaklaşıyor (tahmini) 🌸'));
      }
    }
    if (on('fertile') && fertileStart != null) {
      final at = DateTime(fertileStart.year, fertileStart.month, fertileStart.day, 9);
      if (at.isAfter(now)) {
        // C3/C5: nötr + "tahmini".
        await _scheduleOnce(_cycleBase + 1, at, tr('Tahmini doğurgan pencere başlıyor'));
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

/// Yalnız test: arka plan erteleme gövdesi, sahte plugin ile.
@visibleForTesting
Future<void> debugSnoozeFeedInBackground(
        ({bool sound, int slot, String babyName}) fp,
        {required FlutterLocalNotificationsPlugin plugin}) =>
    _snoozeFeedInBackground(fp, plugin: plugin);

Future<void> _snoozeFeedInBackground(
    ({bool sound, int slot, String babyName}) fp,
    {FlutterLocalNotificationsPlugin? plugin}) async {
  await warmI18nFromCache(); // M7: "Ertele 10 dk"/başlık kullanıcının dilinde
  final sound = fp.sound;
  plugin ??= FlutterLocalNotificationsPlugin();
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
  // J4 (O16 regresyonu): ön planla AYNI kural — Android 14+'ta kesin alarm izni
  // varsayılan ret; `exact` sabit kurulum plugin'in fırlatmasına, ertelemenin
  // sessizce kaybolmasına yol açıyordu. İzin yoksa inexact (±dakikalar).
  final mode = await NotificationService.alarmModeFor(plugin);
  try {
    await plugin.zonedSchedule(
      id: NotificationService.feedMainIdFor(fp.slot),
      title: '$prefix${tr('Beslenme zamanı (ertelendi)')}',
      body: tr('10 dk ertelendi 🍼'),
      scheduledDate: when,
      notificationDetails: NotificationDetails(android: android, iOS: ios),
      androidScheduleMode: mode,
      payload: NotificationService.feedPayload(fp.sound, fp.slot, fp.babyName),
    );
  } catch (e, st) {
    // Eylem isolate'inde yakalanmayan hata sessizce kaybolurdu; görünür olsun.
    debugPrint('[notif] bg erteleme kurulamadı ($mode): $e');
    try {
      await FirebaseCrashlytics.instance
          .recordError(e, st, reason: 'bg_snooze_schedule', fatal: false);
    } catch (_) {
      // Firebase bu isolate'te hazır değil → yalnız konsol.
    }
  }
}

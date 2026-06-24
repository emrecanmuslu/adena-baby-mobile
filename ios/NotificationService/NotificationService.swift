import UserNotifications
import WidgetKit

/// Notification Service Extension — uygulama TAMAMEN KAPALI (force-quit) olsa bile,
/// gelen görünür push (alert + mutable-content:1) gösterilmeden ÖNCE çalışır.
/// Amaç: App Group'a "sonraki beslenme"yi yazıp widget timeline'ını yenilemek.
///
/// Neden gerekli: iOS, uygulama kill durumundayken Flutter `onBackgroundMessage`
/// isolate'ini çalıştırmaz → `WidgetService.publishOne` koşmaz → widget bayat kalır.
/// NSE, push'la birlikte deterministik koşan TEK yerdir; widget'ı her durumda
/// (ön plan / arka plan / kapalı) günceller. (Backend görünür iOS push'una
/// mutable_content=True ekler — bkz. api/apps/common/push.py.)
class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttempt: UNMutableNotificationContent?
  private let appGroupId = "group.com.adenababy.adenaBaby"

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    self.bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent
    updateWidget(request.content.userInfo)
    // Bildirimi olduğu gibi teslim et (yalnız yan etki: App Group + widget güncellendi).
    contentHandler(bestAttempt ?? request.content)
  }

  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let content = bestAttempt {
      handler(content)
    }
  }

  /// Beslenme push'u ise (widget_update=feed) App Group'a sonraki-beslenme verisini
  /// yaz ve widget'ı yenile. FCM özel `data` anahtarları userInfo'da üst seviyededir.
  /// Beslenme push'u ise (widget_update=feed) App Group'a sonraki-beslenme verisini
  /// yaz ve widget'ı yenile. FCM özel `data` anahtarları userInfo'da üst seviyededir.
  private func updateWidget(_ info: [AnyHashable: Any]) {
    guard (info["widget_update"] as? String) == "feed",
          let babyId = info["baby_id"] as? String, !babyId.isEmpty,
          let defaults = UserDefaults(suiteName: appGroupId) else { return }

    // Ad = bebek adı. Backend data'da `baby_name` gönderir; yedek alert başlığı / önceki.
    let apsTitle = ((info["aps"] as? [AnyHashable: Any])?["alert"]
      as? [AnyHashable: Any])?["title"] as? String
    let name = (info["baby_name"] as? String) ?? apsTitle
      ?? defaults.string(forKey: "name_\(babyId)") ?? "Bebek"
    defaults.set(name, forKey: "name_\(babyId)")

    if let nextMs = nextFeedMs(info, babyId: babyId, defaults: defaults) {
      defaults.set(String(nextMs), forKey: "next_\(babyId)")
      // Seçimsiz (aktif) widget fallback anahtarları: bu bebek aktifse onu da güncelle.
      if defaults.string(forKey: "active_id") == babyId {
        defaults.set(name, forKey: "baby_name")
        defaults.set(String(nextMs), forKey: "next_feed_ms")
      }
    }

    // Cross-process FLUSH: NSE yazıp hemen reload edince widget eski veriyi
    // okuyabiliyordu; synchronize() yazımı diske zorlar → widget güncel okusun.
    defaults.synchronize()
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadTimelines(ofKind: "FeedWidget")
    }

    // Uygulama FORCE-QUIT iken Dart arka plan handler'ı çalışmaz → sonraki-beslenme
    // BİLDİRİMİ yeniden planlanmazdı (sadece widget güncellenirdi). NSE deterministik
    // koştuğu için burada bildirimi de yeniden planlarız: başka cihaz kayıt girince
    // iPhone kapalı olsa bile hatırlatıcı DOĞRU ZAMANA kayar. (Config'i Dart App
    // Group'a aynalar — bkz. WidgetService.publishFeedReminderConfig.)
    rescheduleFeedReminder(info, babyId: babyId, defaults: defaults, name: name)
  }

  /// App Group'taki beslenme hatırlatıcı config'inden yerel bildirimi yeniden kurar.
  /// flutter_local_notifications ile AYNI id (slot tabanlı) kullanılır → çift olmaz,
  /// uygulama açılınca ön plan yeniden planlaması bunu sorunsuz değiştirir.
  private func rescheduleFeedReminder(
    _ info: [AnyHashable: Any], babyId: String, defaults: UserDefaults, name: String
  ) {
    guard defaults.string(forKey: "fr_enabled_\(babyId)") == "1" else { return }
    // baseType filtresi (nextFeedEstimate/_rescheduleFeedReminder ile birebir):
    // hatırlatıcı türü ile eklenen beslenmenin türü uyuşmuyorsa plana dokunma.
    let base = defaults.string(forKey: "fr_base_\(babyId)") ?? "all"
    let sub = info["feed_sub"] as? String
    if base == "breast" && sub != "breast" { return }
    if base == "formula" && sub != "formula" { return }

    guard let nextMs = nextFeedMs(info, babyId: babyId, defaults: defaults) else { return }
    let next = Date(timeIntervalSince1970: Double(nextMs) / 1000.0)
    let now = Date()
    let slot = readInt(defaults, "fr_slot_\(babyId)")
    let preMin = readInt(defaults, "fr_premin_\(babyId)")
    let soundOn = defaults.string(forKey: "fr_sound_\(babyId)") == "1"

    let center = UNUserNotificationCenter.current()
    // flutter_local_notifications id biçimi = tamsayı id'nin string'i.
    // feedMainBase=800000, feedPreBase=810000 (Dart NotificationService ile aynı).
    let mainId = String(800000 + slot)
    let preId = String(810000 + slot)
    center.removePendingNotificationRequests(withIdentifiers: [mainId, preId])

    let prefix = name.isEmpty ? "" : "\(name) · "
    let mainTitle = defaults.string(forKey: "fr_main_title") ?? "Beslenme zamanı"
    let mainBody = defaults.string(forKey: "fr_main_body") ?? ""

    if next > now {
      scheduleLocal(
        center, id: mainId, fireDate: next,
        title: prefix + mainTitle, body: mainBody,
        sound: soundOn && !quietCovers(next, babyId: babyId, defaults: defaults),
        category: "feed_snooze")
    }
    if preMin > 0 {
      let pre = next.addingTimeInterval(Double(-preMin * 60))
      if pre > now {
        let preTitle = defaults.string(forKey: "fr_pre_title_\(babyId)") ?? mainTitle
        let preBody = defaults.string(forKey: "fr_pre_body_\(babyId)") ?? ""
        scheduleLocal(
          center, id: preId, fireDate: pre,
          title: prefix + preTitle, body: preBody,
          sound: soundOn && !quietCovers(pre, babyId: babyId, defaults: defaults),
          category: nil)
      }
    }
  }

  private func scheduleLocal(
    _ center: UNUserNotificationCenter, id: String, fireDate: Date,
    title: String, body: String, sound: Bool, category: String?
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if sound { content.sound = .default }
    if let cat = category { content.categoryIdentifier = cat }
    let comps = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: fireDate)
    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
  }

  /// QuietHours.covers ile birebir aynı: "1|startMin|endMin" / "0".
  private func quietCovers(_ t: Date, babyId: String, defaults: UserDefaults) -> Bool {
    guard let q = defaults.string(forKey: "fr_quiet_\(babyId)"), q != "0" else { return false }
    let parts = q.split(separator: "|")
    guard parts.count == 3, let start = Int(parts[1]), let end = Int(parts[2]),
          start != end else { return false }
    let c = Calendar.current.dateComponents([.hour, .minute], from: t)
    let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    if start < end { return m >= start && m < end }
    return m >= start || m < end
  }

  /// home_widget int'leri NSNumber/String olarak yazabilir → ikisini de dene.
  private func readInt(_ defaults: UserDefaults, _ key: String) -> Int {
    if let s = defaults.string(forKey: key), let v = Int(s) { return v }
    return defaults.integer(forKey: key)
  }

  /// next = last_feed_ts + interval(dk). interval App Group'tan okunur (Dart yazar);
  /// yoksa kullanıcı varsayılanı; o da yoksa 120 dk. Tarih ayrıştırılamazsa nil.
  private func nextFeedMs(
    _ info: [AnyHashable: Any], babyId: String, defaults: UserDefaults
  ) -> Int64? {
    guard let ts = info["last_feed_ts"] as? String, let last = parseDate(ts) else { return nil }
    var interval = defaults.double(forKey: "feed_interval_\(babyId)")
    if interval <= 0 { interval = defaults.double(forKey: "feed_interval_default") }
    if interval <= 0 { interval = 120 }
    let next = last.addingTimeInterval(interval * 60)
    return Int64(next.timeIntervalSince1970 * 1000)
  }

  /// ISO8601 ayrıştır. Django `isoformat()` MİKROSANİYE (6 hane) üretir, ör.
  /// "2026-06-23T14:30:00.123456+00:00"; ISO8601DateFormatter bunu sık reddeder →
  /// önce kesirli saniyeli/değil dener, olmazsa kesirli kısmı atıp yeniden dener.
  private func parseDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    if let d = f.date(from: s) { return d }
    // Kesirli saniyeyi (örn. ".123456") at, saat dilimini koru, yeniden dene.
    if let dot = s.firstIndex(of: ".") {
      let afterDot = s[s.index(after: dot)...]
      if let tz = afterDot.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
        let trimmed = String(s[..<dot]) + String(afterDot[tz...])
        return f.date(from: trimmed)
      }
    }
    return nil
  }
}

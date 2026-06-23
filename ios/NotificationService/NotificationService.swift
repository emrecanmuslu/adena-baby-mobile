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
    // Bildirimi olduğu gibi teslim et (içeriği değiştirmiyoruz; yalnız yan etki
    // olarak App Group + widget'ı güncelledik).
    contentHandler(bestAttempt ?? request.content)
  }

  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let content = bestAttempt {
      handler(content)
    }
  }

  /// Beslenme push'u ise (widget_update=feed) App Group'a sonraki-beslenme verisini
  /// yaz ve widget'ı yenile. FCM özel `data` anahtarları userInfo'da üst seviyededir.
  private func updateWidget(_ info: [AnyHashable: Any]) {
    guard (info["widget_update"] as? String) == "feed",
          let babyId = info["baby_id"] as? String, !babyId.isEmpty,
          let defaults = UserDefaults(suiteName: appGroupId) else { return }

    // Ad = bebek adı. Backend artık data'da `baby_name` gönderir (en güvenilir).
    // Yedekler: alert başlığı (görünür push'ta = bebek adı), App Group'taki önceki
    // ad, son çare varsayılan.
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

    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadTimelines(ofKind: "FeedWidget")
    }
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

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
    let mutable = request.content.mutableCopy() as? UNMutableNotificationContent
    self.bestAttempt = mutable
    let diag = updateWidget(request.content.userInfo)
    // ⚠️ GEÇİCİ TEŞHİS: NSE çalıştı mı + ne yaptı, bildirim gövdesinde görünsün
    // (force-quit'te uygulama AÇMADAN teşhis). Tespit edilince KALDIRILACAK.
    if let c = mutable {
      c.body = c.body + "  ⚙️[\(diag)]"
    }
    contentHandler(mutable ?? request.content)
  }

  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let content = bestAttempt {
      handler(content)
    }
  }

  /// Beslenme push'u ise (widget_update=feed) App Group'a sonraki-beslenme verisini
  /// yaz ve widget'ı yenile. FCM özel `data` anahtarları userInfo'da üst seviyededir.
  /// Dönüş = teşhis dizesi (bildirim gövdesine eklenir). Beslenme push'u ise
  /// App Group'a yazar + widget'ı yeniler.
  private func updateWidget(_ info: [AnyHashable: Any]) -> String {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return "noGroup" }
    let wu = info["widget_update"] as? String
    guard wu == "feed" else { return "wu=\(wu ?? "nil")" }
    guard let babyId = info["baby_id"] as? String, !babyId.isEmpty else { return "noBabyId" }

    // Ad = bebek adı. Backend data'da `baby_name` gönderir; yedek alert başlığı / önceki.
    let apsTitle = ((info["aps"] as? [AnyHashable: Any])?["alert"]
      as? [AnyHashable: Any])?["title"] as? String
    let name = (info["baby_name"] as? String) ?? apsTitle
      ?? defaults.string(forKey: "name_\(babyId)") ?? "Bebek"
    defaults.set(name, forKey: "name_\(babyId)")

    let active = defaults.string(forKey: "active_id") ?? "nil"
    let matched = (active == babyId)
    var nx = "nil"
    if let nextMs = nextFeedMs(info, babyId: babyId, defaults: defaults) {
      defaults.set(String(nextMs), forKey: "next_\(babyId)")
      if matched {
        defaults.set(name, forKey: "baby_name")
        defaults.set(String(nextMs), forKey: "next_feed_ms")
      }
      nx = "\(nextMs)"
    }

    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadTimelines(ofKind: "FeedWidget")
    }
    let lf = (info["last_feed_ts"] as? String) != nil
    // Yaz-okuma teyidi: az önce yazdığımız next_<babyId> geri okunabiliyor mu?
    let readback = defaults.string(forKey: "next_\(babyId)") != nil
    return "ok m=\(matched) wr=\(readback) nx=\(nx != "nil") lf=\(lf) a=\(active.prefix(4)) b=\(babyId.prefix(4))"
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

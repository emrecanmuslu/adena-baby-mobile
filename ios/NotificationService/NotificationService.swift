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
    // İlaç v2 (A6): aile üyesinin doz işareti / üyelikten çıkarılma → ilgili
    // bekleyen ilaç hatırlatmalarını iptal et (ya da geri alındıysa geri ekle).
    handleMedication(request.content.userInfo)
    // Bildirimi olduğu gibi teslim et (yalnız yan etki: App Group + widget güncellendi).
    contentHandler(bestAttempt ?? request.content)
  }

  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let content = bestAttempt {
      handler(content)
    }
  }

  // MARK: - İlaç v2 (ILAC-TASARIM §4.3)

  /// Dart `MedicationScheduler` defteri (App Group `med_notif_registry`):
  /// `{"planUuid|YYYY-MM-DD|HH:MM|m|x": {"id": Int, "at": ms, "b": babyId,
  /// "t": başlık, "y": gövde, ...}}`. Bildirim kimliği = String(id) (FLN).
  private func loadMedRegistry(_ defaults: UserDefaults) -> [String: [String: Any]] {
    guard let raw = defaults.string(forKey: "med_notif_registry"),
          let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    var out: [String: [String: Any]] = [:]
    for (k, v) in obj { if let e = v as? [String: Any] { out[k] = e } }
    return out
  }

  private func saveMedRegistry(_ defaults: UserDefaults, _ reg: [String: [String: Any]]) {
    guard let data = try? JSONSerialization.data(withJSONObject: reg),
          let raw = String(data: data, encoding: .utf8) else { return }
    defaults.set(raw, forKey: "med_notif_registry")
  }

  private func medId(_ e: [String: Any]) -> String? {
    if let i = e["id"] as? Int { return String(i) }
    if let n = e["id"] as? NSNumber { return n.stringValue }
    return nil
  }

  /// `med_dose` (verildi/atlandı → o dozun ana + "işaretlenmedi" bildirimini
  /// bekleyen ve ekrandakilerden kaldır; geri alındı → defterdeki içerikle,
  /// zamanı gelmemişse geri ekle) ve `access_removed` (+ baby_id → o bebeğin
  /// TÜM ilaç bildirimleri). Uygulama force-quit olsa da çalışır.
  private func handleMedication(_ info: [AnyHashable: Any]) {
    guard let type = info["type"] as? String,
          let defaults = UserDefaults(suiteName: appGroupId) else { return }
    let center = UNUserNotificationCenter.current()
    var reg = loadMedRegistry(defaults)
    if reg.isEmpty { return }

    if type == "access_removed" {
      guard let babyId = info["baby_id"] as? String, !babyId.isEmpty else { return }
      var ids: [String] = []
      for (k, e) in reg where (e["b"] as? String) == babyId {
        if let id = medId(e) { ids.append(id) }
        reg.removeValue(forKey: k)
      }
      if ids.isEmpty { return }
      center.removePendingNotificationRequests(withIdentifiers: ids)
      center.removeDeliveredNotifications(withIdentifiers: ids)
      saveMedRegistry(defaults, reg)
      return
    }

    guard type == "med_dose",
          let event = info["event"] as? String,
          let plan = info["plan_uuid"] as? String, !plan.isEmpty,
          let date = info["dose_date"] as? String, !date.isEmpty,
          let time = info["dose_time"] as? String, !time.isEmpty else { return }
    let base = "\(plan)|\(date)|\(time)"
    let keys = ["\(base)|m", "\(base)|x"]

    // V7: geri alınan kaydın dozunu başka biri de vermiş (still_given) → doz
    // HÂLÂ verildi: "verildi" gibi işlenir, hatırlatma geri EKLENMEZ.
    let stillGiven = event == "undone" && (info["still_given"] as? String) == "1"
    if event == "given" || event == "skipped" || stillGiven {
      var ids: [String] = []
      for k in keys {
        if let e = reg[k], let id = medId(e) { ids.append(id) }
      }
      if ids.isEmpty { return }
      center.removePendingNotificationRequests(withIdentifiers: ids)
      center.removeDeliveredNotifications(withIdentifiers: ids)
      // Defterde KALIR (V6 — Dart cancelDose ile aynı model: girdi iptal
      // işaretli kalır): ön plan yeniden kurması "bekleyen değil" görüp kaydın
      // çözüldüğünü senkronla öğrenir; geri alınırsa NSE içerikten geri ekler.
      return
    }

    if event == "undone" {
      let now = Date()
      for k in keys {
        guard let e = reg[k], let id = medId(e),
              let atMs = (e["at"] as? NSNumber)?.doubleValue else { continue }
        let fire = Date(timeIntervalSince1970: atMs / 1000)
        if fire <= now { continue }
        scheduleLocal(center, id: id, fireDate: fire,
                      title: (e["t"] as? String) ?? "", body: (e["y"] as? String) ?? "",
                      sound: true, category: nil, payload: "med:\(k)")
      }
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

    let activeId = defaults.string(forKey: "active_id")
    let isActive = activeId == babyId
    // Seçimsiz (aktif/fallback) widget anahtarlarını (baby_name/next_feed_ms/last_feed_ms)
    // şu durumda da güncelle: aktif bu bebek VEYA active_id hiç yazılmamış/boş
    // (ör. publishAll henüz koşmadı). Widget active_id boşken fallback'i okur; NSE de
    // yazmazsa BAYAT kalıyordu — bu, "push dolu geldi ama widget güncellenmedi"nin
    // başlıca cihaz-tarafı nedeni. Çok-bebekte (active_id dolu, başka bebek) dokunmaz.
    let writeFallback = isActive || (activeId?.isEmpty ?? true)

    // Ön planın App Group'a aynaladığı tahmin ayarı (aralık + baz türü). nil ise
    // BİLMİYORUZ → widget'a tahmin YAZMA (eskiden 120 dk'ya düşülüyordu; 3 saatlik
    // ayarı olan kullanıcıda widget sessizce "son beslenme + 2 saat"e kayıyordu).
    // Baz türü filtresi Dart nextFeedEstimate/lastFeedAt ile birebir: hatırlatıcı
    // "son MAMA sonrası" ise eklenen ANNE SÜTÜ kaydı çapayı OYNATMAMALI — bu dal
    // eskiden filtrelemiyordu, ön plan/bg sync filtreliyordu; widget her push'ta
    // ileri, her arka plan turunda geri zıplıyordu.
    let est0 = feedEstimate(babyId, defaults)
    if let est = est0, let lastTs = resolveLastFeedTs(info, est: est) {
      if let nextMs = nextFeedMs(lastTs: lastTs, est: est) {
        defaults.set(String(nextMs), forKey: "next_\(babyId)")
        if writeFallback {
          defaults.set(name, forKey: "baby_name")
          defaults.set(String(nextMs), forKey: "next_feed_ms")
        }
      }
      // Widget "Son besleme HH:MM" gösterir → çözülen last_feed'i de yaz.
      // Ön planda `lastFeedAt` de baz türüyle filtrelenir; bu yüzden "son besleme"
      // de yalnız çapayı oynatan türde güncellenir (iki gösterge tutarlı kalsın).
      if let last = parseDate(lastTs) {
        let lastMs = Int64(last.timeIntervalSince1970 * 1000)
        defaults.set(String(lastMs), forKey: "last_\(babyId)")
        if writeFallback { defaults.set(String(lastMs), forKey: "last_feed_ms") }
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
    // Hatırlatıcı AÇIK olduğu için [feedEstimate] burada kullanıcının kendi
    // aralığını + baz türünü döndürür (varsayılana düşmez).
    guard let est = feedEstimate(babyId, defaults) else { return }
    // baseType filtresi (nextFeedEstimate/_rescheduleFeedReminder ile birebir):
    // hatırlatıcı türü ile değişen beslenmenin türü uyuşmuyorsa plana dokunma.
    guard let lastTs = resolveLastFeedTs(info, est: est) else { return }

    guard let nextMs = nextFeedMs(lastTs: lastTs, est: est) else { return }
    let next = Date(timeIntervalSince1970: Double(nextMs) / 1000.0)
    let now = Date()
    let slot = readInt(defaults, "fr_slot_\(babyId)")
    let preMin = readInt(defaults, "fr_premin_\(babyId)")
    let soundOn = defaults.string(forKey: "fr_sound_\(babyId)") == "1"

    let center = UNUserNotificationCenter.current()
    // flutter_local_notifications id biçimi = tamsayı id'nin string'i.
    // feedMainBase=800000, feedPreBase=810000, feedForgotBase=820000 (Dart
    // NotificationService ile aynı).
    let mainId = String(800000 + slot)
    let preId = String(810000 + slot)
    let forgotId = String(820000 + slot)
    center.removePendingNotificationRequests(withIdentifiers: [mainId, preId, forgotId])

    let prefix = name.isEmpty ? "" : "\(name) · "
    let mainTitle = defaults.string(forKey: "fr_main_title") ?? "Beslenme zamanı"
    let mainBody = defaults.string(forKey: "fr_main_body") ?? ""

    if next > now {
      let s = soundOn && !quietCovers(next, babyId: babyId, defaults: defaults)
      scheduleLocal(
        center, id: mainId, fireDate: next,
        title: prefix + mainTitle, body: mainBody,
        sound: s, category: "feed_snooze",
        payload: feedPayload(sound: s, slot: slot, babyName: name))
    }
    if preMin > 0 {
      let pre = next.addingTimeInterval(Double(-preMin * 60))
      if pre > now {
        let preTitle = defaults.string(forKey: "fr_pre_title_\(babyId)") ?? mainTitle
        let preBody = defaults.string(forKey: "fr_pre_body_\(babyId)") ?? ""
        let s = soundOn && !quietCovers(pre, babyId: babyId, defaults: defaults)
        scheduleLocal(
          center, id: preId, fireDate: pre,
          title: prefix + preTitle, body: preBody,
          sound: s, category: nil,
          payload: feedPayload(sound: s, slot: slot, babyName: name))
      }
    }
    // "Kaydı unuttun mu?" dürtmesi — tahmini beslenme saatinden 30 dk sonra.
    // Dart tarafı (notification_service.dart scheduleFeedReminder) bunu her
    // zaman iptal edip yeniden kurar; NSE bunu YAPMIYORDU (yalnız main+pre'yi
    // yeniden planlıyordu) → uygulama force-quit iken başka üye kayıt girse
    // bile eski "unuttun mu" bildirimi ESKİ (kayıttan ÖNCEKİ) tahmini zamana
    // göre ateşleniyordu. Artık main/pre ile birebir aynı şekilde yeniden kurulur.
    // Kullanıcı bu dürtmeyi Bildirimler ayarından kapatabilir (fr_forgot_<babyId>
    // = "0"). Anahtar yoksa (eski kurulum) AÇIK kabul edilir — mevcut davranış.
    let forgotOn = defaults.string(forKey: "fr_forgot_\(babyId)") != "0"
    let forgot = next.addingTimeInterval(30 * 60)
    if forgotOn && forgot > now {
      let forgotTitle = defaults.string(forKey: "fr_forgot_title") ?? "Kaydı unuttun mu?"
      let forgotBody = defaults.string(forKey: "fr_forgot_body") ?? ""
      let s = soundOn && !quietCovers(forgot, babyId: babyId, defaults: defaults)
      scheduleLocal(
        center, id: forgotId, fireDate: forgot,
        title: prefix + forgotTitle, body: forgotBody,
        sound: s, category: "feed_snooze",
        payload: feedPayload(sound: s, slot: slot, babyName: name))
    }
  }

  /// Dart `NotificationService.feedPayload` ile aynı biçim (U+0001 ayraçlı).
  private func feedPayload(sound: Bool, slot: Int, babyName: String) -> String {
    return "feed\u{1}\(sound ? 1 : 0)\u{1}\(slot)\u{1}\(babyName)"
  }

  /// V4 (ILAC-INCELEME-2): userInfo, flutter_local_notifications'ın kendi
  /// isteklerine koyduğu anahtarlarla doldurulur (`NotificationId`, `payload`,
  /// `present*`). Aksi hâlde FLN'nin Dart tarafı `pendingNotificationRequests`
  /// listesinin TAMAMINI (`id` null → TypeError) düşürür ve ön planda/dokunmada
  /// bu bildirimi kendi bildirimi saymaz.
  private func scheduleLocal(
    _ center: UNUserNotificationCenter, id: String, fireDate: Date,
    title: String, body: String, sound: Bool, category: String?, payload: String? = nil
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if sound { content.sound = .default }
    if let cat = category { content.categoryIdentifier = cat }
    content.userInfo = [
      "NotificationId": NSNumber(value: Int(id) ?? 0),
      "payload": payload.map { $0 as Any } ?? NSNull(),
      "presentAlert": NSNumber(value: true),
      "presentSound": NSNumber(value: sound),
      "presentBadge": NSNumber(value: true),
      "presentBanner": NSNumber(value: true),
      "presentList": NSNumber(value: true),
    ]
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

  /// "Sonraki beslenme" tahmini için efektif ayar (aralık + çapa türü).
  private struct FeedEstimate {
    let intervalMin: Double
    let base: String // 'all' | 'breast' | 'formula'
  }

  /// Bu bebek için ön planın App Group'a aynaladığı ayar (bkz. Dart
  /// `WidgetService.publishFeedReminderConfig`). Ayar HİÇ yazılmamışsa nil döner —
  /// çağıran taraf o zaman widget'a tahmin yazmaz. Eskiden burada 120 dk'lık
  /// varsayılana düşülüyordu; kullanıcının aralığı 3 saat olsa bile widget "son
  /// beslenme + 2 saat" gösteriyordu.
  ///
  /// Hatırlatıcı KAPALIYKEN Dart `FeedReminderConfig.effectiveForEstimate` ile
  /// birebir aynı kural uygulanır: tahmin varsayılana düşer (2 saat · tüm beslenmeler).
  private func feedEstimate(_ babyId: String, _ defaults: UserDefaults) -> FeedEstimate? {
    let interval = defaults.double(forKey: "feed_interval_\(babyId)")
    guard interval > 0 else { return nil }
    guard defaults.string(forKey: "fr_enabled_\(babyId)") == "1" else {
      return FeedEstimate(intervalMin: 120, base: "all")
    }
    return FeedEstimate(
      intervalMin: interval,
      base: defaults.string(forKey: "fr_base_\(babyId)") ?? "all")
  }

  /// Eklenen beslenmenin alt türü çapa türüyle uyuşuyor mu? Dart
  /// `FeedReminderConfig.matchesBase` ile BİREBİR aynı.
  private func matchesBase(_ base: String, _ sub: String?) -> Bool {
    switch base {
    case "breast": return sub == "breast"
    case "formula": return sub == "formula"
    default: return true
    }
  }

  /// Bu push'ta hangi last_feed zaman damgasının kullanılacağını çözer — iki farklı
  /// push şekli var:
  /// - EKLEME (family_activity): TEK aday `last_feed_ts` + `feed_sub` gelir;
  ///   `feed_sub` hatırlatıcının baz türüyle (est.base) uyuşmuyorsa kullanılmaz
  ///   (eklenen kayıt çapayı oynatmıyor demektir).
  /// - GÜNCELLEME/SİLME (sync_nudge): "hangi kayıt değişti" tek başına yetmez —
  ///   sunucu ÜÇ baz-türü ('all'/'breast'/'formula') karşılığını gönderir
  ///   (bkz. api _feed_anchors); burada doğrudan est.base'e karşılık geleni okuruz.
  private func resolveLastFeedTs(_ info: [AnyHashable: Any], est: FeedEstimate) -> String? {
    if let anchor = info["last_feed_\(est.base)"] as? String, !anchor.isEmpty {
      return anchor
    }
    guard let ts = info["last_feed_ts"] as? String,
          matchesBase(est.base, info["feed_sub"] as? String) else { return nil }
    return ts
  }

  /// next = lastTs + interval(dk). Tarih ayrıştırılamazsa nil.
  private func nextFeedMs(lastTs: String, est: FeedEstimate) -> Int64? {
    guard let last = parseDate(lastTs) else { return nil }
    // O17: ileri tarihli çapa (şimdi + 1 saatten sonra) hatırlatıcıyı günler
    // sonrasına kurmasın — Dart feedAnchorPlausible ile aynı eşik.
    if last.timeIntervalSinceNow > 3600 { return nil }
    let next = last.addingTimeInterval(est.intervalMin * 60)
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

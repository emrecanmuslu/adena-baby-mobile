import WidgetKit
import SwiftUI

// Adena Baby — "Sonraki Beslenme" widget'ı (iOS, ana ekran + kilit ekranı).
//
// GERİ SAYIM DEĞİL, mutlak SAAT gösterir (ör. "14:30"): değer sabit olduğundan
// widget'ın dakika-dakika güncellenmesi gerekmez → eski timeline donması ortadan
// kalkar, refresh bütçesi harcanmaz. Ayrıca "Son besleme HH:MM" (gerçek bilgi).
// Saat bugün değilse önüne "Dün" / "Yarın" / kısa tarih eklenir (G7).
//
// Flutter (lib/core/widget_service.dart) App Group'a şunları yazar:
//   babies_json (doğmuş bebekler), name_<id>/next_<id>/last_<id>,
//   active_id (+ eski yedek baby_name/next_feed_ms/last_feed_ms), locale.
// NSE (push) de bebek-başı anahtarları günceller ve WidgetCenter'ı yeniler.
//
// iOS 17+: widget başına bebek seçilebilir (FeedWidgetConfigurable.swift,
// "Widget'ı Düzenle"); seçim yoksa uygulamadaki aktif bebek. iOS 15–16: bu
// dosyadaki statik widget (aktif bebek). İkisi aynı `kind` ("FeedWidget").

let feedWidgetKind = "FeedWidget"
private let appGroupId = "group.com.adenababy.adenaBaby"
private let coral = Color(red: 1.0, green: 138.0 / 255.0, blue: 122.0 / 255.0)

enum FeedState {
    case ok
    /// Seçili bebek artık listede yok (silindi, aileden çıkarıldı, gebelik, hesap
    /// değişti). Eski ad/saat ASLA gösterilmez (K4).
    case missing
    /// Hiç (doğmuş) bebek yok ya da oturum kapalı.
    case noBabies
}

struct FeedEntry: TimelineEntry {
    let date: Date
    let babyName: String
    let nextFeed: Date? // nil → henüz kayıt yok
    let lastFeed: Date?
    let lang: String
    let state: FeedState
}

// MARK: - Metinler (uygulama dilinde; App Group `locale`)

enum FeedText {
    case next, due, awaiting, last, lastShort, noFeed, missing, reselect, noBabies
    case yesterday, tomorrow, baby
}

private let feedTexts: [String: [FeedText: String]] = [
    "tr": [.next: "Sonraki beslenme", .due: "Beslenme zamanı", .awaiting: "Beslenme bekleniyor",
           .last: "Son besleme %@", .lastShort: "Son %@", .noFeed: "kayıt yok",
           .missing: "Bebek bulunamadı", .reselect: "Düzenleyip yeniden seç",
           .noBabies: "Önce uygulamayı açıp bebek ekleyin",
           .yesterday: "Dün", .tomorrow: "Yarın", .baby: "Bebek"],
    "en": [.next: "Next feeding", .due: "Feeding time", .awaiting: "Awaiting feeding",
           .last: "Last feeding %@", .lastShort: "Last %@", .noFeed: "no feeding",
           .missing: "Baby not found", .reselect: "Edit the widget to choose again",
           .noBabies: "Open the app and add a baby first",
           .yesterday: "Yesterday", .tomorrow: "Tomorrow", .baby: "Baby"],
    "es": [.next: "Próxima alimentación", .due: "Hora de alimentar", .awaiting: "Esperando alimentación",
           .last: "Última alimentación %@", .lastShort: "Última %@", .noFeed: "sin registros",
           .missing: "Bebé no encontrado", .reselect: "Edita el widget para volver a elegir",
           .noBabies: "Primero abre la app y añade un bebé",
           .yesterday: "Ayer", .tomorrow: "Mañana", .baby: "Bebé"],
    "fr": [.next: "Prochain repas", .due: "Heure du repas", .awaiting: "En attente du repas",
           .last: "Dernier repas %@", .lastShort: "Dernier %@", .noFeed: "aucun repas",
           .missing: "Bébé introuvable", .reselect: "Modifiez le widget pour choisir à nouveau",
           .noBabies: "Ouvrez d'abord l'app et ajoutez un bébé",
           .yesterday: "Hier", .tomorrow: "Demain", .baby: "Bébé"],
    "ar": [.next: "الرضعة التالية", .due: "حان وقت الرضعة", .awaiting: "بانتظار الرضعة",
           .last: "آخر رضعة %@", .lastShort: "آخر %@", .noFeed: "لا سجلات",
           .missing: "لم يتم العثور على الطفل", .reselect: "عدّل الأداة لإعادة الاختيار",
           .noBabies: "افتح التطبيق وأضف طفلًا أولًا",
           .yesterday: "أمس", .tomorrow: "غدًا", .baby: "الطفل"],
    "hi": [.next: "अगली फीडिंग", .due: "फीडिंग का समय", .awaiting: "फीडिंग की प्रतीक्षा",
           .last: "पिछली फीडिंग %@", .lastShort: "पिछली %@", .noFeed: "कोई रिकॉर्ड नहीं",
           .missing: "शिशु नहीं मिला", .reselect: "फिर से चुनने के लिए विजेट संपादित करें",
           .noBabies: "पहले ऐप खोलकर शिशु जोड़ें",
           .yesterday: "कल", .tomorrow: "कल", .baby: "शिशु"],
    "zh": [.next: "下一次喂养", .due: "该喂养了", .awaiting: "等待喂养",
           .last: "上次喂养 %@", .lastShort: "上次 %@", .noFeed: "暂无记录",
           .missing: "找不到宝宝", .reselect: "编辑小组件以重新选择",
           .noBabies: "请先打开应用并添加宝宝",
           .yesterday: "昨天", .tomorrow: "明天", .baby: "宝宝"],
]

func feedText(_ key: FeedText, _ lang: String) -> String {
    feedTexts[lang]?[key] ?? feedTexts["tr"]![key]!
}

// MARK: - Veri

/// App Group `babies_json` (yoksa / okunamazsa nil).
func widgetBabies() -> [(id: String, name: String)]? {
    guard let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: "babies_json"),
          let data = raw.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else { return nil }
    return arr.compactMap { m -> (id: String, name: String)? in
        guard let id = m["id"] as? String else { return nil }
        return (id: id, name: (m["name"] as? String) ?? "")
    }
}

/// [selectedBabyId] nil → aktif bebek (statik widget ve seçimsiz iOS 17 widget'ı).
func readFeedEntry(selectedBabyId: String?) -> FeedEntry {
    let defaults = UserDefaults(suiteName: appGroupId)
    let lang = defaults?.string(forKey: "locale") ?? "tr"
    let babies = widgetBabies()

    func perBaby(_ id: String, _ listName: String?) -> FeedEntry {
        let name = (listName?.isEmpty == false ? listName : nil)
            ?? defaults?.string(forKey: "name_\(id)") ?? feedText(.baby, lang)
        return FeedEntry(date: Date(), babyName: name,
                         nextFeed: dateFromMs(defaults?.string(forKey: "next_\(id)")),
                         lastFeed: dateFromMs(defaults?.string(forKey: "last_\(id)")),
                         lang: lang, state: .ok)
    }
    func status(_ state: FeedState) -> FeedEntry {
        FeedEntry(date: Date(), babyName: "", nextFeed: nil, lastFeed: nil, lang: lang, state: state)
    }

    if let sel = selectedBabyId, !sel.isEmpty {
        if let list = babies {
            guard let b = list.first(where: { $0.id == sel }) else { return status(.missing) }
            return perBaby(sel, b.name)
        }
        guard defaults?.string(forKey: "name_\(sel)") != nil else { return status(.missing) }
        return perBaby(sel, nil)
    }

    if let list = babies {
        guard let first = list.first else { return status(.noBabies) }
        let activeId = defaults?.string(forKey: "active_id")
        let b = list.first(where: { $0.id == activeId }) ?? first
        return perBaby(b.id, b.name)
    }

    // Eski kurulum (babies_json hiç yazılmamış): aktif bebek anahtarı, yoksa yedek.
    if let id = defaults?.string(forKey: "active_id"), !id.isEmpty,
       defaults?.string(forKey: "name_\(id)") != nil {
        return perBaby(id, nil)
    }
    return FeedEntry(date: Date(),
                     babyName: defaults?.string(forKey: "baby_name") ?? feedText(.baby, lang),
                     nextFeed: dateFromMs(defaults?.string(forKey: "next_feed_ms")),
                     lastFeed: dateFromMs(defaults?.string(forKey: "last_feed_ms")),
                     lang: lang, state: .ok)
}

private func dateFromMs(_ s: String?) -> Date? {
    if let s = s, let ms = Int(s), ms > 0 {
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }
    return nil
}

/// Şimdi + (vakit gelecekteyse) tam vakit anı → etiket kendiliğinden "Beslenme
/// zamanı"na döner. 30 dk'da bir yedek tazeleme (tarih bağlamı gece yarısı da kayar).
func feedTimeline(_ base: FeedEntry) -> Timeline<FeedEntry> {
    let now = Date()
    var entries = [FeedEntry(date: now, babyName: base.babyName, nextFeed: base.nextFeed,
                             lastFeed: base.lastFeed, lang: base.lang, state: base.state)]
    if let feed = base.nextFeed, feed > now {
        entries.append(FeedEntry(date: feed, babyName: base.babyName, nextFeed: feed,
                                 lastFeed: base.lastFeed, lang: base.lang, state: base.state))
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800)))
}

func placeholderFeedEntry() -> FeedEntry {
    FeedEntry(date: Date(), babyName: "Bebek",
              nextFeed: Date().addingTimeInterval(3600),
              lastFeed: Date().addingTimeInterval(-3600), lang: "tr", state: .ok)
}

// MARK: - Biçim

/// Cihaz biçiminde saat (TR 24s "14:30", US 12s "2:30 PM").
private func timeStr(_ d: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: d)
}

/// Saat bugünse yalnız saat; değilse "Dün 23:10" / "Yarın 02:00" / "12 Ağu 15:13".
private func whenStr(_ d: Date, now: Date, lang: String) -> String {
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                  to: cal.startOfDay(for: d)).day ?? 0
    switch days {
    case 0: return timeStr(d)
    case -1: return "\(feedText(.yesterday, lang)) \(timeStr(d))"
    case 1: return "\(feedText(.tomorrow, lang)) \(timeStr(d))"
    default:
        let f = DateFormatter()
        f.locale = Locale(identifier: lang)
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return "\(f.string(from: d)) \(timeStr(d))"
    }
}

/// Etiket: vakit geçtiyse nazikçe "Beslenme zamanı", değilse "Sonraki beslenme".
private func labelText(_ e: FeedEntry) -> String {
    guard let f = e.nextFeed else { return feedText(.next, e.lang) }
    if f < e.date { return feedText(.due, e.lang) }
    return feedText(.next, e.lang)
}

// MARK: - Görünümler

/// Ana ekran widget'ı (systemSmall/Medium).
struct FeedHomeView: View {
    var entry: FeedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch entry.state {
            case .missing:
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3).foregroundColor(coral)
                Spacer(minLength: 0)
                Text(feedText(.missing, entry.lang)).font(.subheadline).fontWeight(.semibold)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(feedText(.reselect, entry.lang)).font(.caption2)
                    .foregroundColor(.secondary).lineLimit(2)
            case .noBabies:
                Image(systemName: "drop.fill").font(.caption).foregroundColor(coral)
                Spacer(minLength: 0)
                Text(feedText(.noBabies, entry.lang)).font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.secondary).lineLimit(3).minimumScaleFactor(0.8)
            case .ok:
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill").font(.caption).foregroundColor(coral)
                    Text(entry.babyName).font(.caption).fontWeight(.semibold)
                        .foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(labelText(entry)).font(.caption2).foregroundColor(.secondary)
                if let feed = entry.nextFeed {
                    Text(whenStr(feed, now: entry.date, lang: entry.lang)).font(.title3).fontWeight(.bold)
                        .monospacedDigit().foregroundColor(coral)
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(feedText(.awaiting, entry.lang))
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                }
                if let last = entry.lastFeed {
                    Text(String(format: feedText(.last, entry.lang),
                                whenStr(last, now: entry.date, lang: entry.lang)))
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// Kilit ekranı (saat altı) accessory widget'ları — iOS 16+.
@available(iOS 16.0, *)
struct FeedAccessoryView: View {
    var entry: FeedEntry
    var family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            switch entry.state {
            case .missing:
                Label(feedText(.missing, entry.lang), systemImage: "drop.fill")
            case .noBabies:
                Label(feedText(.noFeed, entry.lang), systemImage: "drop.fill")
            case .ok:
                if let feed = entry.nextFeed {
                    Label { Text(whenStr(feed, now: entry.date, lang: entry.lang)) }
                        icon: { Image(systemName: "drop.fill") }
                } else {
                    Label(feedText(.noFeed, entry.lang), systemImage: "drop.fill")
                }
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").font(.caption2)
                    if entry.state == .ok, let feed = entry.nextFeed {
                        Text(timeStr(feed)).font(.system(size: 13, weight: .semibold))
                            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    } else {
                        Text("—").font(.caption2)
                    }
                }
            }
        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                switch entry.state {
                case .missing:
                    Label(feedText(.missing, entry.lang), systemImage: "drop.fill")
                        .font(.caption2).fontWeight(.semibold).lineLimit(1)
                    Text(feedText(.reselect, entry.lang)).font(.caption2)
                        .foregroundStyle(.secondary).lineLimit(2)
                case .noBabies:
                    Label(feedText(.noBabies, entry.lang), systemImage: "drop.fill")
                        .font(.caption2).lineLimit(3)
                case .ok:
                    Label(entry.babyName, systemImage: "drop.fill")
                        .font(.caption2).fontWeight(.semibold).lineLimit(1)
                    Text(labelText(entry)).font(.caption2).foregroundStyle(.secondary)
                    if let feed = entry.nextFeed {
                        Text(whenStr(feed, now: entry.date, lang: entry.lang)).font(.headline)
                            .fontWeight(.bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    } else {
                        Text(feedText(.awaiting, entry.lang))
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    if let last = entry.lastFeed {
                        Text(String(format: feedText(.lastShort, entry.lang),
                                    whenStr(last, now: entry.date, lang: entry.lang)))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FeedWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FeedEntry

    var body: some View {
        if #available(iOS 16.0, *) {
            switch family {
            case .accessoryInline, .accessoryCircular, .accessoryRectangular:
                FeedAccessoryView(entry: entry, family: family)
            default:
                FeedHomeView(entry: entry)
            }
        } else {
            FeedHomeView(entry: entry)
        }
    }
}

/// Desteklenen boyutlar (ana ekran + iOS 16+ kilit ekranı).
var feedWidgetFamilies: [WidgetFamily] {
    var f: [WidgetFamily] = [.systemSmall, .systemMedium]
    if #available(iOS 16.0, *) {
        f += [.accessoryRectangular, .accessoryInline, .accessoryCircular]
    }
    return f
}

// MARK: - iOS 15–16: statik widget (aktif bebek)

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry { placeholderFeedEntry() }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        completion(readFeedEntry(selectedBabyId: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        completion(feedTimeline(readFeedEntry(selectedBabyId: nil)))
    }
}

struct FeedWidget: Widget {
    let kind = feedWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FeedProvider()) { entry in
            if #available(iOS 17.0, *) {
                FeedWidgetEntryView(entry: entry)
                    .containerBackground(.background, for: .widget)
            } else {
                FeedWidgetEntryView(entry: entry)
                    .background(Color(.systemBackground))
            }
        }
        .configurationDisplayName("Sonraki Beslenme")
        .description("Aktif bebeğin tahmini sonraki beslenme saatini gösterir.")
        .supportedFamilies(feedWidgetFamilies)
    }
}

import WidgetKit
import SwiftUI

// Adena Baby — "Sonraki Beslenme" widget'ı (iOS, ana ekran + kilit ekranı).
//
// GERİ SAYIM DEĞİL, mutlak SAAT gösterir (ör. "14:30"): değer sabit olduğundan
// widget'ın dakika-dakika güncellenmesi gerekmez → eski timeline donması ortadan
// kalkar, refresh bütçesi harcanmaz. Ayrıca "Son besleme HH:MM" (gerçek bilgi).
//
// Flutter (lib/core/widget_service.dart) App Group'a şunları yazar:
//   name_<id>/next_<id>/last_<id> (+ aktif fallback baby_name/next_feed_ms/last_feed_ms),
//   active_id, locale. NSE (push) de aynı anahtarları günc: WidgetCenter reload eder.

private let appGroupId = "group.com.adenababy.adenaBaby"
private let coral = Color(red: 1.0, green: 138.0 / 255.0, blue: 122.0 / 255.0)

struct FeedEntry: TimelineEntry {
    let date: Date
    let babyName: String
    let nextFeed: Date? // nil → henüz kayıt yok
    let lastFeed: Date?
    let en: Bool
}

/// epoch ms → cihaz biçiminde saat (TR 24s "14:30", US 12s "2:30 PM").
private func timeStr(_ d: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: d)
}

/// Etiket: vakit geçtiyse nazikçe "Beslenme zamanı", değilse "Sonraki beslenme".
private func labelText(_ e: FeedEntry) -> String {
    guard let f = e.nextFeed else { return e.en ? "Next feed" : "Sonraki beslenme" }
    if f < e.date { return e.en ? "Feed time" : "Beslenme zamanı" }
    return e.en ? "Next feed" : "Sonraki beslenme"
}

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: Date(), babyName: "Bebek",
                  nextFeed: Date().addingTimeInterval(3600),
                  lastFeed: Date().addingTimeInterval(-3600), en: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        let base = readEntry()
        guard let feed = base.nextFeed else {
            completion(Timeline(entries: [base],
                                policy: .after(Date().addingTimeInterval(1800))))
            return
        }
        let now = Date()
        var entries = [FeedEntry(date: now, babyName: base.babyName,
                                 nextFeed: feed, lastFeed: base.lastFeed, en: base.en)]
        // Vakit gelecekteyse, tam o ana bir entry daha ekle → etiket "Beslenme
        // zamanı"na kendiliğinden dönsün (sistemi uyandırmadan). Saat metni sabit.
        if feed > now {
            entries.append(FeedEntry(date: feed, babyName: base.babyName,
                                     nextFeed: feed, lastFeed: base.lastFeed, en: base.en))
        }
        // Veri değişince publish/NSE reloadTimelines tetikler; yine de 30 dk'da bir
        // tazele (son-besleme vb. yedek güncelleme).
        completion(Timeline(entries: entries,
                            policy: .after(now.addingTimeInterval(1800))))
    }

    private func readEntry() -> FeedEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let en = defaults?.string(forKey: "locale") == "en"
        // Aktif bebek per-baby anahtarlardan (name_/next_/last_<id>); yoksa fallback.
        let activeId = defaults?.string(forKey: "active_id")
        var name: String
        var nextStr: String?
        var lastStr: String?
        if let id = activeId, !id.isEmpty,
           let perName = defaults?.string(forKey: "name_\(id)") {
            name = perName
            nextStr = defaults?.string(forKey: "next_\(id)")
            lastStr = defaults?.string(forKey: "last_\(id)")
        } else {
            name = defaults?.string(forKey: "baby_name") ?? (en ? "Baby" : "Bebek")
            nextStr = defaults?.string(forKey: "next_feed_ms")
            lastStr = defaults?.string(forKey: "last_feed_ms")
        }
        return FeedEntry(date: Date(), babyName: name,
                         nextFeed: dateFromMs(nextStr), lastFeed: dateFromMs(lastStr), en: en)
    }

    private func dateFromMs(_ s: String?) -> Date? {
        if let s = s, let ms = Int(s), ms > 0 {
            return Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return nil
    }
}

/// Ana ekran widget'ı (systemSmall/Medium).
struct FeedHomeView: View {
    var entry: FeedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill").font(.caption).foregroundColor(coral)
                Text(entry.babyName).font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(labelText(entry)).font(.caption2).foregroundColor(.secondary)
            if let feed = entry.nextFeed {
                Text(timeStr(feed)).font(.title3).fontWeight(.bold)
                    .monospacedDigit().foregroundColor(coral)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(entry.en ? "Awaiting feed" : "Beslenme bekleniyor")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
            }
            if let last = entry.lastFeed {
                Text((entry.en ? "Last " : "Son besleme ") + timeStr(last))
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
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
            if let feed = entry.nextFeed {
                Label { Text(timeStr(feed)) } icon: { Image(systemName: "drop.fill") }
            } else {
                Label(entry.en ? "no feed" : "kayıt yok", systemImage: "drop.fill")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").font(.caption2)
                    if let feed = entry.nextFeed {
                        Text(timeStr(feed)).font(.system(size: 13, weight: .semibold))
                            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    } else {
                        Text("—").font(.caption2)
                    }
                }
            }
        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.babyName, systemImage: "drop.fill")
                    .font(.caption2).fontWeight(.semibold).lineLimit(1)
                Text(labelText(entry)).font(.caption2).foregroundStyle(.secondary)
                if let feed = entry.nextFeed {
                    Text(timeStr(feed)).font(.headline).fontWeight(.bold)
                        .monospacedDigit().lineLimit(1)
                } else {
                    Text(entry.en ? "Awaiting feed" : "Beslenme bekleniyor")
                        .font(.subheadline).fontWeight(.semibold)
                }
                if let last = entry.lastFeed {
                    Text((entry.en ? "Last " : "Son ") + timeStr(last))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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

struct FeedWidget: Widget {
    let kind = "FeedWidget"

    private static var families: [WidgetFamily] {
        var f: [WidgetFamily] = [.systemSmall, .systemMedium]
        if #available(iOS 16.0, *) {
            f += [.accessoryRectangular, .accessoryInline, .accessoryCircular]
        }
        return f
    }

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
        .supportedFamilies(Self.families)
    }
}

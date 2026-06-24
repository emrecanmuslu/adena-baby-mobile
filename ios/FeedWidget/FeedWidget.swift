import WidgetKit
import SwiftUI

// Adena Baby — "Sonraki Beslenme" ana ekran widget'ı (iOS).
//
// Flutter tarafı (lib/core/widget_service.dart) paylaşımlı App Group depolama
// alanına şu anahtarları yazar:
//   - "baby_name"     : String   (aktif bebeğin adı)
//   - "next_feed_ms"  : String   (TAHMİNİ sonraki beslenme epoch ms; "-1" = kayıt yok)
//   - "locale"        : String   ("tr" | "en" — geri sayım metni dili)
// home_widget eklentisi WidgetCenter.reloadTimelines(ofKind: "FeedWidget")
// çağırır → kind ile iOSName ('FeedWidget') birebir aynı olmalı.
//
// @main, FeedWidgetBundle.swift'te tanımlı; bu dosya yalnız widget'ı sağlar.

private let appGroupId = "group.com.adenababy.adenaBaby"

// Tasarım mercan rengi #FF8A7A.
private let coral = Color(red: 1.0, green: 138.0 / 255.0, blue: 122.0 / 255.0)

struct FeedEntry: TimelineEntry {
    let date: Date
    let babyName: String
    let nextFeed: Date? // nil → henüz kayıt yok
    let en: Bool
}

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: Date(), babyName: "Bebek",
                  nextFeed: Date().addingTimeInterval(3600), en: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        let base = readEntry()
        guard let feed = base.nextFeed else {
            // Kayıt yok → tek entry, 15 dakikada bir tazele.
            let next = Date().addingTimeInterval(900)
            completion(Timeline(entries: [base], policy: .after(next)))
            return
        }
        // Saniye GÖSTERMEDEN dakikanın gerçek zamanlı düşmesi için, her biri kendi
        // anına (date) sahip dakika-dakika entry üret. Metin entry.date'e göre
        // hesaplandığından (countdownWords) widget tam dakika sınırında günceller —
        // sistemi uyandırmadan, refresh bütçesi harcamadan.
        let now = Date()
        var entries: [FeedEntry] = [
            FeedEntry(date: now, babyName: base.babyName, nextFeed: feed, en: base.en)
        ]
        // İlk dakika sınırına kalan saniye (gelecekte geri, geçmişte ileri sayım).
        let secs = feed.timeIntervalSince(now)
        var step = secs > 0
            ? secs.truncatingRemainder(dividingBy: 60)
            : 60 - (-secs).truncatingRemainder(dividingBy: 60)
        if step <= 0 { step += 60 }
        var t = now.addingTimeInterval(step)
        // DONMA FIX: eskiden sabit 60 entry (1 saat) üretilirdi → 2-3 saatlik
        // aralıkta 1. saatten sonra geri sayım DONUYORDU. Artık beslenmeye kadar
        // (+30 dk gecikme payı) dakika-dakika entry üret; 6 saatle (360) sınırla
        // (WidgetKit + reload bütçesi). Böylece widget tüm aralıkta canlı sayar.
        let minsToFeed = secs > 0 ? Int(secs / 60) : 0
        let count = min(max(minsToFeed + 30, 60), 360)
        for _ in 0..<count {
            entries.append(FeedEntry(date: t, babyName: base.babyName, nextFeed: feed, en: base.en))
            t = t.addingTimeInterval(60)
        }
        completion(Timeline(entries: entries, policy: .after(t)))
    }

    private func readEntry() -> FeedEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let en = defaults?.string(forKey: "locale") == "en"
        // Aktif bebeğin verisi ÖNCE per-baby anahtarlardan (name_<id>/next_<id>)
        // okunur — push arka plan handler'ı (publishOne) ve NSE bunları yazar; iOS
        // widget'ı tek bebek (aktif) gösterir. Yoksa eski aktif-fallback anahtarlarına
        // (baby_name/next_feed_ms — publishAll ön planda yazar) düş. Bu okuma değişikliği
        // olmadan push'la yazılan veriyi widget göremiyordu (yalnız açılışta güncellenirdi).
        let activeId = defaults?.string(forKey: "active_id")
        var name: String
        var msStr: String?
        if let id = activeId, !id.isEmpty,
           let perBabyName = defaults?.string(forKey: "name_\(id)") {
            name = perBabyName
            msStr = defaults?.string(forKey: "next_\(id)")
        } else {
            name = defaults?.string(forKey: "baby_name") ?? (en ? "Baby" : "Bebek")
            msStr = defaults?.string(forKey: "next_feed_ms")
        }
        var feed: Date?
        if let msStr = msStr, let ms = Int(msStr), ms > 0 {
            feed = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return FeedEntry(date: Date(), babyName: name, nextFeed: feed, en: en)
    }
}

/// Geri sayım metni — DAKİKA çözünürlüğü (saniye YOK). Android FeedWidgetProvider
/// (durText) ile aynı biçim: "1 sa 42 dk", "3 gün 5 sa", "şimdi". asOf = entry.date
/// olduğundan, timeline dakika-başı entry ürettiği için değer canlı düşer. Gelecekte
/// geri, geçmişte (gecikme) ileri sayar.
private func countdownWords(_ feed: Date, asOf now: Date, en: Bool) -> String {
    let diff = feed.timeIntervalSince(now)        // saniye; geçmiş → negatif
    if diff >= 0 && diff < 60 { return en ? "now" : "şimdi" }
    let totalMin = Int(abs(diff)) / 60
    let days = totalMin / 1440
    let hours = (totalMin % 1440) / 60
    let mins = totalMin % 60
    if days > 0 { return en ? "\(days)d \(hours)h" : "\(days) gün \(hours) sa" }
    if hours > 0 && mins > 0 { return en ? "\(hours)h \(mins)m" : "\(hours) sa \(mins) dk" }
    if hours > 0 { return en ? "\(hours)h" : "\(hours) sa" }
    return en ? "\(mins)m" : "\(mins) dk"
}

/// Hedef geçmişte mi (gecikmiş mi) — etiket için (entry.date = timeline anı).
private func isOverdue(_ entry: FeedEntry) -> Bool {
    guard let f = entry.nextFeed else { return false }
    return f < entry.date
}

/// Ana ekran widget'ı (systemSmall/Medium) görünümü.
struct FeedHomeView: View {
    var entry: FeedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundColor(coral)
                Text(entry.babyName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(isOverdue(entry) ? (entry.en ? "Overdue" : "Gecikti")
                                  : (entry.en ? "Next feed" : "Sonraki beslenme"))
                .font(.caption2)
                .foregroundColor(.secondary)
            if let feed = entry.nextFeed {
                Text(countdownWords(feed, asOf: entry.date, en: entry.en))
                    .font(.headline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(entry.en ? "Awaiting feed" : "Beslenme bekleniyor")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// Kilit ekranı (saat altı) accessory widget'ları — iOS 16+. Tek renkli/tint
/// render edilir, color'a güvenmeyiz. Kısa "sonraki beslenme" bilgisi.
@available(iOS 16.0, *)
struct FeedAccessoryView: View {
    var entry: FeedEntry
    var family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            // Saatin hemen altında tek satır (ikon + CANLI sayaç).
            if let feed = entry.nextFeed {
                Label { Text(countdownWords(feed, asOf: entry.date, en: entry.en)) } icon: { Image(systemName: "drop.fill") }
            } else {
                Label(entry.en ? "no feed" : "kayıt yok", systemImage: "drop.fill")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").font(.caption2)
                    if let feed = entry.nextFeed {
                        Text(countdownWords(feed, asOf: entry.date, en: entry.en))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    } else {
                        Text("—").font(.caption2)
                    }
                }
            }
        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.babyName, systemImage: "drop.fill")
                    .font(.caption2).fontWeight(.semibold)
                    .lineLimit(1)
                Text(isOverdue(entry) ? (entry.en ? "Overdue" : "Gecikti")
                                      : (entry.en ? "Next feed" : "Sonraki beslenme"))
                    .font(.caption2).foregroundStyle(.secondary)
                if let feed = entry.nextFeed {
                    Text(countdownWords(feed, asOf: entry.date, en: entry.en))
                        .font(.headline).fontWeight(.bold).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(entry.en ? "Awaiting feed" : "Beslenme bekleniyor")
                        .font(.subheadline).fontWeight(.semibold)
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

    // iOS 16+ kilit ekranı accessory aileleri eklenir; eski sürümlerde yalnız ana ekran.
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
        .description("Aktif bebeğin tahmini sonraki beslenmesini gösterir.")
        .supportedFamilies(Self.families)
    }
}

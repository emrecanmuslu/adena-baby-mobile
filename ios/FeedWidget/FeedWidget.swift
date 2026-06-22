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

private let appGroupId = "group.com.adenababy.adena_baby"

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
        let entry = readEntry()
        // Geri sayım güncel kalsın diye 5 dakikada bir yenile.
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())
            ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> FeedEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let name = defaults?.string(forKey: "baby_name") ?? "Bebek"
        let msStr = defaults?.string(forKey: "next_feed_ms")
        let en = defaults?.string(forKey: "locale") == "en"
        var feed: Date?
        if let msStr = msStr, let ms = Int(msStr), ms > 0 {
            feed = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return FeedEntry(date: Date(), babyName: name, nextFeed: feed, en: en)
    }
}

/// Tahmini sonraki beslenmeye kalan/geçen süreyi kısa biçimde verir (TR/EN).
private func countdownLabel(_ date: Date, _ en: Bool) -> String {
    let diff = Int(date.timeIntervalSince(Date()))
    if diff >= 0 && diff < 60 { return en ? "now" : "şimdi" }
    let late = diff < 0
    let dur = durText(abs(diff), en)
    if late { return en ? "\(dur) overdue" : "\(dur) gecikti" }
    return en ? "in \(dur)" : "\(dur) kaldı"
}

private func durText(_ secs: Int, _ en: Bool) -> String {
    let totalMin = secs / 60
    let days = totalMin / 1440
    let hours = (totalMin % 1440) / 60
    let mins = totalMin % 60
    if days > 0 { return en ? "\(days)d \(hours)h" : "\(days) gün \(hours) sa" }
    if hours > 0 && mins > 0 { return en ? "\(hours)h \(mins)m" : "\(hours) sa \(mins) dk" }
    if hours > 0 { return en ? "\(hours)h" : "\(hours) sa" }
    return en ? "\(mins)m" : "\(mins) dk"
}

struct FeedWidgetEntryView: View {
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
            Text(entry.en ? "Next feed" : "Sonraki beslenme")
                .font(.caption2)
                .foregroundColor(.secondary)
            if let feed = entry.nextFeed {
                Text(countdownLabel(feed, entry.en))
                    .font(.headline)
                    .fontWeight(.bold)
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

struct FeedWidget: Widget {
    let kind = "FeedWidget"

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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

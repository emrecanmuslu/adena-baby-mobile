import WidgetKit
import SwiftUI

// Adena Baby — "Son Beslenme" ana ekran widget'ı (iOS).
//
// Flutter tarafı (lib/core/widget_service.dart) paylaşımlı App Group depolama
// alanına şu anahtarları yazar:
//   - "baby_name"     : String   (aktif bebeğin adı)
//   - "last_feed_ms"  : String   (son beslenme epoch ms; "-1" = kayıt yok)
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
    let lastFeed: Date? // nil → henüz kayıt yok
}

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: Date(), babyName: "Bebek", lastFeed: Date().addingTimeInterval(-3600))
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        let entry = readEntry()
        // "X önce" güncel kalsın diye 5 dakikada bir yenile.
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())
            ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> FeedEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let name = defaults?.string(forKey: "baby_name") ?? "Bebek"
        let msStr = defaults?.string(forKey: "last_feed_ms")
        var feed: Date?
        if let msStr = msStr, let ms = Int(msStr), ms > 0 {
            feed = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return FeedEntry(date: Date(), babyName: name, lastFeed: feed)
    }
}

/// Geçen süreyi Türkçe kısa biçimde verir: "az önce" / "12 dk önce" / "3 sa önce" / "2 gün önce".
private func relativeLabel(_ date: Date) -> String {
    let secs = max(0, Int(Date().timeIntervalSince(date)))
    if secs < 60 { return "az önce" }
    let mins = secs / 60
    if mins < 60 { return "\(mins) dk önce" }
    let hours = mins / 60
    if hours < 24 { return "\(hours) sa önce" }
    let days = hours / 24
    return "\(days) gün önce"
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
            Text("Son beslenme")
                .font(.caption2)
                .foregroundColor(.secondary)
            if let feed = entry.lastFeed {
                Text(relativeLabel(feed))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Henüz kayıt yok")
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
        .configurationDisplayName("Son Beslenme")
        .description("Aktif bebeğin son beslenmesini gösterir.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

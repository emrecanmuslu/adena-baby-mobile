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

/// CANLI sayan geri sayım metni: Text(_:style:.timer) her saniye kendi günceller
/// (timeline yenilemesine bağlı DEĞİL) → widget "geri kalmış" görünmez. Gelecekte
/// aşağı, geçmişte (gecikme) yukarı sayar. Format HH:MM:SS (dil-bağımsız).
private func liveTimer(_ feed: Date) -> Text {
    Text(feed, style: .timer)
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
                liveTimer(feed)
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
                Label { liveTimer(feed) } icon: { Image(systemName: "drop.fill") }
            } else {
                Label(entry.en ? "no feed" : "kayıt yok", systemImage: "drop.fill")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").font(.caption2)
                    if let feed = entry.nextFeed {
                        liveTimer(feed)
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
                    liveTimer(feed)
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

import AppIntents
import SwiftUI
import WidgetKit

// iOS 17+: widget başına bebek seçimi (K5). Uzun bas → "Widget'ı Düzenle" →
// "Bebek". Seçim yoksa (mevcut widget'lar güncellemeden sonra dahil) uygulamadaki
// aktif bebek gösterilir — FeedWidget.swift'teki statik davranışın aynısı.
// Seçilen bebek artık listede değilse "Bebek bulunamadı" (K4).
//
// Bebek listesi App Group `babies_json`'dan okunur (Flutter WidgetService yazar);
// ayrı Intents Extension gerekmez (AppIntentConfiguration + EntityQuery).

@available(iOS 17.0, *)
struct BabyEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Bebek"
    static var defaultQuery = BabyQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17.0, *)
struct BabyQuery: EntityQuery {
    func entities(for identifiers: [BabyEntity.ID]) async throws -> [BabyEntity] {
        let list = widgetBabies() ?? []
        // Listede olmayan (silinmiş) bebek de DÖNDÜRÜLÜR: aksi halde parametre
        // boşa düşer ve widget sessizce aktif bebeği gösterirdi. Sağlayıcı bebeği
        // babies_json'da bulamayınca "Bebek bulunamadı" çizer (K4).
        return identifiers.map { id -> BabyEntity in
            if let b = list.first(where: { $0.id == id }) {
                return BabyEntity(id: b.id, name: b.name)
            }
            return BabyEntity(id: id, name: "—")
        }
    }

    func suggestedEntities() async throws -> [BabyEntity] {
        (widgetBabies() ?? []).map { BabyEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> BabyEntity? { nil }
}

@available(iOS 17.0, *)
struct SelectBabyIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Bebek seç"
    static var description = IntentDescription("Widget'ın göstereceği bebeği seç.")

    @Parameter(title: "Bebek")
    var baby: BabyEntity?

    init() {}
}

@available(iOS 17.0, *)
struct ConfigurableFeedProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FeedEntry { placeholderFeedEntry() }

    func snapshot(for configuration: SelectBabyIntent, in context: Context) async -> FeedEntry {
        readFeedEntry(selectedBabyId: configuration.baby?.id)
    }

    func timeline(for configuration: SelectBabyIntent, in context: Context) async -> Timeline<FeedEntry> {
        feedTimeline(readFeedEntry(selectedBabyId: configuration.baby?.id))
    }
}

/// Aynı `kind` → iOS 17'ye geçen mevcut widget'lar korunur (parametre boş = aktif bebek).
@available(iOS 17.0, *)
struct FeedWidgetConfigurable: Widget {
    let kind = feedWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectBabyIntent.self,
                               provider: ConfigurableFeedProvider()) { entry in
            FeedWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Sonraki Beslenme")
        .description("Seçtiğin bebeğin sonraki beslenme saatini gösterir.")
        .supportedFamilies(feedWidgetFamilies)
    }
}

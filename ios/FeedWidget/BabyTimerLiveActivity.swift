import ActivityKit
import WidgetKit
import SwiftUI

// Süren emzirme/uyku sayacı Live Activity arayüzü (kilit ekranı + Dynamic Island).
// Sayaç cihaz-tarafı Text(_:style:.timer) ile saniye saniye sayar (push'suz).
@available(iOS 16.1, *)
struct BabyTimerLiveActivity: Widget {
    private let coral = Color(red: 1.0, green: 138.0 / 255.0, blue: 122.0 / 255.0)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BabyTimerActivityAttributes.self) { context in
            // Kilit ekranı / banner görünümü.
            HStack(spacing: 12) {
                Image(systemName: icon(context.state))
                    .font(.title2)
                    .foregroundColor(coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.babyName)
                        .font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    Text(title(context.state))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                timerText(context.state)
                    .font(.title2).fontWeight(.bold).monospacedDigit()
                    .foregroundColor(coral)
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground).opacity(0.6))
            .activitySystemActionForegroundColor(coral)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(context.state))
                        .font(.title2).foregroundColor(coral)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(context.state)
                        .font(.title2).fontWeight(.bold).monospacedDigit()
                        .foregroundColor(coral)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.babyName)
                        .font(.caption).fontWeight(.semibold).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(title(context.state))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: icon(context.state)).foregroundColor(coral)
            } compactTrailing: {
                timerText(context.state).monospacedDigit().foregroundColor(coral)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: icon(context.state)).foregroundColor(coral)
            }
            .widgetURL(URL(string: "adenababy://timer"))
        }
    }

    private func icon(_ s: BabyTimerActivityAttributes.ContentState) -> String {
        s.kind == "sleep" ? "moon.zzz.fill" : "drop.fill"
    }

    private func title(_ s: BabyTimerActivityAttributes.ContentState) -> String {
        if s.kind == "sleep" {
            return s.paused ? (s.en ? "Sleep paused" : "Uyku duraklatıldı")
                            : (s.en ? "Sleeping" : "Uyku sürüyor")
        }
        let side = s.side == "right" ? (s.en ? "Right" : "Sağ")
                 : s.side == "left" ? (s.en ? "Left" : "Sol") : ""
        let base = s.en ? "Breastfeeding" : "Emzirme"
        let label = side.isEmpty ? base : "\(side) · \(base)"
        return s.paused ? "\(label) (\(s.en ? "paused" : "duraklatıldı"))" : label
    }

    @ViewBuilder
    private func timerText(_ s: BabyTimerActivityAttributes.ContentState) -> some View {
        if s.paused {
            Text(format(s.pausedSeconds))
        } else {
            // Geçmiş tarih → süre yukarı sayar (geçen süre).
            Text(Date(timeIntervalSince1970: s.startEpoch), style: .timer)
        }
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}

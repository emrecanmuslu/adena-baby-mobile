import ActivityKit
import Foundation

// Emzirme/uyku süren sayacı Live Activity öznitelikleri.
// ÖNEMLİ: Bu tip HEM ana uygulamada (Activity başlatır/günceller) HEM widget
// extension'ında (render eder) derlenmeli — AYNI tip olmak zorunda. pbxproj'da
// Runner + FeedWidgetExtension Sources'a eklendi.
@available(iOS 16.1, *)
struct BabyTimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var babyName: String
        var kind: String          // "sleep" | "breast"
        // Sayacın ETKİN başlangıcı (epoch saniye): geçen süre = now - startEpoch.
        // Emzirmede biriken süre çıkarılarak hesaplanır (Dart tarafı).
        var startEpoch: Double
        var paused: Bool
        var pausedSeconds: Double  // duraklatıldıysa gösterilecek donmuş süre (sn)
        var side: String           // emzirme: "left" | "right" | ""
        var en: Bool               // dil (TR/EN metin)
    }
}

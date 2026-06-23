import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

// Dart ↔ iOS köprüsü: MethodChannel "adena/live_activity" → ActivityKit.
// Tek bir süren-sayaç Live Activity yönetilir (startOrUpdate / end).
enum LiveActivityBridge {
    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "adena/live_activity", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            guard #available(iOS 16.1, *) else { result(nil); return }
            switch call.method {
            case "startOrUpdate":
                let a = call.arguments as? [String: Any] ?? [:]
                LiveActivityManager.startOrUpdate(
                    babyName: a["babyName"] as? String ?? "",
                    kind: a["kind"] as? String ?? "sleep",
                    startEpoch: (a["startEpoch"] as? NSNumber)?.doubleValue ?? 0,
                    paused: a["paused"] as? Bool ?? false,
                    pausedSeconds: (a["pausedSeconds"] as? NSNumber)?.doubleValue ?? 0,
                    side: a["side"] as? String ?? "",
                    en: a["en"] as? Bool ?? false
                )
                result(true)
            case "end":
                LiveActivityManager.end()
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}

@available(iOS 16.1, *)
enum LiveActivityManager {
    static func startOrUpdate(babyName: String, kind: String, startEpoch: Double,
                              paused: Bool, pausedSeconds: Double, side: String, en: Bool) {
        let state = BabyTimerActivityAttributes.ContentState(
            babyName: babyName, kind: kind, startEpoch: startEpoch,
            paused: paused, pausedSeconds: pausedSeconds, side: side, en: en)
        if let act = Activity<BabyTimerActivityAttributes>.activities.first {
            Task { await act.update(using: state) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                _ = try Activity.request(
                    attributes: BabyTimerActivityAttributes(),
                    contentState: state,
                    pushType: nil)
            } catch {
                // sessiz: Live Activity izni yok / sistem reddetti → app çalışmaya devam
            }
        }
    }

    static func end() {
        for act in Activity<BabyTimerActivityAttributes>.activities {
            Task { await act.end(dismissalPolicy: .immediate) }
        }
    }
}

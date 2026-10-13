//
//  FeedWidgetBundle.swift
//  FeedWidget
//
//  Created by Emrecan Muslu on 17.06.2026.
//

import WidgetKit
import SwiftUI

@main
struct FeedWidgetBundle: WidgetBundle {
    var body: some Widget {
        // "Sonraki beslenme" — iOS 17+: widget başına bebek seçimi (AppIntent);
        // iOS 15–16: statik (aktif bebek). İkisi aynı kind; yalnız biri kayıtlı olmalı.
        // WidgetBundleBuilder `if/else` (buildEither) desteklemez; buildOptional da
        // yalnız erişilebilirlik koşulundan (#available / #unavailable →
        // buildLimitedAvailability) gelen içeriği kabul eder — sade Bool koşulu derlenmez.
        if #available(iOS 17.0, *) {
            FeedWidgetConfigurable()
        }
        if #unavailable(iOS 17.0) {
            FeedWidget()
        }
        // Süren emzirme/uyku sayacı Live Activity'si (iOS 16.1+).
        if #available(iOS 16.1, *) {
            BabyTimerLiveActivity()
        }
    }
}

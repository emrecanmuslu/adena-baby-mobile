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
        feedWidget
        // Süren emzirme/uyku sayacı Live Activity'si (iOS 16.1+).
        if #available(iOS 16.1, *) {
            BabyTimerLiveActivity()
        }
    }

    /// "Sonraki beslenme" — iOS 17+: widget başına bebek seçimi (AppIntent);
    /// iOS 15–16: statik (aktif bebek). İkisi aynı kind → yalnız biri kaydedilir.
    ///
    /// WidgetBundleBuilder `if/else` (buildEither) desteklemez; `buildOptional` da
    /// yalnız `buildLimitedAvailability` işaretli içeriği kabul eder (sade Bool ya da
    /// `#unavailable` koşulu derlenmedi — ios-v1.7.2 koşuları 38397891033, 38399168818).
    /// Bu yüzden seçim builder DIŞINDA yapılır ve her iki dal aynı builder
    /// çağrılarıyla sarılır → iki `return` aynı (opak) türü döndürür.
    private var feedWidget: some Widget {
        if #available(iOS 17.0, *) {
            return WidgetBundleBuilder.buildOptional(
                WidgetBundleBuilder.buildLimitedAvailability(FeedWidgetConfigurable()))
        }
        return WidgetBundleBuilder.buildOptional(
            WidgetBundleBuilder.buildLimitedAvailability(FeedWidget()))
    }
}

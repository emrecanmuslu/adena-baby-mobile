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
    /// iOS 16.1–16.x: statik (aktif bebek). İkisi aynı kind → yalnız biri kaydedilir.
    /// Widget uzantısının dağıtım hedefi 16.1: buildLimitedAvailability 16.1 öncesinde
    /// "may crash" uyarısı veriyordu → iOS 15.x / 16.0'da widget hiç sunulmaz
    /// (ana uygulama ve NSE 15.0'da kalır).
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

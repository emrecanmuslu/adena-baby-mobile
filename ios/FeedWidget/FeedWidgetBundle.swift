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
        FeedWidget()
        // Süren emzirme/uyku sayacı Live Activity'si (iOS 16.1+).
        if #available(iOS 16.1, *) {
            BabyTimerLiveActivity()
        }
    }
}

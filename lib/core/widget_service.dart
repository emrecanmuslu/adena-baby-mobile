import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'i18n.dart';

/// Ana ekran (home screen) widget'ı köprüsü — "sonraki beslenme" geri sayımı.
///
/// Çok-bebek: her widget örneği KENDİ bebeğini gösterebilir (Android
/// yapılandırma aktivitesi `widget_baby_<widgetId>` = babyId yazar). Bu yüzden
/// veri bebek-başına saklanır: `name_<id>`, `next_<id>`. Ayrıca yapılandırma
/// ekranının listeleyebilmesi için `babies_json`, seçim yapılmamış widget'lar
/// için fallback olarak aktif bebek (`baby_name`/`next_feed_ms`/`active_id`).
///
/// Geri sayım metnini native taraf hesaplar (widget kendi periyodunda da güncel
/// kalsın); `locale` de yazılır ki TR/EN doğru gösterilsin.
class WidgetService {
  // iOS App Group — Xcode'da Widget Extension + ana uygulamada aynı grup tanımlı olmalı.
  static const _appGroupId = 'group.com.adenababy.adena_baby';
  static const _qualifiedAndroidName = 'com.adenababy.adena_baby.FeedWidgetProvider';

  static bool _inited = false;

  static Future<void> _ensureInit() async {
    if (_inited) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    _inited = true;
  }

  /// TÜM bebeklerin sonraki-beslenme verisini + bebek listesini yazar (ön plan,
  /// reaktif). [babies] sırası listeyi belirler; [activeId] seçim yapılmamış
  /// widget'ların göstereceği bebek.
  static Future<void> publishAll(
      List<WidgetBaby> babies, String activeId) async {
    try {
      await _ensureInit();
      final list = [for (final b in babies) {'id': b.id, 'name': b.name}];
      await HomeWidget.saveWidgetData<String>('babies_json', jsonEncode(list));
      for (final b in babies) {
        await HomeWidget.saveWidgetData<String>('name_${b.id}', b.name);
        await HomeWidget.saveWidgetData<String>('next_${b.id}', _ms(b.nextFeed));
      }
      final active = babies.where((b) => b.id == activeId).firstOrNull ??
          (babies.isNotEmpty ? babies.first : null);
      await HomeWidget.saveWidgetData<String>('active_id', active?.id ?? '');
      await HomeWidget.saveWidgetData<String>('baby_name', active?.name ?? 'Bebek');
      await HomeWidget.saveWidgetData<String>('next_feed_ms', _ms(active?.nextFeed));
      await HomeWidget.saveWidgetData<String>('locale', I18n.instance.locale);
      await _refresh();
    } catch (_) {
      // Widget eklenmemiş / platform desteklemiyor → yoksay.
    }
  }

  /// Tek bir bebeğin verisini günceller (push arka plan handler — yalnız o bebeği
  /// bilir). O bebeği seçen widget'lar tazelenir; seçimsiz (aktif) widget'lar bir
  /// sonraki ön planda güncellenir.
  static Future<void> publishOne(
      {required String babyId,
      required String babyName,
      DateTime? nextFeed}) async {
    try {
      await _ensureInit();
      await HomeWidget.saveWidgetData<String>('name_$babyId', babyName);
      await HomeWidget.saveWidgetData<String>('next_$babyId', _ms(nextFeed));
      await HomeWidget.saveWidgetData<String>('locale', I18n.instance.locale);
      await _refresh();
    } catch (_) {}
  }

  static String _ms(DateTime? d) => (d?.millisecondsSinceEpoch ?? -1).toString();

  static Future<void> _refresh() => HomeWidget.updateWidget(
        androidName: 'FeedWidgetProvider',
        qualifiedAndroidName: _qualifiedAndroidName,
        iOSName: 'FeedWidget',
      );
}

/// Widget'a yazılacak tek bebek: kimlik + ad + tahmini sonraki beslenme.
class WidgetBaby {
  final String id;
  final String name;
  final DateTime? nextFeed;
  const WidgetBaby({required this.id, required this.name, this.nextFeed});
}

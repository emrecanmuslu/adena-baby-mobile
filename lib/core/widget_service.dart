import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../models/quiet_hours.dart';
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
  // NOT: Apple App Group id'lerinde alt çizgi (_) YASAK → bundle ile aynı camelCase.
  static const _appGroupId = 'group.com.adenababy.adenaBaby';
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
  // build() her rebuild'de publishAll çağırır; içerik değişmediyse native widget
  // yazımı + refresh'i atla (gereksiz platform-channel/jank). LiveActivityService
  // ._lastSig deseniyle aynı. Yazım başarısızsa sıfırlanır → bir sonraki tekrar dener.
  static String? _lastPublishSig;

  static Future<void> publishAll(
      List<WidgetBaby> babies, String activeId) async {
    final sig = [
      for (final b in babies)
        '${b.id}|${b.name}|${_ms(b.nextFeed)}|${_ms(b.lastFeed)}',
      'active=$activeId|loc=${I18n.instance.locale}',
    ].join(';');
    if (sig == _lastPublishSig) return;
    _lastPublishSig = sig;
    try {
      await _ensureInit();
      final list = [for (final b in babies) {'id': b.id, 'name': b.name}];
      await HomeWidget.saveWidgetData<String>('babies_json', jsonEncode(list));
      for (final b in babies) {
        await HomeWidget.saveWidgetData<String>('name_${b.id}', b.name);
        await HomeWidget.saveWidgetData<String>('next_${b.id}', _ms(b.nextFeed));
        await HomeWidget.saveWidgetData<String>('last_${b.id}', _ms(b.lastFeed));
      }
      final active = babies.where((b) => b.id == activeId).firstOrNull ??
          (babies.isNotEmpty ? babies.first : null);
      await HomeWidget.saveWidgetData<String>('active_id', active?.id ?? '');
      await HomeWidget.saveWidgetData<String>('baby_name', active?.name ?? 'Bebek');
      await HomeWidget.saveWidgetData<String>('next_feed_ms', _ms(active?.nextFeed));
      await HomeWidget.saveWidgetData<String>('last_feed_ms', _ms(active?.lastFeed));
      await HomeWidget.saveWidgetData<String>('locale', I18n.instance.locale);
      await _refresh();
    } catch (_) {
      _lastPublishSig = null; // başarısız → sonraki çağrı tekrar denesin
      // Widget eklenmemiş / platform desteklemiyor → yoksay.
    }
  }

  /// Tek bir bebeğin verisini günceller (push arka plan handler — yalnız o bebeği
  /// bilir). O bebeği seçen widget'lar tazelenir; seçimsiz (aktif) widget'lar bir
  /// sonraki ön planda güncellenir.
  static Future<void> publishOne(
      {required String babyId,
      required String babyName,
      DateTime? nextFeed,
      DateTime? lastFeed,
      int? intervalMin}) async {
    try {
      await _ensureInit();
      await HomeWidget.saveWidgetData<String>('name_$babyId', babyName);
      await HomeWidget.saveWidgetData<String>('next_$babyId', _ms(nextFeed));
      await HomeWidget.saveWidgetData<String>('last_$babyId', _ms(lastFeed));
      // iOS Notification Service Extension (uygulama KAPALIYKEN) sonraki beslenmeyi
      // last_feed_ts + bu aralıktan hesaplar — App Group'a önbelleğe al.
      if (intervalMin != null) {
        await HomeWidget.saveWidgetData<int>('feed_interval_$babyId', intervalMin);
        await HomeWidget.saveWidgetData<int>('feed_interval_default', intervalMin);
      }
      await HomeWidget.saveWidgetData<String>('locale', I18n.instance.locale);
      await _refresh();
    } catch (_) {}
  }

  /// iOS Notification Service Extension'ın (uygulama FORCE-QUIT iken) beslenme
  /// hatırlatıcısını yeniden planlayabilmesi için gereken config'i App Group'a
  /// aynalar. Sorun: hatırlatıcı parametreleri Secure Storage'daki
  /// FeedReminderCache'tedir; NSE (ayrı extension) onu okuyamaz. Bu yüzden NSE'nin
  /// okuyabileceği App Group'a da yazarız. Android'de gerekmez (Dart arka plan
  /// handler'ı zaten yeniden planlar) ama yazması zararsız/idempotent.
  ///
  /// Locale-bağımlı başlık/gövde metinleri burada (ön planda, doğru dilde) çözülüp
  /// yazılır; NSE yalnız okuyup bebek adını başa ekler.
  static Future<void> publishFeedReminderConfig({
    required String babyId,
    required bool enabled,
    required int intervalMin,
    required int preMin,
    required int slot,
    required bool sound,
    required String baseType,
    required QuietHours quiet,
    required String mainTitle,
    required String mainBody,
    required String preTitle,
    required String preBody,
  }) async {
    try {
      await _ensureInit();
      await HomeWidget.saveWidgetData<String>(
          'fr_enabled_$babyId', enabled ? '1' : '0');
      await HomeWidget.saveWidgetData<int>('feed_interval_$babyId', intervalMin);
      await HomeWidget.saveWidgetData<int>('fr_premin_$babyId', preMin);
      await HomeWidget.saveWidgetData<int>('fr_slot_$babyId', slot);
      await HomeWidget.saveWidgetData<String>('fr_sound_$babyId', sound ? '1' : '0');
      await HomeWidget.saveWidgetData<String>('fr_base_$babyId', baseType);
      // Sessiz saat: "1|startMin|endMin" veya "0".
      await HomeWidget.saveWidgetData<String>('fr_quiet_$babyId',
          quiet.enabled ? '1|${quiet.startMin}|${quiet.endMin}' : '0');
      // Ön-hatırlatma metinleri preMin'e bağlı → bebek-başına çözülmüş yazılır.
      await HomeWidget.saveWidgetData<String>('fr_pre_title_$babyId', preTitle);
      await HomeWidget.saveWidgetData<String>('fr_pre_body_$babyId', preBody);
      // Ana uyarı metni bebekten bağımsız (yalnız dile bağlı) → ortak anahtar.
      await HomeWidget.saveWidgetData<String>('fr_main_title', mainTitle);
      await HomeWidget.saveWidgetData<String>('fr_main_body', mainBody);
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
  final DateTime? lastFeed;
  const WidgetBaby(
      {required this.id, required this.name, this.nextFeed, this.lastFeed});
}

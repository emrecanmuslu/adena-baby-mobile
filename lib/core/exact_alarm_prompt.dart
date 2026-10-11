import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'notification_service.dart';

/// M4 / KB-4 — Android 12+ "Alarmlar ve hatırlatıcılar" (kesin alarm) izni:
/// planlama yolunda otomatik istenmez (O16); ilk ilaç planı oluşturulurken ve
/// beslenme hatırlatıcısı ilk kez açılırken, izin yoksa TEK SEFERLİK açıklama
/// diyaloğu → sistem sayfası. Reddedilirse bir daha sorulmaz (prefs bayrağı);
/// Bildirimler ayarından her zaman açılabilir. iOS'ta hiç görünmez.
class ExactAlarmPrompt {
  static const prefsKey = 'exact_alarm_prompt_shown';

  final Future<bool> Function() canSchedule;
  final Future<bool> Function() request;
  final bool isAndroid;

  /// J12: izin GERÇEKTEN verilince çağrılır — o ana dek inexact kurulmuş
  /// beslenme/ilaç planları yeniden kurulsun (bkz. `resyncAfterExactAlarmGranted`).
  final Future<void> Function()? onGranted;

  ExactAlarmPrompt({
    Future<bool> Function()? canSchedule,
    Future<bool> Function()? request,
    bool? isAndroid,
    this.onGranted,
  })  : canSchedule = canSchedule ?? NotificationService.instance.canScheduleExact,
        request = request ?? NotificationService.instance.requestExactAlarmPermission,
        isAndroid = isAndroid ?? Platform.isAndroid;

  /// Sistem iznini ister; verildiyse [onGranted]'ı çalıştırır. Döner: izin var mı.
  Future<bool> requestAndResync() async {
    final ok = await request();
    if (ok) await onGranted?.call();
    return ok;
  }

  /// Diyalog gösterilmeli mi: Android + izin yok + daha önce gösterilmedi.
  Future<bool> shouldShow() async {
    if (!isAndroid) return false;
    if (await canSchedule()) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(prefsKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<void> _markShown() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(prefsKey, true);
    } catch (_) {}
  }

  /// Gerekirse açıklama diyaloğunu gösterir; "İzin ver" → sistem sayfası.
  /// Döner: diyalog gösterildi mi.
  Future<bool> maybeShow(BuildContext context) async {
    if (!await shouldShow()) return false;
    // J12: bayrak diyalog GERÇEKTEN gösterildikten sonra yazılır; context
    // düşmüşse diyalog görünmeden "gösterildi" sayılmasın.
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Tam zamanında bildirim')),
        content: Text(tr(
            'İlaç ve beslenme hatırlatıcılarının tam saatinde gelmesi için '
            '"Alarmlar ve hatırlatıcılar" izni gerekli. İzin vermezsen '
            'hatırlatıcılar birkaç dakika gecikebilir.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Daha sonra'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('İzin ver'))),
        ],
      ),
    );
    await _markShown();
    if (ok == true) await requestAndResync();
    return true;
  }
}

/// Bildirimler ayarı satırı (yalnız Android): izin durumu + açma düğmesi.
class ExactAlarmTile extends StatefulWidget {
  final ExactAlarmPrompt? prompt;
  /// J12: izin verilince yeniden kurulum (prompt'un [ExactAlarmPrompt.onGranted]
  /// alanı yoksa bu kullanılır).
  final Future<void> Function()? onGranted;
  const ExactAlarmTile({super.key, this.prompt, this.onGranted});

  @override
  State<ExactAlarmTile> createState() => _ExactAlarmTileState();
}

class _ExactAlarmTileState extends State<ExactAlarmTile> {
  late final ExactAlarmPrompt _p =
      widget.prompt ?? ExactAlarmPrompt(onGranted: widget.onGranted);
  bool? _can;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!_p.isAndroid) return;
    final can = await _p.canSchedule();
    if (mounted) setState(() => _can = can);
  }

  @override
  Widget build(BuildContext context) {
    if (!_p.isAndroid) return const SizedBox.shrink();
    final can = _can;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(can == true ? Icons.alarm_on_rounded : Icons.alarm_off_rounded),
      title: Text(tr('Tam zamanında bildirim')),
      subtitle: Text(can == null
          ? ''
          : can
              ? tr('İzin verildi')
              : tr('İzin yok — hatırlatıcılar birkaç dakika gecikebilir')),
      trailing: can == false
          ? TextButton(
              onPressed: () async {
                await _p.requestAndResync();
                await _refresh();
              },
              child: Text(tr('İzin ver')))
          : null,
    );
  }
}

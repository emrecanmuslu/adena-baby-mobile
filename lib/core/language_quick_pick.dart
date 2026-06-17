import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/i18n_repository.dart';
import '../features/settings/locale_controller.dart';
import '../models/locale_info.dart';
import 'i18n.dart';
import 'restart_widget.dart';
import 'theme.dart';

const _flags = {'tr': '🇹🇷', 'en': '🇬🇧'};

/// Kompakt dil seçici — açılış/rıza/welcome ekranlarının altına konur. Kullanıcı
/// diller arasında geçiş yapabilir; seçince dil kaydedilir ve uygulama yeniden
/// başlar (tüm metinler yeni dilde değerlensin). Desteklenen diller sunucudan;
/// yüklenene kadar tr+en.
class LanguageQuickPick extends ConsumerWidget {
  const LanguageQuickPick({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // localeController async çözülürken 'tr' fallback'ine düşüp TR→EN flaşı
    // yaratmasın: I18n.instance.locale (önyüklemede zaten doğru dile set edildi).
    final current =
        ref.watch(localeControllerProvider).asData?.value ?? I18n.instance.locale;
    final langs = ref.watch(supportedLocalesProvider).asData?.value ??
        const [
          SupportedLocale(code: 'tr', nativeName: 'Türkçe', englishName: 'Turkish'),
          SupportedLocale(
              code: 'en', nativeName: 'English', englishName: 'English'),
        ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final l in langs)
          _LangPill(
            flag: _flags[l.code] ?? '🌐',
            name: l.nativeName,
            selected: current == l.code,
            onTap: () async {
              if (current == l.code) return;
              await ref
                  .read(localeControllerProvider.notifier)
                  .setLocale(l.code);
              if (context.mounted) RestartWidget.restartApp(context);
            },
          ),
      ],
    );
  }
}

class _LangPill extends StatelessWidget {
  final String flag;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _LangPill({
    required this.flag,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.coral.withValues(alpha: 0.14)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.coral : AppColors.line,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(flag, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 7),
              Text(
                name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? AppColors.coral : AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

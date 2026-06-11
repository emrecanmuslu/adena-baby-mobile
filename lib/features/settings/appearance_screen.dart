import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';
import 'locale_controller.dart';
import 'theme_controller.dart';

/// Görünüm (design 28 · ScrAppearance): tema seçimi + birimler (aile geneli)
/// tek sayfada. Eski ayrı "Görünüm" (tema picker) ve "Birimler" sayfaları birleşti.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider).asData?.value ?? ThemeMode.system;
    final locale = ref.watch(localeControllerProvider).asData?.value ?? 'tr';
    final baby = ref.watch(activeBabyProvider);
    final units = ref.watch(activeUnitsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Görünüm')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          adSec(tr('Tema')),
          Row(
            children: [
              _ThemeCard(
                  label: tr('Açık'),
                  mode: ThemeMode.light,
                  selected: mode == ThemeMode.light,
                  onTap: () => ref.read(themeControllerProvider.notifier).setMode(ThemeMode.light)),
              const SizedBox(width: 10),
              _ThemeCard(
                  label: tr('Gece'),
                  mode: ThemeMode.dark,
                  selected: mode == ThemeMode.dark,
                  onTap: () => ref.read(themeControllerProvider.notifier).setMode(ThemeMode.dark)),
              const SizedBox(width: 10),
              _ThemeCard(
                  label: tr('Otomatik'),
                  mode: ThemeMode.system,
                  selected: mode == ThemeMode.system,
                  onTap: () => ref.read(themeControllerProvider.notifier).setMode(ThemeMode.system)),
            ],
          ),
          const SizedBox(height: 10),
          _Note(tr('Gece beslemesi için Gece teması düşük parlaklık ve daha büyük '
              'dokunma hedefleri kullanır. Otomatik, cihazının ayarını izler.')),
          adSec(tr('Dil')),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.softShadow,
            ),
            child: Column(
              children: [
                _LangRow(
                    flag: '🇹🇷',
                    name: 'Türkçe',
                    selected: locale == 'tr',
                    onTap: () => ref.read(localeControllerProvider.notifier).setLocale('tr')),
                _LangRow(
                    flag: '🇬🇧',
                    name: 'English',
                    selected: locale == 'en',
                    onTap: () => ref.read(localeControllerProvider.notifier).setLocale('en'),
                    last: true),
              ],
            ),
          ),
          if (baby != null) ...[
            adSec(tr('Birimler (aile geneli)')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.softShadow,
              ),
              child: Column(
                children: [
                  _UnitRow(
                    title: tr('Hacim'),
                    subtitle: tr('Beslenme & süt sağma'),
                    options: const {'ml': 'ml', 'oz': 'oz'},
                    selected: units.volume,
                    onSelected: (v) => updateUnits(ref, baby.id, units.copyWith(volume: v)),
                  ),
                  _UnitRow(
                    title: tr('Ağırlık'),
                    subtitle: tr('Bebek kilosu'),
                    options: const {'kg': 'kg', 'lb': 'lb'},
                    selected: units.weight,
                    onSelected: (v) => updateUnits(ref, baby.id, units.copyWith(weight: v)),
                  ),
                  _UnitRow(
                    title: tr('Uzunluk'),
                    subtitle: tr('Boy & baş çevresi'),
                    options: const {'cm': 'cm', 'in': 'in'},
                    selected: units.length,
                    onSelected: (v) => updateUnits(ref, baby.id, units.copyWith(length: v)),
                  ),
                  _UnitRow(
                    title: tr('Ateş'),
                    subtitle: tr('Yeni kayıtlarda varsayılan'),
                    options: const {'C': '°C', 'F': '°F'},
                    selected: units.temp,
                    onSelected: (v) => updateUnits(ref, baby.id, units.copyWith(temp: v)),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Note(tr('Mevcut kayıtlar otomatik olarak seçtiğin birime çevrilerek gösterilir.')),
          ],
        ],
      ),
    );
  }
}

/// Tema önizleme kartı (design .ad-pricecard): renk önizlemesi + ad; seçili coral çerçeve.
class _ThemeCard extends StatelessWidget {
  final String label;
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeCard(
      {required this.label,
      required this.mode,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? AppColors.coral : AppColors.line,
                  width: selected ? 2 : 1),
              boxShadow: selected ? null : AppColors.softShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: _preview(mode),
                    border: Border.all(color: AppColors.line, width: 1),
                  ),
                ),
                const SizedBox(height: 8),
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: selected ? AppColors.coralDd : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static LinearGradient _preview(ThemeMode m) => switch (m) {
        ThemeMode.light => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8F4), Color(0xFFFFE0D2)]),
        ThemeMode.dark => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF251D2E), Color(0xFF191320)]),
        ThemeMode.system => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [0.5, 0.5],
            colors: [Color(0xFFFFF8F4), Color(0xFF251D2E)]),
      };
}

/// .ad-setting satırı: başlık/alt başlık + .ad-sides ikili birim seçimi.
class _UnitRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool last;

  const _UnitRow({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 132,
            child: AdSides(
              selected: selected,
              onSelect: onSelected,
              items: [
                for (final e in options.entries) (key: e.key, label: e.value, small: null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dil seçim satırı: bayrak + ad + seçiliyse check. Dil adları çevrilmez.
class _LangRow extends StatelessWidget {
  final String flag;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final bool last;
  const _LangRow({
    required this.flag,
    required this.name,
    required this.selected,
    required this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: AppColors.line, width: 1)),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: AppColors.coral, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text,
          style: TextStyle(
              color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

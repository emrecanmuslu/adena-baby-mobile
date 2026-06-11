import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/subscription_repository.dart';
import '../babies/baby_controller.dart';

/// AI Veri Dışa Aktarımı (design ScrAIExport): dönem seç + özet üret + paylaş.
/// Premium özelliği — değilse upsell gösterir.
class AIExportScreen extends ConsumerStatefulWidget {
  const AIExportScreen({super.key});

  @override
  ConsumerState<AIExportScreen> createState() => _AIExportScreenState();
}

class _AIExportScreenState extends ConsumerState<AIExportScreen> {
  int _days = 3;
  String? _summary;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final isPremium =
        ref.watch(subscriptionProvider).asData?.value.isPremium ?? false;
    final baby = ref.watch(activeBabyProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('AI Veri Dışa Aktarımı')),
      ),
      body: baby == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.coral))
          : !isPremium
              ? const _Upsell()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    Row(
                      children: [
                        AdIconChip('ai',
                            color: AppColors.med, bg: AppColors.medBg, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              tr('Doktora ya da yapay zekâya hazır, düzenli bir özet oluştur.'),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.muted)),
                        ),
                      ],
                    ),
                    adSec(tr('Dönem seç')),
                    AdSides(
                      items: [
                        (key: '1', label: tr('1 gün'), small: null),
                        (key: '3', label: tr('3 gün'), small: null),
                        (key: '7', label: tr('7 gün'), small: null),
                      ],
                      selected: '$_days',
                      onSelect: (k) => setState(() {
                        _days = int.parse(k);
                        _summary = null; // dönem değişti → eski özeti temizle
                      }),
                    ),
                    adSec(tr('Önizleme')),
                    _PreviewCard(summary: _summary, loading: _loading),
                    const SizedBox(height: 14),
                    if (_summary == null)
                      AdSaveButton(
                        label: _loading ? tr('Oluşturuluyor…') : tr('Özeti oluştur'),
                        color: AppColors.coral,
                        onTap: _loading ? () {} : () => _generate(baby.id),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: AdSaveButton(
                              label: tr('Kopyala'),
                              color: AppColors.coralDd,
                              ghost: true,
                              onTap: _copy,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AdSaveButton(
                              label: tr('Paylaş'),
                              color: AppColors.coral,
                              onTap: _share,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 14),
                    const Center(child: _PremiumPill()),
                  ],
                ),
    );
  }

  Future<void> _generate(String babyId) async {
    setState(() => _loading = true);
    try {
      final text = await ref.read(subscriptionRepositoryProvider).aiExport(babyId, _days);
      if (mounted) setState(() => _summary = text);
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy() {
    final s = _summary;
    if (s == null) return;
    Clipboard.setData(ClipboardData(text: s));
    showAdToast(context, tr('Özet kopyalandı'));
  }

  Future<void> _share() async {
    final s = _summary;
    if (s == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/adena-ozet-$_days-gun.txt');
      await file.writeAsString(s);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: trp('Adena Baby · son {n} günün özeti', {'n': _days}),
          text: s,
        ),
      );
    } catch (_) {
      if (mounted) showAdToast(context, tr('Paylaşılamadı'));
    }
  }
}

/// Önizleme kartı — monospace özet ya da placeholder/yükleme.
class _PreviewCard extends StatelessWidget {
  final String? summary;
  final bool loading;
  const _PreviewCard({required this.summary, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: AppColors.coral),
              ),
            )
          : Text(
              summary ?? tr('Dönem seçip "Özeti oluştur"a dokun — özet burada görünecek.'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.7,
                fontWeight: FontWeight.w600,
                color: summary == null ? AppColors.muted : AppColors.ink2,
              ),
            ),
    );
  }
}

/// Premium olmayan kullanıcıya yükseltme kartı.
class _Upsell extends StatelessWidget {
  const _Upsell();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                    colors: [AppColors.premiumGoldLight, AppColors.premiumGold]),
              ),
              alignment: Alignment.center,
              child: const AdenaIcon('star', size: 32, color: Colors.white, sw: 2.2),
            ),
            const SizedBox(height: 14),
            Text(tr('AI özeti Premium özelliği'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
                tr('Doktora hazır 1/3/7 günlük özetler oluşturmak için Premium’a geç.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
            const SizedBox(height: 18),
            AdSaveButton(
              label: tr('Premium’a geç'),
              color: AppColors.coral,
              onTap: () => context.push('/premium'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumPill extends StatelessWidget {
  const _PremiumPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
            colors: [AppColors.premiumGoldLight, AppColors.premiumGold]),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdenaIcon('star', size: 11, color: AppColors.premiumInk, sw: 2.4),
          const SizedBox(width: 5),
          Text(tr('Premium özelliği'),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.premiumInk)),
        ],
      ),
    );
  }
}

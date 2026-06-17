import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/migration_service.dart';

/// free→premium yükleme sürecini gösteren tam-ekran overlay. Kök Stack'e
/// (MaterialApp.builder) bağlanır; migrasyon çalışırken/biterken görünür.
/// Kullanıcı her adımın yüklendiğini ve verisinin buluta alındığını görür.
class MigrationOverlay extends ConsumerWidget {
  const MigrationOverlay({super.key});

  String _label(String key) => switch (key) {
        'babies' => tr('Bebek profilleri'),
        'records' => tr('Kayıtlar (uyku, beslenme, bez…)'),
        'memories' => tr('Anılar ve fotoğraflar'),
        'mom' => tr('Anne takibi'),
        'cycle' => tr('Adet takvimi'),
        _ => key,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(migrationControllerProvider);
    if (st.phase == MigrationPhase.idle) return const SizedBox.shrink();
    final done = st.phase == MigrationPhase.done;

    // Migrasyon sırasında geri tuşunu engelle (yarıda bırakılmasın).
    return PopScope(
      canPop: false,
      child: Material(
        color: AppColors.cream,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandEmblem()),
                    const SizedBox(height: 20),
                    Text(
                      done
                          ? tr('Yedekleme tamamlandı 🎉')
                          : tr('Verilerin buluta yedekleniyor'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      done
                          ? tr('Artık verilerin güvende — her cihazdan erişebilir, '
                              'ailenle paylaşabilirsin.')
                          : tr('Telefonundaki kayıtlar buluta taşınıyor. Lütfen '
                              'uygulamayı kapatma; bu işlem yalnız bir kez yapılır.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 22),
                    // İlerleme çubuğu.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: done ? 1 : (st.progress.clamp(0.04, 1)),
                        minHeight: 8,
                        backgroundColor: AppColors.coral.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(AppColors.coral),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: AppColors.softShadow,
                      ),
                      child: Column(
                        children: [
                          for (final s in st.steps)
                            _StepRow(label: _label(s.key), step: s),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (done)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.coral,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => ref
                            .read(migrationControllerProvider.notifier)
                            .dismiss(),
                        child: Text(tr('Harika!'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final MigrationStep step;
  const _StepRow({required this.label, required this.step});

  @override
  Widget build(BuildContext context) {
    final Widget leading = switch (step.status) {
      StepStatus.done => Icon(Icons.check_circle_rounded,
          color: AppColors.coral, size: 22),
      StepStatus.active => SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2.4, color: AppColors.coral)),
      StepStatus.pending => Icon(Icons.radio_button_unchecked_rounded,
          color: AppColors.muted.withValues(alpha: 0.4), size: 22),
    };
    final faded = step.status == StepStatus.pending;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: faded ? AppColors.muted : AppColors.ink),
            ),
          ),
          if (step.count > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${step.count}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.coral)),
            ),
        ],
      ),
    );
  }
}

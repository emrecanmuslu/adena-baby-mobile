import 'package:flutter/material.dart';

import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'onboarding_kit.dart';

/// "Kayıtlarını hesabına aktaralım mı?" alt sayfası (tasarım [11]) — misafir
/// veri girmişse, giriş/kayıt sonrası bir kez. Kapatılamaz: kullanıcı ya aktarır
/// ya da (onaylayarak) siler. Aktarım yereldir ve hızlıdır → belirsiz gösterge.
/// Dönüş: işlem tamamlandı mı (false → istemsiz kapanma; sonra tekrar sorulur).
Future<bool> showGuestMigrationSheet(
  BuildContext context, {
  required String body,
  required String deleteBody,
  required Future<void> Function() onMigrate,
  required Future<void> Function() onDiscard,
}) async {
  final done = await showOnbSheet<bool>(
    context,
    dismissible: false,
    builder: (_) => _MigrationFlow(
        body: body, deleteBody: deleteBody, onMigrate: onMigrate, onDiscard: onDiscard),
  );
  return done == true;
}

enum _Step { ask, confirmDelete, progress, done }

class _MigrationFlow extends StatefulWidget {
  final String body;
  final String deleteBody;
  final Future<void> Function() onMigrate;
  final Future<void> Function() onDiscard;
  const _MigrationFlow({
    required this.body,
    required this.deleteBody,
    required this.onMigrate,
    required this.onDiscard,
  });

  @override
  State<_MigrationFlow> createState() => _MigrationFlowState();
}

class _MigrationFlowState extends State<_MigrationFlow> {
  _Step _step = _Step.ask;
  bool _deleting = false;

  Future<void> _migrate() async {
    setState(() => _step = _Step.progress);
    await widget.onMigrate();
    if (mounted) setState(() => _step = _Step.done);
  }

  Future<void> _discard() async {
    setState(() => _deleting = true);
    await widget.onDiscard();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final a = OnbAccent.coral(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    const title = TextStyle(
        fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.2);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      alignment: Alignment.topCenter,
      child: switch (_step) {
        _Step.ask => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: a.grad,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const AdenaIcon('cloud', size: 28, color: Colors.white, sw: 1.9),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Kayıtlarını hesabına aktaralım mı?'), style: title),
              const SizedBox(height: 8),
              Text(widget.body, style: onbSubStyle()),
              const SizedBox(height: 22),
              OnbPrimaryButton(
                  label: tr('Hesabıma aktar'), accent: a, onTap: _migrate),
              const SizedBox(height: 4),
              OnbTextButton(
                label: tr('Aktarma, sil'),
                color: AppColors.coralDd,
                onTap: () => setState(() => _step = _Step.confirmDelete),
              ),
            ],
          ),
        _Step.confirmDelete => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Misafir verileri silinsin mi?'), style: title),
              const SizedBox(height: 8),
              Text(widget.deleteBody, style: onbSubStyle()),
              const SizedBox(height: 22),
              OnbPrimaryButton(
                label: tr('Sil'),
                accent: a,
                loading: _deleting,
                onTap: _discard,
              ),
              const SizedBox(height: 4),
              OnbTextButton(
                label: tr('Vazgeç'),
                onTap: _deleting ? null : () => setState(() => _step = _Step.ask),
              ),
            ],
          ),
        _Step.progress => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Aktarılıyor…'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  color: a.c,
                  backgroundColor: dark
                      ? Colors.white.withValues(alpha: 0.07)
                      : AppColors.ink.withValues(alpha: 0.06),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Uygulamayı kapatma; birkaç saniye sürer.'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted)),
              const SizedBox(height: 20),
            ],
          ),
        _Step.done => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: dark
                        ? OnbAccent.sage.withValues(alpha: 0.18)
                        : AppColors.sageBg,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const AdenaIcon('check',
                      size: 34, color: OnbAccent.sage, sw: 2.6),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Hepsi hesabında ✓'),
                  textAlign: TextAlign.center, style: title),
              const SizedBox(height: 22),
              OnbPrimaryButton(
                  label: tr('Tamam'),
                  accent: a,
                  onTap: () => Navigator.pop(context, true)),
            ],
          ),
      },
    );
  }
}

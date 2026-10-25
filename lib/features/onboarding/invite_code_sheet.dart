import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../data/baby_repository.dart';
import '../../models/baby.dart';
import 'onboarding_kit.dart';

/// Davet kodu uzunluğu — backend `secrets.token_hex(4).upper()` (8 hex karakter).
const inviteCodeLength = 8;

/// "Davet kodunu gir" alt sayfası (tasarım [8]). Kod geçerliyse katılınan
/// bebeği döndürür; hata sayfa içinde gösterilir (sayfa açık kalır).
Future<Baby?> showInviteCodeSheet(BuildContext context) =>
    showOnbSheet<Baby>(context, builder: (_) => const _InviteCodeForm());

class _InviteCodeForm extends ConsumerStatefulWidget {
  const _InviteCodeForm();

  @override
  ConsumerState<_InviteCodeForm> createState() => _InviteCodeFormState();
}

class _InviteCodeFormState extends ConsumerState<_InviteCodeForm> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      if (mounted) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final baby =
          await ref.read(babyRepositoryProvider).acceptInvitation(_ctrl.text.trim());
      if (mounted) Navigator.pop(context, baby);
    } catch (e) {
      if (!mounted) return;
      final full = e is DioException && e.response?.statusCode == 409;
      setState(() {
        _busy = false;
        _error = full
            ? tr('Bu aile dolu — en fazla 5 üye olabilir')
            : tr('Bu kod geçersiz ya da süresi dolmuş');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = OnbAccent.coral(context);
    final code = _ctrl.text;
    final complete = code.length == inviteCodeLength;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('Davet kodunu gir'),
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text(
            tr('Eşin veya bakıcın bebeği zaten eklediyse, paylaştığı kodla katıl.'),
            style: onbSubStyle()),
        const SizedBox(height: 20),
        OnbCodeInput(
          controller: _ctrl,
          length: inviteCodeLength,
          accent: a,
          error: _error != null,
          autofocus: true,
          onSubmitted: (_) => complete && !_busy ? _join() : null,
        ),
        if (_error != null) OnbFieldError(_error!),
        const SizedBox(height: 20),
        OnbPrimaryButton(
          label: tr('Katıl'),
          accent: a,
          loading: _busy,
          onTap: complete ? _join : null,
        ),
      ],
    );
  }
}

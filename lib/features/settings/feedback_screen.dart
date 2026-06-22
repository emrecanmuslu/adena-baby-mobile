import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/auth_repository.dart';

/// Geri bildirim: kullanıcı bir özellik isteği, sorun/şikayet veya genel görüş
/// gönderir (POST /auth/feedback). Admin'den okunur + destek adresine e-posta gider.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  String _category = 'feature';
  bool _sending = false;

  // (anahtar, etiket, ikon) — anahtar backend ile birebir.
  List<(String, String, IconData)> get _cats => [
        ('feature', tr('Özellik isteği'), Icons.lightbulb_outline_rounded),
        ('bug', tr('Sorun bildir'), Icons.bug_report_outlined),
        ('other', tr('Diğer'), Icons.chat_bubble_outline_rounded),
      ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await ref.read(authRepositoryProvider).submitFeedback(
            category: _category,
            message: _message.text.trim(),
          );
      if (!mounted) return;
      showAdToast(context, tr('Teşekkürler! Geri bildirimin bize ulaştı 💛'));
      context.pop();
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Geri Bildirim')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Bir özellik mi istiyorsun, bir sorun mu var? Görüşün '
                      'uygulamayı senin için daha iyi yapmamıza yardım eder.'),
                  style: TextStyle(
                      fontSize: 13.5, height: 1.5, color: AppColors.muted,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                AdField(
                  label: tr('Konu'),
                  info: tr('Özellik isteği: yeni bir özellik öner. '
                      'Sorun bildir: bir hata/şikayet ilet. Diğer: genel görüş.'),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final (key, label, icon) in _cats)
                        _CatChip(
                          label: label,
                          icon: icon,
                          selected: _category == key,
                          onTap: () => setState(() => _category = key),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                AdField(
                  label: tr('Mesajın'),
                  child: TextFormField(
                    controller: _message,
                    minLines: 5,
                    maxLines: 8,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: tr('Bize iletmek istediğini yaz…'),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      contentPadding: const EdgeInsets.all(14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.line, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().length < 5)
                        ? tr('Lütfen biraz daha ayrıntı yaz')
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                _sending
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: AppColors.coral)),
                        ),
                      )
                    : AdSaveButton(
                        label: tr('Gönder'),
                        color: AppColors.coral,
                        onTap: _submit,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.coral : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppColors.coral : AppColors.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 17, color: selected ? Colors.white : AppColors.muted),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: selected ? Colors.white : AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

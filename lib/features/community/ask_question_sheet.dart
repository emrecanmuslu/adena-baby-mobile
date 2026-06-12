import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/community_repository.dart';
import '../../data/content_repository.dart';

/// Soru sor sheet'ini açar — başarıyla oluşturulursa yeni soru id'sini döndürür.
Future<String?> showAskQuestionSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _AskQuestionSheet(ref: ref),
  );
}

class _AskQuestionSheet extends StatefulWidget {
  final WidgetRef ref;
  const _AskQuestionSheet({required this.ref});

  @override
  State<_AskQuestionSheet> createState() => _AskQuestionSheetState();
}

class _AskQuestionSheetState extends State<_AskQuestionSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _category;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showAdError(context, tr('Lütfen bir soru başlığı yaz.'));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await widget.ref.read(communityRepositoryProvider).createQuestion(
            title: title,
            body: _body.text.trim(),
            category: _category,
          );
      if (mounted) {
        Navigator.pop(context, id);
        showAdToast(context, tr('Sorun paylaşıldı 💬'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.ref.watch(contentCategoriesProvider).asData?.value ?? const [];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: adGrabHandle()),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 14),
                child: Text(tr('Soru sor'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              AdField(
                label: tr('Sorun'),
                info: tr('Net ve kısa bir başlık yaz. Örn. "6 aylık bebek gece '
                    'sık uyanıyor, ne önerirsiniz?"'),
                child: AdInput(
                  controller: _title,
                  hint: tr('Sorunu buraya yaz'),
                  capitalization: TextCapitalization.sentences,
                ),
              ),
              AdField(
                label: tr('Detay'),
                info: tr('İstersen durumu biraz aç — yaş, ne denedin, neyi merak '
                    'ediyorsun. İsteğe bağlı.'),
                child: AdInput(
                  controller: _body,
                  hint: tr('isteğe bağlı'),
                  capitalization: TextCapitalization.sentences,
                ),
              ),
              AdField(
                label: tr('Kategori'),
                info: tr('Sorunu bir konuya bağla — doğru kişilere ulaşsın. '
                    'İsteğe bağlı.'),
                child: SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip(null, tr('Genel')),
                      for (final c in cats) _chip(c.slug, c.name),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              AdSaveButton(
                label: _saving ? tr('Paylaşılıyor…') : tr('Paylaş'),
                color: AppColors.coral,
                onTap: _saving ? () {} : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String? slug, String label) {
    final sel = _category == slug;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _category = slug),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: sel ? AppColors.feedBg : fieldBg(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: sel ? AppColors.coral : AppColors.line, width: 1.5),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: sel ? AppColors.coralDd : null)),
        ),
      ),
    );
  }
}

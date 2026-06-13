import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/memory_repository.dart';
import '../../models/memory.dart';
import '../babies/baby_controller.dart';

/// Anılar / Fotoğraf günlüğü — fotoğraf-odaklı akış (scrapbook); aylara gruplu,
/// büyük foto kartları + "ilk" kilometre taşı rozetleri. Fotoğraflar her zaman
/// buluta yedeklenir (herkese).
class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final async = ref.watch(memoriesProvider(baby.id));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(tr('Anılar')),
            const SizedBox(width: 8),
            AdInfoDot(
              title: tr('Anılar / Fotoğraf günlüğü'),
              body: tr('Bebeğinin özel anlarını fotoğrafla sakla. İlk gülümseme, '
                  'ilk diş, ilk adım gibi "ilk"leri etiketleyebilirsin. Anılar '
                  'aileyle paylaşılır — herkes ekleyebilir, görebilir.'),
              size: 16,
            ),
          ],
        ),
      ),
      // Anı ekleme yalnız owner/parent — bakıcı yalnız görüntüler.
      floatingActionButton: baby.canFullWrite
          ? FloatingActionButton.extended(
              onPressed: () => showAddMemorySheet(context, ref, baby.id),
              backgroundColor: AppColors.coral,
              foregroundColor: Colors.white,
              icon: const AdenaIcon('plus', size: 20, color: Colors.white, sw: 2.4),
              label: Text(tr('Anı ekle'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            )
          : null,
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            for (var i = 0; i < 3; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Skeleton(height: 280, radius: 20),
              ),
          ],
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(apiErrorText(e),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
          ),
        ),
        data: (items) {
          if (items.isEmpty) return const _Empty();
          // Aylara grupla (en yeni önce; liste zaten sunucu sıralı).
          final groups = <String, List<Memory>>{};
          for (final m in items) {
            final key = DateFormat('MMMM y', 'tr_TR').format(m.date);
            (groups[key] ??= []).add(m);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 100 + MediaQuery.of(context).padding.bottom),
            children: [
              const _CloudChip(),
              for (final entry in groups.entries) ...[
                _MonthHeader(entry.key),
                for (final m in entry.value)
                  _MemoryCard(
                    memory: m,
                    onTap: () => _showMemoryDetail(
                        context, ref, baby.id, m, baby.canFullWrite),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Büyük foto-odaklı anı kartı (scrapbook akışı): foto + üstte "ilk" rozeti +
/// altında başlık/tarih/not önizleme.
class _MemoryCard extends StatelessWidget {
  final Memory memory;
  final VoidCallback onTap;
  const _MemoryCard({required this.memory, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = firstTagInfo(memory.firstTag);
    final hasPhoto = memory.photo != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPhoto)
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.network(memory.photo!,
                          fit: BoxFit.cover,
                          // Ham foto 3000px+ olabilir; decode'u ekran genişliğine
                          // sınırla (bellek/OOM koruması).
                          cacheWidth: 1080,
                          errorBuilder: (_, _, _) => const _PhotoPlaceholder()),
                    ),
                    if (info != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _MilestonePill(
                            emoji: info.emoji, label: info.label(), onPhoto: true),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fotosuz anılarda rozet başlığın üstünde durur.
                    if (!hasPhoto && info != null) ...[
                      _MilestonePill(emoji: info.emoji, label: info.label()),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      memory.title.isNotEmpty
                          ? memory.title
                          : (info?.label() ?? tr('Anı')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AdenaIcon('calendar', size: 13, color: AppColors.muted),
                        const SizedBox(width: 5),
                        Text(DateFormat('d MMMM y', 'tr_TR').format(memory.date),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted)),
                      ],
                    ),
                    if (memory.note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(memory.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "İlk" kilometre taşı rozeti — foto üstünde koyu yarı saydam, metin alanında
/// şeftali tonlu.
class _MilestonePill extends StatelessWidget {
  final String emoji;
  final String label;
  final bool onPhoto;
  const _MilestonePill(
      {required this.emoji, required this.label, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onPhoto ? Colors.black.withValues(alpha: 0.5) : AppColors.feedBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$emoji $label',
          style: TextStyle(
              color: onPhoto ? Colors.white : AppColors.coralDd,
              fontSize: 11,
              fontWeight: FontWeight.w900)),
    );
  }
}

/// Bulut yedek ibaresi — herkeste her zaman açık (premium/free ayrımı yok).
class _CloudChip extends StatelessWidget {
  const _CloudChip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.growthBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('☁️', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Text(tr('Anıların buluta yedekleniyor'),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF349970))),
          ],
        ),
      ),
    );
  }
}

/// Ay başlığı — başlık + ince ayraç çizgisi.
class _MonthHeader extends StatelessWidget {
  final String label;
  const _MonthHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 12),
      child: Row(
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.coralDd,
                  letterSpacing: 0.6)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1.5, color: AppColors.line)),
        ],
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.feedBg,
      alignment: Alignment.center,
      child: const AdenaIcon('camera', size: 30, color: AppColors.coralDd),
    );
  }
}

/// Boş durum — ilk anıyı eklemeye davet.
class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📸', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(tr('Henüz anı yok'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              tr('İlk gülümseme, ilk diş, ilk adım… özel anları fotoğrafla sakla.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anı detay sheet'i — büyük foto + başlık + not + tarih + Sil.
void _showMemoryDetail(BuildContext context, WidgetRef ref, String babyId,
    Memory m, bool canFullWrite) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (sheetCtx) {
      final info = firstTagInfo(m.firstTag);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: adGrabHandle()),
              if (m.photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(m.photo!,
                      fit: BoxFit.cover,
                      cacheWidth: 1080,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              const SizedBox(height: 14),
              if (info != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${info.emoji} ${info.label()}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.coralDd)),
                ),
              Text(m.title.isNotEmpty ? m.title : tr('Anı'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(DateFormat('d MMMM y', 'tr_TR').format(m.date),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
              if (m.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(m.note,
                    style: const TextStyle(
                        fontSize: 14, height: 1.45, fontWeight: FontWeight.w600)),
              ],
              // Silme yalnız owner/parent — bakıcıya gösterilmez.
              if (canFullWrite) ...[
                const SizedBox(height: 18),
                AdSaveButton(
                  label: tr('Anıyı sil'),
                  color: AppColors.fever,
                  ghost: true,
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    try {
                      await ref.read(memoryRepositoryProvider).delete(babyId, m.id);
                      ref.invalidate(memoriesProvider(babyId));
                      if (context.mounted) showAdToast(context, tr('Anı silindi'));
                    } catch (e) {
                      if (context.mounted) showAdError(context, apiErrorText(e));
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Anı ekleme sheet'ini açar.
Future<void> showAddMemorySheet(
    BuildContext context, WidgetRef ref, String babyId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _AddMemorySheet(babyId: babyId, ref: ref),
  );
}

class _AddMemorySheet extends StatefulWidget {
  final String babyId;
  final WidgetRef ref;
  const _AddMemorySheet({required this.babyId, required this.ref});

  @override
  State<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends State<_AddMemorySheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  String? _photoPath;
  String _firstTag = '';
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (x != null) setState(() => _photoPath = x.path);
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  /// Kamera / galeri kaynağı seçtiren küçük sheet.
  void _choosePhotoSource() {
    showModalBottomSheet(
      context: context,
      shape: adSheetShape,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: adGrabHandle()),
            ListTile(
              leading: const AdenaIcon('camera', size: 22, color: AppColors.coralDd),
              title: Text(tr('Kamera'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const AdenaIcon('charts', size: 22, color: AppColors.pump),
              title: Text(tr('Galeri'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: tr('Anının tarihi'),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.ref.read(memoryRepositoryProvider).create(
            widget.babyId,
            date: _date,
            title: _title.text.trim(),
            note: _note.text.trim(),
            firstTag: _firstTag,
            photoPath: _photoPath,
          );
      widget.ref.invalidate(memoriesProvider(widget.babyId));
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Anı eklendi 📸'));
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
                child: Text(tr('Anı ekle'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              // Foto seçici
              GestureDetector(
                onTap: _choosePhotoSource,
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fieldBg(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _photoPath != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(_photoPath!), fit: BoxFit.cover),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(tr('Değiştir'),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const AdenaIcon('camera',
                                  size: 34, color: AppColors.coralDd),
                              const SizedBox(height: 8),
                              Text(tr('Fotoğraf ekle'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink2)),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AdField(
                label: tr('Başlık'),
                info: tr('Anıya kısa bir ad ver (isteğe bağlı). Örn. "Parkta ilk gün".'),
                child: AdInput(
                  controller: _title,
                  hint: tr('örn. Parkta ilk gün'),
                  capitalization: TextCapitalization.sentences,
                ),
              ),
              AdField(
                label: tr('"İlk" mi?'),
                info: tr('Bu bir kilometre taşıysa etiketle (ilk gülümseme, ilk diş…). '
                    'Değilse "Düz anı" bırak.'),
                child: _firstTagPicker(),
              ),
              AdField(
                label: tr('Tarih'),
                child: _dateRow(),
              ),
              AdField(
                label: tr('Not'),
                info: tr('Anıyla ilgili birkaç söz (isteğe bağlı).'),
                child: AdInput(
                  controller: _note,
                  hint: tr('isteğe bağlı'),
                  capitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(height: 6),
              AdSaveButton(
                label: _saving ? tr('Kaydediliyor…') : tr('Kaydet'),
                color: AppColors.coral,
                onTap: _saving ? () {} : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "İlk" etiketi seçici — yatay kaydırmalı çipler ("Düz anı" + katalog).
  Widget _firstTagPicker() {
    Widget chip(String key, String label) {
      final selected = _firstTag == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _firstTag = key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.feedBg : fieldBg(context),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: selected ? AppColors.coral : AppColors.line, width: 1.5),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? AppColors.coralDd : null)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('', tr('Düz anı')),
          for (final t in kFirstTags) chip(t.key, '${t.emoji} ${t.label()}'),
        ],
      ),
    );
  }

  Widget _dateRow() => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
                color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                AdenaIcon('calendar', size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                Text(DateFormat('d MMMM y', 'tr_TR').format(_date),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink2)),
                const Spacer(),
                Text(tr('değiştir'),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.coralDark)),
              ],
            ),
          ),
        ),
      );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/memory_repository.dart';
import '../../models/memory.dart';
import '../babies/baby_controller.dart';

/// Anı fotoğrafını gösterir — local-first: yerel dosya yolu (free, henüz
/// yüklenmemiş) ise Image.file, sunucu URL'i (premium) ise Image.network.
Widget _memoryPhoto(String path,
    {required int cacheWidth, required Widget error}) {
  Widget eb(BuildContext _, Object _, StackTrace? _) => error;
  return path.startsWith('http')
      ? Image.network(path,
          fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: eb)
      : Image.file(File(path),
          fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: eb);
}

/// Anılar / Fotoğraf günlüğü — galeri ızgarası (3 sütun kare); aylara gruplu,
/// "ilk" kilometre taşı rozetleri. Karaya dokununca detay sheet'i açılır.
/// Local-first: foto free'de telefonda; premium'da buluta yedeklenir.
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
            final key = fmtMonthYear(m.date);
            (groups[key] ??= []).add(m);
          }
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _CloudChip(),
                ),
              ),
              for (final entry in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _MonthHeader(entry.key),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final m = entry.value[i];
                        return _MemoryTile(
                          memory: m,
                          onTap: () => _showMemoryDetail(
                              context, ref, baby.id, m, baby.canFullWrite),
                        );
                      },
                      childCount: entry.value.length,
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(
                    height: 100 + MediaQuery.of(context).padding.bottom),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Galeri ızgarası karesi — foto kapak + (varsa) "ilk" rozeti (emoji) + fotolu
/// olanlarda altta başlık gradyanı. Dokununca detay sheet'i açılır.
class _MemoryTile extends StatelessWidget {
  final Memory memory;
  final VoidCallback onTap;
  const _MemoryTile({required this.memory, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = firstTagInfo(memory.firstTag);
    final hasPhoto = memory.photo != null;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              // Izgara karesi küçük; decode'u sınırla (bellek koruması).
              _memoryPhoto(memory.photo!,
                  cacheWidth: 600, error: const _PhotoPlaceholder())
            else
              Container(
                color: AppColors.feedBg,
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(info?.emoji ?? '📝', style: const TextStyle(fontSize: 26)),
                    const SizedBox(height: 6),
                    Text(
                      memory.title.isNotEmpty
                          ? memory.title
                          : (info?.label() ?? tr('Anı')),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            // "ilk" rozeti — sol üst, emoji
            if (info != null)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Text(info.emoji, style: const TextStyle(fontSize: 12)),
                ),
              ),
            // başlık gradyanı (fotolu + başlıklı)
            if (hasPhoto && memory.title.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent
                      ],
                    ),
                  ),
                  child: Text(memory.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
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

/// Boş durum — ilk anıyı eklemeye davet (sıcak, davetkâr tasarım).
class _Empty extends StatelessWidget {
  const _Empty();

  // Ne tür "ilk"ler eklenebileceğini gösteren önizleme çipleri.
  static const _firsts = [
    ('😊', 'İlk gülümseme'),
    ('🦷', 'İlk diş'),
    ('👣', 'İlk adım'),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Yumuşak gradyan kapsül içinde kamera — görsel odak.
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.peachLight, AppColors.peach],
                ),
                boxShadow: AppColors.smallShadow,
              ),
              child: const Center(
                child: Text('📸', style: TextStyle(fontSize: 54)),
              ),
            ),
            const SizedBox(height: 22),
            Text(tr('İlk anını ekle'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(
              tr('Büyürken kaçırmak istemeyeceğin anları burada sakla — '
                  'bir fotoğraf çek, etiketle, yıllar sonra yeniden yaşa.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  height: 1.45),
            ),
            const SizedBox(height: 22),
            // "İlk"ler önizleme çipleri.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final (emoji, label) in _firsts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.peachLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$emoji  ${tr(label)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.coralDd)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              tr('Başlamak için sağ alttaki + düğmesine dokun'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted2),
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
                  child: _memoryPhoto(m.photo!,
                      cacheWidth: 1080, error: const SizedBox.shrink()),
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
              Text(fmtDayMonthYear(m.date),
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
                    // Anılar (fotoğraflar) geri alınamaz → silmeden önce onay.
                    final ok = await showDialog<bool>(
                      context: sheetCtx,
                      builder: (dctx) => AlertDialog(
                        title: Text(tr('Anıyı sil')),
                        content: Text(tr(
                            'Bu anı ve fotoğrafı kalıcı olarak silinecek. Bu geri alınamaz.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: Text(tr('Vazgeç'))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.fever),
                            onPressed: () => Navigator.pop(dctx, true),
                            child: Text(tr('Sil')),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
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
                child: AdInput(
                  controller: _title,
                  hint: tr('örn. Parkta ilk gün'),
                  capitalization: TextCapitalization.sentences,
                ),
              ),
              AdField(
                label: tr('"İlk" mi?'),
                child: _firstTagPicker(),
              ),
              AdField(
                label: tr('Tarih'),
                child: _dateRow(),
              ),
              AdField(
                label: tr('Not'),
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
                Text(fmtDayMonthYear(_date),
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

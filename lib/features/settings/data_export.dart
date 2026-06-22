import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../data/auth_repository.dart';
import '../../data/cycle_repository.dart';
import '../../data/memory_repository.dart';
import '../../data/mom_repository.dart';
import '../../data/sync_gate.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_controller.dart';
import '../records/record_controller.dart';

/// Kullanıcının verisini JSON olarak toplar, dosyaya yazar ve paylaşımı açar.
///
/// LOCAL-FIRST: veri birincil olarak telefonda. Free kullanıcı (hesaplı/hesapsız)
/// için **tam yerel export** üretilir — veri kaybı güvenlik ağı (premium yedeği
/// olmayan kullanıcı verisini her an dosyaya alabilir). Premium + oturum açık
/// ise sunucudaki eksiksiz kopya (topluluk Q&A, rıza izi, sağlık) tercih edilir.
Future<void> exportUserData(BuildContext context, WidgetRef ref) async {
  try {
    Map<String, dynamic> export;
    if (ref.read(cloudSyncEnabledProvider)) {
      try {
        export = await ref.read(authRepositoryProvider).exportData();
        export['exported_at'] = DateTime.now().toIso8601String();
      } catch (_) {
        export = await _localExport(ref);
      }
    } else {
      // Free → yerel veri tek doğru kaynak.
      export = await _localExport(ref);
    }

    final jsonStr = const JsonEncoder.withIndent('  ').convert(export);
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    final file = File('${dir.path}/adena-veri-$stamp.json');
    await file.writeAsString(jsonStr);

    // Paylaşım sayfası bazı ortamlarda (ör. paylaşım hedefi olmayan cihaz/
    // emülatör) hiç dönmeyebilir; timeout ile spinner'ın sonsuz takılmasını
    // önle. İptal/dismiss hata değildir — sessiz geç.
    await SharePlus.instance
        .share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: tr('Adena Baby verilerim'),
            text: trp('Adena Baby dışa aktarılan verim ({stamp}).', {'stamp': stamp}),
          ),
        )
        .timeout(const Duration(seconds: 60), onTimeout: () {
      // Dosya hazır ve diske yazıldı; yalnızca paylaşım sayfası açılamadı.
      throw TimeoutException('share');
    });
  } on TimeoutException {
    if (context.mounted) {
      showAdToast(context, tr('Paylaşım açılamadı — dosya cihaza kaydedildi.'));
    }
  } catch (_) {
    if (context.mounted) showAdToast(context, tr('Dışa aktarılamadı'));
  }
}

/// Yerel DB'den TAM export: profil + bebekler + kayıtlar + anılar + anne takibi
/// + adet. (Foto'lar yerel dosya yolu olarak referanslanır.)
Future<Map<String, dynamic>> _localExport(WidgetRef ref) async {
  final user = ref.read(authControllerProvider).asData?.value;
  final babies = ref.read(babyControllerProvider).asData?.value ?? const [];
  final memoryRepo = ref.read(memoryRepositoryProvider);
  final momRepo = ref.read(momRepositoryProvider);
  final babyList = <Map<String, dynamic>>[];
  for (final b in babies) {
    final records = await ref.read(recordsProvider(b.id).future);
    final memories = await memoryRepo.list(b.id);
    final momEntries = await momRepo.list(b.id);
    babyList.add({
      'id': b.id,
      'name': b.name,
      'status': b.status.name,
      'gender': b.gender.name,
      'birth_date': b.birthDate?.toIso8601String(),
      'due_date': b.dueDate?.toIso8601String(),
      'records': [
        for (final r in records.where((r) => !r.isDeleted))
          {
            'id': r.id,
            'type': r.type.name,
            'ts': r.ts.toIso8601String(),
            'data': r.data,
          },
      ],
      'memories': [
        for (final m in memories)
          {
            'id': m.id,
            'date': m.date.toIso8601String(),
            'title': m.title,
            'note': m.note,
            'first_tag': m.firstTag,
            'photo': m.photo, // yerel dosya yolu veya sunucu URL'i
          },
      ],
      'mom_entries': [
        for (final e in momEntries)
          {
            'id': e.id,
            'kind': e.kind.name,
            'date': e.date.toIso8601String(),
            'weight_kg': e.weightKg,
            'title': e.title,
            'note': e.note,
          },
      ],
    });
  }
  // Adet (kullanıcıya özel, bebekten bağımsız).
  final cycleRepo = ref.read(cycleRepositoryProvider);
  final cycleSettings = await cycleRepo.getSettings();
  final cycleEntries = await cycleRepo.listEntries();
  return {
    'app': 'Adena Baby',
    'local_first': true, // yerel-önce tam kopya
    'exported_at': DateTime.now().toIso8601String(),
    'user': user == null
        ? null
        : {'id': user.id, 'email': user.email, 'name': user.name},
    'babies': babyList,
    'cycle': {
      'settings': cycleSettings.toPatchJson(),
      'entries': [for (final e in cycleEntries) e.toJson()],
    },
  };
}

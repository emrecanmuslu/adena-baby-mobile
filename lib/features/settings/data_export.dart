import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_controller.dart';
import '../records/record_controller.dart';

/// Kullanıcının tüm yerel verisini (profil + bebekler + kayıtlar) JSON olarak
/// toplar, geçici bir dosyaya yazar ve sistem paylaşım sayfasını açar.
/// Offline-first: veriyi yerel DB'den okur, backend gerektirmez.
Future<void> exportUserData(BuildContext context, WidgetRef ref) async {
  try {
    final user = ref.read(authControllerProvider).asData?.value;
    final babies = ref.read(babyControllerProvider).asData?.value ?? const [];

    final babyList = <Map<String, dynamic>>[];
    for (final b in babies) {
      final records = await ref.read(recordsProvider(b.id).future);
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
      });
    }

    final export = <String, dynamic>{
      'app': 'Adena Baby',
      'exported_at': DateTime.now().toIso8601String(),
      'user': user == null
          ? null
          : {'id': user.id, 'email': user.email, 'name': user.name},
      'babies': babyList,
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(export);
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    final file = File('${dir.path}/adena-veri-$stamp.json');
    await file.writeAsString(jsonStr);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: tr('Adena Baby verilerim'),
        text: trp('Adena Baby dışa aktarılan verim ({stamp}).', {'stamp': stamp}),
      ),
    );
  } catch (_) {
    if (context.mounted) showAdToast(context, tr('Dışa aktarılamadı'));
  }
}

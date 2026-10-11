import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/records/record_form.dart';
import 'package:adena_baby/models/record.dart';

/// O37 — düzenlemede `createdBy` ("kim ekledi") ve kimlik korunur; yeni kayıtta
/// createdBy null, id yeni.
void main() {
  final existing = Record(
    id: 'r1',
    baby: 'b1',
    type: RecordType.feed,
    ts: DateTime(2026, 5, 1, 10),
    data: const {'amount': 90},
    createdBy: 'u9',
  );

  test('düzenleme: id ve createdBy korunur, ts/data yenisi', () {
    final r = recordForSave(
      existing: existing,
      newId: 'NEW',
      babyId: 'b1',
      type: RecordType.feed,
      ts: DateTime(2026, 5, 1, 11),
      data: const {'amount': 120},
    );
    expect(r.id, 'r1');
    expect(r.createdBy, 'u9');
    expect(r.ts, DateTime(2026, 5, 1, 11));
    expect(r.data, {'amount': 120});
  });

  test('yeni kayıt: newId, createdBy null', () {
    final r = recordForSave(
      existing: null,
      newId: 'NEW',
      babyId: 'b1',
      type: RecordType.sleep,
      ts: DateTime(2026, 5, 1),
      data: const {},
    );
    expect(r.id, 'NEW');
    expect(r.createdBy, isNull);
  });
}

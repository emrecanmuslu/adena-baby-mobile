import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/records/record_controller.dart';

/// ILAC-INCELEME-2 V11 (M11): sahibin premium'u bitince kayıt `/sync` 403 verir;
/// ilaç planları yine de (GET ile) okunmalı → plan senkronu ÖNCE ve kendi hata
/// sınırında çalışır.
void main() {
  test('kayıt senkronu 403 atsa da plan senkronu önce çalışmış olur; 403 çağırana fırlar',
      () async {
    final calls = <String>[];
    Future<void> run() => syncPlansThenRecords(
          plans: () async => calls.add('plans'),
          records: () async {
            calls.add('records');
            throw DioException(
                requestOptions: RequestOptions(path: '/sync'),
                response: Response(requestOptions: RequestOptions(path: '/sync'), statusCode: 403));
          },
        );
    await expectLater(run(), throwsA(isA<DioException>()));
    expect(calls, ['plans', 'records']);
  });

  test('plan senkronu hata verse de kayıt senkronu çalışır', () async {
    var records = false;
    await syncPlansThenRecords(
        plans: () async => throw StateError('plan'), records: () async => records = true);
    expect(records, isTrue);
  });
}

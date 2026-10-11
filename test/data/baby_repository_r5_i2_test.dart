import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/models/baby.dart';

class _Tokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'a';
  @override
  Future<String?> get refreshToken async => 'r';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

/// POST sürerken [midFlight] çalışır (kullanıcı düzenler), sonra [reply] döner.
class _SlowAdapter implements HttpClientAdapter {
  final Future<void> Function() midFlight;
  final Map<String, dynamic> reply;
  final requests = <RequestOptions>[];
  _SlowAdapter(this.midFlight, this.reply);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    await midFlight();
    return ResponseBody.fromString(jsonEncode(reply), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// I2 (INCELEME.md) — R5: bebek profil push'u uçuştayken yapılan düzenleme
/// `dirty=false` ile ezilmesin (aksi hâlde yerelde temiz ama sunucuda yok →
/// sonraki pull sunucu kopyasını yazar, düzenleme kaybolur).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    LocalSession.setActiveAccount('u1');
  });
  tearDown(() => db.close());

  Future<BabyRow> row() =>
      (db.select(db.babies)..where((b) => b.id.equals('b1'))).getSingle();

  test('ad düzenlemesi POST uçuştayken → dirty KALIR, ad yeni değer', () async {
    final api = ApiClient(_Tokens());
    late BabyRepository repo;
    final adapter = _SlowAdapter(
        () => repo.update('b1', {'name': 'Yeni'}),
        {'id': 'b1', 'name': 'Eski', 'photo': null});
    api.dio.httpClientAdapter = adapter;
    repo = BabyRepository(db, api);
    await repo.create(Baby(
        id: 'b1', name: 'Eski', gender: BabyGender.unknown, status: BabyStatus.born));

    await repo.pushDirty(accountId: 'u1');

    final r = await row();
    expect(r.name, 'Yeni');
    expect(r.dirty, isTrue, reason: 'uçuş içi düzenleme bir sonraki turda gitmeli (R5)');
    expect(r.pushError, isNull);
  });

  test('foto (multipart) yüklenirken yeni foto seçildi → sunucu URL\'i yerel yolu ezmez, dirty kalır',
      () async {
    final dir = await Directory.systemTemp.createTemp('adena_i2');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {} // Windows: multipart akışı dosyayı tutabilir
    });
    final p1 = File('${dir.path}/one.jpg')..writeAsBytesSync([1, 2, 3]);
    final p2 = File('${dir.path}/two.jpg')..writeAsBytesSync([4, 5, 6]);
    final api = ApiClient(_Tokens());
    late BabyRepository repo;
    final adapter = _SlowAdapter(
        () => repo.updatePhoto('b1', p2.path),
        {'id': 'b1', 'name': 'Eski', 'photo': 'http://srv/one.jpg'});
    api.dio.httpClientAdapter = adapter;
    repo = BabyRepository(db, api);
    await repo.create(Baby(
        id: 'b1',
        name: 'Eski',
        gender: BabyGender.unknown,
        status: BabyStatus.born,
        photo: p1.path));

    await repo.pushDirty(accountId: 'u1');

    expect(adapter.requests.single.data, isA<FormData>(), reason: 'ilk push multipart');
    final r = await row();
    expect(r.photo, p2.path, reason: 'uçuşta seçilen yerel foto korunur');
    expect(r.dirty, isTrue);
  });

  test('uçuşta değişiklik yoksa eski davranış: dirty=false, foto sunucu URL\'i', () async {
    final api = ApiClient(_Tokens());
    final adapter = _SlowAdapter(
        () async {}, {'id': 'b1', 'name': 'Eski', 'photo': 'http://srv/p.jpg'});
    api.dio.httpClientAdapter = adapter;
    final repo = BabyRepository(db, api);
    final dir = await Directory.systemTemp.createTemp('adena_i2b');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {} // Windows: multipart akışı dosyayı tutabilir
    });
    final p1 = File('${dir.path}/one.jpg')..writeAsBytesSync([1]);
    await repo.create(Baby(
        id: 'b1',
        name: 'Eski',
        gender: BabyGender.unknown,
        status: BabyStatus.born,
        photo: p1.path));

    await repo.pushDirty(accountId: 'u1');

    final r = await row();
    expect(r.dirty, isFalse);
    expect(r.photo, 'http://srv/p.jpg');
  });

  test('uçuşta silindi (tombstone) → dirty kalır, sonraki turda DELETE gider', () async {
    final api = ApiClient(_Tokens());
    late BabyRepository repo;
    final adapter = _SlowAdapter(
        () => repo.delete('b1'), {'id': 'b1', 'name': 'Eski', 'photo': null});
    api.dio.httpClientAdapter = adapter;
    repo = BabyRepository(db, api);
    await repo.create(Baby(
        id: 'b1', name: 'Eski', gender: BabyGender.unknown, status: BabyStatus.born));

    await repo.pushDirty(accountId: 'u1');
    var r = await row();
    expect(r.isDeleted, isTrue);
    expect(r.dirty, isTrue, reason: 'silme bir sonraki turda DELETE olarak gitmeli');

    await repo.pushDirty(accountId: 'u1');
    expect(adapter.requests.last.method, 'DELETE');
    r = await row();
    expect(r.dirty, isFalse);
  });
}

import 'package:dio/dio.dart';

/// Senkron birleştirme kuralları — SAF (drift/ağ bağımsız), birim testli.
/// Bkz. TASARIM-SENKRON.md §2 (R1-R5) ve §3. Repository'ler pull/push
/// sırasında kararı buradan alır, yazımı kendi companion'larıyla yapar.

/// Pull'dan gelen bir sunucu satırı için karar (R1, R2).
enum MergeDecision {
  /// Sunucu satırı yerele uygulanır (yerel yok / temiz).
  apply,

  /// Yerel satır gönderilmemiş değişiklik taşıyor → sunucu kopyası uygulanmaz,
  /// bir sonraki push gönderir (R1).
  keepDirty,

  /// Yerel satır dirty ve sunucu damgası yerelden YENİ → çakışma. Karar yine
  /// "yerel kalır" (R1); ayrı değer yalnız loglama/teşhis için.
  keepDirtyConflict,

  /// Yerel satır bekleyen silme (tombstone) → sunucu kopyası onu geri getiremez,
  /// DELETE yeniden denenir (R2).
  keepDeleted,
}

/// Sunucu satırı uygulanmalı mı? [localExists] false ise her zaman [MergeDecision.apply].
/// Damgalar yalnız çakışma sınıflandırması için; karar damgaya göre DEĞİŞMEZ
/// (dirty yerel her durumda korunur — records `_applyServerRow` ile tutarlı).
MergeDecision decideServerRow({
  required bool localExists,
  bool localDirty = false,
  bool localDeleted = false,
  DateTime? localStamp,
  DateTime? serverStamp,
}) {
  if (!localExists) return MergeDecision.apply;
  if (localDeleted && localDirty) return MergeDecision.keepDeleted;
  if (localDirty) {
    final serverNewer = serverStamp != null &&
        localStamp != null &&
        serverStamp.isAfter(localStamp);
    return serverNewer ? MergeDecision.keepDirtyConflict : MergeDecision.keepDirty;
  }
  // Temiz (dirty=false) satır: silinmiş olsa bile sunucu otoriter (records'ta
  // onaylanmış tombstone sunucuda da tombstone'dur; dirilme sunucu kararıdır).
  return MergeDecision.apply;
}

/// Yerel satırın R4 için gereken durumu.
class LocalRowState {
  final String id;
  final bool dirty;
  final bool deleted;
  const LocalRowState(this.id, {required this.dirty, required this.deleted});
}

/// R4 sonucu: silinecek yerel id'ler ya da silmenin neden atlandığı.
class StaleResult {
  final Set<String> ids;

  /// null → silme uygulanabilir ([ids] boş olabilir). Dolu → silme ATLANDI
  /// (koruma devreye girdi), çağıran loglamalı.
  final String? skippedReason;
  const StaleResult(this.ids, {this.skippedReason});

  bool get skipped => skippedReason != null;
}

/// Silinecek satır sayısı bu eşiği aşarsa oran koruması devreye girer (K-2).
const staleDeleteCountThreshold = 5;

/// R4: sunucunun TAM listesinde olmayan, yerelde temiz (dirty=false, deleted=false)
/// satırlar sunucuda silinmiş sayılır. Korumalar (K-2):
///  • yalnız HTTP 200 + yanıt tamamen parse edildiyse,
///  • sunucu listesi boşsa hiç silme,
///  • silinecek > [staleDeleteCountThreshold] VE temiz satırların yarısından
///    fazlasıysa silme atlanır.
/// Dirty ya da tombstone'lu yerel satırlar hiçbir zaman aday değildir.
StaleResult staleLocalIds({
  required Iterable<LocalRowState> local,
  required Set<String> serverIds,
  required int statusCode,
  required bool parsedOk,
}) {
  if (statusCode != 200 || !parsedOk) {
    return const StaleResult({}, skippedReason: 'untrusted_response');
  }
  final clean = local.where((r) => !r.dirty && !r.deleted).toList();
  final candidates = {
    for (final r in clean)
      if (!serverIds.contains(r.id)) r.id,
  };
  if (candidates.isEmpty) return const StaleResult({});
  if (serverIds.isEmpty) {
    return const StaleResult({}, skippedReason: 'server_list_empty');
  }
  if (candidates.length > staleDeleteCountThreshold &&
      candidates.length * 2 > clean.length) {
    return StaleResult({},
        skippedReason:
            'too_many_deletions:${candidates.length}/${clean.length}');
  }
  return StaleResult(candidates);
}

/// Push başarısızlığı sınıfı (R3).
enum PushFailure {
  /// Ağ/zaman aşımı/5xx/401/403/408/429 → dirty kalır, sessizce yeniden denenir.
  transient,

  /// Diğer 4xx (400/404/413/422…) → sunucu bu değişikliği hiçbir zaman kabul
  /// etmeyecek. Yerel değişiklik KORUNUR (K-1), satıra pushError not edilir.
  permanent,
}

/// [statusCode] null → ağ/zaman aşımı (geçici).
PushFailure classifyPushFailure({int? statusCode}) {
  final code = statusCode;
  if (code == null) return PushFailure.transient;
  if (code >= 500) return PushFailure.transient;
  if (code == 401 || code == 403 || code == 408 || code == 429) {
    return PushFailure.transient;
  }
  if (code >= 400) return PushFailure.permanent;
  return PushFailure.transient; // 2xx/3xx buraya düşmez; savunmacı
}

/// Dio hatası için kısayol: yanıt yoksa (bağlantı/timeout) geçici.
PushFailure classifyDioError(DioException e) =>
    classifyPushFailure(statusCode: e.response?.statusCode);

/// "Değişikliği geri al" (K-1) sonucu.
enum RevertResult {
  /// Sunucu kopyası uygulandı; dirty=false, pushError=null.
  applied,

  /// Satır sunucuda yok (yerelde oluşturulmuş / sunucuda silinmiş) → çağıran
  /// kullanıcı onayıyla yerelden siler ya da yerelde temiz bırakır.
  notOnServer,

  /// Ağ/sunucu hatası → hiçbir şey değişmedi.
  failed,
}

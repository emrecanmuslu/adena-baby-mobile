import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/auth_controller.dart';

/// ADET-INCELEME B1 (karar S7): "Bu dönemde bir adet kaydını unutmuş olabilir
/// misin?" sorusunun cevapları — döngü başlangıç günü → cevap. Cevap kalıcıdır
/// (hesap başına, bu cihazda; bulut senkronu YOK — sunucu şemasında alan yok).
///  • `long`  = "Hayır, döngüm uzundu" → döngü hesaba DAHİL edilir.
///  • `asked` = "Kayıt ekle" seçildi → soru tekrar sorulmaz; döngü kayıt
///    eklenene dek hesap dışı kalır.
class CycleLongAnswers {
  final Map<String, String> byStart;
  const CycleLongAnswers(this.byStart);

  static String keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Motor için: kullanıcının "döngüm uzundu" dediği başlangıçlar.
  Set<DateTime> get confirmedLong => {
        for (final e in byStart.entries)
          if (e.value == 'long') DateTime.parse(e.key),
      };

  bool answered(DateTime start) => byStart.containsKey(keyOf(start));
}

class CycleLongAnswersNotifier extends Notifier<CycleLongAnswers> {
  String? _acct;
  String get _prefsKey => 'cycle_long_answers_${_acct ?? 'local'}';

  @override
  CycleLongAnswers build() {
    _acct = ref.watch(activeAccountIdProvider);
    _load();
    return const CycleLongAnswers({});
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final m = (jsonDecode(raw) as Map).cast<String, String>();
      if (ref.mounted) state = CycleLongAnswers(m);
    } catch (_) {
      // Okunamazsa soru yeniden sorulur — güvenli taraf.
    }
  }

  Future<void> answer(DateTime start, {required bool longCycle}) async {
    final next = {...state.byStart, CycleLongAnswers.keyOf(start): longCycle ? 'long' : 'asked'};
    state = CycleLongAnswers(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(next));
    } catch (_) {}
  }
}

final cycleLongAnswersProvider =
    NotifierProvider<CycleLongAnswersNotifier, CycleLongAnswers>(
        CycleLongAnswersNotifier.new);

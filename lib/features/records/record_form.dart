import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/feed_input_cache.dart';
import '../../data/health_repository.dart';
import '../../models/record.dart';
import '../../models/symptom.dart';
import '../auth/auth_controller.dart';
import '../babies/family_settings.dart';
import 'entry_widgets.dart';
import 'record_controller.dart';
import 'record_ui.dart';

const _uuid = Uuid();

/// Tüm kayıt tipleri için tek form — yeni ekleme veya [existing] düzenleme.
/// Zaman seçici dahil (geçmişe dönük kayıt için).
Future<void> showRecordForm(
  BuildContext context,
  WidgetRef ref,
  String babyId,
  RecordType type, {
  Record? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => Padding(
      // Klavye açılınca sheet yukarı kaysın → builder'ın KENDİ context'i (modal'ın
      // güncel viewInsets'i). Dış context güncellenmez → klavye sheet'i örter.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _RecordFormSheet(babyId: babyId, type: type, existing: existing),
    ),
  );
}

class _RecordFormSheet extends ConsumerStatefulWidget {
  final String babyId;
  final RecordType type;
  final Record? existing;
  const _RecordFormSheet({required this.babyId, required this.type, this.existing});

  @override
  ConsumerState<_RecordFormSheet> createState() => _RecordFormSheetState();
}

class _RecordFormSheetState extends ConsumerState<_RecordFormSheet> {
  late DateTime _ts;
  DateTime? _endTs; // sleep bitişi
  late String _sub; // diaper/feed alt tipi
  String _unit = 'C'; // temperature
  String _timing = 'after'; // pumping
  String _symptomKey = ''; // symptom: seçili belirti
  String _severity = 'moderate'; // symptom: hafif/orta/şiddetli
  bool _diaperDetail = false; // bez: dışkı detayı (renk/kıvam) açık mı
  String _stool = ''; // bez: renk / kıvam
  late Units _units; // birim tercihleri (form açılışında okunur)

  // Randevu hatırlatıcısı (yalnız appointment türü)
  bool _apptRemind = true; // yeni randevuda varsayılan açık (tasarım: "1 gün önce")
  String _apptLeadSel = '1440'; // '30'|'60'|'1440' (dk) | 'custom' (→ saat)
  int _apptCustomHours = 2;

  int get _apptLeadMin =>
      _apptLeadSel == 'custom' ? _apptCustomHours * 60 : int.parse(_apptLeadSel);

  // Emzirme kronometresi
  bool _manualBreast = false; // kronometre yerine elle dakika girişi (yeni kayıt)
  bool _editDurations = false; // süren kaydı kaydederken süreleri elle düzenleme
  String _side = 'left'; // başlangıç memesi (start state)
  String _nextSide = 'left'; // önerilen sıradaki meme (= son emzirilen)
  String? _lastSide; // son kullanılan meme (etiket için)
  // Uyku kronometresi
  bool _manualSleep = false; // başlatmak yerine elle başlangıç/bitiş girişi
  bool _sleepEditDurations = false; // bitirirken süreyi elle düzenleme
  Timer? _tick; // çalışan sayaç için saniyelik yeniden çizim (uyku/emzirme)

  final _c = <String, TextEditingController>{};

  TextEditingController ctl(String k, [String? init]) =>
      _c.putIfAbsent(k, () => TextEditingController(text: init ?? ''));

  bool get _editing => widget.existing != null;

  /// Düzenlemede mevcut kayıt; yeni kayıtta aynı türün EN SON kaydının verisi
  /// (tekrar girişi azaltmak için ön-doldurma). Uyku için ön-doldurma yok.
  late final Map<String, dynamic> _prefill;

  Map<String, dynamic> _computePrefill() {
    if (_editing) return widget.existing!.data;
    if (widget.type == RecordType.sleep) return const {};
    final recs = ref.read(recordsProvider(widget.babyId)).asData?.value ?? const [];
    for (final r in recs) {
      if (r.type == widget.type) return r.data; // liste yeni→eski sıralı
    }
    return const {};
  }

  @override
  void initState() {
    super.initState();
    _units = ref.read(activeUnitsProvider);
    _ts = widget.existing?.ts ?? DateTime.now();
    _prefill = _computePrefill();
    final d = _prefill;
    _sub = switch (widget.type) {
      RecordType.diaper => d['sub'] as String? ?? 'pee',
      RecordType.feed => d['sub'] as String? ?? 'breast',
      _ => '',
    };
    _unit = d['unit'] as String? ?? _units.temp; // varsayılan birim tercihinden
    _timing = d['timing'] as String? ?? 'after';
    _stool = d['stool'] as String? ?? '';
    if (_stool.isNotEmpty) _diaperDetail = true;
    // Belirti: yeni kayıtta seçim boş gelir (her hastalıkta farklı); düzenlemede mevcut.
    if (widget.type == RecordType.symptom && _editing) {
      _symptomKey = d['key'] as String? ?? '';
      _severity = d['severity'] as String? ?? 'moderate';
    }
    if (widget.type == RecordType.sleep) {
      final s = DateTime.tryParse(d['start_ts'] as String? ?? '')?.toLocal();
      if (s != null) _ts = s;
      final e = DateTime.tryParse(d['end_ts'] as String? ?? '')?.toLocal();
      // Süren bir uykuyu düzenliyorsak (end yok) bitişi şimdiye varsay.
      _endTs = e ?? (_editing ? DateTime.now() : null);
    }
    if (widget.type == RecordType.appointment) {
      // Düzenlemede: hatırlatıcı bağlı mı? Yeni kayıtta varsayılan açık kalır.
      if (_editing) _apptRemind = widget.existing!.data['reminder_id'] != null;
      final lead = (d['reminder_lead_min'] as num?)?.toInt();
      if (lead != null) {
        if (lead == 30 || lead == 60 || lead == 1440) {
          _apptLeadSel = lead.toString();
        } else {
          _apptLeadSel = 'custom';
          _apptCustomHours = (lead / 60).round().clamp(1, 72);
        }
      }
    }
    if (widget.type == RecordType.feed) {
      _initBreast();
      _applyFeedCache(_sub); // Mama/Sağılmış/Katı: son girilen değeri ön-doldur
    }
    // Çalışan sayaç (mm:ss / HH:MM:SS) için saniyelik yeniden çizim.
    if (widget.type == RecordType.feed || widget.type == RecordType.sleep) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Başlangıç memesi = EN SON emzirilen meme (anneler genelde bıraktıkları
  /// göğüsten devam eder). Geçmiş yoksa sol. Düzenlemede elle giriş moduna geçer.
  void _initBreast() {
    if (_editing && _sub == 'breast') _manualBreast = true;
    final recs = ref.read(recordsProvider(widget.babyId)).asData?.value ?? const [];
    for (final r in recs) {
      if (r.type == RecordType.feed && r.data['sub'] == 'breast' && r.data['end_ts'] != null) {
        final l = (r.data['left_min'] as num?) ?? 0;
        final rt = (r.data['right_min'] as num?) ?? 0;
        _lastSide = (r.data['side'] as String?) ?? (rt > l ? 'right' : 'left');
        break;
      }
    }
    _nextSide = _lastSide ?? 'left';
    _side = _nextSide;
    // Süren emzirme varsa emzirme sekmesini öne al.
    if (ref.read(ongoingBreastProvider(widget.babyId)) != null) _sub = 'breast';
  }

  /// Beslenme alt-türü için son girilen değeri (cache) controller'a yazar.
  /// Anne sütü hariç (kronometre/taraf bazlı) ve düzenlemede yapılmaz.
  /// Controller'ı önceden oluşturur → build'deki _initFor fallback'i devre dışı kalır,
  /// böylece cache değeri öncelikli olur. Cache boşsa dokunmaz (eski prefill çalışır).
  void _applyFeedCache(String sub) {
    if (_editing || sub == 'breast') return;
    final c = FeedInputCache.get(sub);
    void setIf(String key) {
      final v = c[key];
      if (v != null && v.isNotEmpty) ctl(key).text = v;
    }
    if (sub == 'formula' || sub == 'pumped') {
      setIf('ml');
    } else if (sub == 'solid') {
      setIf('food_name');
      setIf('amount');
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) =>
      pickRecordDateTime(context, initial);

  num? _num(String k) => num.tryParse(ctl(k).text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    Map<String, dynamic> data;
    switch (widget.type) {
      case RecordType.diaper:
        data = {'sub': _sub};
        if (_sub != 'pee' && _diaperDetail && _stool.isNotEmpty) data['stool'] = _stool;
      case RecordType.feed:
        data = {'sub': _sub};
        switch (_sub) {
          case 'breast':
            data['left_min'] = _num('left_min') ?? 0;
            data['right_min'] = _num('right_min') ?? 0;
          case 'formula':
          case 'pumped':
            final ml = _num('ml');
            if (ml == null) return _warn(trp('Miktarı ({unit}) gir', {'unit': _units.volumeLabel}));
            data['ml'] = _units.volumeToCanonical(ml.toDouble());
            unawaited(FeedInputCache.put(_sub, {'ml': ctl('ml').text.trim()}));
          case 'solid':
            if (ctl('food_name').text.trim().isEmpty) {
              return _warn(tr('Yiyecek adını gir'));
            }
            data['food_name'] = ctl('food_name').text.trim();
            final amt = _num('amount');
            if (amt != null && amt > 0) data['amount'] = amt;
            final reaction = ctl('reaction').text.trim();
            if (reaction.isNotEmpty) data['reaction'] = reaction;
            unawaited(FeedInputCache.put('solid', {
              'food_name': ctl('food_name').text.trim(),
              if (amt != null && amt > 0) 'amount': ctl('amount').text.trim(),
            }));
        }
      case RecordType.pumping:
        final ml = _num('ml');
        if (ml == null) return _warn(trp('Miktarı ({unit}) gir', {'unit': _units.volumeLabel}));
        data = {'ml': _units.volumeToCanonical(ml.toDouble()), 'timing': _timing};
        _addNote(data);
      case RecordType.sleep:
        if (_endTs == null) return _warn(tr('Bitiş zamanını seç'));
        data = {
          'start_ts': _ts.toUtc().toIso8601String(),
          'end_ts': _endTs!.toUtc().toIso8601String(),
          'duration': _endTs!.difference(_ts).inMinutes,
        };
      case RecordType.growth:
        final w = _num('weight'), h = _num('height'), hc = _num('head_circ');
        data = {
          if (w != null) 'weight': _units.weightToCanonical(w.toDouble()),
          if (h != null) 'height': _units.lengthToCanonical(h.toDouble()),
          if (hc != null) 'head_circ': _units.lengthToCanonical(hc.toDouble()),
        };
        if (data.isEmpty) return _warn(tr('En az bir ölçüm gir'));
      case RecordType.temperature:
        final v = _num('value');
        if (v == null) return _warn(tr('Ateş değerini gir'));
        data = {'value': v, 'unit': _unit};
      case RecordType.medication:
        if (ctl('name').text.trim().isEmpty) return _warn(tr('İlaç adını gir'));
        data = {'name': ctl('name').text.trim(), 'dose': ctl('dose').text.trim(), 'given': true};
      case RecordType.bath:
        data = {};
        _addNote(data);
      case RecordType.appointment:
        if (ctl('title').text.trim().isEmpty) return _warn(tr('Başlık gir'));
        data = {'title': ctl('title').text.trim(), 'datetime': _ts.toUtc().toIso8601String()};
        _addNote(data);
        await _syncApptReminder(data); // data['reminder_id'] / reminder_lead_min ayarlar
      case RecordType.symptom:
        if (_symptomKey.isEmpty) return _warn(tr('Bir belirti seç'));
        data = {'key': _symptomKey, 'severity': _severity};
        _addNote(data);
    }

    final record = Record(
      id: widget.existing?.id ?? _uuid.v4(),
      baby: widget.babyId,
      type: widget.type,
      ts: _ts,
      data: data,
    );
    await ref.read(recordActionsProvider).upsert(record);
    if (!mounted) return;
    // Toast kök overlay'e eklenir → sheet kapansa da görünür kalır.
    showAdToast(context, _editing ? tr('Güncellendi') : tr('Kaydedildi'));
    Navigator.pop(context);
  }

  void _addNote(Map<String, dynamic> data) {
    if (ctl('note').text.trim().isNotEmpty) data['note'] = ctl('note').text.trim();
  }

  /// Randevu hatırlatıcısını ekle/güncelle/kaldır. Düzenlemede bu kayda bağlı eski
  /// hatırlatıcıyı siler; açıksa ve hatırlatma anı gelecekteyse yeni tek-seferlik
  /// hatırlatıcı kurar, id'sini [data]'ya yazar (sonraki düzenlemede bulunsun).
  Future<void> _syncApptReminder(Map<String, dynamic> data) async {
    // Misafir (oturumsuz) kullanıcıda hatırlatıcı kurulmaz — alan da gizli.
    if (ref.read(authControllerProvider).asData?.value == null) return;
    final repo = ref.read(healthRepositoryProvider);
    final oldId = widget.existing?.data['reminder_id'];
    if (oldId is int) {
      try {
        await repo.deleteReminder(oldId);
        await NotificationService.instance.cancelReminder(oldId);
      } catch (_) {}
    }
    if (!_apptRemind) return;
    final fireAt = _ts.subtract(Duration(minutes: _apptLeadMin));
    if (!fireAt.isAfter(DateTime.now())) return; // hatırlatma anı geçmiş → kurma
    try {
      final rem = await repo.createReminder(widget.babyId, type: 'appt', schedule: {
        'repeat': 'once',
        'at': fireAt.toUtc().toIso8601String(),
        'title': trp('Randevu: {title}', {'title': data['title']}),
        'lead_min': _apptLeadMin,
      });
      data['reminder_id'] = rem.id;
      data['reminder_lead_min'] = _apptLeadMin;
      final list = await repo.reminders(widget.babyId);
      await NotificationService.instance.sync(list);
      ref.invalidate(remindersProvider(widget.babyId));
    } catch (_) {
      // Hatırlatıcı kurulamazsa kayıt yine de kaydedilir (sessiz geç).
    }
  }

  void _warn(String msg) => showAdToast(context, msg);

  /// Bölüm kendi zaman/aksiyon butonlarını mı yönetiyor? (genel zaman çipi +
  /// Kaydet gizlenir). Uyku: her zaman. Emzirme: süren ya da kronometre modunda.
  bool get _handlesActionsInternally {
    if (widget.type == RecordType.sleep) return true;
    if (widget.type != RecordType.feed || _sub != 'breast') return false;
    if (ref.read(ongoingBreastProvider(widget.babyId)) != null) return true;
    return !_editing && !_manualBreast;
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final accent = RecordUi.color(type);
    final title = _editing
        ? trp('{label} düzenle', {'label': RecordUi.label(type)})
        : RecordUi.label(type);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            // Başlık (design h3): kategori çipi + ad
            Row(children: [
              RecordUi.chip(type, size: 38, radius: 13),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 16),
            // İçerik kaydırılabilir: uzun formlar (ör. belirti + bakım rehberi +
            // şiddet + not) sheet'i taşırmasın. Kısa formlarda Flexible(loose)
            // sayesinde sheet yine içeriğe göre kompakt kalır.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._fields(accent),
                    // Uyku/emzirme kendi zaman/aksiyon butonlarını yönetir; diğerleri genel.
                    if (!_handlesActionsInternally) ...[
                      AdField(
                        label: tr('Zaman'),
                        child: AdTimeChip(
                            value: _ts,
                            onTap: () => _pick(_ts, (dt) => setState(() => _ts = dt))),
                      ),
                      const SizedBox(height: 8),
                      AdSaveButton(
                          label: _editing ? tr('Güncelle') : tr('Kaydet'),
                          color: accent,
                          onTap: _save),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields(Color accent) {
    switch (widget.type) {
      case RecordType.diaper:
        return [
          AdChoice(
            selected: _sub,
            onSelect: (v) => setState(() => _sub = v),
            items: [
              (key: 'pee', label: tr('Çiş'), icon: 'pump', color: AppColors.bath, bg: AppColors.bathBg),
              (key: 'poo', label: tr('Kaka'), icon: 'diaper', color: AppColors.diaper, bg: AppColors.diaperBg),
              (key: 'poopee', label: tr('Karışık'), icon: 'diaper', color: AppColors.diaper, bg: AppColors.diaperBg),
            ],
          ),
          const SizedBox(height: 13),
          // Dışkı varsa (Kaka/Karışık) renk-kıvam detayı eklenebilir (opsiyonel).
          if (_sub != 'pee') ..._diaperDetailFields(),
        ];
      case RecordType.feed:
        return [
          AdTabs(
            options: {'breast': tr('Anne sütü'), 'formula': tr('Mama'), 'pumped': tr('Sağılmış'), 'solid': tr('Katı')},
            selected: _sub,
            onSelect: (v) => setState(() {
              _sub = v;
              _applyFeedCache(v); // seçilen türün son değerini getir
            }),
          ),
          const SizedBox(height: 14),
          ..._feedFields(accent),
        ];
      case RecordType.pumping:
        return [
          AdField(
            label: trp('Miktar ({unit})', {'unit': _units.volumeLabel}),
            child: _mlStepper(accent),
          ),
          AdField(
            label: tr('Zamanlama'),
            child: AdSides(
              selected: _timing,
              onSelect: (v) => setState(() => _timing = v),
              items: [
                (key: 'before', label: tr('Beslenmeden önce'), small: null),
                (key: 'after', label: tr('Sonra'), small: null),
              ],
            ),
          ),
          AdField(label: tr('Not'), child: _noteInput()),
        ];
      case RecordType.sleep:
        return [_sleepSection(accent)];
      case RecordType.growth:
        final wDec = _units.weight == 'lb' ? 1 : 2;
        return [
          AdField(
            label: trp('Kilo ({unit})', {'unit': _units.weightLabel}),
            child: AdStepper(
                controller: ctl('weight', _initFor('weight')),
                unit: _units.weightLabel,
                step: 0.1,
                decimals: wDec,
                accent: accent),
          ),
          AdField(
            label: trp('Boy ({unit})', {'unit': _units.lengthLabel}),
            child: AdStepper(
                controller: ctl('height', _initFor('height')),
                unit: _units.lengthLabel,
                step: 0.5,
                decimals: 1,
                accent: accent),
          ),
          AdField(
            label: trp('Baş çevresi ({unit})', {'unit': _units.lengthLabel}),
            child: AdStepper(
                controller: ctl('head_circ', _initFor('head_circ')),
                unit: _units.lengthLabel,
                step: 0.5,
                decimals: 1,
                accent: accent),
          ),
        ];
      case RecordType.temperature:
        // Birim ayarlardan gelir (tasarım 17a'da sheet içinde toggle yok).
        return [
          AdField(
            label: tr('Sıcaklık'),
            child: AdStepper(
                controller: ctl('value', _initFor('value')),
                unit: '°$_unit',
                step: 0.1,
                decimals: 1,
                accent: AppColors.coralDd),
          ),
          _infoNote(_unit == 'F'
              ? tr('37 °C ≈ 98.6 °F normal. 100.4 °F (38 °C) üzeri için hatırlatıcı kurabilirsin.')
              : tr('36.5–37.5 °C normal aralık. 38 °C üzeri için hatırlatıcı kurabilirsin.')),
          const SizedBox(height: 14),
        ];
      case RecordType.medication:
        return [
          AdField(
            label: tr('İlaç / vitamin'),
            child: AdInput(
                controller: ctl('name', _initFor('name')),
                hint: tr('örn. D vitamini'),
                capitalization: TextCapitalization.sentences),
          ),
          AdField(
            label: tr('Doz'),
            child: AdInput(controller: ctl('dose', _initFor('dose')), hint: tr('örn. 3 damla')),
          ),
        ];
      case RecordType.bath:
        return [
          _infoNote(tr('Banyo zamanını kaydet — sıklık trendini grafiklerde görebilirsin.')),
          const SizedBox(height: 14),
          AdField(label: tr('Not'), child: _noteInput()),
        ];
      case RecordType.appointment:
        return [
          AdField(
            label: tr('Başlık'),
            child: AdInput(
                controller: ctl('title', _initFor('title')),
                hint: tr('örn. 2. ay kontrolü'),
                capitalization: TextCapitalization.sentences),
          ),
          AdField(label: tr('Not'), child: _noteInput()),
          _apptReminderField(),
        ];
      case RecordType.symptom:
        return _symptomFields();
    }
  }

  // ── Belirti (semptom) bölümü: katalog seçimi + şiddet + not ──────────────
  List<Widget> _symptomFields() {
    return [
      AdField(
        label: tr('Belirti'),
        info: tr('Bebeğinde gözlemlediğin belirtiyi seç. Ateş ve ilaç ayrı kayıt '
            'türleridir. Her belirtiyi tek tek kaydet; aynı gün birden fazla '
            'belirti için ayrı kayıt ekleyebilirsin. Kayıtlar Günlük Akış\'ta ve '
            'Sağlık Hub\'ında görünür.'),
        child: _SymptomGrid(
          selected: _symptomKey,
          onSelect: (k) => setState(() => _symptomKey = k),
        ),
      ),
      if (symptomByKey(_symptomKey) case final s?) ...[
        _SymptomInfoCard(symptom: s),
        const SizedBox(height: 8),
        const AdMedicalNote(),
      ],
      AdField(
        label: tr('Şiddet'),
        info: tr('Belirtinin ne kadar belirgin olduğunu işaretle. Şiddetli ve '
            'sürekli belirtilerde doktora danış.'),
        child: AdTabs(
          options: {
            'mild': tr('Hafif'),
            'moderate': tr('Orta'),
            'severe': tr('Şiddetli'),
          },
          selected: _severity,
          onSelect: (v) => setState(() => _severity = v),
        ),
      ),
      AdField(label: tr('Not'), child: _noteInput()),
    ];
  }

  /// Randevu hatırlatıcısı: aç/kapa + ne kadar önce (hazır + özel).
  Widget _apptReminderField() {
    // Hatırlatıcı sunucuda oluşturulur → hesap gerektirir. Misafir kullanıcıya
    // "hatırlatıcı kur" gösterilmez; arka planda da reminder kurulmaz (false).
    final loggedIn = ref.watch(authControllerProvider).asData?.value != null;
    if (!loggedIn) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Row(
            children: [
              Text(tr('HATIRLATICI KUR'),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.muted,
                      letterSpacing: 0.4)),
              const SizedBox(width: 6),
              AdInfoDot(
                title: tr('Randevu hatırlatıcısı'),
                body: tr('Açık olursa randevudan önce telefonuna bir bildirim gönderir. '
                    'Aşağıdan ne kadar önce olacağını seç. Bu hatırlatıcı '
                    '"Hatırlatıcılar" ekranında da listelenir; istersen oradan '
                    'kapatıp silebilirsin.'),
              ),
              const Spacer(),
              Switch.adaptive(
                value: _apptRemind,
                activeThumbColor: AppColors.coral,
                onChanged: (v) => setState(() => _apptRemind = v),
              ),
            ],
          ),
        ),
        if (_apptRemind) ...[
          AdTabs(
            options: {'30': tr('30 dk'), '60': tr('1 saat'), '1440': tr('1 gün'), 'custom': tr('Özel')},
            selected: _apptLeadSel,
            onSelect: (v) => setState(() => _apptLeadSel = v),
          ),
          if (_apptLeadSel == 'custom')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _LeadStepRow(
                hours: _apptCustomHours,
                onChanged: (h) => setState(() => _apptCustomHours = h),
              ),
            ),
        ],
        const SizedBox(height: 13),
      ],
    );
  }

  List<Widget> _feedFields(Color accent) {
    switch (_sub) {
      case 'breast':
        return [_breastSection(accent)];
      case 'solid':
        return [
          AdField(
            label: tr('Yiyecek'),
            child: AdInput(
                controller: ctl('food_name', _initFor('food_name')),
                hint: tr('örn. yoğurt'),
                capitalization: TextCapitalization.sentences),
          ),
          AdField(
            label: tr('Miktar'),
            child: AdStepper(
                controller: ctl('amount', _initFor('amount')),
                unit: tr('kaşık'),
                accent: accent),
          ),
          AdField(
            label: tr('Tepki / alerji notu'),
            child: AdInput(
                controller: ctl('reaction', _initFor('reaction')),
                hint: tr('opsiyonel — örn. iyi karşıladı'),
                capitalization: TextCapitalization.sentences),
          ),
        ];
      default:
        return [AdField(label: trp('Miktar ({unit})', {'unit': _units.volumeLabel}), child: _mlStepper(accent))];
    }
  }

  // ── Emzirme bölümü: başlat / süren sayaç / elle giriş ────────────────────

  // Getter (`static final` DEĞİL) — AppColors.muted tema-duyarlı; `static final`
  // ilk erişimdeki temaya dondurur (Gece Modu'nda yanlış renk). Her build'de taze.
  static TextStyle get _breastLabelStyle => const TextStyle(
      fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.4).copyWith(color: AppColors.muted);

  Widget _breastSection(Color accent) {
    final ongoing = ref.watch(ongoingBreastProvider(widget.babyId));
    if (ongoing != null) {
      return _editDurations
          ? _breastEditDurations(ongoing, accent)
          : _breastRunning(ongoing, accent);
    }
    if (_editing || _manualBreast) return _breastManual(accent);
    return _breastStart(accent);
  }

  /// Başlamadan önce: başlangıç memesi (= son emzirilen), altında manuel link,
  /// en altta Başlat.
  Widget _breastStart(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text(tr('Hangi memeden başla?'), style: _breastLabelStyle),
          const SizedBox(width: 6),
          // Geçmiş emzirme varsa son kullanılan/duraklatılan göğsü sıradaki göster.
          if (_lastSide != null)
            _nextTag(trp('SIRADAKİ: {side}',
                {'side': _nextSide == 'left' ? tr('SOL') : tr('SAĞ')})),
        ]),
        const SizedBox(height: 8),
        AdSides(
          selected: _side,
          onSelect: (v) => setState(() => _side = v),
          items: [
            (key: 'left', label: tr('Sol'), small: null),
            (key: 'right', label: tr('Sağ'), small: null),
          ],
        ),
        const SizedBox(height: 2),
        _linkButton(tr('Süreleri elle gir'), () => setState(() => _manualBreast = true)),
        const SizedBox(height: 18),
        AdSaveButton(
          label: tr('Emzirmeyi başlat'),
          color: accent,
          onTap: () => ref.read(recordActionsProvider).startBreast(widget.babyId, _side),
        ),
      ],
    );
  }

  /// Süren emzirme: Sol/Sağ geçişi (her biri kendi süresini tutar) + toplam
  /// canlı sayaç + ayrı Durdur(/Devam) ve Kaydet butonları.
  Widget _breastRunning(Record r, Color accent) {
    final d = r.data;
    final side = d['side'] == 'right' ? 'right' : 'left';
    final paused = d['paused'] == true;
    final (leftMs, rightMs) = _accruedMs(d);
    final activeMs = side == 'right' ? rightMs : leftMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdField(
          label: tr('Hangi meme? · geçiş yapabilirsin'),
          child: AdSides(
            selected: side,
            onSelect: (v) => ref.read(recordActionsProvider).switchBreastSide(r, v),
            items: [
              (key: 'left', label: tr('Sol'), small: _msClock(leftMs)),
              (key: 'right', label: tr('Sağ'), small: _msClock(rightMs)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
              color: fieldBg(context), borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(trp('{side} EMZİRME SÜRESİ',
                  {'side': side == 'left' ? tr('SOL') : tr('SAĞ')}),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.muted,
                      letterSpacing: 0.5)),
              const SizedBox(height: 5),
              Text(_msClock(activeMs),
                  style: TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      color: accent,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 5),
              Text(paused ? tr('duraklatıldı') : tr('arka planda devam eder'),
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: AdSaveButton(
                label: paused ? tr('Devam et') : tr('Durdur'),
                color: accent,
                ghost: true,
                onTap: () => paused
                    ? ref.read(recordActionsProvider).resumeBreast(r)
                    : ref.read(recordActionsProvider).pauseBreast(r),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AdSaveButton(
                label: tr('Kaydet'),
                color: accent,
                onTap: () => _askEditAndSave(r),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Kaydetmeden önce süreleri elle düzenleme görünümü (süren kayıt için).
  Widget _breastEditDurations(Record r, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(tr('Ölçülen süreleri düzenleyip kaydet'), style: _breastLabelStyle),
        ),
        _breastMinuteRow(accent),
        const SizedBox(height: 4),
        AdSaveButton(
          label: tr('Kaydet'),
          color: accent,
          onTap: () async {
            await ref.read(recordActionsProvider).stopBreastWithMinutes(
                r, _num('left_min') ?? 0, _num('right_min') ?? 0);
            if (!mounted) return;
            showAdToast(context, tr('Kaydedildi'));
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  /// Elle giriş: Sol/Sağ dakika stepper'ları (genel Kaydet butonu kaydeder).
  Widget _breastManual(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _breastMinuteRow(accent),
        if (!_editing)
          _linkButton(tr('Kronometreye dön'), () => setState(() => _manualBreast = false)),
      ],
    );
  }

  Widget _breastMinuteRow(Color accent) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AdField(
              label: tr('Sol (dk)'),
              child: AdStepper(
                  controller: ctl('left_min', _initFor('left_min')),
                  unit: tr('dk'),
                  accent: accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AdField(
              label: tr('Sağ (dk)'),
              child: AdStepper(
                  controller: ctl('right_min', _initFor('right_min')),
                  unit: tr('dk'),
                  accent: accent),
            ),
          ),
        ],
      );

  /// Süren emzirmede her memenin canlı (ms) toplamı — aktif segment dahil.
  (int, int) _accruedMs(Map<String, dynamic> d) {
    var l = ((d['left_ms'] as num?) ?? 0).toInt();
    var r = ((d['right_ms'] as num?) ?? 0).toInt();
    final segStart = DateTime.tryParse(d['seg_start_ts'] as String? ?? '')?.toLocal();
    if (segStart != null && d['paused'] != true) {
      final add = DateTime.now().difference(segStart).inMilliseconds;
      if (add > 0) {
        if (d['side'] == 'right') {
          r += add;
        } else {
          l += add;
        }
      }
    }
    return (l, r);
  }

  String _msClock(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Kaydetmeden önce "elle düzenle?" sorar; seçime göre kaydeder veya düzenleme
  /// görünümüne (ölçülen dakikalar input'lara set edilmiş) geçer.
  Future<void> _askEditAndSave(Record r) async {
    final (lMs, rMs) = _accruedMs(r.data);
    final choice = await _askEditDurationsDialog();
    if (!mounted || choice == null) return; // iptal → sayaç olduğu gibi kalır
    if (choice == 'save') {
      await ref.read(recordActionsProvider).stopBreast(r);
      if (!mounted) return;
      showAdToast(context, tr('Kaydedildi'));
      Navigator.pop(context);
    } else {
      ctl('left_min').text = (lMs / 60000).round().toString();
      ctl('right_min').text = (rMs / 60000).round().toString();
      await ref.read(recordActionsProvider).pauseBreast(r); // düzenlerken sayma dursun
      if (!mounted) return;
      setState(() => _editDurations = true);
    }
  }

  /// Link görünümlü, az yer kaplayan metin butonu (buton zemini yok).
  Widget _linkButton(String text, VoidCallback onTap) => Align(
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.coralDark,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.coralDark)),
          ),
        ),
      );

  // ── Bez: dışkı detayı (renk / kıvam) ─────────────────────────────────────

  List<String> get _stoolOptions => [
        tr('Sarı · normal'),
        tr('Hardal · normal'),
        tr('Yeşil'),
        tr('Kahverengi'),
        tr('Koyu / siyah'),
        tr('Sulu / ishal'),
        tr('Sert / kabız'),
        tr('Mukuslu'),
      ];

  List<Widget> _diaperDetailFields() {
    return [
      // design .ad-toggle-detail — coral, zeminsiz aç/kapa.
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _diaperDetail = !_diaperDetail),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdenaIcon(_diaperDetail ? 'chevD' : 'plus',
                  size: 15, color: AppColors.coralDark),
              const SizedBox(width: 5),
              Text(
                  _diaperDetail
                      ? tr('Dışkı detayını gizle')
                      : tr('Dışkı detayı ekle (opsiyonel)'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.coralDark)),
            ],
          ),
        ),
      ),
      if (_diaperDetail)
        AdField(
          label: tr('Renk / kıvam'),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pickStool,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              child: Row(
                children: [
                  Text(_stool.isEmpty ? tr('Seç') : _stool,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _stool.isEmpty ? AppColors.muted : null)),
                  const Spacer(),
                  AdenaIcon('chevD', size: 18, color: AppColors.muted2),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Future<void> _pickStool() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: adSheetShape,
      isScrollControlled: true, // uzun liste → taşma yerine kaydırılsın
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: adGrabHandle()),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('Renk / kıvam'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final o in _stoolOptions)
                    ListTile(
                      dense: true,
                      title: Text(o, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: o == _stool
                          ? const AdenaIcon('check', size: 18, color: AppColors.coral)
                          : null,
                      onTap: () => Navigator.pop(ctx, o),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _stool = picked);
  }

  /// design .ad-nexttag — coral zeminli küçük pill.
  Widget _nextTag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: const TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white)),
      );

  /// "Süreleri düzenle?" diyaloğu — 'save' / 'edit' / null (iptal).
  Future<String?> _askEditDurationsDialog() => showEditDurationsDialog(context);

  // ── Uyku bölümü: başlat / süren sayaç / elle giriş ───────────────────────

  Widget _sleepSection(Color accent) {
    // Düzenleme her zaman manuel chip gösterir (süren kaydı düzenleme dahil).
    if (_editing) return _sleepManual(accent);
    final ongoing = ref.watch(ongoingSleepProvider(widget.babyId));
    if (ongoing != null) {
      return _sleepEditDurations
          ? _sleepEditView(ongoing, accent)
          : _sleepRunning(ongoing, accent);
    }
    if (_manualSleep) return _sleepManual(accent);
    return _sleepStart(accent);
  }

  /// Başlamadan önce: Başlat + "Manuel gir" linki.
  Widget _sleepStart(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoNote(tr('Başlat\'a bas → uyku arka planda sayılır ve bildirimde görünür. '
            'Bebek uyanınca bitir; istersen süreyi düzeltirsin.')),
        const SizedBox(height: 14),
        AdSaveButton(
          label: tr('Uykuyu başlat'),
          color: accent,
          onTap: () => ref.read(recordActionsProvider).startSleep(widget.babyId),
        ),
        const SizedBox(height: 8),
        _linkButton(tr('Manuel gir'), () => setState(() => _manualSleep = true)),
      ],
    );
  }

  /// Süren uyku: canlı sayaç + "Uykuyu bitir" (bitirirken süreyi düzenleme sorar).
  Widget _sleepRunning(Record r, Color accent) {
    final start =
        DateTime.tryParse(r.data['start_ts'] as String? ?? '')?.toLocal() ?? r.ts;
    final d = DateTime.now().difference(start);
    final clock = '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
              color: AppColors.sleepBg, borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(tr('UYKU SÜRESİ'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.sleep,
                      letterSpacing: 0.5)),
              const SizedBox(height: 5),
              Text(clock,
                  style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      color: AppColors.sleep,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 5),
              Text(
                  trp('arka planda devam eder · {time}\'de başladı',
                      {'time': fmtTime(start)}),
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ],
          ),
        ),
        const SizedBox(height: 13),
        AdSaveButton(
            label: tr('Uykuyu bitir'), color: accent, onTap: () => _askEditAndSaveSleep(r)),
      ],
    );
  }

  /// Elle giriş / düzenleme: başlangıç + bitiş zaman çipleri (genel _save kaydeder).
  Widget _sleepManual(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._sleepChips(),
        const SizedBox(height: 8),
        AdSaveButton(
            label: _editing ? tr('Güncelle') : tr('Kaydet'), color: accent, onTap: _save),
        if (!_editing)
          _linkButton(tr('Kronometreye dön'), () => setState(() => _manualSleep = false)),
      ],
    );
  }

  /// Bitirirken süreyi elle düzenleme görünümü (süren kayıt için).
  Widget _sleepEditView(Record r, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(tr('Uyku süresini düzenleyip kaydet'), style: _breastLabelStyle),
        ),
        ..._sleepChips(),
        const SizedBox(height: 8),
        AdSaveButton(
          label: tr('Kaydet'),
          color: accent,
          onTap: () async {
            if (_endTs == null) return _warn(tr('Bitiş zamanını seç'));
            await ref
                .read(recordActionsProvider)
                .stopSleepWithTimes(r, _ts, _endTs!);
            if (!mounted) return;
            showAdToast(context, tr('Kaydedildi'));
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  List<Widget> _sleepChips() => [
        AdField(
          label: tr('Başlangıç'),
          child: AdTimeChip(
              value: _ts, onTap: () => _pick(_ts, (dt) => setState(() => _ts = dt))),
        ),
        AdField(
          label: tr('Bitiş'),
          child: AdTimeChip(
              value: _endTs,
              onTap: () => _pick(
                  _endTs ?? DateTime.now(), (dt) => setState(() => _endTs = dt))),
        ),
      ];

  /// "Uykuyu bitir" → süreyi düzenleme sorusu; istenirse yerinde manuel çiplere geçer.
  Future<void> _askEditAndSaveSleep(Record r) async {
    final choice = await _askEditDurationsDialog();
    if (!mounted || choice == null) return;
    if (choice == 'save') {
      await ref.read(recordActionsProvider).stopSleep(r);
      if (!mounted) return;
      showAdToast(context, tr('Kaydedildi'));
      Navigator.pop(context);
    } else {
      final start =
          DateTime.tryParse(r.data['start_ts'] as String? ?? '')?.toLocal() ?? r.ts;
      setState(() {
        _ts = start;
        _endTs = DateTime.now();
        _sleepEditDurations = true;
      });
    }
  }

  Widget _mlStepper(Color accent) => AdStepper(
        controller: ctl('ml', _initFor('ml')),
        unit: _units.volumeLabel,
        step: _units.volume == 'oz' ? 1 : 10,
        decimals: _units.volume == 'oz' ? 1 : 0,
        accent: accent,
      );

  Widget _noteInput() => AdInput(
        controller: ctl('note', _initFor('note')),
        hint: tr('isteğe bağlı'),
        capitalization: TextCapitalization.sentences,
      );

  /// Bilgi notu (design .ad-note) — şeftali zeminli açıklama.
  Widget _infoNote(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.peachLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                height: 1.4)),
      );

  /// Alan başlangıç değeri (kanonik → tercih birimi). Not/tepki yeni kayıtta
  /// tekrarlanmaz.
  String _initFor(String key) {
    if (!_editing && (key == 'note' || key == 'reaction')) return '';
    final v = _prefill[key];
    if (v == null) return '';
    // Katı miktarı sayısal stepper; eski string ("2 kaşık") kayıtlardan sayıyı çıkar.
    if (key == 'amount') return RegExp(r'\d+(\.\d+)?').firstMatch('$v')?.group(0) ?? '';
    if (v is num) {
      switch (key) {
        case 'ml':
          return _units.editValue(_units.volumeFromCanonical(v), decimal: _units.volume == 'oz');
        case 'weight':
          return _units.editValue(_units.weightFromCanonical(v), decimal: true);
        case 'height':
        case 'head_circ':
          return _units.editValue(_units.lengthFromCanonical(v), decimal: true);
      }
    }
    return '$v';
  }

  Future<void> _pick(DateTime initial, ValueChanged<DateTime> onPick) async {
    final dt = await _pickDateTime(initial);
    if (dt != null) onPick(dt);
  }
}

/// "Süreyi düzenle?" diyaloğu — 'save' (ölçülenle kaydet) / 'edit' (elle düzelt)
/// / null (iptal). Uyku ve emzirme bitirilirken kullanılır.
Future<String?> showEditDurationsDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(tr('Süreyi düzenle?'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      content: Text(
          tr('Ölçülen süreyle kaydedebilir ya da süreleri elle düzeltebilirsin.'),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: Text(tr('Elle düzenle'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Kaydet'))),
      ],
    ),
  );
}

/// Süren uykuyu bitirirken (ana ekran banner'ı / hızlı kart) süreyi düzenleme
/// sorar. "Elle düzenle" → uyku formu düzenleme modunda açılır (bitiş = şimdi).
Future<void> confirmStopSleep(
    BuildContext context, WidgetRef ref, Record sleep) async {
  final choice = await showEditDurationsDialog(context);
  if (choice == null) return;
  if (choice == 'edit') {
    if (context.mounted) {
      showRecordForm(context, ref, sleep.baby, RecordType.sleep, existing: sleep);
    }
  } else {
    await ref.read(recordActionsProvider).stopSleep(sleep);
    if (context.mounted) showAdToast(context, tr('Kaydedildi'));
  }
}

/// Seçili belirti için evde bakım + "ne zaman doktora" rehber kartı.
/// Genel bilgilendirmedir; tıbbi tanı yerine geçmez.
class _SymptomInfoCard extends StatelessWidget {
  final SymptomKind symptom;
  const _SymptomInfoCard({required this.symptom});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: AppColors.symptomBg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(symptom.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trp('{s} · bakım rehberi', {'s': symptom.label}),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.symptom)),
                const SizedBox(height: 3),
                Text(symptom.info,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Belirti kataloğu seçim ızgarası (emoji + etiket pill'leri, akışkan Wrap).
/// Seçili pill mercan kenarlık + belirti zemini alır.
class _SymptomGrid extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _SymptomGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in kSymptoms)
          _pill(context, s),
      ],
    );
  }

  Widget _pill(BuildContext context, SymptomKind s) {
    final on = s.key == selected;
    return GestureDetector(
      onTap: () => onSelect(s.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.symptomBg : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: on ? AppColors.symptom : AppColors.line, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 7),
            Text(s.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: on ? AppColors.symptom : AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

/// Randevu "Özel" hatırlatma süresi için − N saat + satırı.
class _LeadStepRow extends StatelessWidget {
  final int hours;
  final ValueChanged<int> onChanged;
  const _LeadStepRow({required this.hours, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration:
          BoxDecoration(color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          _btn('−', hours > 1 ? () => onChanged(hours - 1) : null),
          Expanded(
            child: Text(trp('{hours} saat önce', {'hours': hours}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          ),
          _btn('+', hours < 72 ? () => onChanged(hours + 1) : null),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback? onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: onTap == null ? AppColors.muted2 : AppColors.coralDark)),
          ),
        ),
      );
}

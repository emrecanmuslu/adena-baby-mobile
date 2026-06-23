import 'package:flutter/foundation.dart';

import '../data/slot_registry.dart';

/// Bebek durumu: gebelik (bekleme) / doğmuş (takip).
enum BabyStatus { expecting, born }

enum BabyGender { male, female, unknown }

/// Bebek modeli — API_SOZLESME.md §2.
@immutable
class Baby {
  final String id;
  final String name;
  final BabyGender gender;
  final String? photo;
  final BabyStatus status;
  final DateTime? birthDate;
  final DateTime? dueDate;
  final DateTime? lastMenstrualDate;
  /// Doğumdaki gebelik haftası (prematüre desteği). null = bilinmiyor/zamanında.
  final int? gestationalWeeks;
  /// Gebelik haftasının üstüne gün (0..6).
  final int gestationalDays;
  final String? myRole; // owner|parent|caregiver
  final int memberCount; // bebeği paylaşan üye sayısı (varsayılan 1 = tek kullanıcı)

  const Baby({
    required this.id,
    required this.name,
    this.gender = BabyGender.unknown,
    this.photo,
    this.status = BabyStatus.born,
    this.birthDate,
    this.dueDate,
    this.lastMenstrualDate,
    this.gestationalWeeks,
    this.gestationalDays = 0,
    this.myRole,
    this.memberCount = 1,
  });

  bool get isExpecting => status == BabyStatus.expecting;

  /// Bebek erken mi doğdu? Gebelik < 37 hafta = prematüre. Büyüme/gelişim
  /// düzeltilmiş yaşa göre değerlendirilir (bkz core/age.dart). Aşı takvim yaşında.
  bool get isPremature => gestationalWeeks != null && gestationalWeeks! < 37;

  /// Bebek birden fazla kişiyle mi paylaşılıyor? Paylaşımsızsa (tek üye) istemci
  /// periyodik sync/aktivite yoklamasını yapmaz — başka yazan olmadığından veri
  /// yalnız uygulama açılınca + kayıt yazınca güncellenir (boşa istek atılmaz).
  bool get isShared => memberCount > 1;

  /// Tam yazma yetkisi (owner/parent). Bakıcı (caregiver) hariç — sağlık/anı/anne
  /// takibi salt-okunur ya da gizli, kayıtlarda yalnız kendi eklediğine dokunabilir.
  /// myRole null (tek kullanıcı/eski veri) → tam yetki varsay.
  bool get canFullWrite => myRole == null || myRole == 'owner' || myRole == 'parent';

  /// Yalnız izleyen bakıcı mı?
  bool get isCaregiver => myRole == 'caregiver';

  /// Bildirim id "slot"u — çok-bebekte sayaç/beslenme bildirimleri çakışmasın diye
  /// bebek başına KALICI, BENZERSİZ slot (SlotRegistry). Eski `hashCode % 1000`
  /// nadiren çakışıyordu; registry çakışmayı imkânsız kılar. main()'de load edilir.
  int get notifSlot => SlotRegistry.instance.slotFor(id);

  factory Baby.fromJson(Map<String, dynamic> json) => Baby(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        gender: _genderFrom(json['gender'] as String?),
        photo: json['photo'] as String?,
        status: (json['status'] as String?) == 'expecting'
            ? BabyStatus.expecting
            : BabyStatus.born,
        birthDate: _date(json['birth_date']),
        dueDate: _date(json['due_date']),
        lastMenstrualDate: _date(json['last_menstrual_date']),
        gestationalWeeks: (json['gestational_age_weeks'] as num?)?.toInt(),
        gestationalDays: (json['gestational_age_days'] as num?)?.toInt() ?? 0,
        myRole: json['my_role'] as String?,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 1,
      );

  /// POST /babies için gövde. id istemci-üretimli (offline-first).
  Map<String, dynamic> toCreateJson() => {
        'id': id,
        'name': name,
        if (gender != BabyGender.unknown) 'gender': gender.name,
        'status': status.name,
        if (birthDate != null) 'birth_date': _isoDate(birthDate!),
        if (dueDate != null) 'due_date': _isoDate(dueDate!),
        if (lastMenstrualDate != null) 'last_menstrual_date': _isoDate(lastMenstrualDate!),
        if (gestationalWeeks != null) 'gestational_age_weeks': gestationalWeeks,
        'gestational_age_days': gestationalDays,
      };

  Baby copyWith({
    String? name,
    BabyGender? gender,
    String? photo,
    BabyStatus? status,
    DateTime? birthDate,
    DateTime? dueDate,
    DateTime? lastMenstrualDate,
    int? gestationalWeeks,
    int? gestationalDays,
    String? myRole,
    int? memberCount,
  }) =>
      Baby(
        id: id,
        name: name ?? this.name,
        gender: gender ?? this.gender,
        photo: photo ?? this.photo,
        status: status ?? this.status,
        birthDate: birthDate ?? this.birthDate,
        dueDate: dueDate ?? this.dueDate,
        lastMenstrualDate: lastMenstrualDate ?? this.lastMenstrualDate,
        gestationalWeeks: gestationalWeeks ?? this.gestationalWeeks,
        gestationalDays: gestationalDays ?? this.gestationalDays,
        myRole: myRole ?? this.myRole,
        memberCount: memberCount ?? this.memberCount,
      );

  static BabyGender _genderFrom(String? v) => switch (v) {
        'male' => BabyGender.male,
        'female' => BabyGender.female,
        _ => BabyGender.unknown,
      };

  static DateTime? _date(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

  /// Sadece tarih (YYYY-MM-DD) — API doğum/tahmini tarih alanları gün hassasiyetinde.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

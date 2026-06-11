import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/milestone.dart';
import '../models/reminder.dart';
import '../models/vaccine.dart';

/// Sağlık uçları: aşı takvimi (lazy üretim sunucuda) + işaretleme,
/// ve hatırlatıcılar (CRUD).
class HealthRepository {
  final ApiClient _api;
  HealthRepository(this._api);

  Future<List<Vaccine>> vaccines(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/vaccines');
    final data = resp.data as List<dynamic>;
    return data.map((e) => Vaccine.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Aşıyı yapıldı/bekliyor olarak işaretler.
  Future<Vaccine> setStatus(int id, {required bool done, DateTime? doneDate}) async {
    final date = done ? (doneDate ?? DateTime.now()) : null;
    final resp = await _api.dio.patch('/vaccines/$id', data: {
      'status': done ? 'done' : 'pending',
      'done_date': date == null
          ? null
          : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    });
    return Vaccine.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── Gelişim / kilometre taşları ──

  Future<List<Milestone>> milestones(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/milestones');
    final data = resp.data as List<dynamic>;
    return data.map((e) => Milestone.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Kilometre taşını başarıldı/bekliyor işaretler (tarih opsiyonel; bugün varsayılan).
  Future<Milestone> setMilestoneAchieved(int id,
      {required bool achieved, DateTime? date}) async {
    final d = achieved ? (date ?? DateTime.now()) : null;
    final resp = await _api.dio.patch('/milestones/$id', data: {
      'achieved': achieved,
      if (d != null)
        'achieved_date':
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    });
    return Milestone.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── Hatırlatıcılar ──

  Future<List<Reminder>> reminders(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/reminders');
    final data = resp.data as List<dynamic>;
    return data.map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Reminder> createReminder(String babyId,
      {required String type, required Map<String, dynamic> schedule}) async {
    final resp = await _api.dio.post('/babies/$babyId/reminders',
        data: {'type': type, 'schedule': schedule, 'enabled': true});
    return Reminder.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Reminder> setReminderEnabled(int id, bool enabled) async {
    final resp = await _api.dio.patch('/reminders/$id', data: {'enabled': enabled});
    return Reminder.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteReminder(int id) async {
    await _api.dio.delete('/reminders/$id');
  }
}

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(apiClientProvider)),
);

/// Aktif bebeğin aşıları (due_date'e göre sıralı gelir).
final vaccinesProvider = FutureProvider.family<List<Vaccine>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).vaccines(babyId),
);

/// Aktif bebeğin hatırlatıcıları.
final remindersProvider = FutureProvider.family<List<Reminder>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).reminders(babyId),
);

/// Aktif bebeğin gelişim/kilometre taşları (beklenen aya göre sıralı).
final milestonesProvider = FutureProvider.family<List<Milestone>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).milestones(babyId),
);

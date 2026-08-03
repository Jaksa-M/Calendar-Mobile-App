import 'package:dio/dio.dart';

import '../models/appointment.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'api_exception.dart';

class AppointmentApi {
  AppointmentApi(this._client);
  final ApiClient _client;

  Future<User> me() async {
    final resp = await _client.dio.get('/users/me');
    _ensureOk(resp, 'Failed to load current user');
    return User.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<User>> users() async {
    final resp = await _client.dio.get('/users');
    _ensureOk(resp, 'Failed to load users');
    return (resp.data as List)
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Appointment>> sharedCalendar() => _list('/appointments/shared');

  Future<List<Appointment>> myCalendar() => _list('/appointments/me');

  /// Book a shared appointment. Throws [ApiException] with `isConflict == true`
  /// (and `conflictUserIds`) if a participant is busy.
  Future<Appointment> createShared({
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    required List<int> participantIds,
  }) async {
    final resp = await _client.dio.post('/appointments', data: {
      'title': title,
      'description': description,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'participant_ids': participantIds,
    });
    if (resp.statusCode == 201) {
      return Appointment.fromJson(resp.data as Map<String, dynamic>);
    }
    throw _bookingError(resp);
  }

  /// Add a personal block to the caller's own private calendar.
  Future<Appointment> createPrivate({
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final resp = await _client.dio.post('/appointments/private', data: {
      'title': title,
      'description': description,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
    });
    if (resp.statusCode == 201) {
      return Appointment.fromJson(resp.data as Map<String, dynamic>);
    }
    throw _bookingError(resp);
  }

  /// Set the caller's RSVP for an appointment they're invited to.
  Future<Appointment> respond(int appointmentId, RsvpStatus response) async {
    final value = response == RsvpStatus.yes
        ? 'yes'
        : response == RsvpStatus.no
            ? 'no'
            : 'pending';
    final resp = await _client.dio.post(
      '/appointments/$appointmentId/response',
      data: {'response': value},
    );
    _ensureOk(resp, 'Failed to save your response');
    return Appointment.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Request suggestions for the earliest free slots for all participants.
  Future<List<({DateTime start, DateTime end})>> suggest({
    required List<int> participantIds,
    required int durationMinutes,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final resp = await _client.dio.post('/appointments/suggest', data: {
      'participant_ids': participantIds,
      'duration_minutes': durationMinutes,
      'window_start': windowStart.toUtc().toIso8601String(),
      'window_end': windowEnd.toUtc().toIso8601String(),
    });
    _ensureOk(resp, 'Failed to suggest a time');
    return (resp.data['slots'] as List)
        .map((s) => (
              start: DateTime.parse(s['starts_at'] as String).toLocal(),
              end: DateTime.parse(s['ends_at'] as String).toLocal(),
            ))
        .toList();
  }

  Future<void> delete(int id) async {
    final resp = await _client.dio.delete('/appointments/$id');
    if (resp.statusCode != 204) _ensureOk(resp, 'Failed to delete appointment');
  }

  Future<List<Appointment>> _list(String path) async {
    final resp = await _client.dio.get(path);
    _ensureOk(resp, 'Failed to load calendar');
    return (resp.data as List)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _ensureOk(Response resp, String fallback) {
    final code = resp.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    throw ApiException(_detailString(resp) ?? fallback, statusCode: code);
  }

  ApiException _bookingError(Response resp) {
    // 409 detail is a structured object: {detail, conflicting_user_ids}.
    final data = resp.data;
    if (resp.statusCode == 409 && data is Map && data['detail'] is Map) {
      final d = data['detail'] as Map;
      return ApiException(
        d['detail'] as String? ?? 'Time slot is not free.',
        statusCode: 409,
        conflictUserIds: ((d['conflicting_user_ids'] as List?) ?? [])
            .map((e) => e as int)
            .toList(),
      );
    }
    return ApiException(
      _detailString(resp) ?? 'Could not create appointment',
      statusCode: resp.statusCode,
    );
  }

  String? _detailString(Response resp) {
    final data = resp.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return null;
  }
}

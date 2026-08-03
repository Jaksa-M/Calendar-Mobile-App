import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment.dart';

/// Local scheduled reminders for upcoming appointments.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'appointment_reminders';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Appointment reminders',
      channelDescription: 'Reminders before your appointments',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    const channel = AndroidNotificationChannel(
      _channelId,
      'Appointment reminders',
      description: 'Reminders before your appointments',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _ready = true;
  }

  /// Ask for the notification + exact-alarm permissions (Android 13+/12+).
  Future<void> requestPermission() async {
    if (!_ready) await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> cancelAll() async {
    if (!_ready) await init();
    await _plugin.cancelAll();
  }

  /// Show an immediate notification (used for polled events + confirmations).
  Future<void> show(String title, String body) async {
    if (!_ready) await init();
    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _plugin.show(id, title, body, _details);
  }

  /// Reschedule reminders for all future appointments, [leadMinutes] before start.
  Future<void> scheduleReminders(
    List<Appointment> appointments, {
    int leadMinutes = 10,
  }) async {
    if (!_ready) await init();
    await _plugin.cancelAll();

    final now = DateTime.now();
    var id = 0;
    for (final a in appointments) {
      final fireAt = a.startsAt.subtract(Duration(minutes: leadMinutes));
      if (!fireAt.isAfter(now)) continue; // skip past reminders
      await _plugin.zonedSchedule(
        id++,
        a.title,
        'Starts at ${DateFormat.Hm().format(a.startsAt)}',
        tz.TZDateTime.from(fireAt.toUtc(), tz.UTC),
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}

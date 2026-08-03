import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/appointment_api.dart';
import '../api/auth_api.dart';
import '../api/integration_api.dart';
import '../api/notification_api.dart';
import 'notifications_controller.dart';
import '../models/appointment.dart';
import '../models/user.dart';
import 'auth_controller.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(secureStorageProvider)),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

final appointmentApiProvider = Provider<AppointmentApi>(
  (ref) => AppointmentApi(ref.watch(apiClientProvider)),
);

final integrationApiProvider = Provider<IntegrationApi>(
  (ref) => IntegrationApi(ref.watch(apiClientProvider)),
);

final notificationApiProvider = Provider<NotificationApi>(
  (ref) => NotificationApi(ref.watch(apiClientProvider)),
);

/// Polls for notifications while the user is logged in.
final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
  final controller = NotificationsController(ref.watch(notificationApiProvider));
  if (ref.watch(authControllerProvider).status == AuthStatus.authenticated) {
    controller.start();
  }
  return controller;
});

/// Whether Google Calendar is connected for the current user.
final googleStatusProvider = FutureProvider<bool>((ref) async {
  ref.watch(authControllerProvider);
  ref.watch(calendarRefreshProvider);
  return ref.watch(integrationApiProvider).googleStatus();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(apiClientProvider),
    ref.watch(authApiProvider),
    ref.watch(appointmentApiProvider),
  )..restore();
});

/// All users (for the participant picker). Auto-refreshes after login.
final usersProvider = FutureProvider<List<User>>((ref) async {
  // Re-fetch when auth changes.
  ref.watch(authControllerProvider);
  return ref.watch(appointmentApiProvider).users();
});

/// The shared (team) calendar.
final sharedCalendarProvider = FutureProvider<List<Appointment>>((ref) async {
  // Re-fetch when the logged-in user changes (login/logout) or on refresh.
  ref.watch(authControllerProvider);
  ref.watch(calendarRefreshProvider);
  return ref.watch(appointmentApiProvider).sharedCalendar();
});

/// The current user's private calendar.
final myCalendarProvider = FutureProvider<List<Appointment>>((ref) async {
  // Crucially depends on WHO is logged in — without this, switching users
  // would show the previous user's cached calendar.
  ref.watch(authControllerProvider);
  ref.watch(calendarRefreshProvider);
  return ref.watch(appointmentApiProvider).myCalendar();
});

/// Bump this to force both calendars to reload (e.g. after creating/deleting).
final calendarRefreshProvider = StateProvider<int>((ref) => 0);

/// Whether appointment reminders are enabled.
final remindersEnabledProvider = StateProvider<bool>((ref) => true);

/// How many minutes before an appointment the reminder fires.
final reminderLeadMinutesProvider = StateProvider<int>((ref) => 10);

/// The day currently selected on the calendar. The "New" button uses this as
/// the default date for a new appointment.
final selectedDayProvider = StateProvider<DateTime>((ref) => DateTime.now());

extension CalendarRefresh on WidgetRef {
  void refreshCalendars() =>
      read(calendarRefreshProvider.notifier).state++;
}

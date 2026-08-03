import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import 'calendar_view.dart';
import 'create_appointment_screen.dart';
import 'google_menu.dart';
import 'notifications_screen.dart';
import 'reminders_menu.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// (Re)schedule reminders from the current calendar + settings.
  void _syncReminders(WidgetRef ref) {
    final appts = ref.read(myCalendarProvider).asData?.value;
    if (appts == null) return;
    if (ref.read(remindersEnabledProvider)) {
      NotificationService.instance.scheduleReminders(
        appts.where((a) => a.scope == AppointmentScope.shared ||
            a.scope == AppointmentScope.private).toList(),
        leadMinutes: ref.read(reminderLeadMinutesProvider),
      );
    } else {
      NotificationService.instance.cancelAll();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;

    // Reschedule reminders whenever the calendar or reminder settings change.
    ref.listen(myCalendarProvider, (_, _) => _syncReminders(ref));
    ref.listen(remindersEnabledProvider, (_, _) => _syncReminders(ref));
    ref.listen(reminderLeadMinutesProvider, (_, _) => _syncReminders(ref));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(user == null ? 'Calendar' : 'Hi, ${user.displayName}'),
          actions: [
            const InboxButton(),
            const ReminderMenuButton(),
            const GoogleMenuButton(),
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.groups), text: 'Shared'),
              Tab(icon: Icon(Icons.person), text: 'My calendar'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CalendarView(scope: CalendarScope.shared),
            CalendarView(scope: CalendarScope.mine),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('New'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateAppointmentScreen(
                initialDate: ref.read(selectedDayProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/appointment.dart';
import '../models/user.dart';
import '../state/providers.dart';
import 'appointment_detail_sheet.dart';

enum CalendarScope { shared, mine }

/// A month calendar plus an agenda for the selected day. Shared with both the
/// team calendar and the user's private calendar via [scope].
class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key, required this.scope});

  final CalendarScope scope;

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  static DateTime _key(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final provider = widget.scope == CalendarScope.shared
        ? sharedCalendarProvider
        : myCalendarProvider;
    final async = ref.watch(provider);
    final usersById = ref.watch(usersProvider).maybeWhen(
          data: (users) => {for (final u in users) u.id: u},
          orElse: () => <int, User>{},
        );

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorRetry(
        message: '$e',
        onRetry: () => ref.refreshCalendars(),
      ),
      data: (appointments) {
        final byDay = <DateTime, List<Appointment>>{};
        for (final a in appointments) {
          byDay.putIfAbsent(_key(a.startsAt), () => []).add(a);
        }
        final dayItems = (byDay[_key(_selectedDay)] ?? [])
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

        return RefreshIndicator(
          onRefresh: () async => ref.refreshCalendars(),
          child: ListView(
            children: [
              TableCalendar<Appointment>(
                firstDay: DateTime.utc(2020),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
                eventLoader: (day) => byDay[_key(day)] ?? const [],
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                  // Remember it so the "New" button defaults to this day.
                  ref.read(selectedDayProvider.notifier).state = selected;
                },
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: Theme.of(context)
                      .textTheme
                      .titleMedium!
                      .copyWith(fontWeight: FontWeight.w700),
                  leftChevronIcon: Icon(Icons.chevron_left,
                      color: Theme.of(context).colorScheme.primary),
                  rightChevronIcon: Icon(Icons.chevron_right,
                      color: Theme.of(context).colorScheme.primary),
                ),
                calendarStyle: CalendarStyle(
                  markersMaxCount: 3,
                  todayDecoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  DateFormat.yMMMMEEEEd().format(_selectedDay),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (dayItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No appointments this day.')),
                )
              else
                ...dayItems.map((a) => _AppointmentTile(
                      appointment: a,
                      usersById: usersById,
                    )),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }
}

class _AppointmentTile extends ConsumerWidget {
  const _AppointmentTile({required this.appointment, required this.usersById});

  final Appointment appointment;
  final Map<int, User> usersById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DateFormat.Hm();
    final isShared = appointment.scope == AppointmentScope.shared;
    final names = appointment.participantIds
        .map((id) => usersById[id]?.displayName ?? '#$id')
        .join(', ');
    final currentUserId = ref.watch(_currentUserIdProvider);
    final myResponse =
        currentUserId == null ? null : appointment.responseFor(currentUserId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: false,
          builder: (_) => AppointmentDetailSheet(
            appointment: appointment,
            usersById: usersById,
          ),
        ),
        leading: CircleAvatar(
          child: Icon(isShared ? Icons.groups : Icons.lock_outline),
        ),
        title: Text(appointment.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.format(appointment.startsAt)} – '
                '${t.format(appointment.endsAt)}'),
            if (appointment.description?.isNotEmpty ?? false)
              Text(appointment.description!),
            if (isShared)
              Text('With: $names',
                  style: Theme.of(context).textTheme.bodySmall),
            if (isShared && myResponse != null) _MyRsvpHint(status: myResponse),
          ],
        ),
        trailing: appointment.createdBy == currentUserId
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, ref),
              )
            : null,
        isThreeLine: true,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete appointment?'),
        content: Text('"${appointment.title}" will be removed from all '
            'participants\' calendars.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(appointmentApiProvider).delete(appointment.id);
      ref.refreshCalendars();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

/// Convenience: the logged-in user's id (or null).
final _currentUserIdProvider = Provider<int?>((ref) {
  return ref.watch(authControllerProvider).user?.id;
});

/// Small line under a shared appointment showing the current user's own RSVP.
class _MyRsvpHint extends StatelessWidget {
  const _MyRsvpHint({required this.status});
  final RsvpStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      RsvpStatus.yes => (Icons.check_circle, Colors.green, 'You: Going'),
      RsvpStatus.no => (
          Icons.cancel,
          Theme.of(context).colorScheme.error,
          'You: Not going'
        ),
      RsvpStatus.pending => (
          Icons.touch_app,
          Theme.of(context).colorScheme.primary,
          'Tap to respond'
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/api_exception.dart';
import '../models/appointment.dart';
import '../models/user.dart';
import '../state/providers.dart';

/// Bottom sheet shown when tapping an appointment. Shows the participants and
/// their RSVPs, and — if the current user was invited to a shared appointment —
/// lets them respond Going / Not going.
class AppointmentDetailSheet extends ConsumerStatefulWidget {
  const AppointmentDetailSheet({
    super.key,
    required this.appointment,
    required this.usersById,
  });

  final Appointment appointment;
  final Map<int, User> usersById;

  @override
  ConsumerState<AppointmentDetailSheet> createState() =>
      _AppointmentDetailSheetState();
}

class _AppointmentDetailSheetState
    extends ConsumerState<AppointmentDetailSheet> {
  late Appointment _appt = widget.appointment;
  bool _saving = false;

  String _name(int id) =>
      widget.usersById[id]?.displayName ?? 'User #$id';

  Future<void> _respond(RsvpStatus status) async {
    setState(() => _saving = true);
    try {
      final updated =
          await ref.read(appointmentApiProvider).respond(_appt.id, status);
      setState(() => _appt = updated);
      ref.refreshCalendars(); // keep the calendars in sync
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authControllerProvider).user?.id;
    final myResponse = myId == null ? null : _appt.responseFor(myId);
    final isInvitedToShared =
        myResponse != null && _appt.scope == AppointmentScope.shared;
    final t = DateFormat.Hm();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(_appt.title,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                Text('${DateFormat.yMMMEd().format(_appt.startsAt)}   '
                    '${t.format(_appt.startsAt)} – ${t.format(_appt.endsAt)}'),
              ],
            ),
            if (_appt.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_appt.description!)),
                ],
              ),
            ],
            if (_appt.scope == AppointmentScope.shared) ...[
              const SizedBox(height: 20),
              Text('Participants',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              ..._appt.participants.map(
                (p) => _ParticipantRow(
                  name: _name(p.userId),
                  isYou: p.userId == myId,
                  status: p.response,
                ),
              ),
            ],
            if (isInvitedToShared) ...[
              const Divider(height: 28),
              Text('Are you attending?',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _saving
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: myResponse == RsvpStatus.yes
                                ? FilledButton.styleFrom(
                                    backgroundColor: Colors.green)
                                : null,
                            onPressed: () => _respond(RsvpStatus.yes),
                            icon: const Icon(Icons.check),
                            label: const Text('Going'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: myResponse == RsvpStatus.no
                                ? FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error)
                                : FilledButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                            onPressed: () => _respond(RsvpStatus.no),
                            icon: const Icon(Icons.close),
                            label: const Text('Not going'),
                          ),
                        ),
                      ],
                    ),
              if (myResponse != RsvpStatus.pending && !_saving)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () => _respond(RsvpStatus.pending),
                    child: const Text('Clear my response'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.name,
    required this.isYou,
    required this.status,
  });

  final String name;
  final bool isYou;
  final RsvpStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      RsvpStatus.yes => (Icons.check_circle, Colors.green, 'Going'),
      RsvpStatus.no => (
          Icons.cancel,
          Theme.of(context).colorScheme.error,
          'Not going'
        ),
      RsvpStatus.pending => (
          Icons.help_outline,
          Theme.of(context).colorScheme.outline,
          'No response'
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(isYou ? '$name (you)' : name)),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

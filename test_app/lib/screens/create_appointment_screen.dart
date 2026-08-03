import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/api_exception.dart';
import '../models/user.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';

class CreateAppointmentScreen extends ConsumerStatefulWidget {
  const CreateAppointmentScreen({super.key, this.initialDate});

  /// The day to pre-fill (defaults to today when null).
  final DateTime? initialDate;

  @override
  ConsumerState<CreateAppointmentScreen> createState() =>
      _CreateAppointmentScreenState();
}

class _CreateAppointmentScreenState
    extends ConsumerState<CreateAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  bool _shared = true;
  late DateTime _date = widget.initialDate ?? DateTime.now();
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);
  final Set<int> _participants = {};

  bool _submitting = false;
  bool _suggesting = false;
  String? _error;
  List<int> _conflictIds = [];

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime _combine(TimeOfDay t) =>
      DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked != null) {
      setState(() => isStart ? _start = picked : _end = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final startDt = _combine(_start);
    final endDt = _combine(_end);
    if (!endDt.isAfter(startDt)) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }
    if (_shared && _participants.isEmpty) {
      setState(() => _error = 'Pick at least one participant.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _conflictIds = [];
    });

    final api = ref.read(appointmentApiProvider);
    try {
      if (_shared) {
        await api.createShared(
          title: _title.text.trim(),
          description: _description.text.trim(),
          startsAt: startDt,
          endsAt: endDt,
          participantIds: _participants.toList(),
        );
      } else {
        await api.createPrivate(
          title: _title.text.trim(),
          description: _description.text.trim(),
          startsAt: startDt,
          endsAt: endDt,
        );
      }
      await NotificationService.instance.show(
        'Appointment booked',
        '"${_title.text.trim()}" on ${DateFormat.yMMMd().format(startDt)}',
      );
      ref.refreshCalendars();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = describeError(e);
        _conflictIds = e is ApiException ? e.conflictUserIds : [];
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _suggest() async {
    final myId = ref.read(authControllerProvider).user?.id;
    final ids = _shared ? _participants.toList() : (myId == null ? <int>[] : [myId]);
    if (_shared && ids.isEmpty) {
      setState(() => _error = 'Please select participants first.');
      return;
    }

    // Duration from the currently selected time (defaults to 60 min).
    final startDt = _combine(_start);
    final endDt = _combine(_end);
    var minutes = endDt.difference(startDt).inMinutes;
    if (minutes <= 0) minutes = 60;

    setState(() {
      _suggesting = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final slots = await ref.read(appointmentApiProvider).suggest(
            participantIds: ids,
            durationMinutes: minutes,
            windowStart: now,
            windowEnd: now.add(const Duration(days: 14)),
          );
      if (slots.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No free slot in the next 14 days.')));
        }
        return;
      }
      final s = slots.first;
      setState(() {
        _date = DateTime(s.start.year, s.start.month, s.start.day);
        _start = TimeOfDay.fromDateTime(s.start);
        _end = TimeOfDay.fromDateTime(s.end);
      });
      if (mounted) {
        final f = DateFormat('MMM d, HH:mm');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Suggested: ${f.format(s.start)}–'
                '${DateFormat.Hm().format(s.end)}')));
      }
    } catch (e) {
      setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final myId = ref.watch(authControllerProvider).user?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('New appointment')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.groups),
                    label: Text('Shared')),
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.lock_outline),
                    label: Text('Private')),
              ],
              selected: {_shared},
              onSelectionChanged: (s) => setState(() => _shared = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Date'),
                    subtitle: Text(DateFormat.yMMMMEEEEd().format(_date)),
                    onTap: _pickDate,
                  ),
                  const Divider(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          leading: const Icon(Icons.schedule),
                          title: const Text('Start'),
                          subtitle: Text(_start.format(context)),
                          onTap: () => _pickTime(isStart: true),
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          title: const Text('End'),
                          subtitle: Text(_end.format(context)),
                          onTap: () => _pickTime(isStart: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_shared) ...[
              const SizedBox(height: 16),
              Text('Participants',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              usersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Could not load users: $e'),
                data: (users) => _ParticipantList(
                  users: users,
                  selected: _participants,
                  myId: myId,
                  conflictIds: _conflictIds.toSet(),
                  onToggle: (id, on) => setState(
                      () => on ? _participants.add(id) : _participants.remove(id)),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: (_submitting || _suggesting) ? null : _suggest,
              icon: _suggesting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: const Text('Suggest a time'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_shared ? 'Book appointment' : 'Add to my calendar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantList extends StatelessWidget {
  const _ParticipantList({
    required this.users,
    required this.selected,
    required this.myId,
    required this.conflictIds,
    required this.onToggle,
  });

  final List<User> users;
  final Set<int> selected;
  final int? myId;
  final Set<int> conflictIds;
  final void Function(int id, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: users.map((u) {
        final isConflict = conflictIds.contains(u.id);
        return CheckboxListTile(
          value: selected.contains(u.id),
          onChanged: (v) => onToggle(u.id, v ?? false),
          title: Text(u.id == myId ? '${u.displayName} (you)' : u.displayName),
          subtitle: Text('@${u.username}'),
          secondary: isConflict
              ? Tooltip(
                  message: 'Busy at this time',
                  child: Icon(Icons.event_busy,
                      color: Theme.of(context).colorScheme.error),
                )
              : null,
        );
      }).toList(),
    );
  }
}

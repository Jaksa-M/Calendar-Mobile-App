import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// App-bar button: reminder settings (on/off + lead time).
class ReminderMenuButton extends ConsumerWidget {
  const ReminderMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(remindersEnabledProvider);
    return IconButton(
      tooltip: 'Reminders',
      icon: Icon(enabled ? Icons.alarm : Icons.alarm_off),
      onPressed: () => _openDialog(context, ref),
    );
  }

  void _openDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final enabled = ref.watch(remindersEnabledProvider);
          final lead = ref.watch(reminderLeadMinutesProvider);
          return AlertDialog(
            title: const Text('Reminders'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable reminders'),
                  value: enabled,
                  onChanged: (v) =>
                      ref.read(remindersEnabledProvider.notifier).state = v,
                ),
                const SizedBox(height: 8),
                const Text('Remind me before the appointment:'),
                const SizedBox(height: 8),
                Opacity(
                  opacity: enabled ? 1 : 0.4,
                  child: Wrap(
                    spacing: 8,
                    children: [10, 30, 60].map((m) {
                      return ChoiceChip(
                        label: Text('$m min'),
                        selected: lead == m,
                        onSelected: enabled
                            ? (_) => ref
                                .read(reminderLeadMinutesProvider.notifier)
                                .state = m
                            : null,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}

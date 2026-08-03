import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../state/providers.dart';

/// App-bar button that opens the notifications inbox, with an unread badge.
class InboxButton extends ConsumerWidget {
  const InboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsControllerProvider).unread;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_none),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Mark everything as read when the inbox is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(notificationsControllerProvider).items;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: items.isEmpty
          ? const Center(child: Text('No notifications yet.'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                final invited = n.type == 'invited';
                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(invited ? Icons.person_add : Icons.how_to_reg),
                  ),
                  title: Text(n.title),
                  subtitle: Text(n.body),
                  trailing: Text(
                    DateFormat.MMMd().add_Hm().format(n.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
    );
  }
}

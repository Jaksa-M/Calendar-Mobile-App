import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_exception.dart';
import '../state/providers.dart';

/// App-bar button: Google connection status + connect/disconnect.
class GoogleMenuButton extends ConsumerWidget {
  const GoogleMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(googleStatusProvider);
    final connected = status.asData?.value ?? false;
    return IconButton(
      tooltip: connected ? 'Google Calendar connected' : 'Connect Google Calendar',
      icon: Icon(
        connected ? Icons.event_available : Icons.link,
        color: connected ? Colors.green : null,
      ),
      onPressed: () => _openDialog(context, ref, connected),
    );
  }

  void _openDialog(BuildContext context, WidgetRef ref, bool connected) {
    final userId = ref.read(authControllerProvider).user?.id;
    // Connecting is done in a browser (the redirect goes to the server's localhost).
    final connectUrl =
        'http://localhost:8000/integrations/google/connect?user_id=$userId';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(connected ? 'Google Calendar' : 'Connect Google Calendar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: connected
              ? const [
                  Row(children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(child: Text('Calendar connected. Busy times from '
                        'Google are taken into account when suggesting a time.')),
                  ]),
                ]
              : [
                  const Text('Open the following link in a browser on your '
                      'computer and sign in with your Google account:'),
                  const SizedBox(height: 12),
                  SelectableText(connectUrl,
                      style: const TextStyle(fontFamily: 'monospace')),
                ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (connected)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(integrationApiProvider).disconnectGoogle();
                } on ApiException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
                ref.invalidate(googleStatusProvider);
              },
              child: const Text('Disconnect'),
            )
          else
            FilledButton.icon(
              onPressed: () async {
                await launchUrl(Uri.parse(connectUrl),
                    mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open'),
            ),
        ],
      ),
    ).then((_) => ref.invalidate(googleStatusProvider));
  }
}

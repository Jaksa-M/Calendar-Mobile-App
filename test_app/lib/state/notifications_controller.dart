import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/notification_api.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';

class NotificationsState {
  final List<AppNotification> items;
  final int unread;
  const NotificationsState(this.items, this.unread);
  const NotificationsState.empty()
      : items = const [],
        unread = 0;
}

/// Polls the server for new notifications and shows them as local notifications.
class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._api) : super(const NotificationsState.empty());

  final NotificationApi _api;
  Timer? _timer;
  int _lastShownId = 0;
  bool _primed = false; // avoid popping all existing ones on first load

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => poll());
    poll();
  }

  Future<void> poll() async {
    try {
      final items = await _api.list();
      if (_primed) {
        for (final n in items.where((n) => n.id > _lastShownId)) {
          NotificationService.instance.show(n.title, n.body);
        }
      }
      if (items.isNotEmpty) {
        _lastShownId = items.map((e) => e.id).reduce(max);
      }
      _primed = true;
      state = NotificationsState(items, items.where((n) => !n.read).length);
    } catch (_) {
      // best-effort; try again on next tick
    }
  }

  Future<void> markAllRead() async {
    try {
      await _api.markAllRead();
    } catch (_) {}
    await poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

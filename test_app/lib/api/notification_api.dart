import '../models/app_notification.dart';
import 'api_client.dart';
import 'api_exception.dart';

class NotificationApi {
  NotificationApi(this._client);
  final ApiClient _client;

  Future<List<AppNotification>> list() async {
    final resp = await _client.dio.get('/notifications');
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ApiException('Failed to load notifications', statusCode: code);
    }
    return (resp.data as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markAllRead() async {
    await _client.dio.post('/notifications/read');
  }
}

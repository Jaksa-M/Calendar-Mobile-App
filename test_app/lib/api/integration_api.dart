import '../config.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Calls related to external calendar integration (Google).
class IntegrationApi {
  IntegrationApi(this._client);
  final ApiClient _client;

  Future<bool> googleStatus() async {
    final resp = await _client.dio.get('/integrations/google/status');
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw ApiException('Could not check status', statusCode: code);
    }
    return resp.data['connected'] == true;
  }

  Future<void> disconnectGoogle() async {
    final resp = await _client.dio.delete('/integrations/google/disconnect');
    final code = resp.statusCode ?? 0;
    if (code != 204 && (code < 200 || code >= 300)) {
      throw ApiException('Failed to disconnect', statusCode: code);
    }
  }

  /// URL for connecting a Google account (opens in the browser).
  String connectUrl(int userId) =>
      '$apiBaseUrl/integrations/google/connect?user_id=$userId';
}

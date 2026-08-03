import 'package:dio/dio.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Result of a successful login/register: the JWT plus the authenticated user.
class AuthResult {
  final String token;
  final User user;
  AuthResult(this.token, this.user);
}

class AuthApi {
  AuthApi(this._client);
  final ApiClient _client;

  Future<AuthResult> register({
    required String username,
    required String displayName,
    required String password,
  }) async {
    final resp = await _client.dio.post('/auth/register', data: {
      'username': username,
      'display_name': displayName,
      'password': password,
    });
    if (resp.statusCode == 201) return _parse(resp.data);
    throw _error(resp, fallback: 'Registration failed');
  }

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    // OAuth2 password flow expects form-encoded fields.
    final resp = await _client.dio.post(
      '/auth/login',
      data: {'username': username, 'password': password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (resp.statusCode == 200) return _parse(resp.data);
    throw _error(resp, fallback: 'Login failed');
  }

  AuthResult _parse(dynamic data) => AuthResult(
        data['access_token'] as String,
        User.fromJson(data['user'] as Map<String, dynamic>),
      );

  ApiException _error(Response resp, {required String fallback}) {
    final detail = resp.data is Map ? resp.data['detail'] : null;
    return ApiException(
      detail is String ? detail : fallback,
      statusCode: resp.statusCode,
    );
  }
}

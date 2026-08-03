import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

const _tokenKey = 'access_token';

/// Thin wrapper around Dio that injects the stored JWT on every request and
/// persists/clears the token in secure storage.
class ApiClient {
  ApiClient(this._storage) {
    dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        // Don't throw on 4xx — we handle those explicitly (e.g. 409 conflicts).
        validateStatus: (code) => code != null && code < 500,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) async {
        final token = await _storage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      }),
    );
  }

  final FlutterSecureStorage _storage;
  late final Dio dio;

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}

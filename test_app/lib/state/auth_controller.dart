import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/appointment_api.dart';
import '../api/auth_api.dart';
import '../models/user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final User? user;

  const AuthState(this.status, [this.user]);

  const AuthState.unknown() : this(AuthStatus.unknown, null);
}

/// Holds the authenticated session and bridges login/register/logout.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._client, this._authApi, this._appointmentApi)
      : super(const AuthState.unknown());

  final ApiClient _client;
  final AuthApi _authApi;
  final AppointmentApi _appointmentApi;

  /// On startup: if a token is stored, validate it by fetching the current user.
  Future<void> restore() async {
    final token = await _client.readToken();
    if (token == null) {
      state = const AuthState(AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _appointmentApi.me();
      state = AuthState(AuthStatus.authenticated, user);
    } catch (_) {
      await _client.clearToken();
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String username, String password) async {
    final result = await _authApi.login(username: username, password: password);
    await _client.saveToken(result.token);
    state = AuthState(AuthStatus.authenticated, result.user);
  }

  Future<void> register(
      String username, String displayName, String password) async {
    final result = await _authApi.register(
      username: username,
      displayName: displayName,
      password: password,
    );
    await _client.saveToken(result.token);
    state = AuthState(AuthStatus.authenticated, result.user);
  }

  Future<void> logout() async {
    await _client.clearToken();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}

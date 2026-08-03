import 'dart:io' show Platform;

/// Base URL of the FastAPI backend.
///
/// - iOS simulator / macOS desktop: `localhost` reaches the host machine.
/// - Android emulator: the host is reachable at the special IP `10.0.2.2`.
/// - Physical device: pass `--dart-define=API_BASE_URL=http://YOUR-LAN-IP:8000`
String get apiBaseUrl {
  const override = String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) return override;
  if (Platform.isAndroid) return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}

import 'package:dio/dio.dart';

/// A user-presentable API error. `conflictUserIds` is populated on a 409 when
/// a booking is rejected because some participants were busy.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final List<int> conflictUserIds;

  ApiException(this.message, {this.statusCode, this.conflictUserIds = const []});

  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}

/// Turn any thrown error into a clear, human-readable message for the UI.
///
/// Distinguishes the three things that can go wrong so we never blame the
/// connection when the real problem is elsewhere (e.g. a booking conflict).
String describeError(Object error) {
  if (error is ApiException) return error.message;

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return "Can't reach the server. Is the backend running?";
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return 'Server error${code != null ? ' ($code)' : ''}. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  return 'Something went wrong. Please try again.';
}

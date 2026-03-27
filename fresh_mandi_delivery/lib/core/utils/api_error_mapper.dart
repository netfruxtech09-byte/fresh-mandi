import 'package:dio/dio.dart';

class ApiErrorMapper {
  ApiErrorMapper._();

  static String toMessage(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final serverMessage = _extractServerMessage(error);
      final cleanServerMessage = _cleanServerMessage(serverMessage);
      if (cleanServerMessage != null) return cleanServerMessage;

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Server is taking too long to respond. Please retry.';
        case DioExceptionType.connectionError:
          return 'Unable to connect. Check internet and try again.';
        case DioExceptionType.badCertificate:
          return 'Secure connection failed. Please try again later.';
        case DioExceptionType.cancel:
          return 'Request cancelled.';
        case DioExceptionType.unknown:
          return 'Unexpected network error. Please try again.';
        case DioExceptionType.badResponse:
          if (statusCode == 401) return 'Session expired. Please login again.';
          if (statusCode == 403) {
            return 'You are not allowed to perform this action.';
          }
          if (statusCode == 404) return 'Requested data was not found.';
          if (statusCode == 409) {
            return 'Action cannot be completed in current order state.';
          }
          if (statusCode != null && statusCode >= 500) {
            return 'Server error. Please try again shortly.';
          }
          return 'Request failed. Please retry.';
      }
    }

    return fallback;
  }

  static String? _extractServerMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final dynamic message =
          data['message'] ?? data['error'] ?? data['detail'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return null;
  }

  static String? _cleanServerMessage(String? input) {
    if (input == null || input.isEmpty) return null;
    final lower = input.toLowerCase();
    const technicalMarkers = [
      'dioexception',
      'requestoptions',
      'status code',
      'read more about status codes',
      'validate status',
      'socketexception',
      'xmlhttprequest',
      'timeoutexception',
      'stack trace',
      'typeerror',
    ];
    for (final marker in technicalMarkers) {
      if (lower.contains(marker)) return null;
    }
    return input;
  }
}

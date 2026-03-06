import 'package:dio/dio.dart';

import '../errors/app_exception.dart';

AppException mapDioError(DioException e, {String fallback = 'Something went wrong. Please try again.'}) {
  final data = e.response?.data;
  if (data is Map<String, dynamic> && data['message'] != null) {
    return AppException('${data['message']}');
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return AppException('Request timed out. Please check your internet and try again.');
    case DioExceptionType.connectionError:
      return AppException('Unable to connect to server. Please check your internet connection.');
    case DioExceptionType.badCertificate:
      return AppException('Secure connection failed. Please try again later.');
    case DioExceptionType.cancel:
      return AppException('Request was cancelled.');
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      return AppException(fallback);
  }
}

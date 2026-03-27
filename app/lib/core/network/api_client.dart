import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'api_error_mapper.dart';
import '../storage/secure_storage.dart';

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.readToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        log(
          '[API][REQUEST] ${options.method} ${options.uri}',
          name: 'fresh_mandi_app.api',
        );
        handler.next(options);
      },
      onResponse: (response, handler) {
        log(
          '[API][RESPONSE] ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}',
          name: 'fresh_mandi_app.api',
        );
        handler.next(response);
      },
      onError: (error, handler) {
        final friendly = mapDioErrorMessage(error);
        log(
          '[API][ERROR] ${error.response?.statusCode ?? 'NO_STATUS'} ${error.requestOptions.method} ${error.requestOptions.uri} :: $friendly',
          name: 'fresh_mandi_app.api',
        );
        handler.next(error.copyWith(message: friendly));
      },
    ),
  );
  return dio;
});

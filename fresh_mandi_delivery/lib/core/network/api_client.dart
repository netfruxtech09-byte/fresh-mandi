import 'dart:developer';

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../storage/secure_store.dart';
import '../utils/api_error_mapper.dart';

class ApiClient {
  ApiClient._();

  static final Dio dio =
      Dio(
          BaseOptions(
            baseUrl: AppConstants.apiBaseUrl,
            connectTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 45),
            headers: {'Content-Type': 'application/json'},
          ),
        )
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              final token = await SecureStore.read(SecureStore.keyToken);
              if (token != null && token.isNotEmpty) {
                options.headers['Authorization'] = 'Bearer $token';
              }
              log(
                '[API][REQUEST] ${options.method} ${options.uri}',
                name: 'fresh_mandi_delivery.api',
              );
              handler.next(options);
            },
            onResponse: (response, handler) {
              log(
                '[API][RESPONSE] ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}',
                name: 'fresh_mandi_delivery.api',
              );
              handler.next(response);
            },
            onError: (error, handler) {
              final friendly = ApiErrorMapper.toMessage(error);
              log(
                '[API][ERROR] ${error.response?.statusCode ?? 'NO_STATUS'} ${error.requestOptions.method} ${error.requestOptions.uri} :: $friendly',
                name: 'fresh_mandi_delivery.api',
              );
              handler.next(error.copyWith(message: friendly));
            },
          ),
        );
}

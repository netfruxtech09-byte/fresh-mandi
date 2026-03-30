import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'constants/app_constants.dart';

class ApiService {
  ApiService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 45),
          headers: {'Content-Type': 'application/json'},
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          log('[PROCESSING][REQUEST] ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (res, handler) {
          log(
            '[PROCESSING][RESPONSE] ${res.statusCode} ${res.requestOptions.uri}',
          );
          handler.next(res);
        },
        onError: (e, handler) {
          final friendly = mapError(e);
          log('[PROCESSING][ERROR] ${e.requestOptions.uri} $friendly');
          handler.next(e.copyWith(message: friendly));
        },
      ),
    );
  }

  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String mapError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map &&
          data['message'] is String &&
          (data['message'] as String).trim().isNotEmpty) {
        final backendMessage = (data['message'] as String).trim();
        final lower = backendMessage.toLowerCase();
        if (lower.contains('dioexception') ||
            lower.contains('stack trace') ||
            lower.contains('requestoptions.validatestatus') ||
            lower.contains('client error')) {
          return 'Request failed. Please retry.';
        }
        return backendMessage;
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Server is taking too long to respond. Please retry.';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'Unable to connect. Check internet and retry.';
      }
      return 'Request failed. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> saveSession(String token, String? roleCode) async {
    await _storage.write(key: 'token', value: token);
    await _storage.write(key: 'role_code', value: roleCode ?? 'STORE_MANAGER');
  }

  Future<String?> readToken() => _storage.read(key: 'token');

  Future<String?> readRoleCode() => _storage.read(key: 'role_code');

  Future<void> clearSession() async {
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'role_code');
  }

  Future<void> requestOtp(String phone, String deviceId) async {
    await _dio.post(
      '/processing/login',
      data: {'phone': phone, 'device_id': deviceId},
    );
  }

  Future<Map<String, dynamic>> verifyOtp(
    String phone,
    String otp,
    String deviceId,
  ) async {
    final res = await _dio.post(
      '/processing/verify-otp',
      data: {'phone': phone, 'otp': otp, 'device_id': deviceId},
    );
    return Map<String, dynamic>.from((res.data['data'] ?? {}) as Map);
  }

  Future<Map<String, dynamic>> dashboard() async {
    final res = await _dio.get('/processing/dashboard');
    return Map<String, dynamic>.from((res.data['data'] ?? {}) as Map);
  }

  Future<List<Map<String, dynamic>>> inventoryAlerts() async {
    final res = await _dio.get('/processing/inventory-alerts');
    return ((res.data['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> generateRoutes() async {
    await _dio.post(
      '/processing/generate-routes',
      options: Options(receiveTimeout: const Duration(seconds: 90)),
    );
  }

  Future<List<Map<String, dynamic>>> routesToday() async {
    DioException? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _dio.get(
          '/processing/routes-today',
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
        return ((res.data['data'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } on DioException catch (error) {
        lastError = error;
        final isTimeout =
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout;
        if (!isTimeout || attempt == 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    throw lastError!;
  }

  Future<Map<String, dynamic>> routeSummary(int routeId) async {
    final res = await _dio.get('/processing/route-summary/$routeId');
    return Map<String, dynamic>.from((res.data['data'] ?? {}) as Map);
  }

  Future<Map<String, dynamic>> routeOrders(int routeId) async {
    final res = await _dio.get('/processing/route-orders/$routeId');
    return Map<String, dynamic>.from((res.data['data'] ?? {}) as Map);
  }

  Future<List<Map<String, dynamic>>> routeLabels(int routeId) async {
    final res = await _dio.get('/processing/route-labels/$routeId');
    return ((res.data['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> lockOrder(int orderId) async {
    await _dio.post('/processing/lock-order', data: {'order_id': orderId});
  }

  Future<void> unlockOrder(int orderId) async {
    await _dio.post('/processing/unlock-order', data: {'order_id': orderId});
  }

  Future<void> scanPack(
    int orderId,
    String barcode,
    String? crateNumber,
  ) async {
    await _dio.post(
      '/processing/scan-pack',
      data: {
        'order_id': orderId,
        'barcode': barcode,
        if (crateNumber != null && crateNumber.trim().isNotEmpty)
          'crate_number': crateNumber.trim(),
      },
    );
  }

  Future<void> printRouteLabels(
    int routeId, {
    String actionType = 'PRINT',
    String? reason,
  }) async {
    await _dio.post(
      '/processing/print-route-labels',
      data: {
        'route_id': routeId,
        'action_type': actionType,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> goodsReceived() async {
    final res = await _dio.get('/processing/goods-received');
    return ((res.data['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> createGoodsReceived({
    required String supplierName,
    required String invoiceNumber,
    String? imageUrl,
    required List<Map<String, dynamic>> items,
  }) async {
    await _dio.post(
      '/processing/goods-received',
      data: {
        'supplier_name': supplierName,
        'invoice_number': invoiceNumber,
        if (imageUrl != null && imageUrl.trim().isNotEmpty)
          'image_url': imageUrl.trim(),
        'items': items,
      },
    );
  }

  Future<List<Map<String, dynamic>>> qualityQueue() async {
    final res = await _dio.get('/processing/quality-queue');
    return ((res.data['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> approveQuality(Map<String, dynamic> payload) async {
    await _dio.post('/processing/quality-check', data: payload);
  }

  Future<List<Map<String, dynamic>>> products() async {
    final res = await _dio.get('/catalog/products');
    return ((res.data['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}

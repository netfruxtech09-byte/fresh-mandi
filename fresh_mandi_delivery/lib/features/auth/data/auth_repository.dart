import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../models/delivery_executive.dart';

class AuthRepository {
  Future<void> requestOtp({
    required String phone,
    required String deviceId,
  }) async {
    await ApiClient.dio.post(
      '/delivery/login',
      data: {'phone': phone, 'device_id': deviceId},
    );
  }

  Future<DeliveryExecutive> verifyOtp({
    required String phone,
    required String otp,
    required String deviceId,
  }) async {
    final res = await ApiClient.dio.post(
      '/delivery/verify-otp',
      data: {'phone': phone, 'otp': otp, 'device_id': deviceId},
    );

    final data = (res.data['data'] ?? {}) as Map<String, dynamic>;
    await SecureStore.write(
      SecureStore.keyToken,
      (data['token'] ?? '') as String,
    );
    await SecureStore.write(
      SecureStore.keyRefreshToken,
      (data['refresh_token'] ?? '') as String,
    );
    await SecureStore.write(SecureStore.keyDeviceId, deviceId);
    return DeliveryExecutive.fromJson(
      (data['user'] ?? {}) as Map<String, dynamic>,
    );
  }

  Future<void> logout() async {
    try {
      await ApiClient.dio.post('/delivery/logout');
    } on DioException {
      // Clear local session even if the network call fails.
    } finally {
      await SecureStore.clearSession();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_name');
      await prefs.remove('user_phone');
      await prefs.remove('user_id');
    }
  }

  Future<bool> hasSession() async {
    final token = await SecureStore.read(SecureStore.keyToken);
    return token != null && token.isNotEmpty;
  }

  String normalizeError(Object e) {
    if (e is DioException) return ApiErrorMapper.toMessage(e);
    return ApiErrorMapper.toMessage(
      e,
      fallback: 'Unable to process request. Please try again.',
    );
  }
}

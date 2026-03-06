import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/firebase_bootstrap.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider), ref.watch(secureStorageProvider));
});

class VerifyOtpResult {
  const VerifyOtpResult({required this.isNewUser, required this.hasAddress});
  final bool isNewUser;
  final bool hasAddress;
}

class AuthRepository {
  AuthRepository(this._dio, this._storage);
  final Dio _dio;
  final SecureStorageService _storage;

  Future<void> requestOtp(String phone) async {
    try {
      await _dio.post('/auth/otp/request', data: {'phone': phone});
    } on DioException catch (e) {
      throw mapDioError(e, fallback: 'Failed to send OTP. Please try again.');
    } catch (_) {
      throw AppException('Failed to send OTP. Please try again.');
    }
  }

  Future<VerifyOtpResult> verifyOtp(String phone, String otp) async {
    try {
      final res = await _dio.post('/auth/otp/verify', data: {'phone': phone, 'otp': otp});
      final data = (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final token = res.data['data']?['token']?.toString();
      if (token != null && token.isNotEmpty) {
        await _storage.saveToken(token);
        try {
          final fcmToken = await FirebaseBootstrap.getFcmToken();
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await _dio.post('/notifications/fcm-token', data: {'token': fcmToken});
          }
        } catch (_) {
          // Ignore token registration until Firebase is configured.
        }
      }
      return VerifyOtpResult(
        isNewUser: data['is_new_user'] == true,
        hasAddress: data['has_address'] == true,
      );
    } on DioException catch (e) {
      throw mapDioError(e, fallback: 'OTP verification failed. Please try again.');
    } catch (_) {
      throw AppException('OTP verification failed. Please try again.');
    }
  }

  Future<bool> hasValidSession() async {
    final token = await _storage.readToken();
    if (token == null || token.isEmpty) return false;
    try {
      await _dio.get('/users/me');
      return true;
    } catch (_) {
      await _storage.clearSession();
      return false;
    }
  }

  Future<void> logout() => _storage.clearSession();
}

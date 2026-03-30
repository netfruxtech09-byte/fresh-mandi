import 'package:flutter/foundation.dart';

import '../core/api_service.dart';

class AuthState extends ChangeNotifier {
  AuthState(this._api);

  final ApiService _api;

  String? token;
  String roleCode = 'STORE_MANAGER';
  bool restoring = true;
  bool loading = false;
  String? error;
  String? pendingPhone;

  bool get canUseInbound =>
      roleCode == 'STORE_MANAGER' ||
      roleCode == 'PROCUREMENT_MANAGER' ||
      roleCode == 'QUALITY_CHECKER';
  bool get canUseQuality =>
      roleCode == 'STORE_MANAGER' || roleCode == 'QUALITY_CHECKER';
  bool get canUseRoutes =>
      roleCode == 'STORE_MANAGER' ||
      roleCode == 'PACKING_STAFF' ||
      roleCode == 'LABEL_PRINTING_STAFF' ||
      roleCode == 'QUALITY_CHECKER';
  bool get canSeeDashboard => roleCode != 'PACKING_STAFF' || true;

  Future<void> restore() async {
    token = await _api.readToken();
    roleCode = await _api.readRoleCode() ?? 'STORE_MANAGER';
    restoring = false;
    notifyListeners();
  }

  Future<bool> requestOtp(String phone) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final normalized = _normalizePhone(phone);
      if (normalized == null) {
        error = 'Enter valid Indian mobile number.';
        return false;
      }
      pendingPhone = normalized;
      await _api.requestOtp(normalized, 'processing-device-001');
      return true;
    } catch (e) {
      error = _api.mapError(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String otp) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (pendingPhone == null) {
        error = 'Request OTP first.';
        return false;
      }
      if (otp.trim().length != 6) {
        error = 'Enter 6-digit OTP.';
        return false;
      }
      final data = await _api.verifyOtp(
        pendingPhone!,
        otp.trim(),
        'processing-device-001',
      );
      final t = (data['token'] ?? '').toString();
      final user = Map<String, dynamic>.from((data['user'] ?? {}) as Map);
      if (t.isEmpty) {
        error = 'Login failed. Please retry.';
        return false;
      }
      roleCode = '${user['role_code'] ?? 'STORE_MANAGER'}';
      await _api.saveSession(t, roleCode);
      token = t;
      return true;
    } catch (e) {
      error = _api.mapError(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api.clearSession();
    token = null;
    pendingPhone = null;
    roleCode = 'STORE_MANAGER';
    notifyListeners();
  }

  String? _normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    if (digits.length == 13 && digits.startsWith('091')) {
      return '+91${digits.substring(3)}';
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+91${digits.substring(1)}';
    }
    return null;
  }
}

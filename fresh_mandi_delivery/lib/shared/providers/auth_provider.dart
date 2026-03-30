import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/models/delivery_executive.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo);

  final AuthRepository _repo;

  DeliveryExecutive? user;
  bool loading = false;
  String? error;

  Future<bool> restoreSession() async {
    final ok = await _repo.hasSession();
    if (!ok) return false;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? 'Delivery Executive';
    final phone = prefs.getString('user_phone') ?? '';
    final id = prefs.getInt('user_id') ?? 0;
    user = DeliveryExecutive(id: id, name: name, phone: phone);
    notifyListeners();
    return true;
  }

  Future<void> requestOtp({
    required String phone,
    required String deviceId,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _repo.requestOtp(phone: phone, deviceId: deviceId);
    } catch (e) {
      error = _repo.normalizeError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp({
    required String phone,
    required String otp,
    required String deviceId,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      user = await _repo.verifyOtp(phone: phone, otp: otp, deviceId: deviceId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', user!.name);
      await prefs.setString('user_phone', user!.phone);
      await prefs.setInt('user_id', user!.id);
      return true;
    } catch (e) {
      error = _repo.normalizeError(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    error = null;
    await _repo.logout();
    user = null;
    notifyListeners();
  }
}

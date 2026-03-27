import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();
  static const _storage = FlutterSecureStorage();

  static const keyToken = 'auth_token';
  static const keyRefreshToken = 'refresh_token';
  static const keyDeviceId = 'bound_device_id';

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> delete(String key) => _storage.delete(key: key);

  static Future<void> clearSession() async {
    await _storage.delete(key: keyToken);
    await _storage.delete(key: keyRefreshToken);
  }
}

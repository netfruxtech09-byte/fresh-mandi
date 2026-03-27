import 'dart:math';

import '../storage/secure_store.dart';

class DeviceIdentity {
  DeviceIdentity._();

  static Future<String> getOrCreate() async {
    final existing = await SecureStore.read(SecureStore.keyDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final now = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random.secure().nextInt(1 << 32).toRadixString(16);
    final generated = 'fm-delivery-$now-$rnd';
    await SecureStore.write(SecureStore.keyDeviceId, generated);
    return generated;
  }
}

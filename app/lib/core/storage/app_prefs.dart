import 'package:hive_flutter/hive_flutter.dart';

class AppPrefs {
  static const _boxName = 'app_prefs';
  static const _onboardingKey = 'onboarding_seen';

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<bool> isOnboardingSeen() async {
    final box = await _box();
    return box.get(_onboardingKey, defaultValue: false) as bool;
  }

  Future<void> setOnboardingSeen() async {
    final box = await _box();
    await box.put(_onboardingKey, true);
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

class FirebaseBootstrap {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      FirebaseMessaging.onMessage.listen((message) {
        // Hook for in-app message banners/local notifications.
      });
    } on FirebaseException catch (e) {
      _initialized = false;
      debugPrint('Firebase init skipped: ${e.code} ${e.message}');
    } catch (e) {
      _initialized = false;
      debugPrint('Firebase init skipped: $e');
    }
  }

  static Future<String?> getFcmToken() async {
    if (!_initialized) return null;
    return FirebaseMessaging.instance.getToken();
  }
}

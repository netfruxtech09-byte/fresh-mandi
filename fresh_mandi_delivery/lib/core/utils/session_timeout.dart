import 'dart:async';

import 'package:flutter/widgets.dart';

class SessionTimeoutService {
  SessionTimeoutService({required this.timeout, required this.onTimeout});

  final Duration timeout;
  final VoidCallback onTimeout;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer(timeout, onTimeout);
  }

  void ping() {
    start();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

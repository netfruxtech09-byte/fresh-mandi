import 'package:flutter/material.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/dashboard/presentation/home_screen.dart';

class AppRouter extends StatelessWidget {
  const AppRouter({super.key, required this.isAuthenticated});

  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) {
    return isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}

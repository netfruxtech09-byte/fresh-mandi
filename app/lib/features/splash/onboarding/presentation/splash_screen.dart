import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../../core/storage/app_prefs.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(seconds: 2));
    final prefs = AppPrefs();
    final seen = await prefs.isOnboardingSeen();
    if (!seen) {
      if (mounted) context.go('/onboarding');
      return;
    }

    final loggedIn = await ref.read(authRepositoryProvider).hasValidSession();
    if (!mounted) return;
    context.go(loggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12D667), Color(0xFF06C958)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -70,
              bottom: 130,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 20),
                  borderRadius: BorderRadius.circular(96),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 28,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(28),
                      child: Image.asset('assets/icon/app_icon.png',
                          fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Fresh Mandi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 26),
                      child: Text(
                        'Today\'s Mandi. Tomorrow Morning at\nYour Door.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xD8FFFFFF),
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '•  •  •',
                      style: TextStyle(
                        color: Color(0x8FFFFFFF),
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

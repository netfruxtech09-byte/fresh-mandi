import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/storage/app_prefs.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _index = 0;

  final pages = const [
    (
      icon: Icons.eco_outlined,
      title: 'Farm Fresh Guarantee',
      subtitle: 'We pick the freshest produce directly\nfrom local farms every morning',
    ),
    (
      icon: Icons.access_time_rounded,
      title: 'Next Day Delivery',
      subtitle: 'Order before 9 PM and get fresh\nvegetables delivered tomorrow morning',
    ),
    (
      icon: Icons.credit_card_rounded,
      title: 'Pay After Delivery',
      subtitle: 'No advance payment needed. Pay\nafter receiving your fresh vegetables',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await AppPrefs().setOnboardingSeen();
                  if (!context.mounted) return;
                  context.go('/login');
                },
                child: const Text('Skip', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (_, i) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF14C6A4),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(pages[i].icon, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      pages[i].title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 25 / 1.35, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      pages[i].subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _index == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _index == i ? const Color(0xFF09C856) : const Color(0xFFD1D5DB),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF08C04B),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () async {
                    if (_index == pages.length - 1) {
                      await AppPrefs().setOnboardingSeen();
                      if (!context.mounted) return;
                      context.go('/login');
                    } else {
                      _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                    }
                  },
                  child: Text(_index == pages.length - 1 ? 'Get Started  ›' : 'Next  ›'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

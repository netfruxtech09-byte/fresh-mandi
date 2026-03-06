import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../shared/widgets/fresh_app_bar.dart';
import '../../auth/data/auth_repository.dart';
import '../../address/data/address_repository.dart';
import '../../wallet/data/wallet_repository.dart';
import '../data/profile_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with RouteAware {
  late Future<({Map<String, dynamic>? me, int addressCount, double credits})> _profileFuture;
  bool _elderMode = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _retry();
  }

  Future<({Map<String, dynamic>? me, int addressCount, double credits})> _load() async {
    final me = await ref.read(profileRepositoryProvider).me();
    int addressCount = 0;
    double credits = 0;

    try {
      final addresses = await ref.read(addressRepositoryProvider).fetchAddresses();
      addressCount = addresses.length;
    } catch (_) {}

    try {
      final wallet = await ref.read(walletRepositoryProvider).fetchWallet();
      final raw = wallet['balance'];
      credits = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    } catch (_) {}

    return (me: me, addressCount: addressCount, credits: credits);
  }

  Future<void> _retry() async {
    final next = _load();
    setState(() => _profileFuture = next);
    await next;
  }

  Future<void> _openAndMaybeRefresh(String route, {bool refreshOnReturn = false}) async {
    await context.push(route);
    if (!mounted || !refreshOnReturn) return;
    await _retry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DT.bg,
      appBar: const FreshAppBar(title: 'Profile'),
      body: SafeArea(
        top: false,
        bottom: false,
        child: FutureBuilder<({Map<String, dynamic>? me, int addressCount, double credits})>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load profile'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final me = data.me;
          final name = me?['name']?.toString().isNotEmpty == true ? '${me!['name']}' : 'User';
          final phone = '${me?['phone'] ?? '-'}';

          return RefreshIndicator(
            onRefresh: _retry,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: DT.primary,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: DT.softShadow,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0FCB61),
                                      borderRadius: BorderRadius.circular(32),
                                    ),
                                    child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 34),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(name, style: const TextStyle(fontSize: 30 / 1.75, fontWeight: FontWeight.w700, color: DT.text)),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.local_shipping_outlined, color: DT.primaryDark, size: 14),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(phone, style: const TextStyle(fontSize: 13.5, color: DT.sub, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _statCard(
                                      value: '${data.addressCount}',
                                      label: 'Addresses',
                                      textColor: DT.primaryDark,
                                      bg: const Color(0xFFEAF7EF),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _statCard(
                                      value: '₹${data.credits.toStringAsFixed(0)}',
                                      label: 'Credits',
                                      textColor: const Color(0xFFF05A17),
                                      bg: const Color(0xFFF8F1E8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _switchTile(),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _tile(
                    title: 'My Addresses',
                    icon: Icons.location_on_outlined,
                    route: '/address',
                    onTapOverride: () => _openAndMaybeRefresh('/address', refreshOnReturn: true),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _tile(
                    title: 'My Orders',
                    icon: Icons.receipt_long_outlined,
                    route: '/orders',
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _tile(
                    title: 'Wallet & Credits',
                    icon: Icons.account_balance_wallet_outlined,
                    route: '/wallet',
                    trailingPill: '₹${data.credits.toStringAsFixed(0)}',
                    onTapOverride: () => _openAndMaybeRefresh('/wallet', refreshOnReturn: true),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _tile(
                    title: 'Terms & Conditions',
                    icon: Icons.description_outlined,
                    route: '/terms',
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _tile(
                    title: 'Privacy Policy',
                    icon: Icons.lock_outline_rounded,
                    route: '/privacy',
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(authRepositoryProvider).logout();
                      if (!context.mounted) return;
                      AppFeedback.info(context, 'Logged out successfully.');
                      context.go('/login');
                    },
                    icon: const Icon(Icons.logout_rounded),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      side: const BorderSide(color: Color(0xFFF3D4D9)),
                      foregroundColor: const Color(0xFFE11D48),
                      backgroundColor: const Color(0xFFFDF2F4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Version 1.0.0',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _statCard({
    required String value,
    required String label,
    required Color textColor,
    required Color bg,
  }) {
    return Container(
      height: 68,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 23 / 1.8, fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12.5, color: DT.sub, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _switchTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: DT.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEDEFFF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.switch_access_shortcut_rounded, size: 18, color: Color(0xFF4F46E5)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Elder Friendly Mode', style: TextStyle(fontSize: 16 / 1.1, fontWeight: FontWeight.w700, color: DT.text)),
                SizedBox(height: 2),
                Text('Larger text & buttons', style: TextStyle(fontSize: 13, color: DT.sub)),
              ],
            ),
          ),
          Switch(
            value: _elderMode,
            onChanged: (v) => setState(() => _elderMode = v),
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF16A34A),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFD1D5DB),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required String title,
    required IconData icon,
    required String route,
    String? trailingPill,
    VoidCallback? onTapOverride,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTapOverride ?? () => context.push(route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: DT.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: DT.primaryDark, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16 / 1.1, fontWeight: FontWeight.w700, color: DT.text),
                ),
              ),
              if (trailingPill != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8F5DE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    trailingPill,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DT.primaryDark),
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

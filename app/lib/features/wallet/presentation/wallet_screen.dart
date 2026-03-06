import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/parse_num.dart';
import '../../../shared/widgets/fresh_app_bar.dart';
import '../data/wallet_repository.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  late Future<Map<String, dynamic>> _walletFuture;

  @override
  void initState() {
    super.initState();
    _walletFuture = _load();
  }

  Future<Map<String, dynamic>> _load() => ref.read(walletRepositoryProvider).fetchWallet();

  Future<void> _retry() async {
    final next = _load();
    setState(() => _walletFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DT.bg,
      appBar: const FreshAppBar(title: 'Wallet & Credits'),
      body: SafeArea(
        top: false,
        child: FutureBuilder<Map<String, dynamic>>(
        future: _walletFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load wallet'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            );
          }

          final wallet = snapshot.data;
          if (wallet == null) {
            return const Center(child: Text('Wallet data unavailable'));
          }

          final balance = parseDouble(wallet['balance']);
          final txns = ((wallet['transactions'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>();

          return RefreshIndicator(
            onRefresh: _retry,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: DT.primaryDark, borderRadius: BorderRadius.circular(24)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 27),
                          ),
                          const SizedBox(width: 12),
                          const Text('Available Credits', style: TextStyle(color: Colors.white, fontSize: 32 / 2.2, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('₹${balance.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 52 / 2.1, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('Use up to 20% of order value', style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w400)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _miniCard(
                              icon: Icons.trending_up_rounded,
                              title: 'Total Earned',
                              value: '₹${balance.toStringAsFixed(0)}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: _MiniCardStatic(
                              icon: Icons.card_giftcard_rounded,
                              title: 'Cashback Rate',
                              value: '2%',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'How Credits Work',
                  child: const Column(
                    children: [
                      _RuleRow(index: 1, text: 'Earn 2% cashback on every order'),
                      _RuleRow(index: 2, text: 'Credits are added instantly after order delivery'),
                      _RuleRow(index: 3, text: 'Use up to 20% of your order value with credits'),
                      _RuleRow(index: 4, text: 'No expiry - credits never expire!'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'Transaction History',
                  child: txns.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('No transactions yet.', style: TextStyle(color: DT.sub)),
                        )
                      : Column(
                          children: txns.map((t) {
                            final amount = parseDouble(t['amount']);
                            final rawDate = t['created_at']?.toString() ?? '';
                            final date = DateTime.tryParse(rawDate);
                            final dateText = date == null ? 'Recent' : DateFormat('d MMM y').format(date);
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF7EF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFD3F0DE)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(color: const Color(0xFFD5F4DF), borderRadius: BorderRadius.circular(20)),
                                      child: const Icon(Icons.card_giftcard_rounded, color: DT.primaryDark),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${t['reason'] ?? t['type'] ?? 'Cashback Earned'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 26 / 1.8)),
                                          const SizedBox(height: 2),
                                          Text(dateText, style: const TextStyle(color: DT.sub, fontSize: 14.5)),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${amount >= 0 ? '+' : '-'}₹${amount.abs().toStringAsFixed(0)}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28 / 1.7, color: DT.primaryDark),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
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

  Widget _miniCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14))),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 32 / 2.0, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: DT.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 31 / 1.8, color: DT.text)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.index, required this.text});
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: const Color(0xFFD7F1E0), borderRadius: BorderRadius.circular(17)),
            alignment: Alignment.center,
            child: Text('$index', style: const TextStyle(color: DT.primaryDark, fontWeight: FontWeight.w700, fontSize: 21 / 1.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 29 / 2.1, color: Color(0xFF344054), height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _MiniCardStatic extends StatelessWidget {
  const _MiniCardStatic({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14))),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 32 / 2.0, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

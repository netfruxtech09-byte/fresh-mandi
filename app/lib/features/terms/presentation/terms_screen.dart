import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../shared/widgets/fresh_app_bar.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final Map<String, bool> _expanded = {
    'Fresh Delivery Guarantee': true,
    'Ordering & Delivery': false,
    'Payment Options': false,
    'Credits & Cashback': false,
    'Cancellation & Refunds': false,
    'Quality Assurance': false,
    'Privacy & Data': false,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DT.bg,
      appBar: const FreshAppBar(title: 'Terms & Conditions'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: DT.softShadow,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to Fresh Mandi! Please read these terms carefully before using our service. By placing an order, you agree to these terms and conditions.',
                    style: TextStyle(fontSize: 16, color: Color(0xFF475467), height: 1.55),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Last updated: March 2, 2026',
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._expanded.keys.map(
              (title) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _expansion(title),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expansion(String title) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: DT.softShadow,
      ),
      child: ExpansionTile(
        initiallyExpanded: _expanded[title] ?? false,
        onExpansionChanged: (v) => setState(() => _expanded[title] = v),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        iconColor: title == 'Fresh Delivery Guarantee' ? DT.primaryDark : const Color(0xFF98A2B3),
        collapsedIconColor: const Color(0xFF98A2B3),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 30 / 1.8,
            fontWeight: FontWeight.w700,
            color: DT.text,
          ),
        ),
        children: [
          if (title == 'Fresh Delivery Guarantee')
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bullet('We guarantee farm-fresh produce delivered to your doorstep every morning.'),
                SizedBox(height: 10),
                _Bullet('All fruits and vegetables are handpicked the same day you receive them.'),
                SizedBox(height: 10),
                _Bullet('If you\'re not satisfied with the freshness, we\'ll replace or refund 100%.'),
              ],
            ),
          if (title != 'Fresh Delivery Guarantee')
            const Text(
              'Policy details are aligned with our current operations and are updated regularly.',
              style: TextStyle(color: DT.sub, fontSize: 15, height: 1.45),
            ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '•',
          style: TextStyle(fontSize: 17, color: DT.primaryDark, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, color: Color(0xFF344054), height: 1.45),
          ),
        ),
      ],
    );
  }
}

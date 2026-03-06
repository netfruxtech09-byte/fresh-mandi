import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../shared/widgets/fresh_app_bar.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  final Map<String, bool> _expanded = {
    'What We Collect': true,
    'How We Use Data': false,
    'Data Security': false,
    'Your Controls': false,
    'Third-Party Services': false,
    'Contact & Updates': false,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DT.bg,
      appBar: const FreshAppBar(title: 'Privacy Policy'),
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
                    'At Fresh Mandi, your trust matters. We collect only the information needed to deliver fresh orders, improve service quality, and keep your account secure.',
                    style: TextStyle(fontSize: 16, color: Color(0xFF475467), height: 1.55),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Last updated: March 3, 2026',
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
        iconColor: title == 'What We Collect' ? DT.primaryDark : const Color(0xFF98A2B3),
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
          _contentFor(title),
        ],
      ),
    );
  }

  Widget _contentFor(String title) {
    switch (title) {
      case 'What We Collect':
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bullet('Mobile number for OTP login and account security.'),
            SizedBox(height: 10),
            _Bullet('Delivery address and order preferences for fulfillment.'),
            SizedBox(height: 10),
            _Bullet('Order, payment, and wallet activity for billing records.'),
          ],
        );
      case 'How We Use Data':
        return const Text(
          'We use your data to process orders, assign delivery slots, share order updates, improve product recommendations, and support customer care.',
          style: TextStyle(color: DT.sub, fontSize: 15, height: 1.45),
        );
      case 'Data Security':
        return const Text(
          'Fresh Mandi uses encrypted connections, token-based authentication, and restricted backend access to protect your personal information.',
          style: TextStyle(color: DT.sub, fontSize: 15, height: 1.45),
        );
      case 'Your Controls':
        return const Text(
          'You can update your phone number, addresses, and notification preferences anytime from the Profile section of the app.',
          style: TextStyle(color: DT.sub, fontSize: 15, height: 1.45),
        );
      case 'Third-Party Services':
        return const Text(
          'Payment providers and notification partners may process limited technical data required to complete payments and send order alerts.',
          style: TextStyle(color: DT.sub, fontSize: 15, height: 1.45),
        );
      default:
        return const Text(
          'For privacy questions, contact support from the app. Policy updates will be reflected here with a revised date.',
          style: TextStyle(color: DT.sub, fontSize: 15, height: 1.45),
        );
    }
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

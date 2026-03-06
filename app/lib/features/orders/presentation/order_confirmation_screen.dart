import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';

class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({
    super.key,
    this.orderId,
    this.total,
    this.slotLabel,
  });

  final int? orderId;
  final double? total;
  final String? slotLabel;

  @override
  Widget build(BuildContext context) {
    final displayOrder = orderId == null ? 'Order placed' : 'Order #ORD$orderId';
    final displaySlot = (slotLabel?.trim().isNotEmpty ?? false) ? slotLabel!.trim() : '7 AM - 9 AM';
    final displayTotal = total == null ? '₹0' : '₹${total!.toStringAsFixed(0)}';

    return Scaffold(
      backgroundColor: DT.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            children: [
              Container(
                width: 132,
                height: 132,
                decoration: const BoxDecoration(
                  color: Color(0xFFCFEFD9),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: const BoxDecoration(
                      color: DT.primaryDark,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 46),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Payment Successful!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: DT.text),
              ),
              const SizedBox(height: 8),
              const Text(
                'Thank you for your payment',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: DT.sub),
              ),
              const SizedBox(height: 6),
              Text(
                displayOrder,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF667085), fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: DT.softShadow,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Amount Paid', style: TextStyle(fontSize: 15, color: Color(0xFF475467))),
                        ),
                        Text(
                          displayTotal,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: DT.primaryDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFDDE3E6), height: 1),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Payment Method', style: TextStyle(fontSize: 15, color: Color(0xFF475467))),
                    ),
                    const SizedBox(height: 4),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('UPI / Online', style: TextStyle(fontSize: 16, color: DT.text, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFDDE3E6), height: 1),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Delivery Expected', style: TextStyle(fontSize: 15, color: Color(0xFF475467))),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(displaySlot, style: const TextStyle(fontSize: 16, color: DT.text, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F7EE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF9DE5BA), width: 1.2),
                ),
                child: const Text(
                  '🎉 Your order is confirmed! We\'ll deliver fresh produce to your doorstep.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF047A3B), fontWeight: FontWeight.w500, height: 1.35),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: DT.primaryDark,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => context.go('/orders'),
                  icon: const Icon(Icons.inventory_2_outlined, size: 20),
                  label: const Text('Track Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: const BorderSide(color: Color(0xFFC4CBD4), width: 1.5),
                  ),
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home_outlined, size: 20, color: Color(0xFF344054)),
                  label: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF344054))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/parse_num.dart';
import '../../../shared/widgets/fresh_app_bar.dart';
import '../data/orders_repository.dart';

class OrderDetailsScreen extends ConsumerStatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId});
  final int orderId;

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  late Future<Map<String, dynamic>?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _load();
  }

  Future<Map<String, dynamic>?> _load() =>
      ref.read(ordersRepositoryProvider).fetchOrderDetails(widget.orderId);

  Future<void> _retry() async {
    final next = _load();
    setState(() => _detailsFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DT.bg,
      appBar: const FreshAppBar(title: 'Order Details'),
      body: SafeArea(
        top: false,
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Unable to load order details'),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              );
            }

            final order = snapshot.data;
            if (order == null) {
              return const Center(child: Text('Order not found'));
            }

            final items = ((order['items'] as List<dynamic>?) ?? [])
                .cast<Map<String, dynamic>>();
            final status = '${order['status'] ?? 'CONFIRMED'}'.toUpperCase();
            final createdAt = DateTime.tryParse('${order['created_at'] ?? ''}');
            final dateText = createdAt == null
                ? 'Recent order'
                : DateFormat('d MMM y, h:mm a').format(createdAt);

            final subtotal = parseDouble(order['subtotal']);
            final discount = parseDouble(order['discount']);
            final gst = parseDouble(order['gst']);
            final wallet = parseDouble(order['wallet_redeem']);
            final total = parseDouble(order['total']);

            return RefreshIndicator(
              onRefresh: _retry,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: DT.softShadow),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Order #ORD${order['id']}',
                                  style: const TextStyle(
                                      fontSize: 20 / 1.25,
                                      fontWeight: FontWeight.w700)),
                            ),
                            _statusPill(status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(dateText,
                            style:
                                const TextStyle(fontSize: 13.5, color: DT.sub)),
                        const SizedBox(height: 12),
                        _timelineStep(
                            done: true,
                            label: 'Order Placed',
                            icon: Icons.check_circle_outline_rounded),
                        _timelineStep(
                            done: status != 'PENDING_PAYMENT',
                            label: 'Mandi Purchase',
                            icon: Icons.inventory_2_outlined),
                        _timelineStep(
                            done: status == 'OUT_FOR_DELIVERY' ||
                                status == 'DELIVERED',
                            label: 'Out for Delivery',
                            icon: Icons.local_shipping_outlined),
                        _timelineStep(
                            done: status == 'DELIVERED',
                            label: 'Delivered',
                            icon: Icons.check_circle_outline_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: DT.softShadow),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Items',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ...items.map(
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${i['name']}',
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text('Qty: ${i['quantity']}',
                                          style: const TextStyle(
                                              fontSize: 12.5, color: DT.sub)),
                                    ],
                                  ),
                                ),
                                Text(
                                    '₹${parseDouble(i['unit_price']).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: DT.softShadow),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payment Details',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _line('Item Total', subtotal),
                        _line('GST', gst),
                        _line('Coupon', -discount),
                        _line('Wallet', -wallet),
                        const Divider(height: 14),
                        _line('Total', total, bold: true),
                      ],
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

  Widget _statusPill(String status) {
    final confirmed = status == 'CONFIRMED' ||
        status == 'DELIVERED' ||
        status == 'OUT_FOR_DELIVERY';
    final bg = confirmed ? const Color(0xFFDDF4E6) : const Color(0xFFFFEAC2);
    final fg = confirmed ? DT.primaryDark : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _timelineStep(
      {required bool done, required String label, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: done ? const Color(0xFFE8F0FF) : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon,
                color: done ? const Color(0xFF2563EB) : const Color(0xFF98A2B3),
                size: 20),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                  color: done ? DT.text : DT.sub)),
        ],
      ),
    );
  }

  Widget _line(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: bold ? DT.text : DT.sub,
                  fontSize: 13.5)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: bold ? DT.primaryDark : DT.text,
                  fontSize: 13.5)),
        ],
      ),
    );
  }
}

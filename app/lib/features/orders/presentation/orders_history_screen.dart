import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/parse_num.dart';
import '../../../shared/widgets/fresh_app_bar.dart';
import '../data/orders_repository.dart';

class OrdersHistoryScreen extends ConsumerStatefulWidget {
  const OrdersHistoryScreen({super.key});

  @override
  ConsumerState<OrdersHistoryScreen> createState() =>
      _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends ConsumerState<OrdersHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(ordersRepositoryProvider).fetchOrders();

  Future<void> _retry() async {
    final next = _load();

    setState(() {
      _ordersFuture = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DT.bg,
      appBar: FreshAppBar(
        title: 'My Orders',
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).maybePop();
            return;
          }
          context.go('/home');
        },
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Unable to load orders'),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              );
            }

            final orders = snapshot.data ?? const <Map<String, dynamic>>[];
            if (orders.isEmpty) {
              return RefreshIndicator(
                onRefresh: _retry,
                child: ListView(
                  children: const [
                    SizedBox(height: 180),
                    Center(child: Text('No past orders yet.')),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _retry,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                children: [
                  ...orders.map((o) => _orderCard(context, o)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _orderCard(BuildContext context, Map<String, dynamic> o) {
    final total = parseDouble(o['total']);
    final createdAt = DateTime.tryParse('${o['created_at'] ?? ''}');
    final dateText =
        createdAt == null ? 'Today' : DateFormat('d MMM y').format(createdAt);
    final status = '${o['status'] ?? 'CONFIRMED'}'.toUpperCase();
    final deliveryText = (status == 'CONFIRMED' || status == 'PENDING_PAYMENT')
        ? 'Delivery: 7 AM - 9 AM'
        : 'Delivery update in progress';
    final isDelivered = status == 'DELIVERED';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: DT.softShadow),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/order-details/${o['id']}'),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: const BoxDecoration(
                color: DT.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order #ORD${o['id']}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        const SizedBox(height: 1),
                        Text(dateText,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total',
                          style:
                              TextStyle(color: Colors.white, fontSize: 11.5)),
                      Text('₹${total.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22)),
                    ],
                  ),
                ],
              ),
            ),
            if (!isDelivered)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCE4EF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15)),
                            child: const Icon(
                                Icons.check_circle_outline_rounded,
                                color: Color(0xFF2563EB),
                                size: 21),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status == 'PENDING_PAYMENT'
                                      ? 'Payment Pending'
                                      : 'Order Placed',
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: DT.text),
                                ),
                                const SizedBox(height: 1),
                                Text(deliveryText,
                                    style: const TextStyle(
                                        fontSize: 11.5, color: DT.sub)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!isDelivered) ...[
                      _timelineStep(
                        done: true,
                        label: 'Order Placed',
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      _timelineStep(
                        done: status != 'PENDING_PAYMENT',
                        label: 'Mandi Purchase',
                        icon: Icons.inventory_2_outlined,
                      ),
                      _timelineStep(
                        done: status == 'OUT_FOR_DELIVERY' ||
                            status == 'DELIVERED',
                        label: 'Out for Delivery',
                        icon: Icons.local_shipping_outlined,
                      ),
                      _timelineStep(
                        done: status == 'DELIVERED',
                        label: 'Delivered',
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8EDC9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFF2C88F), width: 1.2),
                      ),
                      child: const Text(
                        '🎁 You earned ₹3 credits on this order',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFC2410C)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () =>
                            context.push('/order-details/${o['id']}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          side: const BorderSide(
                              color: Color(0xFFC3CAD4), width: 1.6),
                        ),
                        child: const Text('View Details',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: Color(0xFF344054))),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Order Delivered 🎉",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Hope you enjoy your fresh items!",
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _timelineStep(
      {required bool done, required String label, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: done ? const Color(0xFFE8F0FF) : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon,
                color: done ? const Color(0xFF2563EB) : const Color(0xFF98A2B3),
                size: 17),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                  color: done ? DT.text : DT.sub)),
        ],
      ),
    );
  }
}

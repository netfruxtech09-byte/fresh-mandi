import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/providers/delivery_provider.dart';
import '../../../shared/widgets/status_chip.dart';
import '../models/delivery_order.dart';
import 'order_detail_screen.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DeliveryProvider>().loadOrders();
    });
  }

  Color _statusColor(DeliveryOrderStatus s) {
    switch (s) {
      case DeliveryOrderStatus.delivered:
        return Colors.green;
      case DeliveryOrderStatus.notAvailable:
      case DeliveryOrderStatus.failed:
        return Colors.red;
      case DeliveryOrderStatus.rescheduled:
        return Colors.orange;
      case DeliveryOrderStatus.pending:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryProvider>();
    final orders = provider.filteredOrders;
    final error = provider.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Route Orders')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: provider.setQuery,
              decoration: const InputDecoration(
                hintText: 'Search by customer or flat',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (error != null && error.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: provider.loadOrders,
              child: provider.loadingOrders
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : orders.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text(
                            'No orders found for this route yet.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemBuilder: (context, i) {
                        final o = orders[i];
                        return Card(
                          child: ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailScreen(order: o),
                                ),
                              );
                            },
                            title: Text('${o.stopNumber}. ${o.customerName}'),
                            subtitle: Text(
                              '${o.building} / ${o.flat}\n₹${o.orderValue.toStringAsFixed(2)} • ${o.paymentType}',
                            ),
                            trailing: StatusChip(
                              label: o.deliveryStatus,
                              color: _statusColor(o.normalizedStatus),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

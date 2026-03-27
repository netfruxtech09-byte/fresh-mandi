import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/delivery_provider.dart';
import '../../collection/presentation/collection_summary_screen.dart';
import '../../orders/presentation/order_list_screen.dart';
import '../../orders/models/delivery_order.dart';
import '../../auth/presentation/login_screen.dart';
import '../../route/models/assigned_route.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeliveryProvider>().loadAssignedRoute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final delivery = context.watch<DeliveryProvider>();
    final route = delivery.assignedRoute;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Dashboard'),
        actions: [
          IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await auth.logout();
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => delivery.loadAssignedRoute(force: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              auth.user?.name ?? 'Delivery Executive',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (!delivery.initialized || delivery.loadingRoute)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Loading assigned route...'),
                    ],
                  ),
                ),
              )
            else if (delivery.error != null &&
                (delivery.error?.isNotEmpty ?? false))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Failed to load route',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        delivery.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonal(
                        onPressed: () =>
                            delivery.loadAssignedRoute(force: true),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (route == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No route assigned today'),
                ),
              )
            else ...[
              _kpiGrid(route, delivery.orders),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: (route.status == 'IN_PROGRESS' || route.status == 'COMPLETED' || route.status == 'SETTLEMENT_DONE')
                    ? null
                    : delivery.startRoute,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Route'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrderListScreen()),
                  );
                  if (!mounted) return;
                  await delivery.loadAssignedRoute(force: true);
                },
                icon: const Icon(Icons.route),
                label: const Text('Open Route Orders'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CollectionSummaryScreen(),
                    ),
                  );
                  if (!mounted) return;
                  await delivery.loadAssignedRoute(force: true);
                },
                icon: const Icon(Icons.summarize),
                label: const Text('Collection Summary'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: delivery.completeRoute,
                child: const Text('Complete Route'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpiGrid(AssignedRoute route, List<DeliveryOrder> orders) {
    final hasOrderSnapshot = orders.isNotEmpty;
    final deliveredFromOrders = orders
        .where((o) => o.deliveryStatus.toUpperCase() == 'DELIVERED')
        .length;
    final pendingFromOrders = orders.length - deliveredFromOrders;
    final totalFromOrders = orders.length;

    final items = [
      ['Route', route.routeCode],
      ['Sector', route.sector],
      ['Total Orders', '${hasOrderSnapshot ? totalFromOrders : route.totalOrders}'],
      ['Delivered', '${hasOrderSnapshot ? deliveredFromOrders : route.deliveredCount}'],
      ['Pending', '${hasOrderSnapshot ? pendingFromOrders : route.pendingCount}'],
      ['Collection', '₹${route.totalCollection.toStringAsFixed(2)}'],
    ];

    return GridView.builder(
      itemCount: items.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
      ),
      itemBuilder: (_, i) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  items[i][0],
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Text(
                  items[i][1],
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

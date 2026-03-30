import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/processing_state.dart';
import '../widgets/shared_widgets.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProcessingState>().loadDashboard();
    });
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      context.read<ProcessingState>().loadDashboard();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProcessingState>();
    final dashboard = state.dashboard;
    final alerts = state.alerts;

    return RefreshIndicator(
      onRefresh: () => state.loadDashboard(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            icon: Icons.hub,
            text:
                'Zero-manual sorting mode is active. Routes, building order, floor sequence, labels, crates, and inventory reservations are system-driven.',
          ),
          const SizedBox(height: 12),
          KpiGrid(
            items: [
              KpiItem('Total Routes', '${dashboard['total_routes'] ?? 0}'),
              KpiItem('Routes Packed', '${dashboard['routes_packed'] ?? 0}'),
              KpiItem('Routes Pending', '${dashboard['routes_pending'] ?? 0}'),
              KpiItem('Orders Packed', '${dashboard['orders_packed'] ?? 0}'),
              KpiItem(
                'Orders Remaining',
                '${dashboard['orders_remaining'] ?? 0}',
              ),
              KpiItem('Printed Orders', '${dashboard['printed_orders'] ?? 0}'),
              KpiItem('Packing Speed', '${dashboard['packing_speed'] ?? 0}/hr'),
              KpiItem(
                'Inventory Left',
                '${dashboard['inventory_remaining'] ?? 0}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  statusChip(
                    'Reserved: ${dashboard['inventory_reserved'] ?? 0}',
                    const Color(0xFF475467),
                    const Color(0xFFF2F4F7),
                  ),
                  statusChip(
                    'Low Stock: ${dashboard['low_stock_items'] ?? 0}',
                    const Color(0xFFB54708),
                    const Color(0xFFFFF2E5),
                  ),
                  statusChip(
                    'Alerts: ${dashboard['active_alerts'] ?? 0}',
                    const Color(0xFFB42318),
                    const Color(0xFFFFF1F1),
                  ),
                  statusChip(
                    'Active Staff: ${dashboard['active_staff'] ?? 0}',
                    const Color(0xFF155EEF),
                    const Color(0xFFEEF4FF),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (state.loadingDashboard)
            const LoadingBody(label: 'Refreshing dashboard...'),
          if ((state.error ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ErrorBox(text: state.error!),
            ),
          const Text(
            'Manager Alerts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            const EmptyBox(
              title: 'No Alerts',
              subtitle:
                  'Inventory and route processing look healthy right now.',
            )
          else
            ...alerts.map(
              (alert) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFB54708),
                    ),
                    title: Text(
                      '${alert['product_name'] ?? 'Inventory Alert'}',
                    ),
                    subtitle: Text('${alert['message'] ?? ''}'),
                    trailing: Text('${alert['route_code'] ?? '-'}'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

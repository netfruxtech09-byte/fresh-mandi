import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../state/processing_state.dart';
import '../widgets/shared_widgets.dart';

class RoutesTab extends StatefulWidget {
  const RoutesTab({super.key});

  @override
  State<RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends State<RoutesTab> {
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<ProcessingState>();
      await state.loadDashboard();
      await state.loadRoutes();
      if (mounted) {
        setState(() => _initialLoadDone = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProcessingState>();
    final routes = state.routes;
    final groupedRoutes = <String, List<Map<String, dynamic>>>{};
    for (final route in routes) {
      final sector =
          '${route['sector_name'] ?? route['sector_code'] ?? 'Unassigned'}';
      groupedRoutes.putIfAbsent(sector, () => []).add(route);
    }

    return RefreshIndicator(
      onRefresh: () => state.loadRoutes(regenerate: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            icon: Icons.route,
            text:
                'After cutoff, route grouping, building order, floor sorting, crate planning, and inventory reservation are generated automatically. No filters. No manual sorting.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.loadingRoutes
                      ? null
                      : () => state.loadRoutes(regenerate: true),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate Routes'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.loadingRoutes
                      ? null
                      : () => state.loadRoutes(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh List'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.loadingRoutes)
            const LoadingBody(label: 'Loading route list...'),
          if ((state.error ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ErrorBox(text: state.error!),
            ),
          if (_initialLoadDone && !state.loadingRoutes && routes.isEmpty)
            const EmptyBox(
              title: 'No Routes Available',
              subtitle:
                  'No pre-generated routes were found. Tap Generate Routes after the cutoff or when new orders are ready.',
            ),
          ...groupedRoutes.entries.expand(
            (entry) => [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              ...entry.value.map(
                (route) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RouteTile(
                    route: route,
                    onOpen: () {
                      final routeId = (route['route_id'] as num).toInt();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RouteOrdersScreen(
                            routeId: routeId,
                            routeCode: '${route['route_code']}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ],
      ),
    );
  }
}

class RouteOrdersScreen extends StatefulWidget {
  const RouteOrdersScreen({
    super.key,
    required this.routeId,
    required this.routeCode,
  });

  final int routeId;
  final String routeCode;

  @override
  State<RouteOrdersScreen> createState() => _RouteOrdersScreenState();
}

class _RouteOrdersScreenState extends State<RouteOrdersScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProcessingState>().loadRouteDetails(widget.routeId);
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      context.read<ProcessingState>().loadRouteDetails(widget.routeId);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _showLabelsAndPrint() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RouteLabelsSheet(
        routeId: widget.routeId,
        routeCode: widget.routeCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProcessingState>();
    final orders = state.orders;
    final summary = state.routeSummary;
    final routeType = state.routeType;
    final pendingOrders = orders
        .where(
          (order) => '${order['packing_status']}'.toLowerCase() != 'packed',
        )
        .toList();
    final packedOrders = orders
        .where(
          (order) => '${order['packing_status']}'.toLowerCase() == 'packed',
        )
        .toList();
    final groupedByBuilding = <String, List<Map<String, dynamic>>>{};
    for (final order in orders) {
      final building = '${order['building_name'] ?? 'Independent House'}';
      groupedByBuilding.putIfAbsent(building, () => []).add(order);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Route ${widget.routeCode}'),
        actions: [
          IconButton(
            onPressed: state.loadingOrders
                ? null
                : () => context.read<ProcessingState>().loadRouteDetails(
                    widget.routeId,
                  ),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () async {
              await _showLabelsAndPrint();
            },
            icon: const Icon(Icons.print),
          ),
        ],
      ),
      body: state.loadingOrders
          ? const LoadingBody(label: 'Loading route orders...')
          : RefreshIndicator(
              onRefresh: () => state.loadRouteDetails(widget.routeId),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          statusChip(
                            'Orders: ${orders.length}',
                            const Color(0xFF475467),
                            const Color(0xFFF2F4F7),
                          ),
                          statusChip(
                            'Packed: ${packedOrders.length}',
                            const Color(0xFF15803D),
                            const Color(0xFFE9F8EF),
                          ),
                          statusChip(
                            'Pending: ${pendingOrders.length}',
                            const Color(0xFFB54708),
                            const Color(0xFFFFF2E5),
                          ),
                          statusChip(
                            'Distance: ${summary['total_distance_km'] ?? 0} km',
                            const Color(0xFF155EEF),
                            const Color(0xFFEEF4FF),
                          ),
                          statusChip(
                            'ETA: ${summary['estimated_time_minutes'] ?? 0} min',
                            const Color(0xFF475467),
                            const Color(0xFFF2F4F7),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Route Item Summary',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ...((summary['item_summary'] as List? ?? const [])
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${(item as Map)['name']} - ${item['total_quantity']}',
                                  ),
                                ),
                              )
                              .toList()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Crate Assignment',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ...((summary['crate_plan'] as List? ?? const [])
                              .map(
                                (crate) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${(crate as Map)['crate_code']} -> Stops ${crate['stop_from']}-${crate['stop_to']}',
                                  ),
                                ),
                              )
                              .toList()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if ((state.error ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ErrorBox(text: state.error!),
                    ),
                  if (orders.isEmpty)
                    const EmptyBox(
                      title: 'No Orders',
                      subtitle: 'This route does not have orders for today.',
                    ),
                  if (routeType == 'APARTMENT') ...[
                    const Text(
                      'Buildings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...groupedByBuilding.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text('${entry.value.length} orders'),
                            trailing: FilledButton.tonal(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BuildingOrdersScreen(
                                      title: entry.key,
                                      routeId: widget.routeId,
                                      orders: entry.value,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Open'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    OrderSection(
                      title: 'Pending Orders',
                      orders: pendingOrders,
                      routeId: widget.routeId,
                    ),
                    const SizedBox(height: 12),
                    OrderSection(
                      title: 'Packed Orders',
                      orders: packedOrders,
                      routeId: widget.routeId,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class BuildingOrdersScreen extends StatelessWidget {
  const BuildingOrdersScreen({
    super.key,
    required this.title,
    required this.routeId,
    required this.orders,
  });

  final String title;
  final int routeId;
  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    final sorted = [...orders]
      ..sort((a, b) {
        final floorA = (a['floor_number'] as num?)?.toInt() ?? 0;
        final floorB = (b['floor_number'] as num?)?.toInt() ?? 0;
        if (floorA != floorB) return floorA.compareTo(floorB);
        return '${a['flat_number']}'.compareTo('${b['flat_number']}');
      });
    final pending = sorted
        .where((e) => '${e['packing_status']}'.toLowerCase() != 'packed')
        .toList();
    final packed = sorted
        .where((e) => '${e['packing_status']}'.toLowerCase() == 'packed')
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            icon: Icons.apartment,
            text:
                'Orders are locked to the system-generated floor and flat sequence. Staff can only open the next apartment order and pack.',
          ),
          const SizedBox(height: 12),
          OrderSection(
            title: 'Pending Orders',
            orders: pending,
            routeId: routeId,
          ),
          const SizedBox(height: 12),
          OrderSection(
            title: 'Packed Orders',
            orders: packed,
            routeId: routeId,
          ),
        ],
      ),
    );
  }
}

class OrderSection extends StatelessWidget {
  const OrderSection({
    super.key,
    required this.title,
    required this.orders,
    required this.routeId,
  });

  final String title;
  final List<Map<String, dynamic>> orders;
  final int routeId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                title == 'Packed Orders'
                    ? 'No packed orders yet.'
                    : 'No pending orders in this section.',
              ),
            ),
          )
        else
          ...orders.map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stop ${order['stop_number'] ?? '-'} • Floor ${order['floor_number'] ?? 0} • Flat ${order['flat_number'] ?? '-'}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${order['customer_name']}'),
                      const SizedBox(height: 2),
                      Text('${order['address']}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          smallStatusChip('${order['packing_status']}'),
                          smallStatusChip('${order['print_status']}'),
                          smallStatusChip('${order['crate_suggestion']}'),
                          if ((order['locked_by_name'] ?? '')
                                  .toString()
                                  .isNotEmpty &&
                              '${order['packing_status']}'.toLowerCase() !=
                                  'packed')
                            statusChip(
                              'Being packed by ${order['locked_by_name']}',
                              const Color(0xFFB42318),
                              const Color(0xFFFFF1F1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PackOrderScreen(
                                  order: order,
                                  routeId: routeId,
                                ),
                              ),
                            );
                            if (!context.mounted) return;
                            await context
                                .read<ProcessingState>()
                                .loadRouteDetails(routeId);
                          },
                          child: Text(
                            '${order['packing_status']}'.toLowerCase() ==
                                    'packed'
                                ? 'View Packed Order'
                                : 'Pack Order',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class RouteLabelsSheet extends StatefulWidget {
  const RouteLabelsSheet({
    super.key,
    required this.routeId,
    required this.routeCode,
  });

  final int routeId;
  final String routeCode;

  @override
  State<RouteLabelsSheet> createState() => _RouteLabelsSheetState();
}

class _RouteLabelsSheetState extends State<RouteLabelsSheet> {
  bool _printing = false;

  Future<void> _printLabels({String actionType = 'PRINT'}) async {
    final processingState = context.read<ProcessingState>();
    String? reason;
    if (actionType == 'REPRINT') {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reprint reason'),
          content: TextField(
            controller: ctrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Why are you reprinting these labels?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (reason == null || reason.trim().isEmpty) return;
    }

    setState(() => _printing = true);
    final error = await processingState.printRouteLabels(
      widget.routeId,
      actionType: actionType,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Route labels marked printed.')),
    );
    if (error == null) {
      await context.read<ProcessingState>().loadRouteDetails(widget.routeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = context.watch<ProcessingState>().routeLabels;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Route ${widget.routeCode} Labels',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...labels.map(
            (label) => Card(
              child: ListTile(
                title: Text(
                  'Order #${label['order_id']} • Stop ${label['stop_number']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${label['customer_name']}\n${label['sector_code']} • ${label['building_name']} • Floor ${label['floor_number']} • Flat ${label['flat_number']}\nQR: ${label['expected_barcode']}',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _printing ? null : () => _printLabels(),
                  child: _printing
                      ? const BtnLoader()
                      : const Text('Print All Labels'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _printing
                      ? null
                      : () => _printLabels(actionType: 'REPRINT'),
                  child: const Text('Reprint'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PackOrderScreen extends StatefulWidget {
  const PackOrderScreen({
    super.key,
    required this.order,
    required this.routeId,
  });

  final Map<String, dynamic> order;
  final int routeId;

  @override
  State<PackOrderScreen> createState() => _PackOrderScreenState();
}

class _PackOrderScreenState extends State<PackOrderScreen> {
  bool _locking = false;
  bool _packing = false;
  final _crateCtrl = TextEditingController();
  final Set<int> _checkedIndices = {};
  late final ProcessingState _processingState;

  bool get _isPacked =>
      '${widget.order['packing_status']}'.toLowerCase().trim() == 'packed';

  @override
  void initState() {
    super.initState();
    _processingState = context.read<ProcessingState>();
    _crateCtrl.text =
        '${widget.order['crate_suggestion'] ?? widget.order['crate_number'] ?? ''}';
    final items = (widget.order['items'] as List? ?? const []);
    for (var i = 0; i < items.length; i++) {
      _checkedIndices.add(i);
    }
    if (!_isPacked) {
      _lock();
    }
  }

  @override
  void dispose() {
    if (!_isPacked) {
      _processingState.unlockOrder((widget.order['order_id'] as num).toInt());
    }
    _crateCtrl.dispose();
    super.dispose();
  }

  Future<void> _lock() async {
    setState(() => _locking = true);
    final msg = await _processingState.lockOrder(
      (widget.order['order_id'] as num).toInt(),
    );
    if (!mounted) return;
    setState(() => _locking = false);
    if (msg != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  Future<void> _scanAndPack() async {
    final items = (widget.order['items'] as List? ?? const []);
    if (_checkedIndices.length != items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete item checklist before packing.'),
        ),
      );
      return;
    }

    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;

    setState(() => _packing = true);
    final msg = await _processingState.scanPack(
      (widget.order['order_id'] as num).toInt(),
      scanned,
      _crateCtrl.text,
    );

    if (!mounted) return;
    setState(() => _packing = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg ?? 'Packed successfully.')));

    if (msg == null) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.order['items'] as List? ?? const []);
    return Scaffold(
      appBar: AppBar(title: Text('Order #${widget.order['order_id']}')),
      body: _locking
          ? const LoadingBody(label: 'Locking order...')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.order['customer_name']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${widget.order['address']}'),
                        const SizedBox(height: 6),
                        Text(
                          'Suggested Crate: ${widget.order['crate_suggestion'] ?? '-'}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: PackingProgress(
                      scanDone: _isPacked,
                      itemsDone: _checkedIndices.length == items.length,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Item Checklist',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          const Text('No items available')
                        else
                          ...items.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = Map<String, dynamic>.from(
                              entry.value as Map,
                            );
                            final shortage =
                                (item['shortage_qty'] as num?)?.toDouble() ?? 0;
                            return CheckboxListTile(
                              value: _checkedIndices.contains(idx),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _checkedIndices.add(idx);
                                  } else {
                                    _checkedIndices.remove(idx);
                                  }
                                });
                              },
                              title: Text('${item['name']}'),
                              subtitle: Text(
                                'Qty: ${item['quantity']} • Reserved: ${item['reserved_qty']}'
                                '${shortage > 0 ? ' • Shortage: $shortage' : ''}',
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isPacked)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.verified, color: Color(0xFF15803D)),
                          SizedBox(width: 8),
                          Text(
                            'This order is already packed.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  TextField(
                    controller: _crateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Crate Number',
                      hintText: 'CRATE-A',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _packing ? null : _scanAndPack,
                      icon: _packing
                          ? const BtnLoader()
                          : const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan Barcode & Mark Packed'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Barcode'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Enter exact barcode'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Order Barcode'),
        actions: [
          IconButton(onPressed: _manualEntry, icon: const Icon(Icons.keyboard)),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (context, error) {
              return ScanFallback(
                message:
                    'Camera is not available right now. You can still enter barcode manually.',
                onManual: _manualEntry,
              );
            },
            onDetect: (capture) {
              if (capture.barcodes.isEmpty) return;
              final value = capture.barcodes.first.rawValue;
              if (value == null || value.isEmpty) return;
              Navigator.pop(context, value);
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter Barcode Manually'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanFallback extends StatelessWidget {
  const ScanFallback({
    super.key,
    required this.message,
    required this.onManual,
  });

  final String message;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 32,
                  color: Colors.black54,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onManual,
                    child: const Text('Enter Barcode'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

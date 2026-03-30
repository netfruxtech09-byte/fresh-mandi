import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/api_error_mapper.dart';
import '../../../features/route/data/route_repository.dart';

class CollectionSummaryScreen extends StatefulWidget {
  const CollectionSummaryScreen({super.key});

  @override
  State<CollectionSummaryScreen> createState() =>
      _CollectionSummaryScreenState();
}

class _CollectionSummaryScreenState extends State<CollectionSummaryScreen> {
  Map<String, dynamic>? summary;
  bool loading = true;
  bool confirmingHandover = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = context.read<RouteRepository>();
      final data = await repo.getDailySummary();
      if (!mounted) return;
      setState(() {
        summary = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = ApiErrorMapper.toMessage(
          e,
          fallback: 'Unable to load collection summary right now.',
        );
        loading = false;
      });
    }
  }

  Future<void> _confirmCashHandover() async {
    final data = summary;
    final routeId = (data?['route_id'] as num?)?.toInt() ?? 0;
    if (routeId <= 0 || confirmingHandover) return;

    setState(() => confirmingHandover = true);
    try {
      final repo = context.read<RouteRepository>();
      await repo.confirmCashHandover(routeId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash handover confirmed successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiErrorMapper.toMessage(
              e,
              fallback: 'Unable to confirm cash handover right now.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => confirmingHandover = false);
    }
  }

  String _formatHour(num? rawHour) {
    final hour = (rawHour ?? 0).toInt().clamp(0, 23);
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final twelveHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$twelveHour:00 $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final routeStatus = '${summary?['route_status'] ?? 'UNASSIGNED'}';
    final handoverAt = summary?['cash_handover_confirmed_at'];
    final canConfirmHandover =
        routeStatus == 'COMPLETED' && handoverAt == null && !confirmingHandover;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Collection Summary')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Failed to load summary'),
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xFFF5FAF3),
                    child: ListTile(
                      leading: const Icon(
                        Icons.schedule,
                        color: Color(0xFF2E7D32),
                      ),
                      title: const Text(
                        'Delivery Window',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${_formatHour(summary?['delivery_window_start_hour'] as num?)} - ${_formatHour(summary?['delivery_window_end_hour'] as num?)}',
                      ),
                    ),
                  ),
                  _tile('Route', '${summary?['route_code'] ?? '-'}'),
                  _tile('Route Status', routeStatus.replaceAll('_', ' ')),
                  _tile('Total Cash', '₹${summary?['total_cash'] ?? 0}'),
                  _tile('Total UPI', '₹${summary?['total_upi'] ?? 0}'),
                  _tile('Total Online', '₹${summary?['total_online'] ?? 0}'),
                  _tile(
                    'Pending Payments',
                    '${summary?['pending_payments'] ?? 0}',
                  ),
                  _tile(
                    'Delivered Orders',
                    '${summary?['total_delivered'] ?? 0}',
                  ),
                  _tile('Failed Orders', '${summary?['total_failed'] ?? 0}'),
                  _tile(
                    'Cash Handover',
                    handoverAt == null
                        ? 'Pending'
                        : '${summary?['cash_handover_amount'] ?? 0} confirmed',
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: canConfirmHandover ? _confirmCashHandover : null,
                    child: confirmingHandover
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            handoverAt != null
                                ? 'Cash Handover Confirmed'
                                : routeStatus == 'COMPLETED'
                                ? 'Confirm Cash Handover to Admin'
                                : 'Complete Route Before Handover',
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tile(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

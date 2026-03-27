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

  @override
  Widget build(BuildContext context) {
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
                  _tile('Total Cash', '₹${summary?['total_cash'] ?? 0}'),
                  _tile('Total UPI', '₹${summary?['total_upi'] ?? 0}'),
                  _tile('Total Online', '₹${summary?['total_online'] ?? 0}'),
                  _tile(
                    'Pending Payments',
                    '${summary?['pending_payments'] ?? 0}',
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cash handover confirmation sent.'),
                        ),
                      );
                    },
                    child: const Text('Confirm Cash Handover to Admin'),
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

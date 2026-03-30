import 'package:flutter/material.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.light = false,
  });

  final String title;
  final String subtitle;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: light ? Colors.white24 : const Color(0xFFE7F6EE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.local_shipping,
            color: light ? Colors.white : const Color(0xFF17834C),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: light ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: light ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AuthTopBanner extends StatelessWidget {
  const AuthTopBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17834C), Color(0xFF0E6237)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandHeader(
            title: 'Fresh Mandi Processing',
            subtitle: 'Smart route-based warehouse operations',
            light: true,
          ),
          SizedBox(height: 10),
          Text(
            'Auto-grouped by Sector -> Building -> Route',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 2),
          Text(
            'Goods receipt, quality approval, route packing, labels, and crate flow in one app.',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF17834C)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.black87)),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD5D5)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFFB42318))),
    );
  }
}

class KpiItem {
  KpiItem(this.label, this.value);

  final String label;
  final String value;
}

class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.items});

  final List<KpiItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 650
            ? 3
            : 2;
        return GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class PackingProgress extends StatelessWidget {
  const PackingProgress({
    super.key,
    required this.itemsDone,
    required this.scanDone,
  });

  final bool itemsDone;
  final bool scanDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Packing Steps',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _stepRow('1. Verify item checklist', itemsDone),
        const SizedBox(height: 6),
        _stepRow('2. Scan barcode / QR', scanDone),
      ],
    );
  }

  Widget _stepRow(String label, bool done) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: done ? const Color(0xFF15803D) : const Color(0xFF98A2B3),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: done ? const Color(0xFF15803D) : const Color(0xFF344054),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

Widget smallStatusChip(String status) {
  final normalized = status.toLowerCase();
  final (bg, fg) = switch (normalized) {
    'packed' => (const Color(0xFFE9F8EF), const Color(0xFF15803D)),
    'printed' => (const Color(0xFFFFF2E5), const Color(0xFFB54708)),
    _ => (const Color(0xFFF2F4F7), const Color(0xFF475467)),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      status.toUpperCase(),
      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11),
    ),
  );
}

Widget goodsStatusPill(String status) {
  final normalized = status.toLowerCase();
  final (bg, fg) = switch (normalized) {
    'approved_for_packing' => (
      const Color(0xFFE9F8EF),
      const Color(0xFF15803D),
    ),
    'awaiting_quality_check' => (
      const Color(0xFFFFF2E5),
      const Color(0xFFB54708),
    ),
    _ => (const Color(0xFFF2F4F7), const Color(0xFF475467)),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      status.replaceAll('_', ' ').toUpperCase(),
      style: TextStyle(
        color: fg,
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 0.2,
      ),
    ),
  );
}

Widget statusChip(String text, Color color, Color bg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class RouteTile extends StatelessWidget {
  const RouteTile({super.key, required this.route, required this.onOpen});

  final Map<String, dynamic> route;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final total = (route['total_orders'] as num?)?.toInt() ?? 0;
    final packed = (route['packed_orders'] as num?)?.toInt() ?? 0;
    final pending = (route['pending_orders'] as num?)?.toInt() ?? 0;
    final buildings = (route['total_buildings'] as num?)?.toInt() ?? 0;
    final crates = (route['total_crates'] as num?)?.toInt() ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sector ${route['sector_code']} - ${route['route_code']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                statusChip(
                  'Total: $total',
                  const Color(0xFF475467),
                  const Color(0xFFF2F4F7),
                ),
                statusChip(
                  'Packed: $packed',
                  const Color(0xFF15803D),
                  const Color(0xFFE9F8EF),
                ),
                statusChip(
                  'Pending: $pending',
                  const Color(0xFFB54708),
                  const Color(0xFFFFF2E5),
                ),
                statusChip(
                  'Buildings: $buildings',
                  const Color(0xFF155EEF),
                  const Color(0xFFEEF4FF),
                ),
                statusChip(
                  'Crates: $crates',
                  const Color(0xFF475467),
                  const Color(0xFFF2F4F7),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Distance ${route['total_distance_km'] ?? 0} km • ETA ${route['estimated_time_minutes'] ?? 0} min',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onOpen,
                child: const Text('Open Route'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyBox extends StatelessWidget {
  const EmptyBox({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.inbox, size: 34, color: Colors.black45),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingScaffold extends StatelessWidget {
  const LoadingScaffold({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: LoadingBody(label: label));
  }
}

class LoadingBody extends StatelessWidget {
  const LoadingBody({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 10),
          Text(label),
        ],
      ),
    );
  }
}

class BtnLoader extends StatelessWidget {
  const BtnLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2.2),
    );
  }
}

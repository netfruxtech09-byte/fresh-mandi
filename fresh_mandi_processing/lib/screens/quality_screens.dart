import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/processing_state.dart';
import '../widgets/shared_widgets.dart';

class QualityQueueTab extends StatefulWidget {
  const QualityQueueTab({super.key});

  @override
  State<QualityQueueTab> createState() => _QualityQueueTabState();
}

class _QualityQueueTabState extends State<QualityQueueTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProcessingState>().loadQualityQueue();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProcessingState>();
    return RefreshIndicator(
      onRefresh: () => state.loadQualityQueue(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            icon: Icons.fact_check,
            text:
                'Approve good stock, log damaged and waste quantities, and the app will push approved inventory into the route allocation pool.',
          ),
          const SizedBox(height: 12),
          if (state.loadingOps)
            const LoadingBody(label: 'Loading quality queue...'),
          if ((state.error ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ErrorBox(text: state.error!),
            ),
          if (state.qualityQueue.isEmpty && !state.loadingOps)
            const EmptyBox(
              title: 'No Quality Queue',
              subtitle: 'All received items are already approved for packing.',
            ),
          ...state.qualityQueue.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  title: Text(
                    '${item['product_name']} • ${item['quantity_received']} kg',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${item['supplier_name']} • Invoice ${item['invoice_number']}\nStatus: ${item['quality_status']}',
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      final approved = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => QualityApproveSheet(item: item),
                      );
                      if (approved == true && context.mounted) {
                        await context
                            .read<ProcessingState>()
                            .loadQualityQueue();
                      }
                    },
                    child: const Text('Approve'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QualityApproveSheet extends StatefulWidget {
  const QualityApproveSheet({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  State<QualityApproveSheet> createState() => _QualityApproveSheetState();
}

class _QualityApproveSheetState extends State<QualityApproveSheet> {
  late final TextEditingController _goodCtrl;
  late final TextEditingController _damagedCtrl;
  late final TextEditingController _wasteCtrl;
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _goodCtrl = TextEditingController(
      text: '${widget.item['quantity_received']}',
    );
    _damagedCtrl = TextEditingController(text: '0');
    _wasteCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _goodCtrl.dispose();
    _damagedCtrl.dispose();
    _wasteCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final good = double.tryParse(_goodCtrl.text.trim()) ?? -1;
    final damaged = double.tryParse(_damagedCtrl.text.trim()) ?? -1;
    final waste = double.tryParse(_wasteCtrl.text.trim()) ?? -1;
    if (good < 0 || damaged < 0 || waste < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid quality quantities.')),
      );
      return;
    }
    setState(() => _saving = true);
    final error = await context.read<ProcessingState>().approveQuality({
      'goods_received_item_id': widget.item['goods_received_item_id'],
      'product_id': widget.item['product_id'],
      'good_quantity': good,
      'damaged_quantity': damaged,
      'waste_quantity': waste,
      'damage_reason': _reasonCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
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
            'Approve ${widget.item['product_name']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _goodCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Good Quantity'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _damagedCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Damaged Quantity'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _wasteCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Waste Quantity'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Damage Reason (optional)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const BtnLoader() : const Text('Approve Batch'),
          ),
        ],
      ),
    );
  }
}

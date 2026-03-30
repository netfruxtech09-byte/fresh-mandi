import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/processing_state.dart';
import '../widgets/shared_widgets.dart';

class GoodsReceivedTab extends StatefulWidget {
  const GoodsReceivedTab({super.key});

  @override
  State<GoodsReceivedTab> createState() => _GoodsReceivedTabState();
}

class _GoodsReceivedTabState extends State<GoodsReceivedTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProcessingState>().loadGoodsReceived(ensureProducts: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProcessingState>();
    return RefreshIndicator(
      onRefresh: () => state.loadGoodsReceived(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GoodsHeroCard(
            onCreate: state.products.isEmpty
                ? null
                : () async {
                    final created = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GoodsReceiptEntryScreen(),
                      ),
                    );
                    if (created == true && context.mounted) {
                      await context.read<ProcessingState>().loadGoodsReceived();
                    }
                  },
          ),
          const SizedBox(height: 12),
          if (state.loadingOps)
            const LoadingBody(label: 'Loading goods received...'),
          if ((state.error ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ErrorBox(text: state.error!),
            ),
          if (state.goodsReceived.isEmpty && !state.loadingOps)
            const EmptyBox(
              title: 'No Goods Received',
              subtitle:
                  'Add the day’s mandi receipts here for inventory and quality control.',
            ),
          ...state.goodsReceived.map(
            (receipt) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GoodsReceiptCard(receipt: receipt),
            ),
          ),
        ],
      ),
    );
  }
}

class GoodsHeroCard extends StatelessWidget {
  const GoodsHeroCard({super.key, required this.onCreate});

  final Future<void> Function()? onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5FBF7), Color(0xFFE7F6EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9EBDD)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF17834C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inbound Stock',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Create mandi receipts before quality and packing.',
                        style: TextStyle(color: Color(0xFF475467)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Record receipts first. Once quality approves the good stock, the app moves it into available packing inventory automatically.',
              style: TextStyle(height: 1.45, color: Color(0xFF344054)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create New Receipt'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoodsReceiptCard extends StatelessWidget {
  const GoodsReceiptCard({super.key, required this.receipt});

  final Map<String, dynamic> receipt;

  @override
  Widget build(BuildContext context) {
    final items = (receipt['items'] as List? ?? const []);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${receipt['supplier_name']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Invoice ${receipt['invoice_number']}',
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                goodsStatusPill('${receipt['status']}'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _receiptMetaTile(
                    'Total Cost',
                    'Rs ${receipt['total_cost']}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _receiptMetaTile('Lines', '${items.length}')),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Products',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEAECF0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${(item as Map)['product_name']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF101828),
                          ),
                        ),
                      ),
                      Text(
                        '${item['quantity_received']} kg',
                        style: const TextStyle(color: Color(0xFF475467)),
                      ),
                      const SizedBox(width: 8),
                      smallStatusChip('${item['quality_status']}'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptMetaTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
        ],
      ),
    );
  }
}

class GoodsReceiptEntryScreen extends StatefulWidget {
  const GoodsReceiptEntryScreen({super.key});

  @override
  State<GoodsReceiptEntryScreen> createState() =>
      _GoodsReceiptEntryScreenState();
}

class _GoodsReceiptEntryScreenState extends State<GoodsReceiptEntryScreen> {
  final _supplierCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final List<GoodsLine> _lines = [GoodsLine()];
  bool _saving = false;

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _invoiceCtrl.dispose();
    _imageCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<ProcessingState>();
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final qty = double.tryParse(line.qtyCtrl.text.trim());
      final rate = double.tryParse(line.rateCtrl.text.trim());
      if (line.productId == null ||
          qty == null ||
          qty <= 0 ||
          rate == null ||
          rate < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete all receipt lines with product, quantity, and rate.',
            ),
          ),
        );
        return;
      }
      items.add({
        'product_id': line.productId,
        'quantity_received': qty,
        'rate_per_kg': rate,
      });
    }
    if (_supplierCtrl.text.trim().isEmpty || _invoiceCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier and invoice are required.')),
      );
      return;
    }

    setState(() => _saving = true);
    final error = await state.createGoodsReceived(
      supplierName: _supplierCtrl.text.trim(),
      invoiceNumber: _invoiceCtrl.text.trim(),
      imageUrl: _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
      items: items,
    );
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
    final products = context.watch<ProcessingState>().products;
    return Scaffold(
      appBar: AppBar(title: const Text('Mandi Goods Entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _supplierCtrl,
            decoration: const InputDecoration(labelText: 'Supplier Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _invoiceCtrl,
            decoration: const InputDecoration(labelText: 'Invoice Number'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _imageCtrl,
            decoration: const InputDecoration(
              labelText: 'Image URL (optional)',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Product List',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._lines.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: entry.value.productId,
                        items: products
                            .map(
                              (product) => DropdownMenuItem<int>(
                                value: (product['id'] as num).toInt(),
                                child: Text('${product['name']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => entry.value.productId = value),
                        decoration: const InputDecoration(labelText: 'Product'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: entry.value.qtyCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Quantity Received',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: entry.value.rateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Rate / kg',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _lines.add(GoodsLine())),
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
              ),
              if (_lines.length > 1) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      final removed = _lines.removeLast();
                      removed.dispose();
                    });
                  },
                  icon: const Icon(Icons.remove),
                  label: const Text('Remove'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const BtnLoader() : const Text('Save Receipt'),
          ),
        ],
      ),
    );
  }
}

class GoodsLine {
  int? productId;
  final qtyCtrl = TextEditingController();
  final rateCtrl = TextEditingController();

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}

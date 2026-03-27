import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/providers/delivery_provider.dart';
import '../models/delivery_order.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final DeliveryOrder order;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _paymentFormKey = GlobalKey<FormState>();
  final _cashCtrl = TextEditingController();
  String _failureReason = 'Not Available';
  bool _scanning = false;
  bool _collectingPayment = false;
  bool _markingDelivered = false;
  bool _markingFailed = false;

  bool get _busy =>
      _scanning || _collectingPayment || _markingDelivered || _markingFailed;

  @override
  void initState() {
    super.initState();
    final mode = widget.order.paymentType.toUpperCase();
    if (mode == 'UPI') {
      _cashCtrl.text = widget.order.orderValue.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  DeliveryOrder _resolveOrder(DeliveryProvider provider) {
    return provider.getOrderById(widget.order.orderId) ?? widget.order;
  }

  bool _isDelivered(DeliveryOrder o) =>
      o.deliveryStatus.toUpperCase() == 'DELIVERED';

  bool _isFailed(DeliveryOrder o) {
    final s = o.deliveryStatus.toUpperCase();
    return s == 'NOT_AVAILABLE' ||
        s == 'RESCHEDULED' ||
        s == 'FAILED' ||
        s == 'CANCELLED';
  }

  bool _isPaymentPaid(DeliveryOrder o) =>
      o.paymentStatus.toUpperCase() == 'PAID';

  bool _isCashLike(DeliveryOrder o) {
    final mode = o.paymentType.toUpperCase();
    return mode == 'CASH' || mode == 'COD';
  }

  bool _isUpi(DeliveryOrder o) => o.paymentType.toUpperCase() == 'UPI';

  bool _isOnline(DeliveryOrder o) => o.paymentType.toUpperCase() == 'ONLINE';

  bool _requiresPaymentCollection(DeliveryOrder o) => !_isOnline(o);

  bool _canScan(DeliveryOrder o) =>
      !_isDelivered(o) && !_isFailed(o) && !o.scanVerified;

  bool _canCollectPayment(DeliveryOrder o) {
    return !_isDelivered(o) &&
        !_isFailed(o) &&
        o.scanVerified &&
        _requiresPaymentCollection(o) &&
        !_isPaymentPaid(o);
  }

  bool _canMarkDelivered(DeliveryOrder o) {
    final paymentOk = _isOnline(o) || _isPaymentPaid(o);
    return !_isDelivered(o) && !_isFailed(o) && o.scanVerified && paymentOk;
  }

  String _paymentModeForApi(DeliveryOrder o) {
    final mode = o.paymentType.toUpperCase();
    if (mode == 'COD') return 'CASH';
    if (mode == 'CASH' || mode == 'UPI' || mode == 'ONLINE') return mode;
    return 'CASH';
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      final apiMsg = e.response?.data is Map
          ? ((e.response?.data['message'] ?? '') as String).trim()
          : '';
      final msg = apiMsg.isNotEmpty ? apiMsg : (e.message ?? 'Request failed');
      final lower = msg.toLowerCase();

      if (lower.contains('invalid barcode for this order')) {
        return msg.replaceFirst(
          'Invalid barcode for this order.',
          'Scanned barcode does not match this order.',
        );
      }
      if (lower.contains('invalid barcode')) {
        return 'Scanned barcode format is invalid.';
      }
      if (lower.contains('already verified')) {
        return 'Barcode is already verified for this order.';
      }
      if (lower.contains('already delivered')) {
        return 'Order is already delivered.';
      }
      if (lower.contains('scan verification required')) {
        return 'Scan barcode first, then continue.';
      }
      if (lower.contains('start route first')) {
        return 'Start route before this action.';
      }
      if (lower.contains('payment pending')) {
        return 'Collect payment first, then mark delivered.';
      }
      if (lower.contains('manual collection is not allowed')) {
        return 'Online payment is verified automatically by backend.';
      }
      if (lower.contains('does not belong to your route')) {
        return 'This order is not part of your assigned route.';
      }
      return ApiErrorMapper.toMessage(e);
    }

    return ApiErrorMapper.toMessage(e);
  }

  Future<void> _scanAndValidate(DeliveryOrder o) async {
    if (_busy || !_canScan(o)) return;
    setState(() => _scanning = true);
    try {
      final provider = context.read<DeliveryProvider>();
      final code = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const _ScanScreen()),
      );
      if (!mounted || code == null || code.isEmpty) return;

      await provider.scanOrder(code);
      await provider.loadAssignedRoute(force: true);
      if (!mounted) return;
      final latest = _resolveOrder(provider);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              latest.expectedBarcode.isNotEmpty
                  ? 'Barcode verified: ${latest.expectedBarcode}'
                  : 'Barcode verified successfully.',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _collectPayment(DeliveryOrder o) async {
    if (_busy || !_canCollectPayment(o)) return;
    setState(() => _collectingPayment = true);
    try {
      final provider = context.read<DeliveryProvider>();
      if (_isCashLike(o)) {
        final valid = _paymentFormKey.currentState?.validate() ?? false;
        if (!valid) return;
      }

      final amount = _isCashLike(o)
          ? (double.tryParse(_cashCtrl.text.trim()) ?? o.orderValue)
          : o.orderValue;

      final result = await provider.collectPayment(
        o.orderId,
        _paymentModeForApi(o),
        amount,
      );
      await provider.loadAssignedRoute(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result == DeliveryActionResult.recoveredFromTimeout
                  ? 'Payment confirmed after delayed server response.'
                  : 'Payment collected.',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
    } finally {
      if (mounted) setState(() => _collectingPayment = false);
    }
  }

  Future<void> _markDelivered(DeliveryOrder o) async {
    if (_busy || !_canMarkDelivered(o)) return;
    setState(() => _markingDelivered = true);
    try {
      final provider = context.read<DeliveryProvider>();
      final result = await provider.markDelivered(o.orderId);
      await provider.loadAssignedRoute(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result == DeliveryActionResult.recoveredFromTimeout
                  ? 'Delivery confirmed after delayed server response.'
                  : 'Order marked delivered.',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
    } finally {
      if (mounted) setState(() => _markingDelivered = false);
    }
  }

  Future<void> _markFailed(DeliveryOrder o) async {
    if (_busy || _isDelivered(o)) return;
    setState(() => _markingFailed = true);
    try {
      final provider = context.read<DeliveryProvider>();
      await provider.markFailed(o.orderId, _failureReason);
      await provider.loadAssignedRoute(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Order marked failed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
    } finally {
      if (mounted) setState(() => _markingFailed = false);
    }
  }

  Future<void> _openMap(DeliveryOrder o) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(o.address)}',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _call(DeliveryOrder o) async {
    final url = Uri.parse('tel:${o.phone}');
    await launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryProvider>();
    final o = _resolveOrder(provider);

    final delivered = _isDelivered(o);
    final failed = _isFailed(o);
    final paid = _isPaymentPaid(o);
    final canScan = _canScan(o);
    final canCollect = _canCollectPayment(o);
    final canDeliver = _canMarkDelivered(o);

    final stepScanDone = o.scanVerified;
    final stepPaymentDone = !_requiresPaymentCollection(o) || paid;
    final stepDeliveredDone = delivered;

    return Scaffold(
      appBar: AppBar(title: Text('Order #${o.orderId}')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _customerCard(o),
              const SizedBox(height: 10),
              _progressCard(
                scanDone: stepScanDone,
                paymentDone: stepPaymentDone,
                deliveredDone: stepDeliveredDone,
                failed: failed,
              ),
              const SizedBox(height: 10),
              _paymentCard(o, paid),
              const SizedBox(height: 12),
              if (canScan)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _scanAndValidate(o),
                  icon: _buttonIcon(_scanning, Icons.qr_code_scanner),
                  label: const Text('Step 1: Scan Barcode / QR'),
                )
              else
                _stepDoneTile(
                  title: 'Step 1 completed',
                  subtitle: o.scanVerified
                      ? 'Barcode verified${o.expectedBarcode.isNotEmpty ? ': ${o.expectedBarcode}' : ''}'
                      : delivered
                      ? 'Order already delivered.'
                      : 'No scan pending.',
                ),
              const SizedBox(height: 8),
              if (_requiresPaymentCollection(o))
                FilledButton.icon(
                  onPressed: (_busy || !canCollect)
                      ? null
                      : () => _collectPayment(o),
                  icon: _buttonIcon(_collectingPayment, Icons.payments),
                  label: Text(
                    paid
                        ? 'Step 2 complete: Payment Received'
                        : 'Step 2: Confirm Payment Received',
                  ),
                )
              else
                _stepDoneTile(
                  title: 'Step 2 completed',
                  subtitle: 'Online payment is verified by backend.',
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_busy || !canDeliver)
                    ? null
                    : () => _markDelivered(o),
                icon: _buttonIcon(_markingDelivered, Icons.check_circle),
                label: Text(
                  delivered
                      ? 'Step 3 complete: Delivered'
                      : 'Step 3: Mark Delivered',
                ),
              ),
              const SizedBox(height: 12),
              if (!delivered)
                DropdownButtonFormField<String>(
                  initialValue: _failureReason,
                  items: const [
                    DropdownMenuItem(
                      value: 'Not Available',
                      child: Text('Not Available'),
                    ),
                    DropdownMenuItem(
                      value: 'Wrong Address',
                      child: Text('Wrong Address'),
                    ),
                    DropdownMenuItem(value: 'Refused', child: Text('Refused')),
                    DropdownMenuItem(
                      value: 'Payment Issue',
                      child: Text('Payment Issue'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _failureReason = v ?? _failureReason),
                  decoration: const InputDecoration(
                    labelText: 'Unable to Deliver? Select Reason',
                  ),
                ),
              if (!delivered) const SizedBox(height: 8),
              if (!delivered)
                FilledButton.tonal(
                  onPressed: (_busy || delivered) ? null : () => _markFailed(o),
                  child: _markingFailed
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Mark Failed / Reschedule'),
                ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _customerCard(DeliveryOrder o) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              o.customerName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text('${o.building}, ${o.flat}'),
            Text(o.address),
            Text('Phone: ${o.phone}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _call(o),
                  icon: const Icon(Icons.call),
                  label: const Text('Call Customer'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openMap(o),
                  icon: const Icon(Icons.map),
                  label: const Text('Open Map'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard({
    required bool scanDone,
    required bool paymentDone,
    required bool deliveredDone,
    required bool failed,
  }) {
    final steps = [
      ['1', 'Scan Order', scanDone],
      ['2', 'Collect Payment', paymentDone],
      ['3', 'Mark Delivered', deliveredDone],
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery Progress',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      step[2] as bool
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: step[2] as bool
                          ? const Color(0xFF16A34A)
                          : Colors.black38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Step ${step[0]}: ${step[1]}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: step[2] as bool
                            ? const Color(0xFF166534)
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            if (failed)
              const Text(
                'Delivery currently marked as failed/rescheduled.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paymentCard(DeliveryOrder o, bool paid) {
    final isCashLike = _isCashLike(o);
    final isUpi = _isUpi(o);
    final isOnline = _isOnline(o);

    if (isUpi && _cashCtrl.text.trim().isEmpty) {
      _cashCtrl.text = o.orderValue.toStringAsFixed(2);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order & Payment',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('Amount: ₹${o.orderValue.toStringAsFixed(2)}'),
            Text('Payment Type: ${o.paymentType}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _tag(
                  label: paid ? 'Payment: PAID' : 'Payment: ${o.paymentStatus}',
                  color: paid
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFB45309),
                ),
                _tag(
                  label: o.scanVerified ? 'Scan Verified' : 'Scan Pending',
                  color: o.scanVerified
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF6B7280),
                ),
              ],
            ),
            if (o.expectedBarcode.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Order Barcode: ${o.expectedBarcode}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (isUpi) Text('UPI ID: ${AppConstants.upiId}'),
            if (isOnline)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Online payment is auto-verified from backend.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            if (isCashLike) ...[
              const SizedBox(height: 8),
              Form(
                key: _paymentFormKey,
                child: TextFormField(
                  controller: _cashCtrl,
                  keyboardType: TextInputType.number,
                  validator: Validators.amount,
                  decoration: const InputDecoration(
                    labelText: 'Collected Amount (Required)',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buttonIcon(bool loading, IconData icon) {
    if (loading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return Icon(icon);
  }

  Widget _stepDoneTile({required String title, required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF166534),
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF166534))),
        ],
      ),
    );
  }

  Widget _tag({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _enterCodeManually() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Barcode'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Enter exact order barcode',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Use Code'),
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
          IconButton(
            onPressed: _enterCodeManually,
            icon: const Icon(Icons.keyboard),
            tooltip: 'Enter code manually',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (capture.barcodes.isEmpty) return;
              final value = capture.barcodes.first.rawValue;
              if (value == null || value.isEmpty) return;
              Navigator.pop(context, value);
            },
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined, size: 36),
                      const SizedBox(height: 10),
                      Text(
                        'Camera is not available right now. You can still enter barcode manually.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _enterCodeManually,
                        child: const Text('Enter Code Manually'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _enterCodeManually,
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

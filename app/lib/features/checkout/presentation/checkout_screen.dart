import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/payment_service.dart';
import '../../../core/utils/parse_num.dart';
import '../../cart/data/cart_repository.dart';
import '../../wallet/data/wallet_repository.dart';
import 'checkout_state_provider.dart';

enum _PaymentUiMethod { upi, wallet, netBanking, card }

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  _PaymentUiMethod _selectedMethod = _PaymentUiMethod.upi;
  bool _placingOrder = false;

  @override
  void initState() {
    super.initState();
    // Invalidate providers after first frame to avoid inherited lookup during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(cartItemsProvider);
      ref.invalidate(cartCountProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final checkout = ref.watch(checkoutProvider);
    final checkoutConfigAsync = ref.watch(checkoutConfigProvider);
    final gstPercent =
        checkoutConfigAsync.valueOrNull?.gstPercent ?? AppConstants.gstPercent;
    final cartItemsAsync = ref.watch(cartItemsProvider);
    final dio = ref.watch(dioProvider);
    final paymentService = PaymentService(dio);

    final items = cartItemsAsync.valueOrNull ?? const [];
    final subtotal = items.fold<double>(
        0, (sum, item) => sum + item.product.price * item.quantity);
    final summary =
        calculateCheckoutTotals(
            subtotal: subtotal, checkout: checkout, gstPercent: gstPercent);
    final cartIsEmpty = !cartItemsAsync.isLoading && items.isEmpty;

    return Scaffold(
      backgroundColor: DT.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: DT.text),
        ),
        titleSpacing: 0,
        title: const Text('Complete Payment',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 20, color: DT.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE6ECE8)),
        ),
      ),
      body: cartItemsAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : cartIsEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F7EE),
                            borderRadius: BorderRadius.circular(43),
                          ),
                          child: const Icon(Icons.shopping_bag_outlined,
                              size: 42, color: DT.primaryDark),
                        ),
                        const SizedBox(height: 12),
                        const Text('Cart is empty',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text(
                          'Add items in cart before payment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: DT.sub, fontSize: 13.5),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: DT.primaryDark,
                            minimumSize: const Size(170, 46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => context.go('/cart'),
                          child: const Text('Go to Cart'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: DT.primaryDark,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: DT.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Amount to Pay',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          Text('₹${summary.total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          const Text('Your payment is secure and encrypted',
                              style: TextStyle(
                                  color: Color(0xFFE7FBEF), fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: const Color(0xFFB1D0FF), width: 1.4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              color: Color(0xFF2563EB), size: 26),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('Your payment is secure and encrypted',
                                style: TextStyle(
                                    color: Color(0xFF1D4ED8),
                                    fontSize: 18 / 1.2,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Payment Method',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: DT.text)),
                    const SizedBox(height: 10),
                    _paymentCard(
                      selected: _selectedMethod == _PaymentUiMethod.upi,
                      onTap: () {
                        setState(() => _selectedMethod = _PaymentUiMethod.upi);
                        ref
                            .read(checkoutProvider.notifier)
                            .setPaymentMode(PaymentMode.upi);
                      },
                      icon: Icons.phone_android_rounded,
                      iconColor: const Color(0xFF7E22CE),
                      iconBg: const Color(0xFFF0E8FA),
                      title: 'UPI',
                      subtitle: 'Google Pay, PhonePe, Paytm',
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<Map<String, dynamic>>(
                      future: ref.read(walletRepositoryProvider).fetchWallet(),
                      builder: (context, snapshot) {
                        final credits = snapshot.hasData
                            ? parseDouble(snapshot.data!['balance'])
                            : 0;
                        final enabled = credits > 0;
                        return _paymentCard(
                          selected: _selectedMethod == _PaymentUiMethod.wallet,
                          enabled: enabled,
                          onTap: enabled
                              ? () {
                                  setState(() => _selectedMethod =
                                      _PaymentUiMethod.wallet);
                                  ref
                                      .read(checkoutProvider.notifier)
                                      .setPaymentMode(PaymentMode.upi);
                                }
                              : null,
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: const Color(0xFF22A95B),
                          iconBg: const Color(0xFFE8F8EF),
                          title: 'Wallet',
                          subtitle:
                              'Use ₹${credits.toStringAsFixed(0)} credits',
                          trailingError:
                              enabled ? null : 'Insufficient balance',
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _paymentCard(
                      selected: _selectedMethod == _PaymentUiMethod.netBanking,
                      onTap: () {
                        setState(() =>
                            _selectedMethod = _PaymentUiMethod.netBanking);
                        ref
                            .read(checkoutProvider.notifier)
                            .setPaymentMode(PaymentMode.upi);
                      },
                      icon: Icons.account_balance_outlined,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE8F0FF),
                      title: 'Net Banking',
                      subtitle: 'All major banks',
                    ),
                    const SizedBox(height: 10),
                    _paymentCard(
                      selected: _selectedMethod == _PaymentUiMethod.card,
                      onTap: () {
                        setState(() => _selectedMethod = _PaymentUiMethod.card);
                        ref
                            .read(checkoutProvider.notifier)
                            .setPaymentMode(PaymentMode.upi);
                      },
                      icon: Icons.credit_card_outlined,
                      iconColor: const Color(0xFFEA580C),
                      iconBg: const Color(0xFFFCEFE2),
                      title: 'Credit/Debit Card',
                      subtitle: 'Visa, Mastercard, Rupay',
                    ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: DT.primaryDark,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            icon: _placingOrder
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.lock_outline_rounded),
            label: Text(
              _placingOrder
                  ? 'Processing...'
                  : 'Pay ₹${summary.total.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: (cartIsEmpty || _placingOrder)
                ? null
                : () async {
                    setState(() => _placingOrder = true);
                    try {
                      final serverCart = await ref
                          .read(cartRepositoryProvider)
                          .fetchCartItems();
                      if (serverCart.isEmpty) {
                        if (!context.mounted) return;
                        AppFeedback.error(context, 'Cart is empty');
                        context.go('/cart');
                        return;
                      }

                      final addressesRes = await dio.get('/addresses');
                      final addresses =
                          (addressesRes.data['data'] as List<dynamic>? ?? [])
                              .cast<Map>();
                      if (addresses.isEmpty) {
                        if (!context.mounted) return;
                        AppFeedback.error(
                            context, 'Please add a delivery address first.');
                        context.push('/address');
                        return;
                      }

                      final defaultAddress = addresses.firstWhere(
                        (a) => a['is_default'] == true,
                        orElse: () => addresses.first,
                      );
                      final addressId = parseInt(defaultAddress['id']);
                      if (addressId <= 0) {
                        if (!context.mounted) return;
                        AppFeedback.error(context, 'Invalid address selected.');
                        return;
                      }

                      final slotsRes = await dio.get('/slots');
                      final slots =
                          (slotsRes.data['data'] as List<dynamic>? ?? [])
                              .cast<Map>();
                      if (slots.isEmpty) {
                        if (!context.mounted) return;
                        AppFeedback.error(
                            context, 'No delivery slots available right now.');
                        return;
                      }

                      Map? selectedSlot;
                      for (final s in slots) {
                        final label = '${s['label'] ?? ''}'.trim();
                        if (label == checkout.slotLabel) {
                          selectedSlot = s;
                          break;
                        }
                      }
                      selectedSlot ??= slots.first;
                      final slotId = parseInt(selectedSlot['id']);
                      if (slotId <= 0) {
                        if (!context.mounted) return;
                        AppFeedback.error(
                            context, 'Invalid delivery slot selected.');
                        return;
                      }

                      final createOrderRes = await dio.post('/orders', data: {
                        'address_id': addressId,
                        'slot_id': slotId,
                        'payment_mode': checkout.paymentMode == PaymentMode.upi
                            ? 'UPI'
                            : 'COD',
                        if (checkout.couponCode.trim().isNotEmpty)
                          'coupon_code': checkout.couponCode.trim(),
                        'wallet_redeem': checkout.walletRedeem,
                      });

                      final order = Map<String, dynamic>.from(
                          (createOrderRes.data['data'] as Map?) ?? {});
                      final orderId = parseInt(order['id']);
                      if (orderId <= 0) {
                        if (!context.mounted) return;
                        AppFeedback.error(
                            context, 'Order creation failed. Please retry.');
                        return;
                      }

                      final orderTotal =
                          parseDouble(order['total'], fallback: summary.total);
                      if (AppConstants.paymentBypass) {
                        try {
                          await dio.post('/payments/mock-success', data: {
                            'order_id': orderId,
                            'provider': 'RAZORPAY',
                          });
                        } on DioException {
                          // Fallback for stale backend instances where mock route is unavailable.
                          final intent = await paymentService.createIntent(
                            orderId: orderId,
                            amount: orderTotal,
                            provider: 'RAZORPAY',
                          );
                          await paymentService.confirmSuccess(
                            reference: '${intent['reference']}',
                            orderId: orderId,
                          );
                        }
                      } else {
                        final intent = await paymentService.createIntent(
                            orderId: orderId,
                            amount: orderTotal,
                            provider: 'RAZORPAY');
                        await paymentService.confirmSuccess(
                            reference: '${intent['reference']}',
                            orderId: orderId);
                      }

                      ref.invalidate(cartItemsProvider);
                      ref.invalidate(cartCountProvider);

                      if (!context.mounted) return;
                      context.go(
                        '/order-confirmation?orderId=$orderId&total=${order['total'] ?? summary.total}&slot=${Uri.encodeComponent(checkout.slotLabel)}',
                      );
                    } on DioException catch (e) {
                      if (!context.mounted) return;
                      final msg = e.response?.data is Map
                          ? '${(e.response!.data as Map)['message'] ?? 'Checkout failed'}'
                          : 'Checkout failed';
                      AppFeedback.error(context, msg);
                    } catch (e, st) {
                      debugPrint('Checkout error: $e');
                      debugPrint('$st');
                      if (!context.mounted) return;
                      AppFeedback.error(context,
                          'Unable to place order right now. Please try again.');
                    } finally {
                      if (mounted) setState(() => _placingOrder = false);
                    }
                  },
          ),
        ),
      ),
    );
  }

  Widget _paymentCard({
    required bool selected,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    String? trailingError,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.62,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: DT.softShadow,
              border: selected
                  ? Border.all(color: const Color(0xFF86EFAC), width: 2)
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                      color: iconBg, borderRadius: BorderRadius.circular(31)),
                  child: Icon(icon, color: iconColor, size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: DT.text)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style:
                              const TextStyle(fontSize: 11.5, color: DT.sub)),
                      if (trailingError != null) ...[
                        const SizedBox(height: 2),
                        Text(trailingError,
                            style: const TextStyle(
                                fontSize: 11.5, color: Color(0xFFEF4444))),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      color: DT.primaryDark, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

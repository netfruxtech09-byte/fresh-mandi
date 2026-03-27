import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

enum PaymentMode { cod, upi }

class CheckoutState {
  const CheckoutState({
    this.slotLabel = '7:00 AM - 9:00 AM',
    this.couponCode = '',
    this.walletRedeem = 0,
    this.paymentMode = PaymentMode.upi,
    this.discount = 0,
  });

  final String slotLabel;
  final String couponCode;
  final double walletRedeem;
  final PaymentMode paymentMode;
  final double discount;

  CheckoutState copyWith({
    String? slotLabel,
    String? couponCode,
    double? walletRedeem,
    PaymentMode? paymentMode,
    double? discount,
  }) {
    return CheckoutState(
      slotLabel: slotLabel ?? this.slotLabel,
      couponCode: couponCode ?? this.couponCode,
      walletRedeem: walletRedeem ?? this.walletRedeem,
      paymentMode: paymentMode ?? this.paymentMode,
      discount: discount ?? this.discount,
    );
  }
}

class CheckoutConfig {
  const CheckoutConfig({
    required this.gstPercent,
    required this.cutoffHour,
  });

  final double gstPercent;
  final int cutoffHour;
}

class CheckoutNotifier extends StateNotifier<CheckoutState> {
  CheckoutNotifier() : super(const CheckoutState());

  void setSlot(String slot) => state = state.copyWith(slotLabel: slot);

  void setCoupon(String code) {
    final trimmed = code.trim().toUpperCase();
    final discount = trimmed == 'FRESH50' ? 50.0 : 0.0;
    state = state.copyWith(couponCode: trimmed, discount: discount);
  }

  void setWalletRedeem(double value) {
    state = state.copyWith(walletRedeem: value < 0 ? 0 : value);
  }

  void setPaymentMode(PaymentMode mode) => state = state.copyWith(paymentMode: mode);
}

final checkoutProvider = StateNotifierProvider<CheckoutNotifier, CheckoutState>((ref) {
  return CheckoutNotifier();
});

final checkoutConfigProvider = FutureProvider<CheckoutConfig>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/catalog/serviceability');
  final data = res.data['data'];
  if (data is Map) {
    final gst = double.tryParse('${data['gst_percent'] ?? AppConstants.gstPercent}') ??
        AppConstants.gstPercent;
    final cutoff =
        int.tryParse('${data['cutoff_hour'] ?? AppConstants.orderCutoffHour}') ??
            AppConstants.orderCutoffHour;
    return CheckoutConfig(gstPercent: gst, cutoffHour: cutoff);
  }
  return const CheckoutConfig(
    gstPercent: AppConstants.gstPercent,
    cutoffHour: AppConstants.orderCutoffHour,
  );
});

({double subtotal, double gst, double total}) calculateCheckoutTotals({
  required double subtotal,
  required CheckoutState checkout,
  required double gstPercent,
}) {
  final gst = ((subtotal - checkout.discount) * gstPercent / 100)
      .clamp(0, double.infinity)
      .toDouble();
  final total = (subtotal - checkout.discount + gst - checkout.walletRedeem)
      .clamp(0, double.infinity)
      .toDouble();

  return (subtotal: subtotal, gst: gst, total: total);
}

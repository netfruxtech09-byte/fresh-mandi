import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';

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

({double subtotal, double gst, double total}) calculateCheckoutTotals({
  required double subtotal,
  required CheckoutState checkout,
}) {
  final gst = ((subtotal - checkout.discount) * AppConstants.gstPercent / 100)
      .clamp(0, double.infinity)
      .toDouble();
  final total = (subtotal - checkout.discount + gst - checkout.walletRedeem)
      .clamp(0, double.infinity)
      .toDouble();

  return (subtotal: subtotal, gst: gst, total: total);
}

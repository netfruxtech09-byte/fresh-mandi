class Validators {
  static String? requiredField(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  static String? indianPhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    final normalized = v.replaceAll(RegExp(r'\s+'), '');
    final regex = RegExp(r'^[6-9]\d{9}$');
    if (!regex.hasMatch(normalized)) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    return null;
  }

  static String? otp6(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'OTP is required';
    if (!RegExp(r'^\d{6}$').hasMatch(v)) {
      return 'Enter a valid 6-digit OTP';
    }
    return null;
  }

  static String? indianPincode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Pincode is required';
    if (!RegExp(r'^[1-9]\d{5}$').hasMatch(v)) {
      return 'Enter a valid 6-digit Indian pincode';
    }
    return null;
  }

  static String? walletAmount(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final amount = double.tryParse(v);
    if (amount == null || amount < 0) {
      return 'Enter a valid amount';
    }
    return null;
  }

  static String? couponCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9]{4,12}$').hasMatch(v)) {
      return 'Enter a valid coupon code';
    }
    return null;
  }

  static String? minLength(String? value, {required int min, required String label}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$label is required';
    if (v.length < min) return '$label must be at least $min characters';
    return null;
  }

  static String? addressLabel(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Address label is required';
    if (v.length < 2) return 'Address label must be at least 2 characters';
    if (v.length > 24) return 'Address label is too long';
    if (!RegExp(r'^[A-Za-z ]+$').hasMatch(v)) {
      return 'Use only letters and spaces';
    }
    return null;
  }
}

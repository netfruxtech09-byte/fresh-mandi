class Validators {
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

  static String? amount(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Amount is required';
    final n = double.tryParse(v);
    if (n == null || n < 0) return 'Enter a valid amount';
    return null;
  }
}

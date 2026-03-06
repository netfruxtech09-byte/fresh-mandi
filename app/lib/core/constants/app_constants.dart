class AppConstants {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://backend-rho-one-36.vercel.app/api/v1',
  );
  static const paymentBypass = bool.fromEnvironment(
    'PAYMENT_BYPASS',
    defaultValue: true,
  );
  static const orderCutoffHour = 21;
  static const gstPercent = 5.0;
}

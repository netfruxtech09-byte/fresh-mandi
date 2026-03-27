import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'https://backend-rho-one-36.vercel.app/api/v1';

  static int get sessionTimeoutMinutes =>
      int.tryParse(dotenv.env['SESSION_TIMEOUT_MINUTES'] ?? '15') ?? 15;

  static String get upiId => dotenv.env['UPI_ID'] ?? 'freshmandi@upi';
}

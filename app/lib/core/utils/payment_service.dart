import 'package:dio/dio.dart';

class PaymentService {
  PaymentService(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> createIntent({
    required int orderId,
    required double amount,
    required String provider,
  }) async {
    final res = await _dio.post('/payments/create-intent', data: {
      'order_id': orderId,
      'amount': amount,
      'provider': provider,
    });
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  Future<void> confirmSuccess({required String reference, required int orderId}) async {
    await _dio.post('/payments/confirm', data: {
      'reference': reference,
      'order_id': orderId,
      'status': 'SUCCESS',
    });
  }
}

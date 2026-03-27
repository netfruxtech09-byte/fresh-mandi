import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/delivery_order.dart';

class OrderRepository {
  Future<List<DeliveryOrder>> getRouteOrders({required int routeId}) async {
    final res = await ApiClient.dio.get(
      '/delivery/route-orders',
      queryParameters: {'route_id': routeId},
    );
    final list = (res.data['data'] ?? []) as List;
    return list
        .map((e) => DeliveryOrder.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.stopNumber.compareTo(b.stopNumber));
  }

  Future<void> scanOrder({
    required int routeId,
    required String barcode,
  }) async {
    await ApiClient.dio.post(
      '/delivery/scan-order',
      data: {'route_id': routeId, 'barcode': barcode},
    );
  }

  Future<void> markDelivered({
    required int orderId,
    required int routeId,
  }) async {
    await _postCritical(
      '/delivery/mark-delivered',
      data: {'order_id': orderId, 'route_id': routeId},
    );
  }

  Future<void> markFailed({
    required int orderId,
    required String reason,
  }) async {
    await ApiClient.dio.post(
      '/delivery/mark-failed',
      data: {'order_id': orderId, 'failure_reason': reason},
    );
  }

  Future<void> collectPayment({
    required int orderId,
    required String paymentMode,
    required double amount,
  }) async {
    await _postCritical(
      '/delivery/collect-payment',
      data: {
        'order_id': orderId,
        'payment_mode': paymentMode,
        'collected_amount': amount,
      },
    );
  }

  Future<void> _postCritical(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final options = Options(
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
    );
    await ApiClient.dio.post(path, data: data, options: options);
  }
}

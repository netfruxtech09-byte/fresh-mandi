import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/api_client.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(ref.watch(dioProvider));
});

class OrdersRepository {
  OrdersRepository(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> fetchOrders() async {
    final res = await _dio.get('/orders');
    return ((res.data['data'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> fetchOrderDetails(int id) async {
    final res = await _dio.get('/orders/$id');
    return (res.data['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<int> reorder(int id) async {
    try {
      final res = await _dio.post('/orders/$id/reorder');
      final data = (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final itemsAdded = data['items_added'];
      if (itemsAdded is num) return itemsAdded.toInt();
      return 0;
    } on DioException catch (e) {
      throw mapDioError(e, fallback: 'Unable to reorder this order right now.');
    } catch (_) {
      throw AppException('Unable to reorder this order right now.');
    }
  }
}

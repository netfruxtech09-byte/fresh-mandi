import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/assigned_route.dart';

class RouteRepository {
  Future<AssignedRoute?> getAssignedRoute() async {
    Response<dynamic> res;
    try {
      res = await ApiClient.dio.get(
        '/delivery/assigned-route',
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
    } on DioException catch (e) {
      final timedOut =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      if (!timedOut) rethrow;

      // Retry once to absorb cold start delays from hosted backend.
      res = await ApiClient.dio.get(
        '/delivery/assigned-route',
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
    }

    final data = res.data['data'];
    if (data == null) return null;
    return AssignedRoute.fromJson(data as Map<String, dynamic>);
  }

  Future<void> startRoute(int routeId) async {
    await ApiClient.dio.post(
      '/delivery/start-route',
      data: {'route_id': routeId},
    );
  }

  Future<void> completeRoute(int routeId) async {
    await ApiClient.dio.post(
      '/delivery/complete-route',
      data: {'route_id': routeId},
    );
  }

  Future<void> confirmCashHandover(int routeId, {String? notes}) async {
    await ApiClient.dio.post(
      '/delivery/cash-handover',
      data: {
        'route_id': routeId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> getDailySummary() async {
    final res = await ApiClient.dio.get('/delivery/daily-summary');
    return (res.data['data'] ?? {}) as Map<String, dynamic>;
  }
}

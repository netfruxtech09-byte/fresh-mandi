import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../features/orders/data/order_repository.dart';
import '../../features/orders/models/delivery_order.dart';
import '../../features/route/data/route_repository.dart';
import '../../features/route/models/assigned_route.dart';
import '../../features/sync/services/offline_sync_service.dart';
import '../../core/utils/api_error_mapper.dart';

enum DeliveryActionResult { success, recoveredFromTimeout }

class DeliveryProvider extends ChangeNotifier {
  DeliveryProvider(this._routeRepo, this._orderRepo);

  final RouteRepository _routeRepo;
  final OrderRepository _orderRepo;

  AssignedRoute? assignedRoute;
  List<DeliveryOrder> orders = const [];
  String query = '';
  bool loadingRoute = false;
  bool loadingOrders = false;
  bool initialized = false;
  String? error;

  Future<void> loadAssignedRoute({bool force = false}) async {
    if (loadingRoute && !force) return;
    loadingRoute = true;
    error = null;
    notifyListeners();
    try {
      assignedRoute = await _routeRepo.getAssignedRoute();
      if (assignedRoute != null) {
        await loadOrders();
      } else {
        orders = const [];
      }
    } catch (e) {
      error = ApiErrorMapper.toMessage(
        e,
        fallback: 'Failed to load assigned route.',
      );
    } finally {
      loadingRoute = false;
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> startRoute() async {
    if (assignedRoute == null) return;
    try {
      await _routeRepo.startRoute(assignedRoute!.routeId);
      await loadAssignedRoute(force: true);
    } on DioException catch (e) {
      final isTimeout =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (!isTimeout) rethrow;
      await loadAssignedRoute(force: true);
      final status = assignedRoute?.status.toUpperCase();
      if (status == 'IN_PROGRESS' || status == 'COMPLETED') return;
      rethrow;
    }
  }

  Future<void> completeRoute() async {
    if (assignedRoute == null) return;
    try {
      await _routeRepo.completeRoute(assignedRoute!.routeId);
      await loadAssignedRoute(force: true);
    } on DioException catch (e) {
      final isTimeout =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (!isTimeout) rethrow;
      await loadAssignedRoute(force: true);
      final status = assignedRoute?.status.toUpperCase();
      if (status == 'COMPLETED' || status == 'SETTLEMENT_DONE') return;
      rethrow;
    }
  }

  Future<void> loadOrders() async {
    if (assignedRoute == null || loadingOrders) return;
    loadingOrders = true;
    error = null;
    notifyListeners();
    try {
      orders = await _orderRepo.getRouteOrders(routeId: assignedRoute!.routeId);
    } catch (e) {
      orders = const [];
      final message = ApiErrorMapper.toMessage(
        e,
        fallback: 'Failed to load route orders.',
      );
      // Completed route should still show dashboard without blocking error UI.
      if (message.toLowerCase().contains('route already completed for today')) {
        error = null;
      } else {
        error = message;
      }
    } finally {
      loadingOrders = false;
      notifyListeners();
    }
  }

  List<DeliveryOrder> get filteredOrders {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return orders;
    return orders.where((o) {
      return o.customerName.toLowerCase().contains(q) ||
          o.flat.toLowerCase().contains(q);
    }).toList();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  DeliveryOrder? getOrderById(int orderId) {
    for (final order in orders) {
      if (order.orderId == orderId) return order;
    }
    return null;
  }

  Future<void> scanOrder(String barcode) async {
    final route = assignedRoute;
    if (route == null) return;

    try {
      await _orderRepo.scanOrder(routeId: route.routeId, barcode: barcode);
      await loadOrders();
    } on DioException catch (e) {
      final queueForRetry =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown;
      if (!queueForRetry) rethrow;
      await OfflineSyncService.instance.enqueue(
        endpoint: '/scan-order',
        payload: {'route_id': route.routeId, 'barcode': barcode},
      );
      rethrow;
    }
  }

  Future<DeliveryActionResult> markDelivered(int orderId) async {
    final route = assignedRoute;
    if (route == null) return DeliveryActionResult.success;

    final conn = await Connectivity().checkConnectivity();
    final isOffline = conn.contains(ConnectivityResult.none);

    if (isOffline) {
      await OfflineSyncService.instance.enqueue(
        endpoint: '/mark-delivered',
        payload: {'order_id': orderId, 'route_id': route.routeId},
      );
      await loadOrders();
      return DeliveryActionResult.success;
    }

    try {
      await _orderRepo.markDelivered(orderId: orderId, routeId: route.routeId);
      await loadOrders();
      return DeliveryActionResult.success;
    } on DioException catch (e) {
      final isTimeout =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (!isTimeout) rethrow;

      // Timeout can happen even when backend has already marked delivery.
      if (await _waitForOrderState(
        orderId: orderId,
        matches: (o) => o.deliveryStatus.toUpperCase() == 'DELIVERED',
      )) {
        return DeliveryActionResult.recoveredFromTimeout;
      }
      rethrow;
    }
  }

  Future<void> markFailed(int orderId, String reason) async {
    await _orderRepo.markFailed(orderId: orderId, reason: reason);
    await loadOrders();
  }

  Future<DeliveryActionResult> collectPayment(
    int orderId,
    String paymentMode,
    double amount,
  ) async {
    try {
      await _orderRepo.collectPayment(
        orderId: orderId,
        paymentMode: paymentMode,
        amount: amount,
      );
      await loadOrders();
      return DeliveryActionResult.success;
    } on DioException catch (e) {
      final isTimeout =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (!isTimeout) rethrow;

      // Timeout can occur after backend has already committed payment.
      if (await _waitForOrderState(
        orderId: orderId,
        matches: (o) => o.paymentStatus.toUpperCase() == 'PAID',
      )) {
        return DeliveryActionResult.recoveredFromTimeout;
      }
      rethrow;
    }
  }

  Future<bool> _waitForOrderState({
    required int orderId,
    required bool Function(DeliveryOrder order) matches,
    int attempts = 3,
    Duration stepDelay = const Duration(seconds: 1),
  }) async {
    for (var i = 0; i < attempts; i++) {
      await Future<void>.delayed(stepDelay);
      await loadOrders();
      final latest = getOrderById(orderId);
      if (latest != null && matches(latest)) return true;
    }
    return false;
  }
}

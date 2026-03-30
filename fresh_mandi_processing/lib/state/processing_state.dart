import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_service.dart';

class ProcessingState extends ChangeNotifier {
  ProcessingState(this._api);

  final ApiService _api;

  bool loadingDashboard = false;
  bool loadingRoutes = false;
  bool loadingOrders = false;
  bool loadingOps = false;
  String? error;
  Map<String, dynamic> dashboard = const {};
  List<Map<String, dynamic>> alerts = const [];
  List<Map<String, dynamic>> routes = const [];
  Map<String, dynamic> routeSummary = const {};
  String routeType = 'MIXED';
  List<Map<String, dynamic>> orders = const [];
  List<Map<String, dynamic>> routeLabels = const [];
  List<Map<String, dynamic>> goodsReceived = const [];
  List<Map<String, dynamic>> qualityQueue = const [];
  List<Map<String, dynamic>> products = const [];
  DateTime? lastRoutesLoadedAt;

  Future<void> loadDashboard() async {
    loadingDashboard = true;
    error = null;
    notifyListeners();
    try {
      dashboard = await _api.dashboard();
      alerts = await _api.inventoryAlerts();
    } catch (e) {
      error = _api.mapError(e);
    } finally {
      loadingDashboard = false;
      notifyListeners();
    }
  }

  Future<void> loadRoutes({bool regenerate = false}) async {
    loadingRoutes = true;
    error = null;
    notifyListeners();
    try {
      if (regenerate) {
        await _api.generateRoutes().timeout(
          const Duration(seconds: 95),
          onTimeout: () => throw TimeoutException(
            'Route generation is still taking too long. Please try again in a moment.',
          ),
        );
      }
      routes = await _api.routesToday().timeout(
        const Duration(seconds: 65),
        onTimeout: () => throw TimeoutException(
          'Route list is taking too long to load. Please tap Refresh List again.',
        ),
      );
      lastRoutesLoadedAt = DateTime.now();
    } on TimeoutException catch (e) {
      error = e.message ?? 'Route request timed out. Please retry.';
    } catch (e) {
      error = _api.mapError(e);
    } finally {
      loadingRoutes = false;
      notifyListeners();
    }
  }

  Future<void> loadRouteDetails(int routeId) async {
    loadingOrders = true;
    error = null;
    notifyListeners();
    try {
      routeSummary = await _api.routeSummary(routeId);
      final routeOrderData = await _api.routeOrders(routeId);
      routeType = '${routeOrderData['route_type'] ?? 'MIXED'}';
      orders = ((routeOrderData['orders'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      routeLabels = await _api.routeLabels(routeId);
    } catch (e) {
      error = _api.mapError(e);
    } finally {
      loadingOrders = false;
      notifyListeners();
    }
  }

  Future<void> loadGoodsReceived({bool ensureProducts = false}) async {
    loadingOps = true;
    error = null;
    notifyListeners();
    try {
      goodsReceived = await _api.goodsReceived();
      if (ensureProducts || products.isEmpty) {
        products = await _api.products();
      }
    } catch (e) {
      error = _api.mapError(e);
    } finally {
      loadingOps = false;
      notifyListeners();
    }
  }

  Future<String?> createGoodsReceived({
    required String supplierName,
    required String invoiceNumber,
    String? imageUrl,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await _api.createGoodsReceived(
        supplierName: supplierName,
        invoiceNumber: invoiceNumber,
        imageUrl: imageUrl,
        items: items,
      );
      await loadGoodsReceived();
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<void> loadQualityQueue() async {
    loadingOps = true;
    error = null;
    notifyListeners();
    try {
      qualityQueue = await _api.qualityQueue();
      if (products.isEmpty) {
        products = await _api.products();
      }
    } catch (e) {
      error = _api.mapError(e);
    } finally {
      loadingOps = false;
      notifyListeners();
    }
  }

  Future<String?> approveQuality(Map<String, dynamic> payload) async {
    try {
      await _api.approveQuality(payload);
      await Future.wait([loadQualityQueue(), loadDashboard()]);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<String?> lockOrder(int orderId) async {
    try {
      await _api.lockOrder(orderId);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<String?> unlockOrder(int orderId) async {
    try {
      await _api.unlockOrder(orderId);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<String?> scanPack(int orderId, String barcode, String? crate) async {
    try {
      await _api.scanPack(orderId, barcode, crate);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<String?> printRouteLabels(
    int routeId, {
    String actionType = 'PRINT',
    String? reason,
  }) async {
    try {
      await _api.printRouteLabels(
        routeId,
        actionType: actionType,
        reason: reason,
      );
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }
}

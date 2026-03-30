class AssignedRoute {
  AssignedRoute({
    required this.routeId,
    required this.routeCode,
    required this.sector,
    required this.totalOrders,
    required this.deliveredCount,
    required this.pendingCount,
    required this.totalCollection,
    required this.status,
    required this.deliveryWindowStartHour,
    required this.deliveryWindowEndHour,
  });

  final int routeId;
  final String routeCode;
  final String sector;
  final int totalOrders;
  final int deliveredCount;
  final int pendingCount;
  final double totalCollection;
  final String status;
  final int deliveryWindowStartHour;
  final int deliveryWindowEndHour;

  String get deliveryWindowLabel =>
      '${_formatHour(deliveryWindowStartHour)} - ${_formatHour(deliveryWindowEndHour)}';

  factory AssignedRoute.fromJson(Map<String, dynamic> json) {
    return AssignedRoute(
      routeId: (json['route_id'] as num?)?.toInt() ?? 0,
      routeCode: (json['route_code'] ?? '-') as String,
      sector: (json['sector'] ?? '-') as String,
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      deliveredCount: (json['delivered_count'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      totalCollection: (json['total_collection_amount'] as num?)?.toDouble() ?? 0,
      status: (json['route_status'] ?? 'ASSIGNED') as String,
      deliveryWindowStartHour:
          (json['delivery_window_start_hour'] as num?)?.toInt() ?? 6,
      deliveryWindowEndHour:
          (json['delivery_window_end_hour'] as num?)?.toInt() ?? 10,
    );
  }

  static String _formatHour(int hour) {
    final normalized = hour.clamp(0, 23);
    final suffix = normalized >= 12 ? 'PM' : 'AM';
    final twelveHour = normalized % 12 == 0 ? 12 : normalized % 12;
    return '$twelveHour:00 $suffix';
  }
}

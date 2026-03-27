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
  });

  final int routeId;
  final String routeCode;
  final String sector;
  final int totalOrders;
  final int deliveredCount;
  final int pendingCount;
  final double totalCollection;
  final String status;

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
    );
  }
}

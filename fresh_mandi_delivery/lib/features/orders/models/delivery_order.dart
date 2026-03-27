enum DeliveryOrderStatus {
  pending,
  delivered,
  notAvailable,
  rescheduled,
  failed,
}

int _toInt(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? fallback;
}

double _toDouble(dynamic v, {double fallback = 0}) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? fallback;
}

class DeliveryOrder {
  DeliveryOrder({
    required this.orderId,
    required this.stopNumber,
    required this.customerName,
    required this.phone,
    required this.building,
    required this.flat,
    required this.orderValue,
    required this.paymentType,
    required this.paymentStatus,
    required this.deliveryStatus,
    required this.scanVerified,
    required this.expectedBarcode,
    required this.address,
    required this.items,
    required this.routeId,
  });

  final int orderId;
  final int stopNumber;
  final String customerName;
  final String phone;
  final String building;
  final String flat;
  final double orderValue;
  final String paymentType;
  final String paymentStatus;
  final String deliveryStatus;
  final bool scanVerified;
  final String expectedBarcode;
  final String address;
  final List<Map<String, dynamic>> items;
  final int routeId;

  DeliveryOrderStatus get normalizedStatus {
    switch (deliveryStatus.toUpperCase()) {
      case 'DELIVERED':
        return DeliveryOrderStatus.delivered;
      case 'NOT_AVAILABLE':
        return DeliveryOrderStatus.notAvailable;
      case 'RESCHEDULED':
        return DeliveryOrderStatus.rescheduled;
      case 'FAILED':
        return DeliveryOrderStatus.failed;
      default:
        return DeliveryOrderStatus.pending;
    }
  }

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry('$k', v)))
              .toList()
        : const <Map<String, dynamic>>[];

    return DeliveryOrder(
      orderId: _toInt(json['order_id'], fallback: _toInt(json['id'])),
      stopNumber: _toInt(json['stop_number']),
      customerName: (json['customer_name'] ?? '-') as String,
      phone: (json['phone'] ?? '') as String,
      building: (json['building'] ?? '-') as String,
      flat: (json['flat'] ?? '-') as String,
      orderValue: _toDouble(json['order_value']),
      paymentType: (json['payment_type'] ?? 'PENDING') as String,
      paymentStatus: (json['payment_status'] ?? 'PENDING') as String,
      deliveryStatus: (json['delivery_status'] ?? 'PENDING') as String,
      scanVerified: json['delivery_scan_verified'] == true,
      expectedBarcode: (json['expected_barcode'] ?? '') as String,
      address: (json['address'] ?? '-') as String,
      routeId: _toInt(json['route_id']),
      items: parsedItems,
    );
  }
}

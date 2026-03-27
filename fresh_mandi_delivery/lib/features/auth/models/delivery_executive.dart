class DeliveryExecutive {
  DeliveryExecutive({
    required this.id,
    required this.name,
    required this.phone,
  });

  final int id;
  final String name;
  final String phone;

  factory DeliveryExecutive.fromJson(Map<String, dynamic> json) {
    return DeliveryExecutive(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '-') as String,
      phone: (json['phone'] ?? '') as String,
    );
  }
}

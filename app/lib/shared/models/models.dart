class Category {
  Category({required this.id, required this.name, required this.type});
  final String id;
  final String name;
  final String type;
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.unit,
    required this.categoryId,
    this.subcategory,
    this.imageUrl,
  });
  final String id;
  final String name;
  final double price;
  final String unit;
  final String categoryId;
  final String? subcategory;
  final String? imageUrl;
}

class CartItem {
  CartItem({required this.product, required this.quantity});
  final Product product;
  final int quantity;

  CartItem copyWith({Product? product, int? quantity}) =>
      CartItem(product: product ?? this.product, quantity: quantity ?? this.quantity);
}

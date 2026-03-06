import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void add(Product product) {
    final index = state.indexWhere((e) => e.product.id == product.id);
    if (index == -1) {
      state = [...state, CartItem(product: product, quantity: 1)];
      return;
    }
    final item = state[index];
    final updated = [...state];
    updated[index] = item.copyWith(quantity: item.quantity + 1);
    state = updated;
  }

  void updateQty(String productId, int qty) {
    if (qty <= 0) {
      state = state.where((e) => e.product.id != productId).toList();
      return;
    }
    state = [
      for (final i in state)
        if (i.product.id == productId) i.copyWith(quantity: qty) else i,
    ];
  }

  double subtotal() => state.fold(0, (sum, i) => sum + (i.product.price * i.quantity));
}

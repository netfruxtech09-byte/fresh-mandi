import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/parse_num.dart';
import '../../../shared/models/models.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return CartRepository(ref.watch(dioProvider));
});

final cartItemsProvider = FutureProvider<List<CartItem>>((ref) async {
  return ref.watch(cartRepositoryProvider).fetchCartItems();
});

final cartSuggestionsProvider = FutureProvider<List<Product>>((ref) async {
  return ref.watch(cartRepositoryProvider).fetchSuggestions();
});

final cartCountProvider = FutureProvider<int>((ref) async {
  final items = await ref.watch(cartRepositoryProvider).fetchCartItems();
  return items.length;
});

class CartRepository {
  CartRepository(this._dio);
  final Dio _dio;

  Future<List<CartItem>> fetchCartItems() async {
    final res = await _dio.get('/cart');
    final data = (res.data['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => CartItem(
              product: Product(
                id: '${e['product_id']}',
                name: '${e['name']}',
                price: parseDouble(e['price']),
                unit: '${e['unit']}',
                categoryId: '',
                imageUrl: _normalizeImageUrl(e['image_url']?.toString()),
              ),
              quantity: parseInt(e['quantity'], fallback: 1),
            ))
        .toList();
  }

  Future<void> upsertItem({required int productId, required int quantity}) async {
    if (quantity <= 0) {
      await _dio.delete('/cart/items/$productId');
      return;
    }
    await _dio.post('/cart/items', data: {'product_id': productId, 'quantity': quantity});
  }

  Future<List<Product>> fetchSuggestions() async {
    final res = await _dio.get('/cart/suggestions');
    final data = (res.data['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => Product(
              id: '${e['id']}',
              name: '${e['name']}',
              price: parseDouble(e['price']),
              unit: '${e['unit']}',
              categoryId: '',
              imageUrl: _normalizeImageUrl(e['image_url']?.toString()),
            ))
        .toList();
  }

  String? _normalizeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final origin = _dio.options.baseUrl.replaceFirst('/api/v1', '');
    if (url.startsWith('/')) return '$origin$url';
    return '$origin/$url';
  }
}

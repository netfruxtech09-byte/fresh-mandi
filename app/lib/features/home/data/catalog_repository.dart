import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/parse_num.dart';
import '../../../shared/models/models.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(dioProvider));
});

class CatalogRepository {
  CatalogRepository(this._dio);
  final Dio _dio;
  static const _productsBox = 'cached_products';

  Future<List<Category>> fetchCategories() async {
    final res = await _dio.get('/catalog/categories');
    final data = (res.data['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => Category(
            id: '${e['id']}', name: '${e['name']}', type: '${e['type']}'))
        .toList();
  }

  Future<List<Product>> fetchProducts({
    String? categoryId,
    String? subcategory,
    String? q,
  }) async {
    final cacheKey = _productsCacheKey(
      categoryId: categoryId,
      subcategory: subcategory,
      q: q,
    );
    try {
      final res = await _dio.get('/catalog/products', queryParameters: {
        if (categoryId != null) 'categoryId': categoryId,
        if (subcategory != null) 'subcategory': subcategory,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      });
      final data = (res.data['data'] as List<dynamic>?) ?? [];

      final box = await Hive.openBox(_productsBox);
      await box.put(cacheKey, data);

      return data.map(_toProduct).toList();
    } catch (_) {
      final box = await Hive.openBox(_productsBox);
      final cached = (box.get(cacheKey) as List<dynamic>?) ?? [];
      return cached.map(_toProduct).toList();
    }
  }

  String _productsCacheKey({
    String? categoryId,
    String? subcategory,
    String? q,
  }) {
    final normalizedQ = (q ?? '').trim().toLowerCase();
    final normalizedSub = (subcategory ?? '').trim().toLowerCase();
    return 'products:${categoryId ?? ''}:$normalizedSub:$normalizedQ';
  }

  Product _toProduct(dynamic e) {
    final rawImage = e['image_url']?.toString();
    return Product(
      id: '${e['id']}',
      name: '${e['name']}',
      price: parseDouble(e['price']),
      unit: '${e['unit']}',
      categoryId: '${e['category_id']}',
      subcategory: e['subcategory']?.toString(),
      imageUrl: _normalizeImageUrl(rawImage),
    );
  }

  String? _normalizeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final origin = _dio.options.baseUrl.replaceFirst('/api/v1', '');
    if (url.startsWith('/')) return '$origin$url';
    return '$origin/$url';
  }
}

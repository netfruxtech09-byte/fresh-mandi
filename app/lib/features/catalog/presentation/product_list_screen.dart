import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/fresh_ui.dart';
import '../../../shared/widgets/product_grid_card.dart';
import '../../cart/data/cart_repository.dart';
import '../../home/data/catalog_repository.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key, required this.type});
  final String type;

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  String filter = 'All';
  late Future<List<Product>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = _loadProducts();
  }

  Future<List<Product>> _loadProducts() async {
    final catalog = ref.read(catalogRepositoryProvider);
    final categories = await catalog.fetchCategories();
    final category = categories
        .where((c) => c.type.toLowerCase() == widget.type.toLowerCase())
        .firstOrNull;
    return catalog.fetchProducts(categoryId: category?.id);
  }

  Future<void> _retry() async {
    final next = _loadProducts();
    setState(() => _productsFuture = next);
    await next;
  }

  String _productRoute(Product p) {
    return '/product/${p.id}?name=${Uri.encodeComponent(p.name)}'
        '&price=${p.price}'
        '&unit=${Uri.encodeComponent(p.unit)}'
        '&image=${Uri.encodeComponent(p.imageUrl ?? '')}'
        '&categoryId=${Uri.encodeComponent(p.categoryId)}';
  }

  bool _isSeasonal(Product p) {
    final sub = (p.subcategory ?? '').toLowerCase();
    return sub.contains('seasonal');
  }

  bool _isOrganic(Product p) {
    final sub = (p.subcategory ?? '').toLowerCase();
    final name = p.name.toLowerCase();
    return sub.contains('organic') || name.contains('organic');
  }

  List<Product> _filteredProducts(List<Product> all) {
    return all.where((p) {
      switch (filter) {
        case 'Seasonal':
          return _isSeasonal(p);
        case 'Regular':
          return !_isSeasonal(p) && !_isOrganic(p);
        case 'Organic':
          return _isOrganic(p);
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _upsertCart(Product product, int qty,
      {bool showAddedToast = false}) async {
    try {
      await ref
          .read(cartRepositoryProvider)
          .upsertItem(productId: int.parse(product.id), quantity: qty);
      ref.invalidate(cartItemsProvider);
      ref.invalidate(cartCountProvider);
      if (showAddedToast && mounted) {
        AppFeedback.success(context, '${product.name} added to cart');
      }
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'Unable to update cart. Please login again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems =
        ref.watch(cartItemsProvider).valueOrNull ?? const <CartItem>[];
    final cartQtyMap = {
      for (final item in cartItems) item.product.id: item.quantity
    };
    final cartItemCount = cartItems.fold<int>(0, (sum, i) => sum + i.quantity);
    final cartTotal = cartItems.fold<double>(
        0, (sum, i) => sum + (i.product.price * i.quantity));
    final title = widget.type[0].toUpperCase() + widget.type.substring(1);

    return Scaffold(
      backgroundColor: DT.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: DT.text),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: DT.text)),
        titleSpacing: 0,
        actions: [
          IconButton(
              onPressed: () => context.push('/profile'),
              icon: const Icon(Icons.menu_rounded, color: DT.text)),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('All'),
                  _chip('Seasonal'),
                  _chip('Regular'),
                  _chip('Organic'),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              color: DT.sub, size: 34),
                          const SizedBox(height: 10),
                          const Text('Unable to load products',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: _retry, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  );
                }

                final allProducts = snapshot.data ?? const <Product>[];
                final products = _filteredProducts(allProducts);

                return RefreshIndicator(
                  onRefresh: _retry,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final crossAxisCount = gridCountForWidth(c.maxWidth);

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        children: [
                          Text(
                            '${products.length} items available',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: DT.sub,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: products.length,
                            itemBuilder: (_, i) {
                              final p = products[i];
                              final qty = cartQtyMap[p.id] ?? 0;
                              final badgeText = _isSeasonal(p)
                                  ? 'Seasonal'
                                  : _isOrganic(p)
                                      ? 'Organic'
                                      : (p.subcategory ?? '');
                              return ProductGridCard(
                                product: p,
                                quantity: qty,
                                badgeText: badgeText,
                                onTap: () => context.push(_productRoute(p)),
                                onQuantityChanged: (nextQty) async {
                                  await _upsertCart(p, nextQty,
                                      showAddedToast: qty <= 0 && nextQty > 0);
                                },
                              );
                            },
                          ),
                          if (products.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Center(
                                child: Text('No matching products found',
                                    style: TextStyle(color: DT.sub)),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: cartItemCount <= 0
          ? null
          : SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                height: 48,
                decoration: BoxDecoration(
                  color: DT.primaryDark,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => context.push('/cart'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '$cartItemCount item${cartItemCount > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₹${cartTotal.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'View Cart ›',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _chip(String text) {
    final selected = filter == text;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => setState(() => filter = text),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: selected ? DT.primaryDark : const Color(0xFFEAECEF),
            borderRadius: BorderRadius.circular(22),
            boxShadow: selected
                ? const [
                    BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 3))
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF4B5563),
              fontSize: 17 / 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

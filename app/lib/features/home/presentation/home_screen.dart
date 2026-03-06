import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/fresh_ui.dart';
import '../../../shared/widgets/product_grid_card.dart';
import '../../cart/data/cart_repository.dart';
import '../data/catalog_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<({List<Category> categories, List<Product> products})>
      _homeFuture;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _homeFuture = _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<({List<Category> categories, List<Product> products})> _load() async {
    final repo = ref.read(catalogRepositoryProvider);

    List<Category> categories = [];
    List<Product> products = [];
    Object? firstError;

    try {
      categories = await repo.fetchCategories();
    } catch (e) {
      firstError ??= e;
    }

    try {
      products = await repo.fetchProducts(q: _searchQuery);
    } catch (e) {
      firstError ??= e;
    }

    if (categories.isEmpty && products.isEmpty && firstError != null) {
      throw firstError;
    }

    return (categories: categories, products: products);
  }

  Future<void> _refresh() async {
    final next = _load();

    setState(() {
      _homeFuture = next;
    });

    await next;
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value.trim();
        _homeFuture = _load();
      });
    });
  }

  String _productRoute(Product p) {
    return '/product/${p.id}?name=${Uri.encodeComponent(p.name)}'
        '&price=${p.price}'
        '&unit=${Uri.encodeComponent(p.unit)}'
        '&image=${Uri.encodeComponent(p.imageUrl ?? '')}'
        '&categoryId=${Uri.encodeComponent(p.categoryId)}';
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
    final cartCount = ref.watch(cartCountProvider).valueOrNull ?? 0;
    final cartItems =
        ref.watch(cartItemsProvider).valueOrNull ?? const <CartItem>[];
    final cartQtyMap = {
      for (final item in cartItems) item.product.id: item.quantity,
    };

    final cartItemCount = cartItems.fold<int>(0, (sum, i) => sum + i.quantity);
    final cartTotal = cartItems.fold<double>(
        0, (sum, i) => sum + (i.product.price * i.quantity));

    return Scaffold(
      backgroundColor: DT.bg,
      appBar: AppBar(
        backgroundColor: DT.bg,
        elevation: 0,
        titleSpacing: 14,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vardevli, Mohali',
                style: TextStyle(fontSize: 11.5, color: DT.sub)),
            SizedBox(height: 2),
            Text('Fresh Mandi',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: DT.text)),
          ],
        ),
        actions: [
          IconButton(
              onPressed: () => context.push('/profile'),
              icon: const Icon(Icons.person_outline_rounded, color: DT.text)),
          Stack(
            children: [
              IconButton(
                  onPressed: () => context.push('/cart'),
                  icon:
                      const Icon(Icons.shopping_cart_outlined, color: DT.text)),
              if (cartCount > 0)
                Positioned(
                  right: 7,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: DT.primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('$cartCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 30, color: Color(0xFF97A0B2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        hintText: 'Search for fresh produce...',
                        hintStyle: TextStyle(fontSize: 14, color: DT.sub),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Search: "$_searchQuery"',
                    style: const TextStyle(fontSize: 11.5, color: DT.sub)),
              ),
            ),
          Expanded(
            child: FutureBuilder<
                ({List<Category> categories, List<Product> products})>(
              future: _homeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              size: 36, color: DT.sub),
                          const SizedBox(height: 10),
                          const Text('Unable to load home data',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11.5, color: DT.sub)),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: _refresh, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  );
                }

                final data = snapshot.data;
                if (data == null) {
                  return Center(
                      child: FilledButton(
                          onPressed: _refresh, child: const Text('Reload')));
                }

                final products = data.products.take(8).toList();

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossCount =
                          gridCountForWidth(constraints.maxWidth);
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                        children: [
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                                color: const Color(0xFFF8711D),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Row(
                              children: [
                                Icon(Icons.timer_outlined,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        'Order before 9 PM for next day delivery',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600))),
                                Text('08:47:33',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const FreshSectionTitle('Shop by Category'),
                          const SizedBox(height: 8),
                          if (data.categories.isEmpty)
                            const FreshCard(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              child: Text(
                                  'Categories are unavailable right now.',
                                  style:
                                      TextStyle(fontSize: 12, color: DT.sub)),
                            )
                          else
                            Row(
                              children: data.categories.take(2).map((c) {
                                final isFruit =
                                    c.type.toLowerCase().contains('fruit');
                                return Expanded(
                                  child: Padding(
                                    padding:
                                        EdgeInsets.only(right: isFruit ? 8 : 0),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => context.push(
                                          '/products?type=${c.type.toLowerCase()}'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        decoration: BoxDecoration(
                                            color: isFruit
                                                ? const Color(0xFFFF8A00)
                                                : DT.primary,
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: Column(
                                          children: [
                                            Image.asset(
                                              isFruit
                                                  ? 'assets/fruits.png'
                                                  : 'assets/vegetables.png',
                                              height: 18,
                                              width: 18,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(c.name,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 14),
                          FreshSectionTitle(
                            'Featured Today',
                            trailing: TextButton(
                              onPressed: () =>
                                  context.push('/products?type=fruit'),
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(20, 20),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              child: const Text('View All',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: DT.primaryDark,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (products.isEmpty)
                            const FreshCard(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              child: Text('Products are unavailable right now.',
                                  style:
                                      TextStyle(fontSize: 12, color: DT.sub)),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossCount,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: products.length,
                              itemBuilder: (_, i) {
                                final p = products[i];
                                final qty = cartQtyMap[p.id] ?? 0;
                                return ProductGridCard(
                                  product: p,
                                  quantity: qty,
                                  onTap: () => context.push(_productRoute(p)),
                                  onQuantityChanged: (nextQty) async {
                                    await _upsertCart(p, nextQty,
                                        showAddedToast:
                                            qty <= 0 && nextQty > 0);
                                  },
                                );
                              },
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
}

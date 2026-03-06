import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/fresh_ui.dart';
import '../../cart/data/cart_repository.dart';
import '../../home/data/catalog_repository.dart';

class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({
    super.key,
    required this.product,
  });

  final Product product;

  @override
  ConsumerState<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  late Future<List<Product>> _relatedFuture;

  @override
  void initState() {
    super.initState();
    _relatedFuture = _loadRelated();
  }

  Future<List<Product>> _loadRelated() async {
    final all = await ref.read(catalogRepositoryProvider).fetchProducts(categoryId: widget.product.categoryId);
    return all.where((p) => p.id != widget.product.id).take(6).toList();
  }

  Future<void> _upsertQty(int qty) async {
    await ref.read(cartRepositoryProvider).upsertItem(productId: int.parse(widget.product.id), quantity: qty);
    ref.invalidate(cartItemsProvider);
    ref.invalidate(cartCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cartItemsAsync = ref.watch(cartItemsProvider);
    final cartItems = cartItemsAsync.valueOrNull ?? const <CartItem>[];
    final cartMap = {for (final i in cartItems) i.product.id: i.quantity};
    final qty = cartMap[widget.product.id] ?? 0;
    final cartItemCount = cartItems.fold<int>(0, (sum, i) => sum + i.quantity);
    final cartTotal = cartItems.fold<double>(0, (sum, i) => sum + (i.product.price * i.quantity));

    return Scaffold(
      backgroundColor: DT.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 1.2,
                        child: Container(
                          color: const Color(0xFFEFF2F7),
                          child: widget.product.imageUrl == null || widget.product.imageUrl!.isEmpty
                              ? const Icon(Icons.image_outlined, size: 64, color: DT.muted)
                              : Image.network(
                                  widget.product.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_rounded, size: 64, color: DT.muted),
                                ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                    child: Text(widget.product.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: '₹${widget.product.price.toStringAsFixed(0)}', style: const TextStyle(color: DT.primaryDark, fontSize: 22, fontWeight: FontWeight.w700)),
                          TextSpan(text: '  per ${widget.product.unit}', style: const TextStyle(color: DT.sub, fontSize: 18, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFE6F4EC), borderRadius: BorderRadius.circular(14)),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.eco_outlined, color: DT.primaryDark),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Farm Fresh Guarantee', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF14532D))),
                                SizedBox(height: 4),
                                Text('Handpicked this morning from local farms. Delivered fresh to your doorstep tomorrow.', style: TextStyle(fontSize: 13, color: Color(0xFF166534), height: 1.35)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 16, 14, 8),
                    child: Text('About this product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text('Sweet and juicy seasonal produce, freshly sourced from trusted farms.', style: TextStyle(fontSize: 14, color: DT.sub, height: 1.5)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Text('Nutrition Benefits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text('Rich in Vitamin C, Vitamin A and dietary fiber. Great for immunity.', style: TextStyle(fontSize: 14, color: DT.sub, height: 1.5)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Text('You may also like', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  FutureBuilder<List<Product>>(
                    future: _relatedFuture,
                    builder: (context, snapshot) {
                      final list = snapshot.data ?? const <Product>[];
                      if (list.isEmpty) return const SizedBox(height: 6);
                      return SizedBox(
                        height: 220,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          scrollDirection: Axis.horizontal,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final p = list[i];
                            return SizedBox(
                              width: 190,
                              child: FreshCard(
                                padding: EdgeInsets.zero,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    context.push(
                                      '/product/${p.id}?name=${Uri.encodeComponent(p.name)}&price=${p.price}&unit=${Uri.encodeComponent(p.unit)}&image=${Uri.encodeComponent(p.imageUrl ?? '')}&categoryId=${Uri.encodeComponent(p.categoryId)}',
                                    );
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                          child: Container(
                                            width: double.infinity,
                                            color: const Color(0xFFF2F4F8),
                                            child: p.imageUrl == null || p.imageUrl!.isEmpty
                                                ? const Icon(Icons.image_outlined, color: DT.muted)
                                                : Image.network(
                                                    p.imageUrl!,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_rounded, color: DT.muted),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                            const SizedBox(height: 2),
                                            Text('₹${p.price.toStringAsFixed(0)}/${p.unit}', style: const TextStyle(color: DT.primaryDark, fontWeight: FontWeight.w700, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: qty <= 0
                            ? FreshPrimaryButton(
                                text: '+ Add to Cart',
                                onPressed: () async {
                                  await _upsertQty(1);
                                  if (!context.mounted) return;
                                  AppFeedback.success(context, '${widget.product.name} added to cart');
                                },
                              )
                            : Container(
                                height: 48,
                                decoration: BoxDecoration(color: const Color(0xFFE8F8EF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFB7E4C7))),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      onPressed: () => _upsertQty(qty - 1),
                                      icon: const Icon(Icons.remove_circle_outline),
                                    ),
                                    Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                    IconButton(
                                      onPressed: () => _upsertQty(qty + 1),
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => context.push('/cart'),
                          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          child: const Text('View Cart'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (cartItemCount > 0)
                  SafeArea(
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
                                const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 16),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../models/models.dart';
import 'fresh_ui.dart';

class ProductGridCard extends StatelessWidget {
  const ProductGridCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onTap,
    required this.onQuantityChanged,
    this.badgeText,
  });

  final Product product;
  final int quantity;
  final VoidCallback onTap;
  final ValueChanged<int> onQuantityChanged;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: FreshCard(
          padding: const EdgeInsets.all(7),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: product.imageUrl == null || product.imageUrl!.isEmpty
                      ? const Icon(Icons.image_outlined, color: DT.muted)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.image_not_supported_rounded, color: DT.muted),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              _badge(badgeText ?? product.subcategory),
              const SizedBox(height: 2),
              SizedBox(
                height: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₹${product.price.toStringAsFixed(0)} / ${product.unit}',
                    style: const TextStyle(color: DT.sub, fontSize: 10.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _cartControl(product, quantity, onQuantityChanged),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _cartControl(Product product, int qty, ValueChanged<int> onQuantityChanged) {
  return SizedBox(
    width: double.infinity,
    height: 36,
    child: qty <= 0
        ? FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DT.primaryDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => onQuantityChanged(1),
            child: const Text(
              '+  Add',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          )
        : Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8EF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF26B865), width: 1.2),
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => onQuantityChanged(qty - 1),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: const Color(0xFFDDF3E6), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.remove, size: 14, color: Color(0xFF0B9E49)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$qty',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF0B9E49)),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => onQuantityChanged(qty + 1),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: const Color(0xFFDDF3E6), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.add, size: 14, color: Color(0xFF0B9E49)),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
  );
}

Widget _badge(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return const SizedBox(height: 22);

  final value = raw.toLowerCase();
  final isSeasonal = value == 'seasonal';
  final isOrganic = value == 'organic';

  final bg = isSeasonal ? const Color(0xFFFDE8D3) : const Color(0xFFDFF3E6);
  final fg = isSeasonal ? const Color(0xFFEA580C) : const Color(0xFF16803D);

  return SizedBox(
    height: 22,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isOrganic ? 'Organic' : raw,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    ),
  );
}

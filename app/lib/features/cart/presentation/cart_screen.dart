import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/fresh_ui.dart';
import '../../address/data/address_repository.dart';
import '../../checkout/presentation/checkout_state_provider.dart';
import '../data/cart_repository.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _couponFormKey = GlobalKey<FormState>();
  late final TextEditingController _couponController;
  late Future<List<Map<String, dynamic>>> _addressFuture;

  @override
  void initState() {
    super.initState();
    final state = ref.read(checkoutProvider);
    _couponController = TextEditingController(text: state.couponCode);
    _addressFuture = ref.read(addressRepositoryProvider).fetchAddresses();
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  void _applyCoupon() {
    final code = _couponController.text.trim();
    if (code.isEmpty) {
      AppFeedback.error(context, 'Please enter coupon code.');
      return;
    }
    ref.read(checkoutProvider.notifier).setCoupon(code);
    final applied = ref.read(checkoutProvider).discount > 0;
    AppFeedback.info(
        context, applied ? 'Coupon applied.' : 'Coupon not applicable.');
  }

  Future<void> _refreshAddress() async {
    final next = ref.read(addressRepositoryProvider).fetchAddresses();
    setState(() => _addressFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(cartItemsProvider);
    final suggestionsAsync = ref.watch(cartSuggestionsProvider);
    final checkout = ref.watch(checkoutProvider);
    final checkoutConfigAsync = ref.watch(checkoutConfigProvider);
    final gstPercent =
        checkoutConfigAsync.valueOrNull?.gstPercent ?? AppConstants.gstPercent;
    final itemCount =
        itemsAsync.maybeWhen(data: (items) => items.length, orElse: () => 0);

    return Scaffold(
      backgroundColor: DT.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        toolbarHeight: 72,
        leadingWidth: 46,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: DT.text, size: 26),
        ),
        titleSpacing: 0,
        title: const Text(
          'My Cart',
          style: TextStyle(
              fontSize: 27, fontWeight: FontWeight.w700, color: DT.text),
        ),
        actions: [
          if (itemCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD4F5DF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                '$itemCount item${itemCount > 1 ? 's' : ''}',
                style: const TextStyle(
                  color: DT.primaryDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE6ECE8)),
        ),
      ),
      body: SafeArea(
        top: false,
        child: itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Failed to load cart')),
          data: (items) {
            const deliveryCharge = 20.0;
            final subtotal = items.fold<double>(
                0, (sum, i) => sum + i.product.price * i.quantity);
            final gst =
                ((subtotal - checkout.discount) * gstPercent / 100)
                    .clamp(0, double.infinity)
                    .toDouble();
            final total = (subtotal - checkout.discount + gst + deliveryCharge)
                .clamp(0, double.infinity)
                .toDouble();

            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F7EE),
                          borderRadius: BorderRadius.circular(46),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined,
                            size: 46, color: DT.primaryDark),
                      ),
                      const SizedBox(height: 14),
                      const Text('Your cart is empty',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text(
                        'Add some fresh fruits and vegetables to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13.5, color: DT.sub, height: 1.45),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: 170,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: DT.primaryDark,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => context.go('/home'),
                          child: const Text('Start Shopping'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    children: [
                      ...items.map(
                        (item) => _CartRow(
                          item: item,
                          onChanged: (q) async {
                            await ref.read(cartRepositoryProvider).upsertItem(
                                productId: int.parse(item.product.id),
                                quantity: q);
                            ref.invalidate(cartItemsProvider);
                            ref.invalidate(cartCountProvider);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      const FreshSectionTitle('You might also need'),
                      const SizedBox(height: 8),
                      suggestionsAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (suggestions) => SizedBox(
                          height: 136,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: suggestions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final s = suggestions[i];
                              return SizedBox(
                                width: 108,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: DT.softShadow,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        height: 72,
                                        child: Container(
                                          color: const Color(0xFFF2F4F8),
                                          child: s.imageUrl == null ||
                                                  s.imageUrl!.isEmpty
                                              ? const Center(
                                                  child: Icon(
                                                      Icons.image_outlined,
                                                      color: DT.muted))
                                              : Image.network(
                                                  s.imageUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(
                                                          Icons
                                                              .image_not_supported_rounded,
                                                          color: DT.muted),
                                                ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 6, 8, 0),
                                        child: Text(
                                          s.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: DT.text),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 2, 8, 0),
                                        child: Text(
                                          '₹${s.price.toStringAsFixed(0)}/kg',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: DT.primaryDark,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FreshCard(
                        borderRadius: BorderRadius.circular(12),
                        child: Form(
                          key: _couponFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.local_offer_outlined,
                                      color: DT.primaryDark, size: 18),
                                  SizedBox(width: 8),
                                  Text('Apply Coupon',
                                      style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          color: DT.text)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _couponController,
                                      style: const TextStyle(
                                          fontSize: 14.5,
                                          color: DT.text,
                                          fontWeight: FontWeight.w500),
                                      decoration: InputDecoration(
                                        hintText: 'Enter code',
                                        hintStyle: const TextStyle(
                                            color: Color(0xFF6B7280),
                                            fontSize: 16),
                                        filled: true,
                                        fillColor: const Color(0xFFF2F4F7),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 10),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            borderSide: BorderSide.none),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            borderSide: BorderSide.none),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          borderSide: const BorderSide(
                                              color: Color(0xFF86EFAC),
                                              width: 1),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: DT.primaryDark,
                                      minimumSize: const Size(72, 40),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                    ),
                                    onPressed: _applyCoupon,
                                    child: const Text('Apply',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FreshCard(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.access_time_rounded,
                                    color: DT.primaryDark, size: 19),
                                SizedBox(width: 8),
                                Text('Delivery Slot (Tomorrow)',
                                    style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                        color: DT.text)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _slotTile(
                              title: '7 AM - 9 AM',
                              subtitle: 'Early morning',
                              selected: checkout.slotLabel.contains('7'),
                              onTap: () => ref
                                  .read(checkoutProvider.notifier)
                                  .setSlot('7:00 AM - 9:00 AM'),
                            ),
                            const SizedBox(height: 10),
                            _slotTile(
                              title: '9 AM - 11 AM',
                              subtitle: 'Late morning',
                              selected: checkout.slotLabel
                                  .contains('9:00 AM - 11:00 AM'),
                              onTap: () => ref
                                  .read(checkoutProvider.notifier)
                                  .setSlot('9:00 AM - 11:00 AM'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _addressFuture,
                        builder: (context, snapshot) {
                          final data =
                              snapshot.data ?? const <Map<String, dynamic>>[];
                          final address = data.isEmpty
                              ? 'Add delivery address'
                              : _addressText(data);
                          return FreshCard(
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.location_on_outlined,
                                  color: DT.primaryDark),
                              title: const Text('Delivery Address',
                                  style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, color: DT.sub),
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  color: Color(0xFF98A2B3)),
                              onTap: () async {
                                await context.push('/address');
                                if (!mounted) return;
                                await _refreshAddress();
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      FreshCard(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Bill Summary',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            _line('Item Total', subtotal),
                            _line(
                                'GST (${gstPercent.toStringAsFixed(0)}%)',
                                gst),
                            _line('Delivery Charge', deliveryCharge),
                            if (checkout.discount > 0)
                              _line('Coupon', -checkout.discount),
                            const Divider(height: 14),
                            _line('Total', total, bold: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 14),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: DT.primaryDark,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                    ),
                    onPressed: () => context.push('/checkout'),
                    icon: const Icon(Icons.shopping_bag_outlined,
                        size: 18, color: Colors.white),
                    label: Text(
                      'Complete Order - ₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.8,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _addressText(List<Map<String, dynamic>> addresses) {
    final selected = addresses.firstWhere(
      (a) => a['is_default'] == true,
      orElse: () => addresses.first,
    );
    final line1 = '${selected['line1'] ?? ''}'.trim();
    final city = '${selected['city'] ?? ''}'.trim();
    if (line1.isEmpty && city.isEmpty) return 'Add delivery address';
    return city.isEmpty ? line1 : '$line1, $city';
  }

  Widget _slotTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7F2EC) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? DT.primaryDark : const Color(0xFFD6DAE1),
            width: selected ? 1.4 : 1.1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: DT.text)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 13.5, color: DT.sub)),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, double amount, {bool bold = false}) {
    final text = '₹${amount.toStringAsFixed(0)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? DT.text : DT.sub,
              fontSize: bold ? 16 : 13.5,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: bold ? DT.primaryDark : DT.text,
              fontSize: bold ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.item, required this.onChanged});
  final CartItem item;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.product.price * item.quantity;
    return FreshCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: const Color(0xFFF2F4F8),
                borderRadius: BorderRadius.circular(10)),
            child:
                item.product.imageUrl == null || item.product.imageUrl!.isEmpty
                    ? const Icon(Icons.image_outlined, color: DT.muted)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(item.product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported_rounded,
                                color: DT.muted)),
                      ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 1),
                Text(
                  '₹${item.product.price.toStringAsFixed(0)}/${item.product.unit}',
                  style: const TextStyle(
                      color: DT.primaryDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, c) {
                    final counterWidth = (c.maxWidth * 0.44).clamp(108.0, 128.0);
                    const sideTapWidth = 28.0;
                    return Row(
                      children: [
                        Container(
                          height: 28,
                          width: counterWidth,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F8EF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: DT.primaryDark, width: 1.1),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => onChanged(item.quantity - 1),
                                child: const SizedBox(
                                  width: sideTapWidth,
                                  child: Icon(Icons.remove, size: 15, color: DT.primaryDark),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '${item.quantity}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: DT.primaryDark,
                                    ),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => onChanged(item.quantity + 1),
                                child: const SizedBox(
                                  width: sideTapWidth,
                                  child: Icon(Icons.add, size: 15, color: DT.primaryDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₹${lineTotal.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: DT.text),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onChanged(0),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 19),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';
import 'checkout_state_provider.dart';

class SlotSelectorScreen extends ConsumerWidget {
  const SlotSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkoutProvider);

    Widget slotTile({
      required String value,
      required String subtitle,
    }) {
      final selected = state.slotLabel == value;
      return InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => ref.read(checkoutProvider.notifier).setSlot(value),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE7F2EC) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? DT.primaryDark : const Color(0xFFD6DAE1),
              width: selected ? 1.6 : 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value.replaceAll(':00', ''), style: const TextStyle(fontSize: 30 / 1.9, fontWeight: FontWeight.w700, color: DT.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 15, color: DT.sub)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DT.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: DT.text),
        ),
        titleSpacing: 0,
        title: const Text('Delivery Slot', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 33 / 1.7, color: DT.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE6ECE8)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        children: [
          const Text('Select preferred slot for tomorrow', style: TextStyle(fontSize: 15, color: DT.sub)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: DT.softShadow),
            child: Column(
              children: [
                slotTile(value: '7:00 AM - 9:00 AM', subtitle: 'Early morning'),
                const SizedBox(height: 10),
                slotTile(value: '9:00 AM - 11:00 AM', subtitle: 'Late morning'),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DT.primaryDark,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => context.pop(),
            child: const Text('Save Slot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ),
    );
  }
}

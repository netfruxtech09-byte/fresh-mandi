import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../shared/widgets/fresh_app_bar.dart';
import '../data/address_repository.dart';

class AddressScreen extends ConsumerStatefulWidget {
  const AddressScreen({super.key, this.onboardingFlow = false});

  final bool onboardingFlow;

  @override
  ConsumerState<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends ConsumerState<AddressScreen> {
  List<Map<String, dynamic>> _addresses = const [];
  bool _loading = true;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      final data = await ref.read(addressRepositoryProvider).fetchAddresses();
      if (!mounted) return;
      setState(() => _addresses = data);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'Unable to load addresses.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({int? id}) async {
    final route = id == null ? '/address/form' : '/address/form?id=$id';
    final result = await context.push(route);
    if (!mounted) return;

    await _loadAddresses(showLoader: false);
    if (!mounted) return;

    if (result == true) {
      if (widget.onboardingFlow && _addresses.isNotEmpty) {
        context.go('/home');
        return;
      }
      AppFeedback.success(context, 'Address updated.');
    }
  }

  Future<void> _deleteAddress(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Address'),
        content: const Text('Are you sure you want to remove this address?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || _actionBusy) return;

    setState(() => _actionBusy = true);
    var actionOk = false;
    try {
      await ref.read(addressRepositoryProvider).deleteAddress(id);
      actionOk = true;
      if (mounted) AppFeedback.success(context, 'Address deleted.');
    } catch (_) {
      if (mounted) AppFeedback.error(context, 'Unable to delete address.');
    } finally {
      await _loadAddresses(showLoader: false);
      if (mounted) setState(() => _actionBusy = false);
      if (!actionOk && mounted && _addresses.isEmpty) {
        // no-op: keeps UX consistent if delete failed on last item
      }
    }
  }

  Future<void> _setDefault(int id) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);

    try {
      await ref.read(addressRepositoryProvider).setDefaultAddress(id);
      if (mounted) AppFeedback.success(context, 'Default address changed.');
    } catch (_) {
      if (mounted)
        AppFeedback.error(context, 'Unable to update default address.');
    } finally {
      await _loadAddresses(showLoader: false);
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.onboardingFlow,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.onboardingFlow) return;
        if (_addresses.isNotEmpty) {
          context.go('/home');
        } else {
          AppFeedback.error(
              context, 'Please add a delivery address to continue.');
        }
      },
      child: Scaffold(
        backgroundColor: DT.bg,
        appBar: FreshAppBar(
          title: 'My Addresses',
          showBack: !widget.onboardingFlow || _addresses.isNotEmpty,
          onBack: widget.onboardingFlow
              ? () {
                  if (_addresses.isNotEmpty) {
                    context.go('/home');
                  } else {
                    AppFeedback.error(
                        context, 'Please add a delivery address to continue.');
                  }
                }
              : null,
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _loadAddresses(showLoader: false),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                    children: [
                      if (_addresses.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: DT.softShadow,
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF7EF),
                                  borderRadius: BorderRadius.circular(35),
                                ),
                                child: const Icon(Icons.location_on_outlined,
                                    color: DT.primaryDark, size: 32),
                              ),
                              const SizedBox(height: 10),
                              const Text('No addresses added yet',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17)),
                              const SizedBox(height: 6),
                              const Text(
                                'Add your delivery address for faster checkout.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: DT.sub, fontSize: 13.5),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: DT.primaryDark,
                                    minimumSize: const Size.fromHeight(44),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                  onPressed:
                                      _actionBusy ? null : () => _openForm(),
                                  child: const Text('Add New Address'),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        ..._addresses.map((a) {
                          final id = (a['id'] as num?)?.toInt() ??
                              int.tryParse('${a['id']}');
                          if (id == null) return const SizedBox.shrink();

                          final isDefault = a['is_default'] == true;
                          final label = ('${a['label'] ?? 'Address'}').trim();
                          final line1 = ('${a['line1'] ?? ''}').trim();
                          final city = ('${a['city'] ?? ''}').trim();
                          final state = ('${a['state'] ?? ''}').trim();
                          final pincode = ('${a['pincode'] ?? ''}').trim();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: DT.softShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(label,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15.5)),
                                    const SizedBox(width: 8),
                                    if (isDefault)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDDF4E6),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Text(
                                          'Default',
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: DT.primaryDark,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(line1,
                                    style: const TextStyle(
                                        color: DT.text,
                                        fontSize: 14.5,
                                        height: 1.35)),
                                const SizedBox(height: 2),
                                Text('$city, $state - $pincode',
                                    style: const TextStyle(
                                        color: DT.sub, fontSize: 13.5)),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (!isDefault)
                                      OutlinedButton(
                                        onPressed: _actionBusy
                                            ? null
                                            : () => _setDefault(id),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: DT.primaryDark,
                                          side: const BorderSide(
                                              color: Color(0xFF86EFAC)),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                        child: const Text('Set Default',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    if (!isDefault) const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _actionBusy
                                          ? null
                                          : () => _openForm(id: id),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF334155),
                                        side: const BorderSide(
                                            color: Color(0xFFCBD5E1)),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 16),
                                      label: const Text('Edit',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _actionBusy
                                          ? null
                                          : () => _deleteAddress(id),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFDC2626),
                                        side: const BorderSide(
                                            color: Color(0xFFFECACA)),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16),
                                      label: const Text('Delete',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _actionBusy ? null : () => _openForm(),
                            style: FilledButton.styleFrom(
                              backgroundColor: DT.primaryDark,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text('Add Another Address'),
                          ),
                        ),
                        if (widget.onboardingFlow && _addresses.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => context.go('/home'),
                              style: FilledButton.styleFrom(
                                backgroundColor: DT.primaryDark,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('Continue to Home'),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

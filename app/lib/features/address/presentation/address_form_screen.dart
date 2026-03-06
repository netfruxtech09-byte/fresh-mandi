import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/fresh_app_bar.dart';
import '../data/address_repository.dart';

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, this.addressId});
  final int? addressId;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();

  bool _isDefault = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _label.dispose();
    _line1.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final all = await ref.read(addressRepositoryProvider).fetchAddresses();
      if (widget.addressId == null) {
        _isDefault = all.isEmpty;
      } else {
        final current = all.firstWhere(
          (a) => ((a['id'] as num?)?.toInt() ?? int.tryParse('${a['id']}')) == widget.addressId,
          orElse: () => <String, dynamic>{},
        );
        if (current.isNotEmpty) {
          _label.text = '${current['label'] ?? 'Home'}';
          _line1.text = '${current['line1'] ?? ''}';
          _city.text = '${current['city'] ?? ''}';
          _state.text = '${current['state'] ?? ''}';
          _pincode.text = '${current['pincode'] ?? ''}';
          _isDefault = current['is_default'] == true;
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      AppFeedback.error(context, 'Please fill all fields correctly.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(addressRepositoryProvider);
      if (widget.addressId == null) {
        await repo.createAddress(
          label: _label.text.trim(),
          line1: _line1.text.trim(),
          city: _city.text.trim(),
          state: _state.text.trim(),
          pincode: _pincode.text.trim(),
          isDefault: _isDefault,
        );
      } else {
        await repo.updateAddress(
          id: widget.addressId!,
          label: _label.text.trim(),
          line1: _line1.text.trim(),
          city: _city.text.trim(),
          state: _state.text.trim(),
          pincode: _pincode.text.trim(),
          isDefault: _isDefault,
        );
      }

      if (!mounted) return;
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'Unable to save address. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: DT.bg,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      backgroundColor: DT.bg,
      appBar: FreshAppBar(title: widget.addressId == null ? 'Add Address' : 'Edit Address'),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: DT.softShadow),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelText('Address Label'),
                    const SizedBox(height: 6),
                    _input(_label, hint: 'Home, Office', validator: Validators.addressLabel),
                    const SizedBox(height: 10),
                    _labelText('Address Line'),
                    const SizedBox(height: 6),
                    _input(_line1, hint: 'House no., Street, Landmark', validator: (v) => Validators.minLength(v, min: 2, label: 'Address line')),
                    const SizedBox(height: 10),
                    _labelText('City'),
                    const SizedBox(height: 6),
                    _input(_city, hint: 'City', validator: (v) => Validators.minLength(v, min: 2, label: 'City')),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelText('State'),
                              const SizedBox(height: 6),
                              _input(_state, hint: 'State', validator: (v) => Validators.minLength(v, min: 2, label: 'State')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelText('Pincode'),
                              const SizedBox(height: 6),
                              _input(
                                _pincode,
                                hint: '160055',
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                validator: Validators.indianPincode,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: _isDefault,
                      onChanged: (v) => setState(() => _isDefault = v),
                      activeThumbColor: Colors.white,
                      activeTrackColor: DT.primaryDark,
                      title: const Text('Set as default address', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.pop(),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: DT.primaryDark,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Save Address', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelText(String text) {
    return Text(text, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: DT.text));
  }

  Widget _input(
    TextEditingController controller, {
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 14.5),
        filled: true,
        fillColor: const Color(0xFFF2F4F7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF86EFAC), width: 1),
        ),
      ),
    );
  }
}
